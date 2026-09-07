package chat

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/keller-cc/ihope/appserver/internal/crypto"
)

type Conversation struct {
	ID                      string  `json:"id"`
	Type                    string  `json:"type"`
	Title                   string  `json:"title"`
	CreatedAt               string  `json:"createdAt"`
	PeerUsername            string  `json:"peerUsername,omitempty"`
	PeerAvatarURL           *string `json:"peerAvatarUrl,omitempty"`
	MemberCount             int     `json:"memberCount,omitempty"`
	LastMessage             string  `json:"lastMessage,omitempty"`
	LastMessageAt           string  `json:"lastMessageAt,omitempty"`
	UnreadCount             int     `json:"unreadCount"`
	GroupNo                 *string `json:"groupNo,omitempty"`
	OwnerID                 *string `json:"ownerId,omitempty"`
	IsOwner                 bool    `json:"isOwner,omitempty"`
	IsAdmin                 bool    `json:"isAdmin,omitempty"`
	Pinned                  bool    `json:"pinned"`
	Muted                   bool    `json:"muted"`
	PinnedAt                *string `json:"pinnedAt,omitempty"`
	AvatarURL               *string `json:"avatarUrl,omitempty"`
	Joined                  bool    `json:"joined,omitempty"`
	JoinMode                string  `json:"joinMode,omitempty"` // anyone | verify | deny
	InviteRequiresApproval  bool    `json:"inviteRequiresApproval"` // legacy: true when joinMode=verify
	Announcement            string  `json:"announcement"` // latest body preview for settings
	AnnouncementCount       int     `json:"announcementCount,omitempty"`
	PendingAnnouncement     *GroupAnnouncement `json:"pendingAnnouncement,omitempty"`
	AnnouncementUpdatedAt   *string `json:"announcementUpdatedAt,omitempty"` // legacy
	AnnouncementUpdatedBy   *string `json:"announcementUpdatedBy,omitempty"` // legacy
	AnnouncementAuthorName  string  `json:"announcementAuthorName,omitempty"` // legacy
	Removed                 bool    `json:"removed,omitempty"`
	RemoveReason            string  `json:"removeReason,omitempty"`
}

const (
	JoinModeAnyone = "anyone"
	JoinModeVerify = "verify"
	JoinModeDeny   = "deny"
)

func normalizeJoinMode(mode string) string {
	switch strings.TrimSpace(mode) {
	case JoinModeAnyone, JoinModeVerify, JoinModeDeny:
		return strings.TrimSpace(mode)
	default:
		return JoinModeVerify
	}
}

func applyJoinMode(c *Conversation, mode string) {
	c.JoinMode = normalizeJoinMode(mode)
	c.InviteRequiresApproval = c.JoinMode == JoinModeVerify
}

type FriendRequest struct {
	ID         string   `json:"id"`
	FromUserID string   `json:"fromUserId"`
	ToUserID   string   `json:"toUserId"`
	Status     string   `json:"status"`
	Message    string   `json:"message"`
	CreatedAt  string   `json:"createdAt"`
	FromUser   *Contact `json:"fromUser,omitempty"`
	ToUser     *Contact `json:"toUser,omitempty"`
}

type GroupJoinRequest struct {
	ID             string        `json:"id"`
	ConversationID string        `json:"conversationId"`
	FromUserID     string        `json:"fromUserId"`
	Status         string        `json:"status"`
	Message        string        `json:"message"`
	CreatedAt      string        `json:"createdAt"`
	FromUser       *Contact      `json:"fromUser,omitempty"`
	InvitedBy      *Contact      `json:"invitedBy,omitempty"`
	Group          *Conversation `json:"group,omitempty"`
}

// JoinGroupResult: joined 已入群；pending 等待管理员同意。
type JoinGroupResult struct {
	Status       string            `json:"status"` // joined | pending
	NewlyJoined  bool              `json:"-"`
	Conversation *Conversation    `json:"conversation,omitempty"`
	Request      *GroupJoinRequest `json:"request,omitempty"`
}

// InviteResult: added 为直接入群人数；pending 为需管理员审批的邀请数。
type InviteResult struct {
	Conversation *Conversation `json:"conversation"`
	Added        int           `json:"added"`
	Pending      int           `json:"pending"`
	AddedNames   []string      `json:"addedNames,omitempty"`
}

type Message struct {
	ID              string  `json:"id"`
	ConversationID  string  `json:"conversationId"`
	SenderID        string  `json:"senderId"`
	SenderUsername  string  `json:"senderUsername,omitempty"`
	SenderAvatarURL *string `json:"senderAvatarUrl,omitempty"`
	SenderTitle     string  `json:"senderTitle,omitempty"`
	Type            string  `json:"type"`
	Body            string  `json:"body"`
	CreatedAt       string  `json:"createdAt"`
	Recalled        bool    `json:"recalled,omitempty"`
	RecalledAt      *string `json:"recalledAt,omitempty"`
	RecalledBy      *string `json:"recalledBy,omitempty"`
}

type Contact struct {
	ID          string  `json:"id"`
	Username    string  `json:"username"`
	Email       string  `json:"email,omitempty"`
	HopeID      *string `json:"hopeId,omitempty"`
	AvatarURL   *string `json:"avatarUrl,omitempty"`
	Remark      string  `json:"remark,omitempty"`
	IsFriend    bool    `json:"isFriend,omitempty"`
	Role        string  `json:"role,omitempty"`
	IsAdmin     bool    `json:"isAdmin,omitempty"`
	MemberTitle string  `json:"memberTitle,omitempty"`
}

type PublicUser struct {
	ID        string  `json:"id"`
	Username  string  `json:"username"`
	HopeID    *string `json:"hopeId,omitempty"`
	AvatarURL *string `json:"avatarUrl,omitempty"`
	IsFriend  bool    `json:"isFriend"`
	IsSelf    bool    `json:"isSelf"`
}

type PublicGroup struct {
	ID          string  `json:"id"`
	Title       string  `json:"title"`
	GroupNo     *string `json:"groupNo,omitempty"`
	MemberCount int     `json:"memberCount"`
	AvatarURL   *string `json:"avatarUrl,omitempty"`
	Joined      bool    `json:"joined"`
	JoinPending bool    `json:"joinPending"`
	JoinMode    string  `json:"joinMode"` // anyone | verify | deny
}

type Service struct {
	pool *pgxpool.Pool
	key  []byte
}

func NewService(pool *pgxpool.Pool, messageKey []byte) *Service {
	return &Service{pool: pool, key: messageKey}
}

func (s *Service) ListConversations(ctx context.Context, userID string) ([]Conversation, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT c.id::text, c.type, c.title, c.created_at::text,
			COALESCE((
				SELECT u.username FROM conversation_members cm
				JOIN users u ON u.id = cm.user_id
				WHERE cm.conversation_id = c.id AND cm.user_id <> $1
				LIMIT 1
			), ''),
			COALESCE((
				SELECT COALESCE(f.remark, '') FROM conversation_members cm
				JOIN users u ON u.id = cm.user_id
				LEFT JOIN friendships f ON f.user_id = $1 AND f.friend_id = u.id
				WHERE cm.conversation_id = c.id AND cm.user_id <> $1
				LIMIT 1
			), ''),
			(
				SELECT u.avatar_url FROM conversation_members cm
				JOIN users u ON u.id = cm.user_id
				WHERE cm.conversation_id = c.id AND cm.user_id <> $1
				LIMIT 1
			),
			(SELECT COUNT(*)::int FROM conversation_members cm2
			 WHERE cm2.conversation_id = c.id AND cm2.removed_at IS NULL),
			COALESCE((
				SELECT m.type FROM messages m
				WHERE m.conversation_id = c.id
				ORDER BY m.created_at DESC LIMIT 1
			), ''),
			COALESCE((
				SELECT m.body_sealed FROM messages m
				WHERE m.conversation_id = c.id
				ORDER BY m.created_at DESC LIMIT 1
			), ''),
			COALESCE((
				SELECT (m.recalled_at IS NOT NULL) FROM messages m
				WHERE m.conversation_id = c.id
				ORDER BY m.created_at DESC LIMIT 1
			), FALSE),
			COALESCE((
				SELECT m.created_at::text FROM messages m
				WHERE m.conversation_id = c.id
				ORDER BY m.created_at DESC LIMIT 1
			), ''),
			COALESCE((
				SELECT COUNT(*)::int FROM messages m
				WHERE m.conversation_id = c.id
				  AND m.sender_id <> $1
				  AND m.created_at > COALESCE(mem.last_read_at, '1970-01-01'::timestamptz)
			), 0),
			c.group_no,
			c.owner_id::text,
			mem.muted,
			mem.pinned_at::text,
			c.avatar_url,
			COALESCE(mem.role, 'member'),
			COALESCE(NULLIF(c.join_mode, ''), 'verify'),
			mem.removed_at IS NOT NULL,
			COALESCE(mem.remove_reason, ''),
			COALESCE((
				SELECT m.created_at FROM messages m
				WHERE m.conversation_id = c.id
				ORDER BY m.created_at DESC LIMIT 1
			), c.created_at) AS sort_at
		FROM conversations c
		JOIN conversation_members mem ON mem.conversation_id = c.id AND mem.user_id = $1
		WHERE mem.hidden_at IS NULL
		ORDER BY mem.pinned_at DESC NULLS LAST, sort_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Conversation
	for rows.Next() {
		var c Conversation
		var sealed string
		var lastType string
		var lastRecalled bool
		var sortAt any
		var ownerID *string
		var pinnedAt *string
		var peerAvatar *string
		var myRole string
		var peerRemark string
		var removed bool
		var removeReason string
		var joinMode string
		if err := rows.Scan(
			&c.ID, &c.Type, &c.Title, &c.CreatedAt, &c.PeerUsername, &peerRemark, &peerAvatar, &c.MemberCount,
			&lastType, &sealed, &lastRecalled, &c.LastMessageAt, &c.UnreadCount, &c.GroupNo, &ownerID,
			&c.Muted, &pinnedAt, &c.AvatarURL, &myRole,
			&joinMode, &removed, &removeReason, &sortAt,
		); err != nil {
			return nil, err
		}
		applyJoinMode(&c, joinMode)
		c.OwnerID = ownerID
		c.PinnedAt = pinnedAt
		c.Pinned = pinnedAt != nil && *pinnedAt != ""
		c.PeerAvatarURL = peerAvatar
		c.Removed = removed
		c.RemoveReason = removeReason
		if c.Type == "dm" {
			c.AvatarURL = peerAvatar
		}
		if ownerID != nil && *ownerID == userID {
			c.IsOwner = true
		}
		if myRole == "admin" {
			c.IsAdmin = true
		}
		if c.Type == "dm" && c.PeerUsername != "" {
			// title = 备注优先，否则原用户名（列表/顶栏展示）；peerUsername 始终为原名
			if strings.TrimSpace(peerRemark) != "" {
				c.Title = strings.TrimSpace(peerRemark)
			} else {
				c.Title = c.PeerUsername
			}
		}
		if sealed != "" || lastRecalled {
			if lastRecalled {
				c.LastMessage = "[消息已撤回]"
			} else if lastType == "image" {
				c.LastMessage = "[图片]"
			} else if lastType == "file" {
				c.LastMessage = "[文件]"
			} else if lastType == "voice" {
				c.LastMessage = "[语音]"
			} else if lastType == "call" {
				c.LastMessage = "[通话]"
			} else if lastType == "forward" {
				c.LastMessage = "[聊天记录]"
			} else if lastType == "system" {
				plain, err := crypto.Open(s.key, sealed)
				if err != nil {
					c.LastMessage = "[系统消息]"
				} else {
					c.LastMessage = string(plain)
				}
			} else {
				plain, err := crypto.Open(s.key, sealed)
				if err != nil {
					c.LastMessage = "[无法解密]"
				} else {
					c.LastMessage = string(plain)
				}
			}
		}
		s.fillAnnouncementMeta(ctx, &c, userID)
		out = append(out, c)
	}
	if out == nil {
		out = []Conversation{}
	}
	return out, rows.Err()
}

