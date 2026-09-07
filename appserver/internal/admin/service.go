package admin

import (
	"context"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

type UserRow struct {
	ID             string  `json:"id"`
	Email          string  `json:"email"`
	Username       string  `json:"username"`
	HopeID         *string `json:"hopeId,omitempty"`
	EmailVerified  bool    `json:"emailVerified"`
	CreatedAt      string  `json:"createdAt"`
	QQBound        bool    `json:"qqBound"`
	QQOpenID       *string `json:"qqOpenId,omitempty"`
	FellowshipID   *string `json:"fellowshipId,omitempty"`
	FellowshipCode *string `json:"fellowshipCode,omitempty"`
	FellowshipName *string `json:"fellowshipName,omitempty"`
	DomainID       *string `json:"domainId,omitempty"`
	DomainName     *string `json:"domainName,omitempty"`
}

type ConversationRow struct {
	ID                     string  `json:"id"`
	Type                   string  `json:"type"`
	Title                  string  `json:"title"`
	MemberCount            int     `json:"memberCount"`
	CreatedAt              string  `json:"createdAt"`
	Members                string  `json:"members"` // usernames joined
	GroupNo                *string `json:"groupNo,omitempty"`
	OwnerUsername          string  `json:"ownerUsername,omitempty"`
	JoinMode               string  `json:"joinMode"`
	InviteRequiresApproval bool    `json:"inviteRequiresApproval"` // legacy mirror of joinMode=verify
	Announcement           string  `json:"announcement,omitempty"`
	PendingJoins           int     `json:"pendingJoins"`
}

type Stats struct {
	Users                 int `json:"users"`
	Groups                int `json:"groups"`
	DMs                   int `json:"dms"`
	PendingFriendRequests int `json:"pendingFriendRequests"`
	PendingGroupJoins     int `json:"pendingGroupJoins"`
	UnverifiedUsers       int `json:"unverifiedUsers"`
	QQBound               int `json:"qqBound"`
}

type GroupMemberRow struct {
	ID          string  `json:"id"`
	Username    string  `json:"username"`
	HopeID      *string `json:"hopeId,omitempty"`
	AvatarURL   *string `json:"avatarUrl,omitempty"`
	Role        string  `json:"role"`
	IsOwner     bool    `json:"isOwner"`
	MemberTitle string  `json:"memberTitle,omitempty"`
	Removed     bool    `json:"removed,omitempty"`
}

type GroupJoinRequestRow struct {
	ID             string  `json:"id"`
	ConversationID string  `json:"conversationId"`
	GroupTitle     string  `json:"groupTitle"`
	GroupNo        *string `json:"groupNo,omitempty"`
	FromUserID     string  `json:"fromUserId"`
	FromUsername   string  `json:"fromUsername"`
	FromHopeID     *string `json:"fromHopeId,omitempty"`
	FromAvatarURL  *string `json:"fromAvatarUrl,omitempty"`
	Message        string  `json:"message"`
	InvitedByName  string  `json:"invitedByName,omitempty"`
	CreatedAt      string  `json:"createdAt"`
}

type GroupDetail struct {
	Conversation ConversationRow   `json:"conversation"`
	Members      []GroupMemberRow  `json:"members"`
	JoinRequests []GroupJoinRequestRow `json:"joinRequests"`
}

type Service struct {
	pool *pgxpool.Pool
}

func NewService(pool *pgxpool.Pool) *Service {
	return &Service{pool: pool}
}

func (s *Service) ListUsers(ctx context.Context) ([]UserRow, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT u.id::text, u.email, u.username, u.hope_id, u.email_verified, u.created_at::text,
			(q.user_id IS NOT NULL), q.qq_openid,
			u.fellowship_id::text, f.code, f.name, d.id::text, d.name
		FROM users u
		LEFT JOIN user_qq_bindings q ON q.user_id = u.id
		LEFT JOIN fellowships f ON f.id = u.fellowship_id
		LEFT JOIN autonomous_domains d ON d.id = f.domain_id
		ORDER BY u.created_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []UserRow
	for rows.Next() {
		var u UserRow
		var openID *string
		if err := rows.Scan(
			&u.ID, &u.Email, &u.Username, &u.HopeID, &u.EmailVerified, &u.CreatedAt,
			&u.QQBound, &openID,
			&u.FellowshipID, &u.FellowshipCode, &u.FellowshipName, &u.DomainID, &u.DomainName,
		); err != nil {
			return nil, err
		}
		u.QQOpenID = openID
		out = append(out, u)
	}
	if out == nil {
		out = []UserRow{}
	}
	return out, rows.Err()
}

func (s *Service) UserExists(ctx context.Context, userID string) (bool, error) {
	var ok bool
	err := s.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)`, userID).Scan(&ok)
	return ok, err
}

func (s *Service) DeleteUser(ctx context.Context, userID string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var exists bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)`, userID).Scan(&exists); err != nil {
		return err
	}
	if !exists {
		return errors.New("user not found")
	}

	// DM conversations involving this user → delete whole conversation (messages cascade).
	_, err = tx.Exec(ctx, `
		DELETE FROM conversations c
		WHERE c.type = 'dm'
		  AND EXISTS (
			SELECT 1 FROM conversation_members m
			WHERE m.conversation_id = c.id AND m.user_id = $1
		  )
	`, userID)
	if err != nil {
		return err
	}

	// Messages they sent in remaining (group) chats.
	if _, err := tx.Exec(ctx, `DELETE FROM messages WHERE sender_id = $1`, userID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `DELETE FROM conversation_members WHERE user_id = $1`, userID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `
		DELETE FROM friendships WHERE user_id = $1 OR friend_id = $1
	`, userID); err != nil {
		return err
	}

	// Empty groups left behind.
	if _, err := tx.Exec(ctx, `
		DELETE FROM conversations c
		WHERE c.type = 'group'
		  AND NOT EXISTS (
			SELECT 1 FROM conversation_members m WHERE m.conversation_id = c.id
		  )
	`); err != nil {
		return err
	}

	tag, err := tx.Exec(ctx, `DELETE FROM users WHERE id = $1`, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("user not found")
	}
	return tx.Commit(ctx)
}

