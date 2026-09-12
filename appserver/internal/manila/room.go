package manila

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"sort"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrRoomFull     = errors.New("room full")
	ErrRoomClosed   = errors.New("room closed")
	ErrNotHost      = errors.New("not host")
	ErrNotMember    = errors.New("not a member")
	ErrTooFew       = errors.New("need at least 3 players")
	ErrAlreadyStart = errors.New("already playing")
	ErrNotFound     = errors.New("room not found")
)

type Store struct {
	pool *pgxpool.Pool
}

func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{pool: pool}
}

func (s *Store) Username(ctx context.Context, userID string) (string, error) {
	var name string
	err := s.pool.QueryRow(ctx, `SELECT username FROM users WHERE id = $1`, userID).Scan(&name)
	return name, err
}

func (s *Store) InsertRoom(ctx context.Context, id, code, hostID string, maxPlayers int, private bool) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO manila_rooms (id, code, host_user_id, status, max_players, is_private)
		VALUES ($1, $2, $3, 'open', $4, $5)
	`, id, code, hostID, maxPlayers, private)
	return err
}

func (s *Store) UpdateRoomStatus(ctx context.Context, id, status string) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE manila_rooms SET status = $2, updated_at = now() WHERE id = $1
	`, id, status)
	return err
}

func (s *Store) UpdateRoomSettings(ctx context.Context, id string, maxPlayers int, private bool) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE manila_rooms
		SET max_players = $2, is_private = $3, updated_at = now()
		WHERE id = $1
	`, id, maxPlayers, private)
	return err
}

type MatchResultPlayer struct {
	UserID   string `json:"userId"`
	Username string `json:"username"`
	Rank     int    `json:"rank"`
	Fortune  int    `json:"fortune"`
}

type MatchResult struct {
	ID         string              `json:"id"`
	RoomID     string              `json:"roomId,omitempty"`
	RoomCode   string              `json:"roomCode"`
	FinishedAt string              `json:"finishedAt"`
	Players    []MatchResultPlayer `json:"players"`
	MyRank     int                 `json:"myRank,omitempty"`
	MyFortune  int                 `json:"myFortune,omitempty"`
}

func (s *Store) loadResultPlayers(ctx context.Context, out []MatchResult) error {
	byID := map[string]*MatchResult{}
	for i := range out {
		byID[out[i].ID] = &out[i]
	}
	for i := range out {
		id := out[i].ID
		prows, err := s.pool.Query(ctx, `
			SELECT user_id::text, username, rank, fortune
			FROM manila_match_result_players
			WHERE match_id = $1
			ORDER BY rank ASC
		`, id)
		if err != nil {
			return err
		}
		mr := byID[id]
		for prows.Next() {
			var p MatchResultPlayer
			if err := prows.Scan(&p.UserID, &p.Username, &p.Rank, &p.Fortune); err != nil {
				prows.Close()
				return err
			}
			mr.Players = append(mr.Players, p)
		}
		err = prows.Err()
		prows.Close()
		if err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) ListRecentResults(ctx context.Context, limit int) ([]MatchResult, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	rows, err := s.pool.Query(ctx, `
		SELECT id, COALESCE(room_id::text, ''), COALESCE(room_code, ''), finished_at
		FROM manila_match_results
		ORDER BY finished_at DESC
		LIMIT $1
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]MatchResult, 0)
	for rows.Next() {
		var mr MatchResult
		var finished time.Time
		if err := rows.Scan(&mr.ID, &mr.RoomID, &mr.RoomCode, &finished); err != nil {
			return nil, err
		}
		mr.FinishedAt = finished.UTC().Format(time.RFC3339)
		mr.Players = []MatchResultPlayer{}
		out = append(out, mr)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if err := s.loadResultPlayers(ctx, out); err != nil {
		return out, err
	}
	return out, nil
}

// ListResultsForUser 当前用户参与过的已结束对局（含全员排名）。
func (s *Store) ListResultsForUser(ctx context.Context, userID string, limit int) ([]MatchResult, error) {
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	rows, err := s.pool.Query(ctx, `
		SELECT r.id, COALESCE(r.room_id::text, ''), COALESCE(r.room_code, ''), r.finished_at,
		       p.rank, p.fortune
		FROM manila_match_results r
		JOIN manila_match_result_players p ON p.match_id = r.id
		WHERE p.user_id = $1
		ORDER BY r.finished_at DESC
		LIMIT $2
	`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]MatchResult, 0)
	for rows.Next() {
		var mr MatchResult
		var finished time.Time
		if err := rows.Scan(&mr.ID, &mr.RoomID, &mr.RoomCode, &finished, &mr.MyRank, &mr.MyFortune); err != nil {
			return nil, err
		}
		mr.FinishedAt = finished.UTC().Format(time.RFC3339)
		mr.Players = []MatchResultPlayer{}
		out = append(out, mr)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if err := s.loadResultPlayers(ctx, out); err != nil {
		return out, err
	}
	return out, nil
}