func (s *Service) MarkRead(ctx context.Context, conversationID, userID string) error {
	ok, err := s.CanAccessConversation(ctx, conversationID, userID)
	if err != nil {
		return err
	}
	if !ok {
		return errors.New("forbidden")
	}
	_, err = s.pool.Exec(ctx, `
		UPDATE conversation_members SET last_read_at = now()
		WHERE conversation_id = $1 AND user_id = $2
	`, conversationID, userID)
	return err
}

// MarkReadUsers advances last_read_at for given members (e.g. after a call summary).
func (s *Service) MarkReadUsers(ctx context.Context, conversationID string, userIDs []string) error {
	if len(userIDs) == 0 {
		return nil
	}
	_, err := s.pool.Exec(ctx, `
		UPDATE conversation_members SET last_read_at = now()
		WHERE conversation_id = $1 AND user_id = ANY($2::uuid[])
	`, conversationID, userIDs)
	return err
}

func (s *Service) SetMemberPrefs(ctx context.Context, conversationID, userID string, pinned, muted, hidden *bool) error {
	var removed bool
	err := s.pool.QueryRow(ctx, `
		SELECT removed_at IS NOT NULL FROM conversation_members
		WHERE conversation_id = $1 AND user_id = $2
	`, conversationID, userID).Scan(&removed)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return errors.New("forbidden")
		}
		return err
	}
	if hidden != nil && *hidden && removed {
		_, err = s.pool.Exec(ctx, `
			DELETE FROM conversation_members WHERE conversation_id = $1 AND user_id = $2
		`, conversationID, userID)
		return err
	}
	ok, err := s.IsMember(ctx, conversationID, userID)
	if err != nil {
		return err
	}
	if !ok && !removed {
		return errors.New("forbidden")
	}
	if !ok {
		// soft-removed: only hide handled above
		return errors.New("forbidden")
	}
	if pinned != nil {
		if *pinned {
			_, err = s.pool.Exec(ctx, `
				UPDATE conversation_members SET pinned_at = COALESCE(pinned_at, now())
				WHERE conversation_id = $1 AND user_id = $2
			`, conversationID, userID)
		} else {
			_, err = s.pool.Exec(ctx, `
				UPDATE conversation_members SET pinned_at = NULL
				WHERE conversation_id = $1 AND user_id = $2
			`, conversationID, userID)
		}
		if err != nil {
			return err
		}
	}
	if muted != nil {
		_, err = s.pool.Exec(ctx, `
			UPDATE conversation_members SET muted = $3
			WHERE conversation_id = $1 AND user_id = $2
		`, conversationID, userID, *muted)
		if err != nil {
			return err
		}
	}
	if hidden != nil {
		if *hidden {
			_, err = s.pool.Exec(ctx, `
				UPDATE conversation_members SET hidden_at = now()
				WHERE conversation_id = $1 AND user_id = $2
			`, conversationID, userID)
		} else {
			_, err = s.pool.Exec(ctx, `
				UPDATE conversation_members SET hidden_at = NULL
				WHERE conversation_id = $1 AND user_id = $2
			`, conversationID, userID)
		}
		if err != nil {
			return err
		}
	}
	return nil
}

func (s *Service) ListFriends(ctx context.Context, userID string) ([]Contact, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT u.id::text, u.username, u.email, u.hope_id, u.avatar_url, COALESCE(f.remark, '')
		FROM friendships f
		JOIN users u ON u.id = f.friend_id
		WHERE f.user_id = $1
		ORDER BY COALESCE(NULLIF(f.remark, ''), u.username)
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Contact
	for rows.Next() {
		var c Contact
		if err := rows.Scan(&c.ID, &c.Username, &c.Email, &c.HopeID, &c.AvatarURL, &c.Remark); err != nil {
			return nil, err
		}
		c.IsFriend = true
		out = append(out, c)
	}
	if out == nil {
		out = []Contact{}
	}
	return out, rows.Err()
}

func (s *Service) ListGroups(ctx context.Context, userID string) ([]Conversation, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT c.id::text, c.type, c.title, c.created_at::text,
			(SELECT COUNT(*)::int FROM conversation_members cm WHERE cm.conversation_id = c.id AND cm.removed_at IS NULL),
			c.group_no, c.owner_id::text, c.avatar_url, COALESCE(m.role, 'member'),
			COALESCE(NULLIF(c.join_mode, ''), 'verify')
		FROM conversations c
		JOIN conversation_members m ON m.conversation_id = c.id
		WHERE m.user_id = $1 AND c.type = 'group' AND m.removed_at IS NULL
		ORDER BY c.title
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Conversation
	for rows.Next() {
		var c Conversation
		var ownerID *string
		var myRole string
		var joinMode string
		if err := rows.Scan(
			&c.ID, &c.Type, &c.Title, &c.CreatedAt, &c.MemberCount, &c.GroupNo, &ownerID, &c.AvatarURL, &myRole,
			&joinMode,
		); err != nil {
			return nil, err
		}
		applyJoinMode(&c, joinMode)
		c.OwnerID = ownerID
		c.Joined = true
		if ownerID != nil && *ownerID == userID {
			c.IsOwner = true
		}
		if myRole == "admin" {
			c.IsAdmin = true
		}
		s.fillAnnouncementMeta(ctx, &c, userID)
		out = append(out, c)
	}
	if out == nil {
		out = []Conversation{}
	}
	return out, rows.Err()
}

func (s *Service) resolveUser(ctx context.Context, login string) (*Contact, error) {
	login = strings.TrimSpace(login)
	if login == "" {
		return nil, errors.New("user not found")
	}
	var c Contact
	var err error
	if looksLikeHopeID(login) {
		err = s.pool.QueryRow(ctx, `
			SELECT id::text, username, email, hope_id, avatar_url FROM users WHERE hope_id = $1
		`, login).Scan(&c.ID, &c.Username, &c.Email, &c.HopeID, &c.AvatarURL)
	} else {
		err = s.pool.QueryRow(ctx, `
			SELECT id::text, username, email, hope_id, avatar_url FROM users WHERE username = $1
		`, login).Scan(&c.ID, &c.Username, &c.Email, &c.HopeID, &c.AvatarURL)
	}
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("user not found")
		}
		return nil, err
	}
	return &c, nil
}