func (s *Service) ListConversations(ctx context.Context) ([]ConversationRow, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT c.id::text, c.type, c.title, c.created_at::text,
			(SELECT COUNT(*)::int FROM conversation_members cm
			 WHERE cm.conversation_id = c.id AND cm.removed_at IS NULL),
			COALESCE((
				SELECT string_agg(u.username, ', ' ORDER BY u.username)
				FROM conversation_members cm2
				JOIN users u ON u.id = cm2.user_id
				WHERE cm2.conversation_id = c.id AND cm2.removed_at IS NULL
			), ''),
			c.group_no,
			COALESCE((SELECT u.username FROM users u WHERE u.id = c.owner_id), ''),
			COALESCE(NULLIF(c.join_mode, ''), 'verify'),
			COALESCE((
				SELECT a.body FROM group_announcements a
				WHERE a.conversation_id = c.id
				ORDER BY a.created_at DESC LIMIT 1
			), ''),
			COALESCE((
				SELECT COUNT(*)::int FROM group_join_requests r
				WHERE r.conversation_id = c.id AND r.status = 'pending'
			), 0)
		FROM conversations c
		ORDER BY c.created_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ConversationRow
	for rows.Next() {
		var c ConversationRow
		if err := rows.Scan(
			&c.ID, &c.Type, &c.Title, &c.CreatedAt, &c.MemberCount, &c.Members,
			&c.GroupNo, &c.OwnerUsername, &c.JoinMode, &c.Announcement, &c.PendingJoins,
		); err != nil {
			return nil, err
		}
		c.InviteRequiresApproval = c.JoinMode == "verify"
		out = append(out, c)
	}
	if out == nil {
		out = []ConversationRow{}
	}
	return out, rows.Err()
}