func (s *Store) SaveResult(ctx context.Context, roomID, code string, players []PlayerView) error {
	matchID := uuid.NewString()
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	_, err = tx.Exec(ctx, `
		INSERT INTO manila_match_results (id, room_id, room_code) VALUES ($1, $2, $3)
	`, matchID, roomID, code)
	if err != nil {
		return err
	}
	for _, p := range players {
		fortune, rank := 0, 0
		if p.Fortune != nil {
			fortune = *p.Fortune
		}
		if p.Rank != nil {
			rank = *p.Rank
		}
		_, err = tx.Exec(ctx, `
			INSERT INTO manila_match_result_players (match_id, user_id, username, rank, fortune)
			VALUES ($1, $2, $3, $4, $5)
		`, matchID, p.UserID, p.Username, rank, fortune)
		if err != nil {
			return err
		}
		// personal best via game_scores
		_, _ = tx.Exec(ctx, `
			INSERT INTO game_scores (game_id, user_id, score)
			SELECT 'manila', $1, $2
			WHERE $2 > COALESCE((SELECT MAX(score) FROM game_scores WHERE game_id = 'manila' AND user_id = $1), -1)
		`, p.UserID, fortune)
	}
	return tx.Commit(ctx)
}

type subscriber struct {
	ch chan []byte
}

type Room struct {
	mu          sync.Mutex
	ID          string
	Code        string
	HostUserID  string
	Status      string
	MaxPlayers  int
	IsPrivate   bool
	Members     []PlayerView
	FirstSeat   int // who opens the first auction (seat index)
	Match       *Match
	settleTimer *time.Timer
	subs        map[string][]*subscriber // userID -> conns
	store       *Store
	manager     *Manager
	createdAt   time.Time
	closedAt    time.Time
	closeReason string
	expireTimer *time.Timer
}

type Manager struct {
	mu    sync.Mutex
	rooms map[string]*Room // by id
	codes map[string]*Room // by code
	store *Store
}

func NewManager(store *Store) *Manager {
	return &Manager{
		rooms: map[string]*Room{},
		codes: map[string]*Room{},
		store: store,
	}
}

// RoomMaxAge: 房间自创建起超过此时长则强制结束并移出内存。
const RoomMaxAge = time.Hour

func (m *Manager) armExpire(r *Room) {
	id := r.ID
	r.expireTimer = time.AfterFunc(RoomMaxAge, func() {
		_ = m.ForceClose(id, "timeout")
	})
}

func (m *Manager) removeRoom(r *Room) {
	r.mu.Lock()
	if r.expireTimer != nil {
		r.expireTimer.Stop()
		r.expireTimer = nil
	}
	r.mu.Unlock()

	m.mu.Lock()
	defer m.mu.Unlock()
	if cur, ok := m.rooms[r.ID]; !ok || cur != r {
		return
	}
	delete(m.rooms, r.ID)
	delete(m.codes, r.Code)
}

// AdminRoomInfo 管理端房间视图（含私密与对局摘要）。
type AdminRoomInfo struct {
	ID           string   `json:"id"`
	Code         string   `json:"code"`
	Status       string   `json:"status"`
	HostUserID   string   `json:"hostUserId"`
	HostUsername string   `json:"hostUsername"`
	MaxPlayers   int      `json:"maxPlayers"`
	IsPrivate    bool     `json:"isPrivate"`
	MemberCount  int      `json:"memberCount"`
	Members      []string `json:"members"`
	Phase        string   `json:"phase,omitempty"`
	Voyage       int      `json:"voyage,omitempty"`
	CreatedAt    string   `json:"createdAt"`
	AgeSeconds   int      `json:"ageSeconds"`
	CloseReason  string   `json:"closeReason,omitempty"`
}