// sameAutonomousDomain is true when both users belong to fellowships in the same domain.
func (s *Service) sameAutonomousDomain(ctx context.Context, a, b string) (bool, error) {
	if a == b {
		return true, nil
	}
	var ok bool
	err := s.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1
			FROM users ua
			JOIN fellowships fa ON fa.id = ua.fellowship_id
			JOIN users ub ON ub.id = $2::uuid
			JOIN fellowships fb ON fb.id = ub.fellowship_id
			WHERE ua.id = $1::uuid AND fa.domain_id = fb.domain_id
		)
	`, a, b).Scan(&ok)
	return ok, err
}

func looksLikeHopeID(s string) bool {
	s = strings.TrimSpace(s)
	n := len(s)
	if n < 5 || n > 12 {
		return false
	}
	if s[0] < '1' || s[0] > '9' {
		return false
	}
	for i := 1; i < n; i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

func (s *Service) AddFriend(ctx context.Context, userID, peerLogin string) (*Contact, error) {
	fr, err := s.RequestFriend(ctx, userID, peerLogin, "")
	if err != nil {
		return nil, err
	}
	if fr.ToUser != nil {
		return fr.ToUser, nil
	}
	return nil, errors.New("friend request sent")
}

func (s *Service) RequestFriend(ctx context.Context, userID, peerLogin, message string) (*FriendRequest, error) {
	peer, err := s.resolveUser(ctx, peerLogin)
	if err != nil {
		return nil, err
	}
	if peer.ID == userID {
		return nil, errors.New("cannot add yourself")
	}
	same, err := s.sameAutonomousDomain(ctx, userID, peer.ID)
	if err != nil {
		return nil, err
	}
	if !same {
		return nil, errors.New("user not found")
	}
	var already bool
	_ = s.pool.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM friendships WHERE user_id = $1 AND friend_id = $2)
	`, userID, peer.ID).Scan(&already)
	if already {
		return nil, errors.New("already friends")
	}
	var pending bool
	_ = s.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM friend_requests
			WHERE from_user_id = $1 AND to_user_id = $2 AND status = 'pending'
		)
	`, userID, peer.ID).Scan(&pending)
	if pending {
		return nil, errors.New("friend request pending")
	}
	var fr FriendRequest
	err = s.pool.QueryRow(ctx, `
		INSERT INTO friend_requests (from_user_id, to_user_id, message)
		VALUES ($1, $2, $3)
		RETURNING id::text, from_user_id::text, to_user_id::text, status, message, created_at::text
	`, userID, peer.ID, strings.TrimSpace(message)).Scan(
		&fr.ID, &fr.FromUserID, &fr.ToUserID, &fr.Status, &fr.Message, &fr.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	fr.ToUser = peer
	return &fr, nil
}

func (s *Service) ListFriendRequests(ctx context.Context, userID string) (incoming, outgoing []FriendRequest, err error) {
	rows, err := s.pool.Query(ctx, `
		SELECT fr.id::text, fr.from_user_id::text, fr.to_user_id::text, fr.status, fr.message, fr.created_at::text,
			fu.id::text, fu.username, fu.email, fu.hope_id, fu.avatar_url,
			tu.id::text, tu.username, tu.email, tu.hope_id, tu.avatar_url
		FROM friend_requests fr
		JOIN users fu ON fu.id = fr.from_user_id
		JOIN users tu ON tu.id = fr.to_user_id
		WHERE fr.status = 'pending' AND (fr.to_user_id = $1 OR fr.from_user_id = $1)
		ORDER BY fr.created_at DESC
	`, userID)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	incoming = []FriendRequest{}
	outgoing = []FriendRequest{}
	for rows.Next() {
		var fr FriendRequest
		var from, to Contact
		if err := rows.Scan(
			&fr.ID, &fr.FromUserID, &fr.ToUserID, &fr.Status, &fr.Message, &fr.CreatedAt,
			&from.ID, &from.Username, &from.Email, &from.HopeID, &from.AvatarURL,
			&to.ID, &to.Username, &to.Email, &to.HopeID, &to.AvatarURL,
		); err != nil {
			return nil, nil, err
		}
		fr.FromUser = &from
		fr.ToUser = &to
		if fr.ToUserID == userID {
			incoming = append(incoming, fr)
		} else {
			outgoing = append(outgoing, fr)
		}
	}
	return incoming, outgoing, rows.Err()
}

func (s *Service) AcceptFriendRequest(ctx context.Context, userID, requestID string) (*Contact, error) {
	var fromID, toID string
	err := s.pool.QueryRow(ctx, `
		SELECT from_user_id::text, to_user_id::text FROM friend_requests
		WHERE id = $1 AND status = 'pending'
	`, requestID).Scan(&fromID, &toID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("request not found")
		}
		return nil, err
	}
	if toID != userID {
		return nil, errors.New("forbidden")
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	_, err = tx.Exec(ctx, `
		UPDATE friend_requests SET status = 'accepted', decided_at = now() WHERE id = $1
	`, requestID)
	if err != nil {
		return nil, err
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO friendships (user_id, friend_id) VALUES ($1, $2), ($2, $1)
		ON CONFLICT DO NOTHING
	`, fromID, toID)
	if err != nil {
		return nil, err
	}
	// 若双方互发申请，一并结案
	_, _ = tx.Exec(ctx, `
		UPDATE friend_requests SET status = 'accepted', decided_at = now()
		WHERE from_user_id = $1 AND to_user_id = $2 AND status = 'pending'
	`, toID, fromID)
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	var c Contact
	err = s.pool.QueryRow(ctx, `
		SELECT id::text, username, email, hope_id, avatar_url FROM users WHERE id = $1
	`, fromID).Scan(&c.ID, &c.Username, &c.Email, &c.HopeID, &c.AvatarURL)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

func (s *Service) RejectFriendRequest(ctx context.Context, userID, requestID string) error {
	tag, err := s.pool.Exec(ctx, `
		UPDATE friend_requests SET status = 'rejected', decided_at = now()
		WHERE id = $1 AND to_user_id = $2 AND status = 'pending'
	`, requestID, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("request not found")
	}
	return nil
}

// CancelFriendRequest lets the sender withdraw a pending request.
func (s *Service) CancelFriendRequest(ctx context.Context, userID, requestID string) error {
	tag, err := s.pool.Exec(ctx, `
		UPDATE friend_requests SET status = 'rejected', decided_at = now()
		WHERE id = $1 AND from_user_id = $2 AND status = 'pending'
	`, requestID, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("request not found")
	}
	return nil
}

func (s *Service) areFriends(ctx context.Context, a, b string) (bool, error) {
	var ok bool
	err := s.pool.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM friendships WHERE user_id = $1 AND friend_id = $2)
	`, a, b).Scan(&ok)
	return ok, err
}

func (s *Service) CreateDM(ctx context.Context, userID, peerLogin string) (*Conversation, error) {
	peer, err := s.resolveUser(ctx, peerLogin)
	if err != nil {
		return nil, err
	}
	peerID := peer.ID
	peerUsername := peer.Username
	if peerID == userID {
		return nil, errors.New("cannot dm yourself")
	}
	friends, err := s.areFriends(ctx, userID, peerID)
	if err != nil {
		return nil, err
	}
	if !friends {
		return nil, errors.New("not friends")
	}

	var existingID string
	err = s.pool.QueryRow(ctx, `
		SELECT c.id::text
		FROM conversations c
		JOIN conversation_members a ON a.conversation_id = c.id AND a.user_id = $1
		JOIN conversation_members b ON b.conversation_id = c.id AND b.user_id = $2
		WHERE c.type = 'dm'
		LIMIT 1
	`, userID, peerID).Scan(&existingID)
	if err == nil {
		_, _ = s.pool.Exec(ctx, `
			UPDATE conversation_members
			SET hidden_at = NULL, removed_at = NULL, remove_reason = NULL
			WHERE conversation_id = $1 AND user_id IN ($2, $3)
		`, existingID, userID, peerID)
		c, err := s.getConversation(ctx, existingID)
		if err != nil {
			return nil, err
		}
		c.PeerUsername = peerUsername
		var remark string
		_ = s.pool.QueryRow(ctx, `
			SELECT COALESCE(remark, '') FROM friendships WHERE user_id = $1 AND friend_id = $2
		`, userID, peerID).Scan(&remark)
		remark = strings.TrimSpace(remark)
		if remark != "" {
			c.Title = remark
		} else {
			c.Title = peerUsername
		}
		return c, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var c Conversation
	err = tx.QueryRow(ctx, `
		INSERT INTO conversations (type, title)
		VALUES ('dm', $1)
		RETURNING id::text, type, title, created_at::text
	`, peerUsername).Scan(&c.ID, &c.Type, &c.Title, &c.CreatedAt)
	if err != nil {
		return nil, err
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2), ($1, $3)
	`, c.ID, userID, peerID)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	c.PeerUsername = peerUsername
	c.MemberCount = 2
	var remark string
	_ = s.pool.QueryRow(ctx, `
		SELECT COALESCE(remark, '') FROM friendships WHERE user_id = $1 AND friend_id = $2
	`, userID, peerID).Scan(&remark)
	remark = strings.TrimSpace(remark)
	if remark != "" {
		c.Title = remark
	} else {
		c.Title = peerUsername
	}
	return &c, nil
}