func (s *Service) DeleteConversation(ctx context.Context, id string) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM conversations WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("conversation not found")
	}
	return nil
}

func (s *Service) Stats(ctx context.Context) (*Stats, error) {
	var st Stats
	err := s.pool.QueryRow(ctx, `
		SELECT
			(SELECT COUNT(*)::int FROM users),
			(SELECT COUNT(*)::int FROM conversations WHERE type = 'group'),
			(SELECT COUNT(*)::int FROM conversations WHERE type = 'dm'),
			(SELECT COUNT(*)::int FROM friend_requests WHERE status = 'pending'),
			(SELECT COUNT(*)::int FROM group_join_requests WHERE status = 'pending'),
			(SELECT COUNT(*)::int FROM users WHERE email_verified = FALSE),
			(SELECT COUNT(*)::int FROM user_qq_bindings)
	`).Scan(
		&st.Users, &st.Groups, &st.DMs,
		&st.PendingFriendRequests, &st.PendingGroupJoins,
		&st.UnverifiedUsers, &st.QQBound,
	)
	if err != nil {
		return nil, err
	}
	return &st, nil
}

func (s *Service) SetEmailVerified(ctx context.Context, userID string, verified bool) error {
	tag, err := s.pool.Exec(ctx, `
		UPDATE users SET email_verified = $2 WHERE id = $1
	`, userID, verified)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("user not found")
	}
	return nil
}

func (s *Service) GetGroupDetail(ctx context.Context, id string) (*GroupDetail, error) {
	var c ConversationRow
	err := s.pool.QueryRow(ctx, `
		SELECT c.id::text, c.type, c.title, c.created_at::text,
			(SELECT COUNT(*)::int FROM conversation_members cm
			 WHERE cm.conversation_id = c.id AND cm.removed_at IS NULL),
			COALESCE((
				SELECT string_agg(u.username, ', ' ORDER BY u.username)
				FROM conversation_members cm2
				JOIN users u ON u.id = cm2.user_id
				WHERE cm2.conversation_id = c.id AND cm2.removed_at IS NULL
			), ''),
			c.group_no,
			COALESCE((SELECT u.username FROM users u WHERE u.id = c.owner_id), ''),
			COALESCE(NULLIF(c.join_mode, ''), 'verify'),
			COALESCE((
				SELECT a.body FROM group_announcements a
				WHERE a.conversation_id = c.id
				ORDER BY a.created_at DESC LIMIT 1
			), ''),
			COALESCE((
				SELECT COUNT(*)::int FROM group_join_requests r
				WHERE r.conversation_id = c.id AND r.status = 'pending'
			), 0)
		FROM conversations c WHERE c.id = $1 AND c.type = 'group'
	`, id).Scan(
		&c.ID, &c.Type, &c.Title, &c.CreatedAt, &c.MemberCount, &c.Members,
		&c.GroupNo, &c.OwnerUsername, &c.JoinMode, &c.Announcement, &c.PendingJoins,
	)
	if err != nil {
		return nil, errors.New("group not found")
	}
	c.InviteRequiresApproval = c.JoinMode == "verify"

	mrows, err := s.pool.Query(ctx, `
		SELECT u.id::text, u.username, u.hope_id, u.avatar_url,
			COALESCE(m.role, 'member'), COALESCE(m.member_title, ''),
			(c.owner_id = m.user_id), (m.removed_at IS NOT NULL)
		FROM conversation_members m
		JOIN users u ON u.id = m.user_id
		JOIN conversations c ON c.id = m.conversation_id
		WHERE m.conversation_id = $1
		ORDER BY m.removed_at NULLS FIRST, m.joined_at
	`, id)
	if err != nil {
		return nil, err
	}
	defer mrows.Close()
	members := []GroupMemberRow{}
	for mrows.Next() {
		var m GroupMemberRow
		if err := mrows.Scan(
			&m.ID, &m.Username, &m.HopeID, &m.AvatarURL,
			&m.Role, &m.MemberTitle, &m.IsOwner, &m.Removed,
		); err != nil {
			return nil, err
		}
		members = append(members, m)
	}

	jrows, err := s.pool.Query(ctx, `
		SELECT r.id::text, r.conversation_id::text, c.title, c.group_no,
			r.from_user_id::text, u.username, u.hope_id, u.avatar_url,
			r.message, COALESCE(ib.username, ''), r.created_at::text
		FROM group_join_requests r
		JOIN conversations c ON c.id = r.conversation_id
		JOIN users u ON u.id = r.from_user_id
		LEFT JOIN users ib ON ib.id = r.invited_by
		WHERE r.conversation_id = $1 AND r.status = 'pending'
		ORDER BY r.created_at DESC
	`, id)
	if err != nil {
		return nil, err
	}
	defer jrows.Close()
	joins := []GroupJoinRequestRow{}
	for jrows.Next() {
		var j GroupJoinRequestRow
		if err := jrows.Scan(
			&j.ID, &j.ConversationID, &j.GroupTitle, &j.GroupNo,
			&j.FromUserID, &j.FromUsername, &j.FromHopeID, &j.FromAvatarURL,
			&j.Message, &j.InvitedByName, &j.CreatedAt,
		); err != nil {
			return nil, err
		}
		joins = append(joins, j)
	}

	return &GroupDetail{Conversation: c, Members: members, JoinRequests: joins}, nil
}