func (m *Manager) AdminList() []AdminRoomInfo {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := time.Now()
	out := make([]AdminRoomInfo, 0, len(m.rooms))
	for _, r := range m.rooms {
		r.mu.Lock()
		hostName := ""
		names := make([]string, 0, len(r.Members))
		for _, mem := range r.Members {
			names = append(names, mem.Username)
			if mem.UserID == r.HostUserID {
				hostName = mem.Username
			}
		}
		info := AdminRoomInfo{
			ID: r.ID, Code: r.Code, Status: r.Status, HostUserID: r.HostUserID,
			HostUsername: hostName, MaxPlayers: r.MaxPlayers, IsPrivate: r.IsPrivate,
			MemberCount: len(r.Members), Members: names,
			CreatedAt: r.createdAt.UTC().Format(time.RFC3339),
			AgeSeconds: int(now.Sub(r.createdAt).Seconds()),
			CloseReason: r.closeReason,
		}
		if r.Match != nil {
			info.Phase = string(r.Match.Phase)
			info.Voyage = r.Match.Voyage
		}
		r.mu.Unlock()
		out = append(out, info)
	}
	return out
}

// ForceClose 强制结束对局并从内存移除（timeout / admin）。
func (m *Manager) ForceClose(roomID, reason string) error {
	m.mu.Lock()
	r := m.rooms[roomID]
	m.mu.Unlock()
	if r == nil {
		return ErrNotFound
	}
	r.mu.Lock()
	if r.Status == "closed" {
		r.closeReason = reason
		r.closedAt = time.Now()
		r.mu.Unlock()
		m.removeRoom(r)
		return nil
	}
	wasPlaying := r.Status == "playing" && r.Match != nil
	r.Status = "closed"
	r.closeReason = reason
	r.closedAt = time.Now()
	if wasPlaying && r.Match != nil {
		r.Match.Phase = PhaseGameOver
	}
	r.broadcastLocked()
	id := r.ID
	r.mu.Unlock()

	go func() {
		_ = r.store.UpdateRoomStatus(context.Background(), id, "closed")
	}()
	m.removeRoom(r)
	return nil
}

func randomCode() string {
	b := make([]byte, 3)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func (m *Manager) Create(ctx context.Context, hostID, hostName string, maxPlayers int, private bool) (*Room, error) {
	if maxPlayers < 3 {
		maxPlayers = 3
	}
	if maxPlayers > 5 {
		maxPlayers = 5
	}
	id := uuid.NewString()
	code := randomCode()
	for i := 0; i < 8; i++ {
		m.mu.Lock()
		_, exists := m.codes[code]
		m.mu.Unlock()
		if !exists {
			break
		}
		code = randomCode()
	}
	if err := m.store.InsertRoom(ctx, id, code, hostID, maxPlayers, private); err != nil {
		return nil, err
	}
	r := &Room{
		ID: id, Code: code, HostUserID: hostID, Status: "open",
		MaxPlayers: maxPlayers, IsPrivate: private,
		Members: []PlayerView{{
			UserID: hostID, Username: hostName, Seat: 0, IsHost: true, Connected: true, Ready: false,
		}},
		subs: map[string][]*subscriber{}, store: m.store, manager: m, createdAt: time.Now(),
	}
	m.armExpire(r)
	m.mu.Lock()
	m.rooms[id] = r
	m.codes[code] = r
	m.mu.Unlock()
	return r, nil
}

func (m *Manager) GetByCode(code string) *Room {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.codes[code]
}

func (m *Manager) GetByID(id string) *Room {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.rooms[id]
}

func (m *Manager) ListOpen() []RoomPublic {
	return m.ListLobby("")
}

// ListLobby returns public open/playing rooms, plus any room the viewer has joined
// (including private). Sets Joined when userID is a member.
func (m *Manager) ListLobby(userID string) []RoomPublic {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]RoomPublic, 0)
	for _, r := range m.rooms {
		r.mu.Lock()
		isMember := false
		if userID != "" {
			for i := range r.Members {
				if r.Members[i].UserID == userID {
					isMember = true
					break
				}
			}
		}
		live := r.Status == "open" || r.Status == "playing"
		showPublic := !r.IsPrivate && live
		showMine := isMember && live
		if showPublic || showMine {
			pub := r.snapshotLocked()
			pub.Joined = isMember
			out = append(out, pub)
		}
		r.mu.Unlock()
	}
	return out
}

