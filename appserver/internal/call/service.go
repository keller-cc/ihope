package call

import (
	"context"
	"encoding/json"
	"errors"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/keller-cc/ihope/appserver/internal/hub"
)

const (
	MaxDMParticipants    = 2
	MaxGroupParticipants = 8
	RingTimeout          = 45 * time.Second
)

var (
	ErrNotFound     = errors.New("call not found")
	ErrForbidden    = errors.New("forbidden")
	ErrBusy         = errors.New("already in a call")
	ErrFull         = errors.New("call is full")
	ErrEnded        = errors.New("call ended")
	ErrInvalidKind  = errors.New("invalid kind")
	ErrActiveExists = errors.New("conversation already has an active call")
)

type MemberInfo struct {
	ID        string
	Username  string
	AvatarURL *string
}

type Membership interface {
	IsMember(ctx context.Context, conversationID, userID string) (bool, error)
	ConversationType(ctx context.Context, conversationID string) (string, error)
	ListMembers(ctx context.Context, conversationID, userID string) ([]MemberInfo, error)
	PostCallMessage(ctx context.Context, conversationID, senderID string, body CallMessageBody, markReadUserIDs []string) error
}

type CallMessageBody struct {
	Kind        string `json:"kind"`
	Status      string `json:"status"` // ended | missed | rejected | cancelled
	DurationSec int    `json:"durationSec,omitempty"`
}

type ICEServer struct {
	URLs       []string `json:"urls"`
	Username   string   `json:"username,omitempty"`
	Credential string   `json:"credential,omitempty"`
}

type Peer struct {
	UserID    string  `json:"userId"`
	Username  string  `json:"username"`
	AvatarURL *string `json:"avatarUrl,omitempty"`
	State     string  `json:"state"` // invited | joined | left | rejected
	Audio     bool    `json:"audio"`
	Video     bool    `json:"video"`
}

type Room struct {
	ID             string    `json:"id"`
	ConversationID string    `json:"conversationId"`
	ConvType       string    `json:"convType"`
	Kind           string    `json:"kind"` // voice | video
	HostID         string    `json:"hostId"`
	Status         string    `json:"status"` // ringing | active | ended
	CreatedAt      time.Time `json:"createdAt"`
	StartedAt      *time.Time `json:"startedAt,omitempty"`
	Participants   []Peer    `json:"participants"`
}

type room struct {
	mu             sync.Mutex
	id             string
	conversationID string
	convType       string
	kind           string
	hostID         string
	status         string
	createdAt      time.Time
	startedAt      *time.Time
	peers          map[string]*Peer
	timer          *time.Timer
}

type Service struct {
	hub  *hub.Hub
	mem  Membership
	ice  []ICEServer
	mu   sync.Mutex
	byID map[string]*room
	byConv map[string]string // active conversation -> call id
	userCall map[string]string // user -> active call id
}

func New(h *hub.Hub, mem Membership, ice []ICEServer) *Service {
	if len(ice) == 0 {
		ice = []ICEServer{{URLs: []string{"stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"}}}
	}
	return &Service{
		hub:      h,
		mem:      mem,
		ice:      ice,
		byID:     make(map[string]*room),
		byConv:   make(map[string]string),
		userCall: make(map[string]string),
	}
}

func (s *Service) ICEServers() []ICEServer {
	return s.ice
}