func (s *Service) ListPendingGroupJoins(ctx context.Context) ([]GroupJoinRequestRow, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT r.id::text, r.conversation_id::text, c.title, c.group_no,
			r.from_user_id::text, u.username, u.hope_id, u.avatar_url,
			r.message, COALESCE(ib.username, ''), r.created_at::text
		FROM group_join_requests r
		JOIN conversations c ON c.id = r.conversation_id AND c.type = 'group'
		JOIN users u ON u.id = r.from_user_id
		LEFT JOIN users ib ON ib.id = r.invited_by
		WHERE r.status = 'pending'
		ORDER BY r.created_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []GroupJoinRequestRow{}
	for rows.Next() {
		var j GroupJoinRequestRow
		if err := rows.Scan(
			&j.ID, &j.ConversationID, &j.GroupTitle, &j.GroupNo,
			&j.FromUserID, &j.FromUsername, &j.FromHopeID, &j.FromAvatarURL,
			&j.Message, &j.InvitedByName, &j.CreatedAt,
		); err != nil {
			return nil, err
		}
		out = append(out, j)
	}
	return out, rows.Err()
}

func (s *Service) PatchGroup(ctx context.Context, id string, joinMode *string, title *string) (*ConversationRow, error) {
	var typ string
	err := s.pool.QueryRow(ctx, `SELECT type FROM conversations WHERE id = $1`, id).Scan(&typ)
	if err != nil {
		return nil, errors.New("group not found")
	}
	if typ != "group" {
		return nil, errors.New("not a group")
	}
	if title != nil {
		t := strings.TrimSpace(*title)
		if len([]rune(t)) == 0 {
			return nil, errors.New("group title required")
		}
		if len([]rune(t)) > 32 {
			return nil, errors.New("group title too long")
		}
		_, err = s.pool.Exec(ctx, `UPDATE conversations SET title = $1 WHERE id = $2`, t, id)
		if err != nil {
			return nil, err
		}
	}
	if joinMode != nil {
		mode := strings.TrimSpace(*joinMode)
		if mode != "anyone" && mode != "verify" && mode != "deny" {
			return nil, errors.New("invalid join mode")
		}
		_, err = s.pool.Exec(ctx, `
			UPDATE conversations
			SET join_mode = $1, invite_requires_approval = ($1 = 'verify')
			WHERE id = $2
		`, mode, id)
		if err != nil {
			return nil, err
		}
	}
	list, err := s.ListConversations(ctx)
	if err != nil {
		return nil, err
	}
	for i := range list {
		if list[i].ID == id {
			return &list[i], nil
		}
	}
	return nil, errors.New("group not found")
}