func (r *Room) snapshotLocked() RoomPublic {
	mem := append([]PlayerView{}, r.Members...)
	sort.SliceStable(mem, func(i, j int) bool { return mem[i].Seat < mem[j].Seat })
	return RoomPublic{
		ID: r.ID, Code: r.Code, HostUserID: r.HostUserID, Status: r.Status,
		MaxPlayers: r.MaxPlayers, IsPrivate: r.IsPrivate, Members: mem,
		FirstSeat: r.FirstSeat, Match: nil,
	}
}

func (r *Room) snapshotForLocked(viewerID string) RoomPublic {
	pub := r.snapshotLocked()
	if r.Match != nil {
		pub.Match = r.Match.PublicFor(viewerID)
	}
	return pub
}

func (r *Room) Public() RoomPublic {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.snapshotLocked()
}

func (r *Room) PublicFor(viewerID string) RoomPublic {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.snapshotForLocked(viewerID)
}

func (r *Room) Join(userID, username string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	for i := range r.Members {
		if r.Members[i].UserID == userID {
			// 原成员随时可重连（含对局中）
			r.Members[i].Connected = true
			r.Members[i].Username = username
			if r.Match != nil {
				if p := r.Match.playerByID(userID); p != nil {
					p.Connected = true
					p.Username = username
				}
			}
			return nil
		}
	}
	if r.Status != "open" {
		return ErrRoomClosed
	}
	if len(r.Members) >= r.MaxPlayers {
		return ErrRoomFull
	}
	seat := r.firstEmptySeatLocked()
	if seat < 0 {
		return ErrRoomFull
	}
	r.Members = append(r.Members, PlayerView{
		UserID: userID, Username: username, Seat: seat,
		Connected: true, Ready: false, IsHost: userID == r.HostUserID,
	})
	return nil
}

func (r *Room) SetReady(userID string, ready bool) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	for i := range r.Members {
		if r.Members[i].UserID == userID {
			r.Members[i].Ready = ready
			return nil
		}
	}
	return ErrNotMember
}

func (r *Room) Leave(userID string) {
	r.mu.Lock()
	dissolved := r.leaveLocked(userID)
	r.mu.Unlock()
	if dissolved {
		r.persistAndRemoveClosed()
	}
}

func (r *Room) Kick(hostID, targetID string) error {
	r.mu.Lock()
	if hostID != r.HostUserID {
		r.mu.Unlock()
		return ErrNotHost
	}
	if r.Status != "open" {
		r.mu.Unlock()
		return ErrAlreadyStart
	}
	out := r.Members[:0]
	for _, m := range r.Members {
		if m.UserID != targetID {
			out = append(out, m)
		}
	}
	r.Members = out
	r.clampLobbySeatsLocked()
	dissolved := r.dissolveWaitingIfEmptyLocked()
	r.mu.Unlock()
	if dissolved {
		r.persistAndRemoveClosed()
	}
	return nil
}

func (r *Room) Start(hostID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.startLocked(hostID)
}

func (r *Room) Subscribe(userID string) (<-chan []byte, func()) {
	r.mu.Lock()
	defer r.mu.Unlock()
	sub := &subscriber{ch: make(chan []byte, 16)}
	r.subs[userID] = append(r.subs[userID], sub)
	for i := range r.Members {
		if r.Members[i].UserID == userID {
			r.Members[i].Connected = true
		}
	}
	if r.Match != nil {
		if p := r.Match.playerByID(userID); p != nil {
			p.Connected = true
		}
	}
	unsub := func() {
		var dissolved bool
		r.mu.Lock()
		list := r.subs[userID]
		out := list[:0]
		for _, s := range list {
			if s != sub {
				out = append(out, s)
			}
		}
		if len(out) == 0 {
			delete(r.subs, userID)
			if r.Status == "open" {
				// 候场断线视为离开；最后一人离开则房间失效
				wasHost := userID == r.HostUserID
				kept := r.Members[:0]
				for _, m := range r.Members {
					if m.UserID != userID {
						kept = append(kept, m)
					}
				}
				r.Members = kept
				r.clampLobbySeatsLocked()
				if len(r.Members) > 0 && wasHost {
					r.promoteHostLocked()
				} else {
					r.syncHostFlagsLocked()
				}
				dissolved = r.dissolveWaitingIfEmptyLocked()
				r.broadcastLocked()
			} else {
				for i := range r.Members {
					if r.Members[i].UserID == userID {
						r.Members[i].Connected = false
					}
				}
				if r.Match != nil {
					if p := r.Match.playerByID(userID); p != nil {
						p.Connected = false
					}
				}
				r.broadcastLocked()
			}
		} else {
			r.subs[userID] = out
		}
		r.mu.Unlock()
		close(sub.ch)
		if dissolved {
			r.persistAndRemoveClosed()
		}
	}
	return sub.ch, unsub
}