func (s *Service) Start(ctx context.Context, conversationID, userID, kind string) (*Room, error) {
	kind = normalizeKind(kind)
	if kind == "" {
		return nil, ErrInvalidKind
	}
	ok, err := s.mem.IsMember(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrForbidden
	}
	convType, err := s.mem.ConversationType(ctx, conversationID)
	if err != nil {
		return nil, err
	}
	members, err := s.mem.ListMembers(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if len(members) < 2 {
		return nil, errors.New("need at least 2 members")
	}

	s.mu.Lock()
	if _, busy := s.userCall[userID]; busy {
		s.mu.Unlock()
		return nil, ErrBusy
	}
	if _, exists := s.byConv[conversationID]; exists {
		s.mu.Unlock()
		return nil, ErrActiveExists
	}

	now := time.Now().UTC()
	r := &room{
		id:             uuid.NewString(),
		conversationID: conversationID,
		convType:       convType,
		kind:           kind,
		hostID:         userID,
		status:         "ringing",
		createdAt:      now,
		peers:          make(map[string]*Peer),
	}
	var hostInfo *MemberInfo
	for i := range members {
		m := members[i]
		if m.ID == userID {
			hostInfo = &m
		}
		state := "invited"
		audio, video := false, false
		if m.ID == userID {
			state = "joined"
			audio = true
			video = kind == "video"
		}
		r.peers[m.ID] = &Peer{
			UserID:    m.ID,
			Username:  m.Username,
			AvatarURL: m.AvatarURL,
			State:     state,
			Audio:     audio,
			Video:     video,
		}
	}
	if hostInfo == nil {
		s.mu.Unlock()
		return nil, ErrForbidden
	}

	s.byID[r.id] = r
	s.byConv[conversationID] = r.id
	s.userCall[userID] = r.id
	s.mu.Unlock()

	snap := r.snapshot()
	notifyIDs := make([]string, 0, len(members))
	for _, m := range members {
		if m.ID != userID {
			notifyIDs = append(notifyIDs, m.ID)
		}
	}
	s.hub.PublishToUsers(notifyIDs, map[string]any{
		"type": "call.invite",
		"call": snap,
	})
	s.hub.PublishToUser(userID, map[string]any{
		"type": "call.started",
		"call": snap,
	})

	r.mu.Lock()
	r.timer = time.AfterFunc(RingTimeout, func() { s.onRingTimeout(r.id) })
	r.mu.Unlock()

	return snap, nil
}

func (s *Service) Get(callID, userID string) (*Room, error) {
	r := s.getRoom(callID)
	if r == nil {
		return nil, ErrNotFound
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.peers[userID] == nil {
		return nil, ErrForbidden
	}
	return r.snapshotLocked(), nil
}

func (s *Service) Accept(ctx context.Context, callID, userID string) (*Room, error) {
	r := s.getRoom(callID)
	if r == nil {
		return nil, ErrNotFound
	}
	ok, err := s.mem.IsMember(ctx, r.conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrForbidden
	}

	s.mu.Lock()
	if other, busy := s.userCall[userID]; busy && other != callID {
		s.mu.Unlock()
		return nil, ErrBusy
	}
	s.mu.Unlock()

	r.mu.Lock()
	if r.status == "ended" {
		r.mu.Unlock()
		return nil, ErrEnded
	}
	p := r.peers[userID]
	if p == nil {
		r.mu.Unlock()
		return nil, ErrForbidden
	}
	joined := 0
	for _, x := range r.peers {
		if x.State == "joined" {
			joined++
		}
	}
	max := MaxDMParticipants
	if r.convType == "group" {
		max = MaxGroupParticipants
	}
	if p.State != "joined" && joined >= max {
		r.mu.Unlock()
		return nil, ErrFull
	}
	p.State = "joined"
	p.Audio = true
	p.Video = r.kind == "video"
	if r.status == "ringing" {
		r.status = "active"
		now := time.Now().UTC()
		r.startedAt = &now
		if r.timer != nil {
			r.timer.Stop()
			r.timer = nil
		}
	}
	snap := r.snapshotLocked()
	r.mu.Unlock()

	s.mu.Lock()
	s.userCall[userID] = callID
	s.mu.Unlock()

	s.broadcast(r, map[string]any{
		"type":   "call.peer_joined",
		"callId": callID,
		"peer":   peerCopy(p),
		"call":   snap,
	})
	return snap, nil
}

func (s *Service) Reject(ctx context.Context, callID, userID string) error {
	r := s.getRoom(callID)
	if r == nil {
		return ErrNotFound
	}
	r.mu.Lock()
	p := r.peers[userID]
	if p == nil {
		r.mu.Unlock()
		return ErrForbidden
	}
	if p.State == "joined" {
		r.mu.Unlock()
		return s.Hangup(ctx, callID, userID)
	}
	p.State = "rejected"
	convType := r.convType
	hostID := r.hostID
	convID := r.conversationID
	kind := r.kind
	shouldEnd := false
	if convType == "dm" {
		shouldEnd = true
	} else {
		// 群聊：若无人再处于 invited，且仅有主持人，保持 ringing；若全部拒绝则结束
		anyInvited := false
		for _, x := range r.peers {
			if x.State == "invited" {
				anyInvited = true
				break
			}
		}
		if !anyInvited {
			joined := 0
			for _, x := range r.peers {
				if x.State == "joined" {
					joined++
				}
			}
			if joined <= 1 {
				shouldEnd = true
			}
		}
	}
	r.mu.Unlock()

	s.hub.PublishToUser(hostID, map[string]any{
		"type":   "call.peer_rejected",
		"callId": callID,
		"userId": userID,
	})

	if shouldEnd {
		return s.endCall(ctx, callID, "rejected", hostID, convID, kind, 0)
	}
	return nil
}

func (s *Service) Hangup(ctx context.Context, callID, userID string) error {
	r := s.getRoom(callID)
	if r == nil {
		return ErrNotFound
	}

	r.mu.Lock()
	p := r.peers[userID]
	if p == nil {
		r.mu.Unlock()
		return ErrForbidden
	}
	wasJoined := p.State == "joined"
	p.State = "left"
	p.Audio = false
	p.Video = false
	joined := 0
	var still []string
	for id, x := range r.peers {
		if x.State == "joined" {
			joined++
			still = append(still, id)
		}
	}
	hostID := r.hostID
	convID := r.conversationID
	kind := r.kind
	status := r.status
	var startedAt *time.Time
	if r.startedAt != nil {
		t := *r.startedAt
		startedAt = &t
	}
	endNow := false
	endStatus := "ended"
	if status == "ringing" && userID == hostID {
		endNow = true
		endStatus = "cancelled"
	} else if joined == 0 {
		endNow = true
		if status == "ringing" {
			endStatus = "cancelled"
		}
	} else if r.convType == "dm" && joined < 2 {
		endNow = true
	}
	peerSnap := peerCopy(p)
	r.mu.Unlock()

	s.mu.Lock()
	delete(s.userCall, userID)
	s.mu.Unlock()

	if wasJoined {
		s.broadcast(r, map[string]any{
			"type":   "call.peer_left",
			"callId": callID,
			"peer":   peerSnap,
		})
	}

	if endNow {
		dur := 0
		if startedAt != nil {
			dur = int(time.Since(*startedAt).Seconds())
		}
		return s.endCall(ctx, callID, endStatus, hostID, convID, kind, dur)
	}
	_ = still
	return nil
}

func (s *Service) SetMedia(callID, userID string, audio, video *bool) error {
	r := s.getRoom(callID)
	if r == nil {
		return ErrNotFound
	}
	r.mu.Lock()
	p := r.peers[userID]
	if p == nil || p.State != "joined" {
		r.mu.Unlock()
		return ErrForbidden
	}
	if audio != nil {
		p.Audio = *audio
	}
	if video != nil {
		p.Video = *video
	}
	snap := peerCopy(p)
	r.mu.Unlock()
	s.broadcast(r, map[string]any{
		"type":   "call.media",
		"callId": callID,
		"peer":   snap,
	})
	return nil
}

func (s *Service) Relay(fromUserID string, payload map[string]any) error {
	callID, _ := payload["callId"].(string)
	toUserID, _ := payload["toUserId"].(string)
	typ, _ := payload["type"].(string)
	if callID == "" || toUserID == "" || typ == "" {
		return errors.New("invalid signal")
	}
	switch typ {
	case "call.offer", "call.answer", "call.ice":
	default:
		return errors.New("unsupported signal")
	}
	r := s.getRoom(callID)
	if r == nil {
		return ErrNotFound
	}
	r.mu.Lock()
	from := r.peers[fromUserID]
	to := r.peers[toUserID]
	ok := from != nil && to != nil && from.State == "joined" && to.State == "joined" && r.status != "ended"
	r.mu.Unlock()
	if !ok {
		return ErrForbidden
	}
	out := map[string]any{}
	for k, v := range payload {
		out[k] = v
	}
	out["fromUserId"] = fromUserID
	s.hub.PublishToUser(toUserID, out)
	return nil
}

func (s *Service) onRingTimeout(callID string) {
	r := s.getRoom(callID)
	if r == nil {
		return
	}
	r.mu.Lock()
	if r.status != "ringing" {
		r.mu.Unlock()
		return
	}
	hostID := r.hostID
	convID := r.conversationID
	kind := r.kind
	r.mu.Unlock()
	_ = s.endCall(context.Background(), callID, "missed", hostID, convID, kind, 0)
}

func (s *Service) endCall(ctx context.Context, callID, status, hostID, convID, kind string, durationSec int) error {
	s.mu.Lock()
	r := s.byID[callID]
	if r == nil {
		s.mu.Unlock()
		return nil
	}
	delete(s.byID, callID)
	if s.byConv[convID] == callID {
		delete(s.byConv, convID)
	}
	for uid, cid := range s.userCall {
		if cid == callID {
			delete(s.userCall, uid)
		}
	}
	s.mu.Unlock()

	r.mu.Lock()
	if r.timer != nil {
		r.timer.Stop()
		r.timer = nil
	}
	r.status = "ended"
	ids := make([]string, 0, len(r.peers))
	markRead := make([]string, 0, len(r.peers))
	for id := range r.peers {
		ids = append(ids, id)
		// 未接听保留未读提醒；已接通/取消/拒绝的通话摘要不打扰
		if status != "missed" {
			markRead = append(markRead, id)
		} else if id == hostID {
			markRead = append(markRead, id)
		}
	}
	snap := r.snapshotLocked()
	r.mu.Unlock()

	s.hub.PublishToUsers(ids, map[string]any{
		"type":   "call.ended",
		"callId": callID,
		"status": status,
		"call":   snap,
	})

	body := CallMessageBody{Kind: kind, Status: status, DurationSec: durationSec}
	_ = s.mem.PostCallMessage(ctx, convID, hostID, body, markRead)
	return nil
}

func (s *Service) getRoom(id string) *room {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.byID[id]
}

func (s *Service) broadcast(r *room, v any) {
	r.mu.Lock()
	ids := make([]string, 0, len(r.peers))
	for id, p := range r.peers {
		if p.State == "joined" || p.State == "invited" {
			ids = append(ids, id)
		}
	}
	r.mu.Unlock()
	s.hub.PublishToUsers(ids, v)
}

func (r *room) snapshot() *Room {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.snapshotLocked()
}

func (r *room) snapshotLocked() *Room {
	peers := make([]Peer, 0, len(r.peers))
	for _, p := range r.peers {
		peers = append(peers, *peerCopy(p))
	}
	out := &Room{
		ID:             r.id,
		ConversationID: r.conversationID,
		ConvType:       r.convType,
		Kind:           r.kind,
		HostID:         r.hostID,
		Status:         r.status,
		CreatedAt:      r.createdAt,
		Participants:   peers,
	}
	if r.startedAt != nil {
		t := *r.startedAt
		out.StartedAt = &t
	}
	return out
}

func peerCopy(p *Peer) *Peer {
	if p == nil {
		return nil
	}
	cp := *p
	return &cp
}

func normalizeKind(k string) string {
	switch k {
	case "voice", "video":
		return k
	default:
		return ""
	}
}

// MarshalCallBody for chat message storage helpers.
func MarshalCallBody(b CallMessageBody) ([]byte, error) {
	return json.Marshal(b)
}