// KickGroupMember soft-removes a member (platform admin, no role checks).
func (s *Service) KickGroupMember(ctx context.Context, conversationID, memberID string) error {
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

// SetGroupMemberRole sets admin/member for a group member (platform admin).
func (s *Service) SetGroupMemberRole(ctx context.Context, conversationID, memberID, role string) error {
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
	if ownerID != nil && *ownerID == memberID {
		return errors.New("cannot change owner role")
	}
	tag, err := s.pool.Exec(ctx, `
		UPDATE conversation_members SET role = $3
		WHERE conversation_id = $1 AND user_id = $2 AND removed_at IS NULL
	`, conversationID, memberID, role)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("member not found")
	}
	return nil
}

// TransferGroupOwner transfers ownership to an active member (platform admin).
// Previous owner becomes admin.
func (s *Service) TransferGroupOwner(ctx context.Context, conversationID, newOwnerID string) error {
	newOwnerID = strings.TrimSpace(newOwnerID)
	if newOwnerID == "" {
		return errors.New("member id required")
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
	if ownerID != nil && *ownerID == newOwnerID {
		return errors.New("already owner")
	}
	var active bool
	err = s.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM conversation_members
			WHERE conversation_id = $1 AND user_id = $2 AND removed_at IS NULL
		)
	`, conversationID, newOwnerID).Scan(&active)
	if err != nil {
		return err
	}
	if !active {
		return errors.New("member not found")
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `UPDATE conversations SET owner_id = $1 WHERE id = $2`, newOwnerID, conversationID); err != nil {
		return err
	}
	if ownerID != nil && *ownerID != "" {
		if _, err = tx.Exec(ctx, `
			UPDATE conversation_members SET role = 'admin'
			WHERE conversation_id = $1 AND user_id = $2 AND removed_at IS NULL
		`, conversationID, *ownerID); err != nil {
			return err
		}
	}
	if _, err = tx.Exec(ctx, `
		UPDATE conversation_members SET role = 'member'
		WHERE conversation_id = $1 AND user_id = $2 AND removed_at IS NULL
	`, conversationID, newOwnerID); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *Service) AcceptGroupJoin(ctx context.Context, conversationID, requestID string) error {
	var fromID, reqConv string
	err := s.pool.QueryRow(ctx, `
		SELECT from_user_id::text, conversation_id::text FROM group_join_requests
		WHERE id = $1 AND status = 'pending'
	`, requestID).Scan(&fromID, &reqConv)
	if err != nil {
		return errors.New("request not found")
	}
	if reqConv != conversationID {
		return errors.New("request not found")
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	tag, err := tx.Exec(ctx, `
		UPDATE group_join_requests SET status = 'accepted', decided_at = now()
		WHERE id = $1 AND status = 'pending'
	`, requestID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("request not found")
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO conversation_members (conversation_id, user_id, role)
		VALUES ($1, $2, 'member')
		ON CONFLICT (conversation_id, user_id) DO UPDATE
		SET removed_at = NULL, remove_reason = NULL, hidden_at = NULL, role = 'member'
	`, conversationID, fromID)
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *Service) RejectGroupJoin(ctx context.Context, conversationID, requestID string) error {
	tag, err := s.pool.Exec(ctx, `
		UPDATE group_join_requests SET status = 'rejected', decided_at = now()
		WHERE id = $1 AND conversation_id = $2 AND status = 'pending'
	`, requestID, conversationID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("request not found")
	}
	return nil
}