func (r *Room) Broadcast() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.broadcastLocked()
}

func (r *Room) broadcastLocked() {
	for userID, list := range r.subs {
		payload, err := encodeState(r.snapshotForLocked(userID))
		if err != nil {
			continue
		}
		for _, s := range list {
			select {
			case s.ch <- payload:
			default:
			}
		}
	}
}

func (r *Room) WithLock(fn func()) {
	r.mu.Lock()
	defer r.mu.Unlock()
	fn()
	r.broadcastLocked()
}

func (r *Room) ApplyAction(userID string, msg map[string]any) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	typ, _ := msg["type"].(string)
	var err error
	switch typ {
	case "ready":
		ready, _ := msg["ready"].(bool)
		for i := range r.Members {
			if r.Members[i].UserID == userID {
				r.Members[i].Ready = ready
			}
		}
	case "start":
		err = r.startLocked(userID)
	case "kick":
		tid, _ := msg["userId"].(string)
		err = r.kickLocked(userID, tid)
	case "settings":
		maxPlayers, hasMax := asInt(msg["maxPlayers"])
		private, hasPrivate := msg["private"].(bool)
		if !hasPrivate {
			if v, ok := msg["isPrivate"].(bool); ok {
				private, hasPrivate = v, true
			}
		}
		err = r.settingsLocked(userID, maxPlayers, hasMax, private, hasPrivate)
	case "claim_seat":
		seat, _ := asInt(msg["seat"])
		err = r.claimSeatLocked(userID, seat)
	case "swap_seat":
		seat, _ := asInt(msg["seat"])
		err = r.swapWithSeatLocked(userID, seat)
	case "set_first_seat":
		seat, _ := asInt(msg["seat"])
		err = r.setFirstSeatLocked(userID, seat)
	case "leave":
		_ = r.leaveLocked(userID)
	case "auction_bid":
		amount, _ := asInt(msg["amount"])
		if r.Match == nil {
			err = ErrBadPhase
		} else {
			err = r.Match.AuctionBid(userID, amount)
		}
	case "auction_pass":
		if r.Match == nil {
			err = ErrBadPhase
		} else {
			err = r.Match.AuctionPass(userID)
		}
	case "buy_share":
		if r.Match == nil {
			err = ErrBadPhase
		} else {
			ware, _ := msg["ware"].(string)
			skip, _ := msg["skip"].(bool)
			err = r.Match.BuyShare(userID, Ware(ware), skip)
		}
	case "load_wares":
		if r.Match == nil {
			err = ErrBadPhase
		} else {
			raw, _ := msg["wares"].([]any)
			wares := make([]Ware, 0, 3)
			for _, v := range raw {
				s, _ := v.(string)
				wares = append(wares, Ware(s))
			}
			err = r.Match.LoadWares(userID, wares)
		}
	case "place_punts":
		if r.Match == nil {
			err = ErrBadPhase
		} else {
			raw, _ := msg["positions"].([]any)
			pos := make([]int, 0, 3)
			for _, v := range raw {
				n, _ := asInt(v)
				pos = append(pos, n)
			}
			err = r.Match.PlacePunts(userID, pos)
		}
	case "place":
		if r.Match == nil {
			err = ErrBadPhase
		} else {
			slot, _ := msg["slotId"].(string)
			err = r.Match.PlaceAccomplice(userID, slot)
		}
	case "pass_place":
		if r.Match == nil {
			err = ErrBadPhase
		} else {
			err = r.Match.PassPlace(userID)
		}
	case "roll_dice":
		if r.Match == nil {
			err = ErrBadPhase
		} else {
			err = r.Match.RollDice(userID)
		}
	case "pirate_board":
		if r.Match == nil {
			err = ErrBadPhase
		} else {
			pi, _ := asInt(msg["punt"])
			skip, _ := msg["skip"].(bool)
			displace := -1
			if raw, ok := msg["displaceSeat"]; ok {
				displace, _ = asInt(raw)
			}
			err = r.Match.PirateBoard(userID, pi, skip, displace)
		}
	case "pilot":
		if r.Match == nil {
			err = ErrBadPhase
		} else {
			skip, _ := msg["skip"].(bool)
			var moves []PilotMove
			if raw, ok := msg["moves"].([]any); ok {
				for _, v := range raw {
					mm, _ := v.(map[string]any)
					p, _ := asInt(mm["punt"])
					d, _ := asInt(mm["delta"])
					moves = append(moves, PilotMove{Punt: p, Delta: d})
				}
			}
			err = r.Match.PilotAct(userID, moves, skip)
		}
	case "pirate_plunder":
		if r.Match == nil {
			err = ErrBadPhase
		} else {
			dec := map[int]bool{}
			if raw, ok := msg["toPort"].(map[string]any); ok {
				for k, v := range raw {
					var idx int
					fmt.Sscanf(k, "%d", &idx)
					b, _ := v.(bool)
					dec[idx] = b
				}
			}
			if raw, ok := msg["decisions"].([]any); ok {
				for _, v := range raw {
					mm, _ := v.(map[string]any)
					p, _ := asInt(mm["punt"])
					tp, _ := mm["toPort"].(bool)
					dec[p] = tp
				}
			}
			err = r.Match.PiratePlunderDecide(userID, dec)
		}
	case "loan":
		if r.Match == nil {
			err = ErrBadPhase
		} else {
			ware, _ := msg["ware"].(string)
			err = r.Match.Loan(userID, Ware(ware))
		}
	case "cancel_loan":
		if r.Match == nil {
			err = ErrBadPhase
		} else {
			ware, _ := msg["ware"].(string)
			err = r.Match.CancelLoan(userID, Ware(ware))
		}
	case "repay":
		if r.Match == nil {
			err = ErrBadPhase
		} else {
			ware, _ := msg["ware"].(string)
			err = r.Match.Repay(userID, Ware(ware))
		}
	default:
		err = ErrBadAction
	}
	if err == nil {
		r.armSettleIfNeededLocked()
		r.broadcastLocked()
		if r.Match != nil && r.Match.Phase == PhaseGameOver {
			pub := r.Match.Public()
			r.Status = "closed"
			r.closedAt = time.Now()
			r.closeReason = "finished"
			mgr := r.manager
			go func() {
				_ = r.store.SaveResult(context.Background(), r.ID, r.Code, pub.Players)
				_ = r.store.UpdateRoomStatus(context.Background(), r.ID, "closed")
				if mgr != nil {
					mgr.removeRoom(r)
				}
			}()
		} else if r.Status == "closed" && r.closeReason == "empty" {
			r.persistAndRemoveClosed()
		}
	}
	return err
}