func (s *Service) CreateGroup(ctx context.Context, userID, title string, memberUsernames []string) (*Conversation, error) {
	title = strings.TrimSpace(title)
	if title == "" {
		return nil, errors.New("group title required")
	}
	if utf8Len(title) > 32 {
		return nil, errors.New("group title too long")
	}

	ids := map[string]struct{}{userID: {}}
	for _, name := range memberUsernames {
		name = strings.TrimSpace(name)
		if name == "" {
			continue
		}
		peer, err := s.resolveUser(ctx, name)
		if err != nil {
			if err.Error() == "user not found" {
				return nil, errors.New("user not found: " + name)
			}
			return nil, err
		}
		ids[peer.ID] = struct{}{}
	}
	if len(ids) < 2 {
		return nil, errors.New("group needs at least one other member")
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var c Conversation
	groupNo, err := allocGroupNo(ctx, tx)
	if err != nil {
		return nil, err
	}
	err = tx.QueryRow(ctx, `
		INSERT INTO conversations (type, title, group_no, owner_id)
		VALUES ('group', $1, $2, $3)
		RETURNING id::text, type, title, created_at::text, group_no, owner_id::text
	`, title, groupNo, userID).Scan(&c.ID, &c.Type, &c.Title, &c.CreatedAt, &c.GroupNo, &c.OwnerID)
	if err != nil {
		return nil, err
	}
	for id := range ids {
		if _, err := tx.Exec(ctx, `
			INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2)
		`, c.ID, id); err != nil {
			return nil, err
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	c.MemberCount = len(ids)
	c.IsOwner = true
	return &c, nil
}

func utf8Len(s string) int {
	return len([]rune(s))
}

func (s *Service) getConversation(ctx context.Context, id string) (*Conversation, error) {
	var c Conversation
	var joinMode string
	err := s.pool.QueryRow(ctx, `
		SELECT id::text, type, title, created_at::text, group_no, owner_id::text, avatar_url,
			(SELECT COUNT(*)::int FROM conversation_members cm
			 WHERE cm.conversation_id = conversations.id AND cm.removed_at IS NULL),
			COALESCE(NULLIF(join_mode, ''), 'verify')
		FROM conversations WHERE id = $1
	`, id).Scan(
		&c.ID, &c.Type, &c.Title, &c.CreatedAt, &c.GroupNo, &c.OwnerID, &c.AvatarURL, &c.MemberCount,
		&joinMode,
	)
	if err != nil {
		return nil, err
	}
	applyJoinMode(&c, joinMode)
	return &c, nil
}

func allocGroupNo(ctx context.Context, tx pgx.Tx) (string, error) {
	for i := 0; i < 40; i++ {
		n, err := rand.Int(rand.Reader, big.NewInt(9_000_000_000))
		if err != nil {
			return "", err
		}
		// 10 位群号，首位 1–9（类似 QQ 群号）
		no := fmt.Sprintf("%d", n.Int64()+1_000_000_000)
		var taken bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM conversations WHERE group_no = $1)`, no).Scan(&taken); err != nil {
			return "", err
		}
		if !taken {
			return no, nil
		}
	}
	return "", errors.New("failed to allocate group number")
}

func (s *Service) JoinGroupByNo(ctx context.Context, userID, groupNo, message string) (*JoinGroupResult, error) {
	groupNo = strings.TrimSpace(groupNo)
	if groupNo == "" {
		return nil, errors.New("group not found")
	}
	message = strings.TrimSpace(message)
	if len([]rune(message)) > 64 {
		return nil, errors.New("message too long")
	}
	var c Conversation
	var joinMode string
	err := s.pool.QueryRow(ctx, `
		SELECT id::text, type, title, created_at::text, group_no, owner_id::text, avatar_url,
			COALESCE(NULLIF(join_mode, ''), 'verify')
		FROM conversations WHERE type = 'group' AND group_no = $1
	`, groupNo).Scan(&c.ID, &c.Type, &c.Title, &c.CreatedAt, &c.GroupNo, &c.OwnerID, &c.AvatarURL, &joinMode)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("group not found")
		}
		return nil, err
	}
	applyJoinMode(&c, joinMode)
	ok, err := s.IsMember(ctx, c.ID, userID)
	if err != nil {
		return nil, err
	}
	if ok {
		_, _ = s.pool.Exec(ctx, `
			UPDATE conversation_members SET hidden_at = NULL
			WHERE conversation_id = $1 AND user_id = $2
		`, c.ID, userID)
		_ = s.pool.QueryRow(ctx, `
			SELECT COUNT(*)::int FROM conversation_members
			WHERE conversation_id = $1 AND removed_at IS NULL
		`, c.ID).Scan(&c.MemberCount)
		s.annotateViewer(ctx, &c, userID)
		return &JoinGroupResult{Status: "joined", Conversation: &c}, nil
	}
	if c.OwnerID == nil || *c.OwnerID == "" {
		return nil, errors.New("group not found")
	}
	same, err := s.sameAutonomousDomain(ctx, userID, *c.OwnerID)
	if err != nil {
		return nil, err
	}
	if !same {
		return nil, errors.New("group not found")
	}
	if c.JoinMode == JoinModeDeny {
		return nil, errors.New("join not allowed")
	}
	if c.JoinMode == JoinModeAnyone {
		added, err := s.restoreOrAddMember(ctx, c.ID, userID)
		if err != nil {
			return nil, err
		}
		_ = s.pool.QueryRow(ctx, `
			SELECT COUNT(*)::int FROM conversation_members
			WHERE conversation_id = $1 AND removed_at IS NULL
		`, c.ID).Scan(&c.MemberCount)
		s.annotateViewer(ctx, &c, userID)
		return &JoinGroupResult{Status: "joined", NewlyJoined: added, Conversation: &c}, nil
	}
	var pending bool
	_ = s.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM group_join_requests
			WHERE conversation_id = $1 AND from_user_id = $2 AND status = 'pending'
		)
	`, c.ID, userID).Scan(&pending)
	if pending {
		return nil, errors.New("join request pending")
	}
	var req GroupJoinRequest
	err = s.pool.QueryRow(ctx, `
		INSERT INTO group_join_requests (conversation_id, from_user_id, message)
		VALUES ($1, $2, $3)
		RETURNING id::text, conversation_id::text, from_user_id::text, status, message, created_at::text
	`, c.ID, userID, message).Scan(
		&req.ID, &req.ConversationID, &req.FromUserID, &req.Status, &req.Message, &req.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	req.Group = &Conversation{
		ID: c.ID, Type: c.Type, Title: c.Title, GroupNo: c.GroupNo, AvatarURL: c.AvatarURL, JoinMode: c.JoinMode,
	}
	return &JoinGroupResult{Status: "pending", Request: &req}, nil
}

func (s *Service) ListGroupJoinRequests(ctx context.Context, conversationID, userID string) ([]GroupJoinRequest, error) {
	ok, err := s.canManageGroup(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	rows, err := s.pool.Query(ctx, `
		SELECT r.id::text, r.conversation_id::text, r.from_user_id::text, r.status, r.message, r.created_at::text,
			u.id::text, u.username, u.email, u.hope_id, u.avatar_url,
			ib.id::text, ib.username, ib.email, ib.hope_id, ib.avatar_url
		FROM group_join_requests r
		JOIN users u ON u.id = r.from_user_id
		LEFT JOIN users ib ON ib.id = r.invited_by
		WHERE r.conversation_id = $1 AND r.status = 'pending'
		ORDER BY r.created_at DESC
	`, conversationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []GroupJoinRequest{}
	for rows.Next() {
		var r GroupJoinRequest
		var from Contact
		var invID, invUser, invEmail *string
		var invHope, invAvatar *string
		if err := rows.Scan(
			&r.ID, &r.ConversationID, &r.FromUserID, &r.Status, &r.Message, &r.CreatedAt,
			&from.ID, &from.Username, &from.Email, &from.HopeID, &from.AvatarURL,
			&invID, &invUser, &invEmail, &invHope, &invAvatar,
		); err != nil {
			return nil, err
		}
		r.FromUser = &from
		if invID != nil && *invID != "" {
			r.InvitedBy = &Contact{
				ID: *invID, Username: derefStr(invUser), Email: derefStr(invEmail),
				HopeID: invHope, AvatarURL: invAvatar,
			}
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

func (s *Service) AcceptGroupJoinRequest(ctx context.Context, conversationID, actorID, requestID string) (*Contact, error) {
	ok, err := s.canManageGroup(ctx, conversationID, actorID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	var fromID, reqConv string
	err = s.pool.QueryRow(ctx, `
		SELECT from_user_id::text, conversation_id::text FROM group_join_requests
		WHERE id = $1 AND status = 'pending'
	`, requestID).Scan(&fromID, &reqConv)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("request not found")
		}
		return nil, err
	}
	if reqConv != conversationID {
		return nil, errors.New("request not found")
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	tag, err := tx.Exec(ctx, `
		UPDATE group_join_requests
		SET status = 'accepted', decided_by = $2, decided_at = now()
		WHERE id = $1 AND status = 'pending'
	`, requestID, actorID)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, errors.New("request not found")
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO conversation_members (conversation_id, user_id, role)
		VALUES ($1, $2, 'member')
		ON CONFLICT (conversation_id, user_id) DO UPDATE
		SET removed_at = NULL, remove_reason = NULL, hidden_at = NULL, role = 'member'
	`, conversationID, fromID)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	var c Contact
	err = s.pool.QueryRow(ctx, `
		SELECT id::text, username, email, hope_id, avatar_url FROM users WHERE id = $1
	`, fromID).Scan(&c.ID, &c.Username, &c.Email, &c.HopeID, &c.AvatarURL)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

func (s *Service) RejectGroupJoinRequest(ctx context.Context, conversationID, actorID, requestID string) error {
	ok, err := s.canManageGroup(ctx, conversationID, actorID)
	if err != nil {
		return err
	}
	if !ok {
		return errors.New("forbidden")
	}
	tag, err := s.pool.Exec(ctx, `
		UPDATE group_join_requests
		SET status = 'rejected', decided_by = $3, decided_at = now()
		WHERE id = $1 AND conversation_id = $2 AND status = 'pending'
	`, requestID, conversationID, actorID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("request not found")
	}
	return nil
}

func (s *Service) CancelGroupJoinRequest(ctx context.Context, userID, requestID string) error {
	tag, err := s.pool.Exec(ctx, `
		UPDATE group_join_requests SET status = 'rejected', decided_at = now()
		WHERE id = $1 AND from_user_id = $2 AND status = 'pending'
	`, requestID, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("request not found")
	}
	return nil
}

func (s *Service) LeaveGroup(ctx context.Context, conversationID, userID string) error {
	var typ string
	var ownerID *string
	err := s.pool.QueryRow(ctx, `
		SELECT type, owner_id::text FROM conversations WHERE id = $1
	`, conversationID).Scan(&typ, &ownerID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return errors.New("group not found")
		}
		return err
	}
	if typ != "group" {
		return errors.New("not a group")
	}
	ok, err := s.IsMember(ctx, conversationID, userID)
	if err != nil {
		return err
	}
	if !ok {
		return errors.New("forbidden")
	}
	if ownerID != nil && *ownerID == userID {
		// 群主退群：转让给最早加入的其他活跃成员，若无人则解散
		var nextOwner *string
		_ = s.pool.QueryRow(ctx, `
			SELECT user_id::text FROM conversation_members
			WHERE conversation_id = $1 AND user_id <> $2 AND removed_at IS NULL
			ORDER BY joined_at ASC LIMIT 1
		`, conversationID, userID).Scan(&nextOwner)
		if nextOwner == nil {
			_, err = s.pool.Exec(ctx, `DELETE FROM conversations WHERE id = $1`, conversationID)
			return err
		}
		_, err = s.pool.Exec(ctx, `UPDATE conversations SET owner_id = $1 WHERE id = $2`, *nextOwner, conversationID)
		if err != nil {
			return err
		}
	}
	// QQ 风格：主动退群后会话仍保留，可查看历史；用户可手动「删除会话」硬删
	_, err = s.pool.Exec(ctx, `
		UPDATE conversation_members
		SET removed_at = now(), remove_reason = 'left', pinned_at = NULL, role = 'member'
		WHERE conversation_id = $1 AND user_id = $2 AND removed_at IS NULL
	`, conversationID, userID)
	return err
}

// InviteToGroup: 任意群成员可邀请好友（不允许加入时仅群主/管理员可邀请）。
// anyone → 直接入群；verify → 普通成员邀请需管理员同意；deny → 仅管理员可直接邀请。
func (s *Service) InviteToGroup(ctx context.Context, conversationID, userID string, memberIDs []string) (*InviteResult, error) {
	ok, err := s.IsMember(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	var typ string
	var joinMode string
	err = s.pool.QueryRow(ctx, `
		SELECT type, COALESCE(NULLIF(join_mode, ''), 'verify')
		FROM conversations WHERE id = $1
	`, conversationID).Scan(&typ, &joinMode)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("group not found")
		}
		return nil, err
	}
	if typ != "group" {
		return nil, errors.New("not a group")
	}
	mode := normalizeJoinMode(joinMode)
	canManage, err := s.canManageGroup(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if mode == JoinModeDeny && !canManage {
		return nil, errors.New("join not allowed")
	}
	directInvite := mode == JoinModeAnyone || canManage

	var inviterName string
	_ = s.pool.QueryRow(ctx, `SELECT username FROM users WHERE id = $1`, userID).Scan(&inviterName)

	added := 0
	pending := 0
	var addedNames []string
	for _, mid := range memberIDs {
		mid = strings.TrimSpace(mid)
		if mid == "" || mid == userID {
			continue
		}
		friends, err := s.areFriends(ctx, userID, mid)
		if err != nil {
			return nil, err
		}
		if !friends {
			return nil, errors.New("not friends")
		}
		already, err := s.IsMember(ctx, conversationID, mid)
		if err != nil {
			return nil, err
		}
		if already {
			continue
		}
		if directInvite {
			addedOne, err := s.restoreOrAddMember(ctx, conversationID, mid)
			if err != nil {
				return nil, err
			}
			if addedOne {
				added++
				addedNames = append(addedNames, s.UsernameByID(ctx, mid))
			}
			_, _ = s.pool.Exec(ctx, `
				UPDATE group_join_requests
				SET status = 'accepted', decided_by = $3, decided_at = now()
				WHERE conversation_id = $1 AND from_user_id = $2 AND status = 'pending'
			`, conversationID, mid, userID)
			continue
		}
		msg := "邀请入群"
		if inviterName != "" {
			msg = inviterName + " 邀请入群"
		}
		var pendingExists bool
		_ = s.pool.QueryRow(ctx, `
			SELECT EXISTS(
				SELECT 1 FROM group_join_requests
				WHERE conversation_id = $1 AND from_user_id = $2 AND status = 'pending'
			)
		`, conversationID, mid).Scan(&pendingExists)
		if pendingExists {
			_, err = s.pool.Exec(ctx, `
				UPDATE group_join_requests
				SET message = $3, invited_by = $4
				WHERE conversation_id = $1 AND from_user_id = $2 AND status = 'pending'
			`, conversationID, mid, msg, userID)
			if err != nil {
				return nil, err
			}
			pending++
			continue
		}
		_, err = s.pool.Exec(ctx, `
			INSERT INTO group_join_requests (conversation_id, from_user_id, message, invited_by)
			VALUES ($1, $2, $3, $4)
		`, conversationID, mid, msg, userID)
		if err != nil {
			return nil, err
		}
		pending++
	}
	if added == 0 && pending == 0 {
		return nil, errors.New("no new members")
	}
	c, err := s.getConversation(ctx, conversationID)
	if err != nil {
		return nil, err
	}
	s.annotateViewer(ctx, c, userID)
	res := &InviteResult{Conversation: c, Added: added, Pending: pending}
	if len(addedNames) > 0 {
		res.AddedNames = addedNames
	}
	return res, nil
}

// KickFromGroup: owner can remove anyone except self; admin can remove regular members only.
func (s *Service) KickFromGroup(ctx context.Context, conversationID, actorID, memberID string) error {
	if actorID == memberID {
		return errors.New("cannot kick yourself")
	}
	var typ string
	var ownerID *string
	err := s.pool.QueryRow(ctx, `SELECT type, owner_id::text FROM conversations WHERE id = $1`, conversationID).
		Scan(&typ, &ownerID)
	if err != nil {
		return errors.New("group not found")
	}
	if typ != "group" {
		return errors.New("not a group")
	}
	if ownerID != nil && *ownerID == memberID {
		return errors.New("cannot kick owner")
	}
	actorIsOwner := ownerID != nil && *ownerID == actorID
	if !actorIsOwner {
		role, err := s.memberRole(ctx, conversationID, actorID)
		if err != nil || role != "admin" {
			return errors.New("forbidden")
		}
		targetRole, err := s.memberRole(ctx, conversationID, memberID)
		if err != nil {
			return errors.New("member not found")
		}
		if targetRole == "admin" {
			return errors.New("admin cannot kick admin")
		}
	}
	tag, err := s.pool.Exec(ctx, `
		UPDATE conversation_members
		SET removed_at = now(), remove_reason = 'kicked', pinned_at = NULL
		WHERE conversation_id = $1 AND user_id = $2 AND removed_at IS NULL
	`, conversationID, memberID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("member not found")
	}
	return nil
}

// SetMemberRole sets admin/member (owner only).
func (s *Service) SetMemberRole(ctx context.Context, conversationID, actorID, memberID, role string) error {
	role = strings.TrimSpace(role)
	if role != "admin" && role != "member" {
		return errors.New("invalid role")
	}
	var typ string
	var ownerID *string
	err := s.pool.QueryRow(ctx, `SELECT type, owner_id::text FROM conversations WHERE id = $1`, conversationID).
		Scan(&typ, &ownerID)
	if err != nil {
		return errors.New("group not found")
	}
	if typ != "group" {
		return errors.New("not a group")
	}
	if ownerID == nil || *ownerID != actorID {
		return errors.New("only owner can set admin")
	}
	if memberID == actorID {
		return errors.New("cannot change own role")
	}
	if ownerID != nil && *ownerID == memberID {
		return errors.New("cannot change owner role")
	}
	tag, err := s.pool.Exec(ctx, `
		UPDATE conversation_members SET role = $3
		WHERE conversation_id = $1 AND user_id = $2
	`, conversationID, memberID, role)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("member not found")
	}
	return nil
}

// DissolveGroup deletes the group (owner only).
func (s *Service) DissolveGroup(ctx context.Context, conversationID, userID string) error {
	var typ string
	var oid *string
	err := s.pool.QueryRow(ctx, `SELECT type, owner_id::text FROM conversations WHERE id = $1`, conversationID).
		Scan(&typ, &oid)
	if err != nil {
		return errors.New("group not found")
	}
	if typ != "group" {
		return errors.New("not a group")
	}
	if oid == nil || *oid != userID {
		return errors.New("only owner can dissolve")
	}
	_, err = s.pool.Exec(ctx, `DELETE FROM conversations WHERE id = $1`, conversationID)
	return err
}

func (s *Service) RenameGroup(ctx context.Context, conversationID, userID, title string) (*Conversation, error) {
	title = strings.TrimSpace(title)
	if title == "" {
		return nil, errors.New("group title required")
	}
	t := title
	c, _, err := s.PatchGroup(ctx, conversationID, userID, &t, nil, nil)
	return c, err
}

// PatchGroup updates title / join mode (owner or admin).
func (s *Service) PatchGroup(
	ctx context.Context,
	conversationID, userID string,
	title *string,
	joinMode *string,
	_ *string, // legacy announcement ignored; use CreateAnnouncement
) (*Conversation, *Message, error) {
	ok, err := s.canManageGroup(ctx, conversationID, userID)
	if err != nil {
		return nil, nil, err
	}
	if !ok {
		return nil, nil, errors.New("forbidden")
	}
	if title == nil && joinMode == nil {
		return nil, nil, errors.New("nothing to update")
	}
	if title != nil {
		t := strings.TrimSpace(*title)
		if t == "" {
			return nil, nil, errors.New("group title required")
		}
		if utf8Len(t) > 32 {
			return nil, nil, errors.New("group title too long")
		}
		_, err = s.pool.Exec(ctx, `UPDATE conversations SET title = $1 WHERE id = $2`, t, conversationID)
		if err != nil {
			return nil, nil, err
		}
	}
	if joinMode != nil {
		mode := strings.TrimSpace(*joinMode)
		if mode != JoinModeAnyone && mode != JoinModeVerify && mode != JoinModeDeny {
			return nil, nil, errors.New("invalid join mode")
		}
		_, err = s.pool.Exec(ctx, `
			UPDATE conversations
			SET join_mode = $1, invite_requires_approval = ($1 = 'verify')
			WHERE id = $2
		`, mode, conversationID)
		if err != nil {
			return nil, nil, err
		}
	}
	c, err := s.getConversation(ctx, conversationID)
	if err != nil {
		return nil, nil, err
	}
	s.annotateViewer(ctx, c, userID)
	return c, nil, nil
}

func derefStr(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

func (s *Service) ListGroupMembers(ctx context.Context, conversationID, userID string) ([]Contact, error) {
	ok, err := s.IsMember(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	var ownerID *string
	_ = s.pool.QueryRow(ctx, `SELECT owner_id::text FROM conversations WHERE id = $1`, conversationID).Scan(&ownerID)
	rows, err := s.pool.Query(ctx, `
		SELECT u.id::text, u.username, u.email, u.hope_id, u.avatar_url,
			COALESCE(m.role, 'member'), COALESCE(m.member_title, ''),
			EXISTS(SELECT 1 FROM friendships f WHERE f.user_id = $2 AND f.friend_id = u.id),
			COALESCE((SELECT f.remark FROM friendships f WHERE f.user_id = $2 AND f.friend_id = u.id), '')
		FROM conversation_members m
		JOIN users u ON u.id = m.user_id
		WHERE m.conversation_id = $1 AND m.removed_at IS NULL
		ORDER BY
			CASE
				WHEN $3::text IS NOT NULL AND u.id::text = $3 THEN 0
				WHEN COALESCE(m.role, 'member') = 'admin' THEN 1
				ELSE 2
			END,
			m.joined_at
	`, conversationID, userID, ownerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Contact
	for rows.Next() {
		var c Contact
		if err := rows.Scan(
			&c.ID, &c.Username, &c.Email, &c.HopeID, &c.AvatarURL, &c.Role, &c.MemberTitle,
			&c.IsFriend, &c.Remark,
		); err != nil {
			return nil, err
		}
		c.IsAdmin = c.Role == "admin"
		c.MemberTitle = resolveMemberTitle(ownerID, c.ID, c.Role, c.MemberTitle)
		out = append(out, c)
	}
	if out == nil {
		out = []Contact{}
	}
	return out, rows.Err()
}

func resolveMemberTitle(ownerID *string, userID, role, custom string) string {
	custom = strings.TrimSpace(custom)
	if custom != "" {
		return custom
	}
	if ownerID != nil && *ownerID == userID {
		return "群主"
	}
	if role == "admin" {
		return "管理员"
	}
	return ""
}

// SetMemberTitle sets a custom group title (owner or admin). Empty clears custom title.
func (s *Service) SetMemberTitle(ctx context.Context, conversationID, actorID, memberID, title string) error {
	title = strings.TrimSpace(title)
	if utf8Len(title) > 12 {
		return errors.New("title too long")
	}
	ok, err := s.canManageGroup(ctx, conversationID, actorID)
	if err != nil {
		return err
	}
	if !ok {
		return errors.New("forbidden")
	}
	tag, err := s.pool.Exec(ctx, `
		UPDATE conversation_members SET member_title = $3
		WHERE conversation_id = $1 AND user_id = $2
	`, conversationID, memberID, title)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("member not found")
	}
	return nil
}

func (s *Service) BackfillGroupNos(ctx context.Context) error {
	rows, err := s.pool.Query(ctx, `
		SELECT id::text FROM conversations WHERE type = 'group' AND (group_no IS NULL OR group_no = '')
	`)
	if err != nil {
		return err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return err
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	for _, id := range ids {
		tx, err := s.pool.Begin(ctx)
		if err != nil {
			return err
		}
		no, err := allocGroupNo(ctx, tx)
		if err != nil {
			_ = tx.Rollback(ctx)
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE conversations SET group_no = $1 WHERE id = $2`, no, id); err != nil {
			_ = tx.Rollback(ctx)
			return err
		}
		if err := tx.Commit(ctx); err != nil {
			return err
		}
	}
	return nil
}

func (s *Service) GetGroup(ctx context.Context, conversationID, userID string) (*Conversation, error) {
	ok, err := s.IsMember(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	c, err := s.getConversation(ctx, conversationID)
	if err != nil {
		return nil, err
	}
	if c.Type != "group" {
		return nil, errors.New("not a group")
	}
	if c.OwnerID != nil && *c.OwnerID == userID {
		c.IsOwner = true
	}
	return c, nil
}

func (s *Service) IsMember(ctx context.Context, conversationID, userID string) (bool, error) {
	var ok bool
	err := s.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM conversation_members
			WHERE conversation_id = $1 AND user_id = $2 AND removed_at IS NULL
		)
	`, conversationID, userID).Scan(&ok)
	return ok, err
}

// CanAccessConversation: active members or soft-removed (kicked) may still read history.
func (s *Service) CanAccessConversation(ctx context.Context, conversationID, userID string) (bool, error) {
	var ok bool
	err := s.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM conversation_members
			WHERE conversation_id = $1 AND user_id = $2
		)
	`, conversationID, userID).Scan(&ok)
	return ok, err
}

func (s *Service) memberRole(ctx context.Context, conversationID, userID string) (string, error) {
	var role string
	err := s.pool.QueryRow(ctx, `
		SELECT COALESCE(role, 'member') FROM conversation_members
		WHERE conversation_id = $1 AND user_id = $2 AND removed_at IS NULL
	`, conversationID, userID).Scan(&role)
	if err != nil {
		return "", err
	}
	return role, nil
}

func (s *Service) annotateViewer(ctx context.Context, c *Conversation, userID string) {
	if c == nil {
		return
	}
	if c.OwnerID != nil && *c.OwnerID == userID {
		c.IsOwner = true
	}
	role, err := s.memberRole(ctx, c.ID, userID)
	if err == nil && role == "admin" {
		c.IsAdmin = true
	}
	s.fillAnnouncementMeta(ctx, c, userID)
}

// canManageGroup: 群主或管理员可改群名/头像、邀请、踢普通成员。
func (s *Service) canManageGroup(ctx context.Context, conversationID, userID string) (bool, error) {
	var typ string
	var ownerID *string
	err := s.pool.QueryRow(ctx, `SELECT type, owner_id::text FROM conversations WHERE id = $1`, conversationID).
		Scan(&typ, &ownerID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return false, errors.New("group not found")
		}
		return false, err
	}
	if typ != "group" {
		return false, errors.New("not a group")
	}
	if ownerID != nil && *ownerID == userID {
		return true, nil
	}
	role, err := s.memberRole(ctx, conversationID, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return false, errors.New("forbidden")
		}
		return false, err
	}
	return role == "admin", nil
}

const recallOwnWindow = 5 * time.Minute

// RecallMessage: DM / ordinary members — own message within 5 minutes.
// Group owner/admin may recall any message at any time (including their own after the window).
func (s *Service) RecallMessage(ctx context.Context, conversationID, userID, messageID string) (*Message, error) {
	ok, err := s.IsMember(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	var senderID string
	var createdAt time.Time
	var recalledAt *time.Time
	err = s.pool.QueryRow(ctx, `
		SELECT sender_id::text, created_at, recalled_at
		FROM messages WHERE id = $1 AND conversation_id = $2
	`, messageID, conversationID).Scan(&senderID, &createdAt, &recalledAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("message not found")
		}
		return nil, err
	}
	if recalledAt != nil {
		return s.getMessage(ctx, conversationID, messageID)
	}

	var convType string
	err = s.pool.QueryRow(ctx, `SELECT type FROM conversations WHERE id = $1`, conversationID).Scan(&convType)
	if err != nil {
		return nil, err
	}

	isGroupAdmin := false
	if convType == "group" {
		can, err := s.canManageGroup(ctx, conversationID, userID)
		if err != nil {
			return nil, err
		}
		isGroupAdmin = can
	}

	if isGroupAdmin {
		// owner/admin: no time limit
	} else if senderID == userID {
		if time.Since(createdAt) > recallOwnWindow {
			return nil, errors.New("recall expired")
		}
	} else {
		return nil, errors.New("forbidden")
	}

	_, err = s.pool.Exec(ctx, `
		UPDATE messages SET recalled_at = now(), recalled_by = $1
		WHERE id = $2 AND conversation_id = $3 AND recalled_at IS NULL
	`, userID, messageID, conversationID)
	if err != nil {
		return nil, err
	}
	return s.getMessage(ctx, conversationID, messageID)
}

func (s *Service) getMessage(ctx context.Context, conversationID, messageID string) (*Message, error) {
	var ownerID *string
	var convType string
	_ = s.pool.QueryRow(ctx, `SELECT type, owner_id::text FROM conversations WHERE id = $1`, conversationID).
		Scan(&convType, &ownerID)
	var m Message
	var sealed string
	var recalledAt, recalledBy *string
	var role, customTitle string
	err := s.pool.QueryRow(ctx, `
		SELECT m.id::text, m.conversation_id::text, m.sender_id::text, m.type, m.body_sealed, m.created_at::text,
			m.recalled_at::text, m.recalled_by::text, u.username, u.avatar_url,
			COALESCE(cm.role, 'member'), COALESCE(cm.member_title, '')
		FROM messages m
		JOIN users u ON u.id = m.sender_id
		LEFT JOIN conversation_members cm ON cm.conversation_id = m.conversation_id AND cm.user_id = m.sender_id
		WHERE m.id = $1 AND m.conversation_id = $2
	`, messageID, conversationID).Scan(
		&m.ID, &m.ConversationID, &m.SenderID, &m.Type, &sealed, &m.CreatedAt,
		&recalledAt, &recalledBy, &m.SenderUsername, &m.SenderAvatarURL, &role, &customTitle,
	)
	if err != nil {
		return nil, err
	}
	applyMessageBody(&m, sealed, recalledAt, recalledBy, s.key)
	if convType == "group" {
		m.SenderTitle = resolveMemberTitle(ownerID, m.SenderID, role, customTitle)
	}
	return &m, nil
}

func applyMessageBody(m *Message, sealed string, recalledAt, recalledBy *string, key []byte) {
	if recalledAt != nil && *recalledAt != "" {
		m.Recalled = true
		m.RecalledAt = recalledAt
		m.Body = ""
		if recalledBy != nil && *recalledBy != "" {
			m.RecalledBy = recalledBy
		}
		return
	}
	plain, err := crypto.Open(key, sealed)
	if err != nil {
		m.Body = "[decrypt error]"
	} else {
		m.Body = string(plain)
	}
}

func (s *Service) fillSenderMeta(ctx context.Context, m *Message, userID string) {
	_ = s.pool.QueryRow(ctx, `SELECT username, avatar_url FROM users WHERE id = $1`, userID).
		Scan(&m.SenderUsername, &m.SenderAvatarURL)
	var ownerID *string
	var convType string
	_ = s.pool.QueryRow(ctx, `SELECT type, owner_id::text FROM conversations WHERE id = $1`, m.ConversationID).
		Scan(&convType, &ownerID)
	if convType != "group" {
		return
	}
	var role, custom string
	_ = s.pool.QueryRow(ctx, `
		SELECT COALESCE(role, 'member'), COALESCE(member_title, '')
		FROM conversation_members WHERE conversation_id = $1 AND user_id = $2
	`, m.ConversationID, userID).Scan(&role, &custom)
	m.SenderTitle = resolveMemberTitle(ownerID, userID, role, custom)
}

func (s *Service) SendText(ctx context.Context, conversationID, userID, body string) (*Message, error) {
	body = strings.TrimSpace(body)
	if body == "" {
		return nil, errors.New("empty message")
	}
	ok, err := s.IsMember(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	sealed, err := crypto.Seal(s.key, []byte(body))
	if err != nil {
		return nil, err
	}
	var m Message
	var sealedOut string
	err = s.pool.QueryRow(ctx, `
		INSERT INTO messages (conversation_id, sender_id, type, body_sealed)
		VALUES ($1, $2, 'text', $3)
		RETURNING id::text, conversation_id::text, sender_id::text, type, body_sealed, created_at::text
	`, conversationID, userID, sealed).Scan(
		&m.ID, &m.ConversationID, &m.SenderID, &m.Type, &sealedOut, &m.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	m.Body = body
	s.fillSenderMeta(ctx, &m, userID)
	_, _ = s.pool.Exec(ctx, `
		UPDATE conversation_members SET hidden_at = NULL
		WHERE conversation_id = $1 AND hidden_at IS NOT NULL
	`, conversationID)
	return &m, nil
}

// ImageBody is stored (sealed) as the message body for type=image.
type ImageBody struct {
	ThumbURL string `json:"thumbUrl"`
	URL      string `json:"url"`
	Width    int    `json:"w"`
	Height   int    `json:"h"`
}

func (s *Service) SendImage(ctx context.Context, conversationID, userID string, img ImageBody) (*Message, error) {
	if strings.TrimSpace(img.ThumbURL) == "" || strings.TrimSpace(img.URL) == "" {
		return nil, errors.New("invalid image")
	}
	ok, err := s.IsMember(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	payload, err := json.Marshal(img)
	if err != nil {
		return nil, err
	}
	sealed, err := crypto.Seal(s.key, payload)
	if err != nil {
		return nil, err
	}
	var m Message
	var sealedOut string
	err = s.pool.QueryRow(ctx, `
		INSERT INTO messages (conversation_id, sender_id, type, body_sealed)
		VALUES ($1, $2, 'image', $3)
		RETURNING id::text, conversation_id::text, sender_id::text, type, body_sealed, created_at::text
	`, conversationID, userID, sealed).Scan(
		&m.ID, &m.ConversationID, &m.SenderID, &m.Type, &sealedOut, &m.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	m.Body = string(payload)
	s.fillSenderMeta(ctx, &m, userID)
	_, _ = s.pool.Exec(ctx, `
		UPDATE conversation_members SET hidden_at = NULL
		WHERE conversation_id = $1 AND hidden_at IS NOT NULL
	`, conversationID)
	return &m, nil
}

// FileBody is stored (sealed) for type=file.
type FileBody struct {
	URL  string `json:"url"`
	Name string `json:"name"`
	Size int64  `json:"size"`
	Mime string `json:"mime,omitempty"`
}

func (s *Service) SendFile(ctx context.Context, conversationID, userID string, f FileBody) (*Message, error) {
	if strings.TrimSpace(f.URL) == "" || strings.TrimSpace(f.Name) == "" {
		return nil, errors.New("invalid file")
	}
	ok, err := s.IsMember(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	payload, err := json.Marshal(f)
	if err != nil {
		return nil, err
	}
	sealed, err := crypto.Seal(s.key, payload)
	if err != nil {
		return nil, err
	}
	var m Message
	var sealedOut string
	err = s.pool.QueryRow(ctx, `
		INSERT INTO messages (conversation_id, sender_id, type, body_sealed)
		VALUES ($1, $2, 'file', $3)
		RETURNING id::text, conversation_id::text, sender_id::text, type, body_sealed, created_at::text
	`, conversationID, userID, sealed).Scan(
		&m.ID, &m.ConversationID, &m.SenderID, &m.Type, &sealedOut, &m.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	m.Body = string(payload)
	s.fillSenderMeta(ctx, &m, userID)
	_, _ = s.pool.Exec(ctx, `
		UPDATE conversation_members SET hidden_at = NULL
		WHERE conversation_id = $1 AND hidden_at IS NOT NULL
	`, conversationID)
	return &m, nil
}

// VoiceBody is stored (sealed) for type=voice.
type VoiceBody struct {
	URL      string  `json:"url"`
	Duration float64 `json:"duration"` // seconds
	Size     int64   `json:"size,omitempty"`
	Mime     string  `json:"mime,omitempty"`
}

func (s *Service) SendVoice(ctx context.Context, conversationID, userID string, v VoiceBody) (*Message, error) {
	if strings.TrimSpace(v.URL) == "" || v.Duration < 0.3 || v.Duration > 60.5 {
		return nil, errors.New("invalid voice")
	}
	ok, err := s.IsMember(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	payload, err := json.Marshal(v)
	if err != nil {
		return nil, err
	}
	sealed, err := crypto.Seal(s.key, payload)
	if err != nil {
		return nil, err
	}
	var m Message
	var sealedOut string
	err = s.pool.QueryRow(ctx, `
		INSERT INTO messages (conversation_id, sender_id, type, body_sealed)
		VALUES ($1, $2, 'voice', $3)
		RETURNING id::text, conversation_id::text, sender_id::text, type, body_sealed, created_at::text
	`, conversationID, userID, sealed).Scan(
		&m.ID, &m.ConversationID, &m.SenderID, &m.Type, &sealedOut, &m.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	m.Body = string(payload)
	s.fillSenderMeta(ctx, &m, userID)
	_, _ = s.pool.Exec(ctx, `
		UPDATE conversation_members SET hidden_at = NULL
		WHERE conversation_id = $1 AND hidden_at IS NOT NULL
	`, conversationID)
	return &m, nil
}

// CallBody is stored (sealed) for type=call system summary.
type CallBody struct {
	Kind        string `json:"kind"`
	Status      string `json:"status"`
	DurationSec int    `json:"durationSec,omitempty"`
}

func (s *Service) SendCallMessage(ctx context.Context, conversationID, senderID string, body CallBody) (*Message, error) {
	ok, err := s.IsMember(ctx, conversationID, senderID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	sealed, err := crypto.Seal(s.key, payload)
	if err != nil {
		return nil, err
	}
	var m Message
	var sealedOut string
	err = s.pool.QueryRow(ctx, `
		INSERT INTO messages (conversation_id, sender_id, type, body_sealed)
		VALUES ($1, $2, 'call', $3)
		RETURNING id::text, conversation_id::text, sender_id::text, type, body_sealed, created_at::text
	`, conversationID, senderID, sealed).Scan(
		&m.ID, &m.ConversationID, &m.SenderID, &m.Type, &sealedOut, &m.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	m.Body = string(payload)
	s.fillSenderMeta(ctx, &m, senderID)
	_, _ = s.pool.Exec(ctx, `
		UPDATE conversation_members SET hidden_at = NULL
		WHERE conversation_id = $1 AND hidden_at IS NOT NULL
	`, conversationID)
	return &m, nil
}

func (s *Service) ConversationType(ctx context.Context, conversationID string) (string, error) {
	var typ string
	err := s.pool.QueryRow(ctx, `SELECT type FROM conversations WHERE id = $1`, conversationID).Scan(&typ)
	if err != nil {
		return "", err
	}
	return typ, nil
}

func (s *Service) SearchUser(ctx context.Context, viewerID, q string) (*PublicUser, error) {
	peer, err := s.resolveUser(ctx, q)
	if err != nil {
		return nil, err
	}
	if peer.ID != viewerID {
		same, err := s.sameAutonomousDomain(ctx, viewerID, peer.ID)
		if err != nil {
			return nil, err
		}
		if !same {
			return nil, errors.New("user not found")
		}
	}
	out := &PublicUser{
		ID:        peer.ID,
		Username:  peer.Username,
		HopeID:    peer.HopeID,
		AvatarURL: peer.AvatarURL,
		IsSelf:    peer.ID == viewerID,
	}
	if peer.ID != viewerID {
		friends, err := s.areFriends(ctx, viewerID, peer.ID)
		if err != nil {
			return nil, err
		}
		out.IsFriend = friends
	}
	return out, nil
}

func (s *Service) SearchGroup(ctx context.Context, viewerID, groupNo string) (*PublicGroup, error) {
	groupNo = strings.TrimSpace(groupNo)
	if groupNo == "" {
		return nil, errors.New("group not found")
	}
	var g PublicGroup
	var ownerID *string
	var joinMode string
	err := s.pool.QueryRow(ctx, `
		SELECT id::text, title, group_no, avatar_url, owner_id::text,
			COALESCE(NULLIF(join_mode, ''), 'verify'),
			(SELECT COUNT(*)::int FROM conversation_members cm
			 WHERE cm.conversation_id = conversations.id AND cm.removed_at IS NULL)
		FROM conversations WHERE type = 'group' AND group_no = $1
	`, groupNo).Scan(&g.ID, &g.Title, &g.GroupNo, &g.AvatarURL, &ownerID, &joinMode, &g.MemberCount)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("group not found")
		}
		return nil, err
	}
	g.JoinMode = normalizeJoinMode(joinMode)
	ok, err := s.IsMember(ctx, g.ID, viewerID)
	if err != nil {
		return nil, err
	}
	g.Joined = ok
	if !ok {
		if ownerID == nil || *ownerID == "" {
			return nil, errors.New("group not found")
		}
		same, err := s.sameAutonomousDomain(ctx, viewerID, *ownerID)
		if err != nil {
			return nil, err
		}
		if !same {
			return nil, errors.New("group not found")
		}
		_ = s.pool.QueryRow(ctx, `
			SELECT EXISTS(
				SELECT 1 FROM group_join_requests
				WHERE conversation_id = $1 AND from_user_id = $2 AND status = 'pending'
			)
		`, g.ID, viewerID).Scan(&g.JoinPending)
	}
	return &g, nil
}

func (s *Service) SetGroupAvatarURL(ctx context.Context, conversationID, userID, url string) (*Conversation, error) {
	ok, err := s.canManageGroup(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	_, err = s.pool.Exec(ctx, `UPDATE conversations SET avatar_url = $1 WHERE id = $2`, url, conversationID)
	if err != nil {
		return nil, err
	}
	c, err := s.getConversation(ctx, conversationID)
	if err != nil {
		return nil, err
	}
	s.annotateViewer(ctx, c, userID)
	return c, nil
}

func (s *Service) SetFriendRemark(ctx context.Context, userID, friendID, remark string) (*Contact, error) {
	remark = strings.TrimSpace(remark)
	if utf8Len(remark) > 32 {
		return nil, errors.New("remark too long")
	}
	friends, err := s.areFriends(ctx, userID, friendID)
	if err != nil {
		return nil, err
	}
	if !friends {
		return nil, errors.New("not friends")
	}
	_, err = s.pool.Exec(ctx, `
		UPDATE friendships SET remark = $3 WHERE user_id = $1 AND friend_id = $2
	`, userID, friendID, remark)
	if err != nil {
		return nil, err
	}
	var c Contact
	err = s.pool.QueryRow(ctx, `
		SELECT u.id::text, u.username, u.email, u.hope_id, u.avatar_url, COALESCE(f.remark, '')
		FROM users u
		JOIN friendships f ON f.friend_id = u.id AND f.user_id = $1
		WHERE u.id = $2
	`, userID, friendID).Scan(&c.ID, &c.Username, &c.Email, &c.HopeID, &c.AvatarURL, &c.Remark)
	if err != nil {
		return nil, err
	}
	c.IsFriend = true
	return &c, nil
}

func (s *Service) MemberUserIDs(ctx context.Context, conversationID string) ([]string, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT user_id::text FROM conversation_members
		WHERE conversation_id = $1 AND removed_at IS NULL
	`, conversationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

func (s *Service) UsernameByID(ctx context.Context, userID string) string {
	var name string
	_ = s.pool.QueryRow(ctx, `SELECT username FROM users WHERE id = $1`, userID).Scan(&name)
	return name
}

// PostSystemMessage writes a centered tip in the chat (type=system).
func (s *Service) PostSystemMessage(ctx context.Context, conversationID, actorID, body string) (*Message, error) {
	body = strings.TrimSpace(body)
	if body == "" {
		return nil, errors.New("empty message")
	}
	sealed, err := crypto.Seal(s.key, []byte(body))
	if err != nil {
		return nil, err
	}
	var m Message
	var sealedOut string
	err = s.pool.QueryRow(ctx, `
		INSERT INTO messages (conversation_id, sender_id, type, body_sealed)
		VALUES ($1, $2, 'system', $3)
		RETURNING id::text, conversation_id::text, sender_id::text, type, body_sealed, created_at::text
	`, conversationID, actorID, sealed).Scan(
		&m.ID, &m.ConversationID, &m.SenderID, &m.Type, &sealedOut, &m.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	m.Body = body
	return &m, nil
}

func (s *Service) restoreOrAddMember(ctx context.Context, conversationID, userID string) (bool, error) {
	var wasActive bool
	_ = s.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM conversation_members
			WHERE conversation_id = $1 AND user_id = $2 AND removed_at IS NULL
		)
	`, conversationID, userID).Scan(&wasActive)
	if wasActive {
		_, _ = s.pool.Exec(ctx, `
			UPDATE conversation_members SET hidden_at = NULL
			WHERE conversation_id = $1 AND user_id = $2
		`, conversationID, userID)
		return false, nil
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO conversation_members (conversation_id, user_id, role)
		VALUES ($1, $2, 'member')
		ON CONFLICT (conversation_id, user_id) DO UPDATE
		SET removed_at = NULL, remove_reason = NULL, hidden_at = NULL, role = 'member'
	`, conversationID, userID)
	if err != nil {
		return false, err
	}
	return true, nil
}

// GroupManagerIDs returns owner + admins for notifications.
func (s *Service) GroupManagerIDs(ctx context.Context, conversationID string) ([]string, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT owner_id::text FROM conversations WHERE id = $1 AND owner_id IS NOT NULL
		UNION
		SELECT user_id::text FROM conversation_members
		WHERE conversation_id = $1 AND removed_at IS NULL AND COALESCE(role, 'member') = 'admin'
	`, conversationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		if id != "" {
			out = append(out, id)
		}
	}
	return out, rows.Err()
}

// ListManagedGroupJoinRequests lists pending join requests for all groups the user manages.
func (s *Service) ListManagedGroupJoinRequests(ctx context.Context, userID string) ([]GroupJoinRequest, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT r.id::text, r.conversation_id::text, r.from_user_id::text, r.status, r.message, r.created_at::text,
			u.id::text, u.username, u.email, u.hope_id, u.avatar_url,
			ib.id::text, ib.username, ib.email, ib.hope_id, ib.avatar_url,
			c.id::text, c.type, c.title, c.created_at::text, c.group_no, c.owner_id::text, c.avatar_url
		FROM group_join_requests r
		JOIN conversations c ON c.id = r.conversation_id AND c.type = 'group'
		JOIN users u ON u.id = r.from_user_id
		LEFT JOIN users ib ON ib.id = r.invited_by
		WHERE r.status = 'pending'
		  AND (
			c.owner_id = $1::uuid
			OR EXISTS (
				SELECT 1 FROM conversation_members m
				WHERE m.conversation_id = c.id AND m.user_id = $1::uuid
				  AND m.removed_at IS NULL AND COALESCE(m.role, 'member') = 'admin'
			)
		  )
		ORDER BY r.created_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []GroupJoinRequest{}
	for rows.Next() {
		var r GroupJoinRequest
		var from Contact
		var invID, invUser, invEmail *string
		var invHope, invAvatar *string
		var g Conversation
		if err := rows.Scan(
			&r.ID, &r.ConversationID, &r.FromUserID, &r.Status, &r.Message, &r.CreatedAt,
			&from.ID, &from.Username, &from.Email, &from.HopeID, &from.AvatarURL,
			&invID, &invUser, &invEmail, &invHope, &invAvatar,
			&g.ID, &g.Type, &g.Title, &g.CreatedAt, &g.GroupNo, &g.OwnerID, &g.AvatarURL,
		); err != nil {
			return nil, err
		}
		r.FromUser = &from
		r.Group = &g
		if invID != nil && *invID != "" {
			r.InvitedBy = &Contact{
				ID: *invID, Username: derefStr(invUser), Email: derefStr(invEmail),
				HopeID: invHope, AvatarURL: invAvatar,
			}
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// RemoveFriend deletes the friendship both ways (QQ-style).
// DM sessions stay visible (soft-removed) so both sides can still read history.
func (s *Service) RemoveFriend(ctx context.Context, userID, friendID string) error {
	friendID = strings.TrimSpace(friendID)
	if friendID == "" || friendID == userID {
		return errors.New("user not found")
	}
	tag, err := s.pool.Exec(ctx, `
		DELETE FROM friendships
		WHERE (user_id = $1 AND friend_id = $2) OR (user_id = $2 AND friend_id = $1)
	`, userID, friendID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("not friends")
	}
	_, _ = s.pool.Exec(ctx, `
		UPDATE friend_requests SET status = 'rejected', decided_at = now()
		WHERE status = 'pending'
		  AND ((from_user_id = $1 AND to_user_id = $2) OR (from_user_id = $2 AND to_user_id = $1))
	`, userID, friendID)
	_, _ = s.pool.Exec(ctx, `
		UPDATE conversation_members mem
		SET removed_at = now(), remove_reason = 'unfriended', pinned_at = NULL, hidden_at = NULL
		FROM conversations c
		WHERE mem.conversation_id = c.id
		  AND c.type = 'dm'
		  AND mem.removed_at IS NULL
		  AND mem.user_id IN ($1, $2)
		  AND EXISTS (
			SELECT 1 FROM conversation_members a
			WHERE a.conversation_id = c.id AND a.user_id = $1
		  )
		  AND EXISTS (
			SELECT 1 FROM conversation_members b
			WHERE b.conversation_id = c.id AND b.user_id = $2
		  )
	`, userID, friendID)
	return nil
}