// SettlePause base; actual wait scales with settlement line count.
const SettlePauseBase = 4 * time.Second
const SettlePausePerLine = 2200 * time.Millisecond
const SettlePauseMax = 36 * time.Second

func (r *Room) armSettleIfNeededLocked() {
	if r.Match == nil || r.Match.Phase != PhaseSettle {
		return
	}
	if r.settleTimer != nil {
		return
	}
	n := len(r.Match.Settlement)
	pause := SettlePauseBase + time.Duration(n)*SettlePausePerLine
	if pause > SettlePauseMax {
		pause = SettlePauseMax
	}
	r.settleTimer = time.AfterFunc(pause, func() {
		r.mu.Lock()
		defer r.mu.Unlock()
		r.settleTimer = nil
		if r.Match == nil || r.Match.Phase != PhaseSettle {
			return
		}
		r.Match.AdvanceFromSettle()
		r.broadcastLocked()
		if r.Match != nil && r.Match.Phase == PhaseGameOver {
			pub := r.Match.Public()
			r.Status = "closed"
			r.closedAt = time.Now()
			r.closeReason = "finished"
			mgr := r.manager
			go func() {
				_ = r.store.SaveResult(context.Background(), r.ID, r.Code, pub.Players)
				_ = r.store.UpdateRoomStatus(context.Background(), r.ID, "closed")
				if mgr != nil {
					mgr.removeRoom(r)
				}
			}()
		}
	})
}

func (r *Room) startLocked(hostID string) error {
	if hostID != r.HostUserID {
		return ErrNotHost
	}
	if r.Status != "open" {
		return ErrAlreadyStart
	}
	if len(r.Members) < 3 {
		return ErrTooFew
	}
	for _, m := range r.Members {
		if m.UserID != r.HostUserID && !m.Ready {
			return fmt.Errorf("players not ready")
		}
	}
	for i := range r.Members {
		if r.Members[i].UserID == r.HostUserID {
			r.Members[i].Ready = true
		}
	}
	r.clampLobbySeatsLocked()
	// Match turn order follows seat numbers; host identity stays HostUserID.
	mem := append([]PlayerView{}, r.Members...)
	sort.SliceStable(mem, func(i, j int) bool { return mem[i].Seat < mem[j].Seat })
	firstIdx := 0
	for i, m := range mem {
		if m.Seat == r.FirstSeat {
			firstIdx = i
			break
		}
	}
	for i := range mem {
		mem[i].Seat = i
		mem[i].IsHost = mem[i].UserID == r.HostUserID
		mem[i].Connected = true
	}
	r.Match = NewMatchWithStart(mem, nil, firstIdx)
	r.Status = "playing"
	go func() { _ = r.store.UpdateRoomStatus(context.Background(), r.ID, "playing") }()
	return nil
}

// syncHostFlagsLocked keeps IsHost in sync with HostUserID (never derived from seat).
func (r *Room) syncHostFlagsLocked() {
	for i := range r.Members {
		r.Members[i].IsHost = r.Members[i].UserID == r.HostUserID
	}
}

func (r *Room) seatOccupiedLocked(seat int) bool {
	for _, m := range r.Members {
		if m.Seat == seat {
			return true
		}
	}
	return false
}

func (r *Room) firstEmptySeatLocked() int {
	for s := 0; s < r.MaxPlayers; s++ {
		if !r.seatOccupiedLocked(s) {
			return s
		}
	}
	return -1
}

// clampLobbySeatsLocked keeps FirstSeat on an occupied pad; does not renumber seats.
func (r *Room) clampLobbySeatsLocked() {
	if len(r.Members) == 0 {
		r.FirstSeat = 0
		r.syncHostFlagsLocked()
		return
	}
	if r.seatOccupiedLocked(r.FirstSeat) {
		r.syncHostFlagsLocked()
		return
	}
	best := -1
	for _, m := range r.Members {
		if best < 0 || m.Seat < best {
			best = m.Seat
		}
	}
	if best < 0 {
		r.FirstSeat = 0
	} else {
		r.FirstSeat = best
	}
	r.syncHostFlagsLocked()
}

// claimSeatLocked lets any member sit on an empty lobby pad (livestream-style).
func (r *Room) claimSeatLocked(userID string, seat int) error {
	if r.Status != "open" {
		return ErrAlreadyStart
	}
	if seat < 0 || seat >= r.MaxPlayers {
		return ErrBadAction
	}
	me := -1
	for i, m := range r.Members {
		if m.UserID == userID {
			me = i
		}
		if m.Seat == seat && m.UserID != userID {
			return ErrSlotTaken
		}
	}
	if me < 0 {
		return ErrNotMember
	}
	if r.Members[me].Seat == seat {
		return nil
	}
	r.Members[me].Seat = seat
	r.Members[me].Ready = false // changing seat clears ready, like switching mic seats
	r.syncHostFlagsLocked()
	return nil
}

// swapWithSeatLocked swaps the caller's seat with whoever sits on targetSeat.
func (r *Room) swapWithSeatLocked(userID string, targetSeat int) error {
	if r.Status != "open" {
		return ErrAlreadyStart
	}
	if targetSeat < 0 || targetSeat >= r.MaxPlayers {
		return ErrBadAction
	}
	me := -1
	other := -1
	for i, m := range r.Members {
		if m.UserID == userID {
			me = i
		}
		if m.Seat == targetSeat {
			other = i
		}
	}
	if me < 0 {
		return ErrNotMember
	}
	if other < 0 {
		return fmt.Errorf("%w: seat empty, claim instead", ErrBadAction)
	}
	if me == other {
		return nil
	}
	a, b := r.Members[me].Seat, r.Members[other].Seat
	r.Members[me].Seat, r.Members[other].Seat = b, a
	r.Members[me].Ready = false
	r.Members[other].Ready = false
	r.syncHostFlagsLocked()
	return nil
}

func (r *Room) setFirstSeatLocked(hostID string, seat int) error {
	if hostID != r.HostUserID {
		return ErrNotHost
	}
	if r.Status != "open" {
		return ErrAlreadyStart
	}
	if seat < 0 || seat >= r.MaxPlayers {
		return ErrBadAction
	}
	if !r.seatOccupiedLocked(seat) {
		return fmt.Errorf("%w: seat empty", ErrBadAction)
	}
	r.FirstSeat = seat
	r.syncHostFlagsLocked()
	return nil
}

func (r *Room) promoteHostLocked() {
	if len(r.Members) == 0 {
		r.HostUserID = ""
		return
	}
	// Succession follows join order (Members slice), never seat number.
	r.HostUserID = r.Members[0].UserID
	r.syncHostFlagsLocked()
}

func (r *Room) kickLocked(hostID, targetID string) error {
	if hostID != r.HostUserID {
		return ErrNotHost
	}
	if r.Status != "open" {
		return ErrAlreadyStart
	}
	out := r.Members[:0]
	for _, m := range r.Members {
		if m.UserID != targetID {
			out = append(out, m)
		}
	}
	r.Members = out
	r.clampLobbySeatsLocked()
	_ = r.dissolveWaitingIfEmptyLocked()
	return nil
}

func (r *Room) settingsLocked(hostID string, maxPlayers int, hasMax, private, hasPrivate bool) error {
	if hostID != r.HostUserID {
		return ErrNotHost
	}
	if r.Status != "open" {
		return ErrAlreadyStart
	}
	if !hasMax && !hasPrivate {
		return ErrBadAction
	}
	nextMax := r.MaxPlayers
	if hasMax {
		if maxPlayers < 3 {
			maxPlayers = 3
		}
		if maxPlayers > 5 {
			maxPlayers = 5
		}
		if maxPlayers < len(r.Members) {
			return fmt.Errorf("max players cannot be below current members (%d)", len(r.Members))
		}
		nextMax = maxPlayers
	}
	nextPrivate := r.IsPrivate
	if hasPrivate {
		nextPrivate = private
	}
	r.MaxPlayers = nextMax
	r.IsPrivate = nextPrivate
	// If seats were beyond new max, move them into empty lower pads.
	for i := range r.Members {
		if r.Members[i].Seat < nextMax {
			continue
		}
		empty := -1
		for s := 0; s < nextMax; s++ {
			taken := false
			for _, m := range r.Members {
				if m.Seat == s && m.UserID != r.Members[i].UserID {
					taken = true
					break
				}
			}
			if !taken {
				empty = s
				break
			}
		}
		if empty >= 0 {
			r.Members[i].Seat = empty
		}
	}
	r.clampLobbySeatsLocked()
	go func() {
		_ = r.store.UpdateRoomSettings(context.Background(), r.ID, nextMax, nextPrivate)
	}()
	return nil
}

func (r *Room) leaveLocked(userID string) (dissolved bool) {
	if r.Status == "playing" {
		for i := range r.Members {
			if r.Members[i].UserID == userID {
				r.Members[i].Connected = false
			}
		}
		if r.Match != nil {
			if p := r.Match.playerByID(userID); p != nil {
				p.Connected = false
			}
		}
		return false
	}
	if r.Status != "open" {
		return false
	}
	wasHost := userID == r.HostUserID
	out := r.Members[:0]
	for _, m := range r.Members {
		if m.UserID != userID {
			out = append(out, m)
		}
	}
	r.Members = out
	r.clampLobbySeatsLocked()
	if wasHost && len(r.Members) > 0 {
		r.promoteHostLocked()
	} else {
		r.syncHostFlagsLocked()
	}
	return r.dissolveWaitingIfEmptyLocked()
}

// dissolveWaitingIfEmptyLocked closes an open (lobby) room when no members remain.
// Playing rooms are never dissolved here.
func (r *Room) dissolveWaitingIfEmptyLocked() bool {
	if r.Status != "open" || len(r.Members) > 0 {
		return false
	}
	r.Status = "closed"
	r.closeReason = "empty"
	r.closedAt = time.Now()
	return true
}

func (r *Room) persistAndRemoveClosed() {
	mgr := r.manager
	id := r.ID
	store := r.store
	go func() {
		if store != nil {
			_ = store.UpdateRoomStatus(context.Background(), id, "closed")
		}
		if mgr != nil {
			mgr.removeRoom(r)
		}
	}()
}

func asInt(v any) (int, bool) {
	switch n := v.(type) {
	case float64:
		return int(n), true
	case int:
		return n, true
	case int64:
		return int(n), true
	default:
		return 0, false
	}
}
