package conversation

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrNotFound      = errors.New("conversation not found")
	ErrNotMember     = errors.New("not a conversation member")
	ErrInvalidPeer   = errors.New("invalid peer user")
	ErrNotOwner      = errors.New("not conversation owner")
	ErrNotGroup      = errors.New("not a group conversation")
	ErrAlreadyMember = errors.New("user already in conversation")
)

type Conversation struct {
	ID        string    `json:"id"`
	Type      string    `json:"type"`
	Name      *string   `json:"name,omitempty"`
	AvatarURL *string   `json:"avatar_url,omitempty"`
	Epoch     int       `json:"epoch"`
	OwnerID   *string   `json:"owner_id,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

type Member struct {
	UserID            string    `json:"user_id"`
	Username          string    `json:"username"`
	AvatarURL         *string   `json:"avatar_url,omitempty"`
	IdentityPublicKey string    `json:"identity_public_key"`
	JoinedAt          time.Time `json:"joined_at"`
	JoinedEpoch       int       `json:"joined_epoch"`
}

type ListItem struct {
	Conversation
	Members     []Member   `json:"members"`
	LastMessage *Preview   `json:"last_message,omitempty"`
}

type Preview struct {
	ID             string    `json:"id"`
	ConversationID string    `json:"conversation_id"`
	SenderID       string    `json:"sender_id"`
	Type           string    `json:"type"`
	Ciphertext     string    `json:"ciphertext"`
	Epoch          int       `json:"epoch"`
	CreatedAt      time.Time `json:"created_at"`
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) FindPrivateBetween(ctx context.Context, userA, userB string) (*Conversation, error) {
	row := r.pool.QueryRow(ctx, `
		SELECT c.id, c.type, c.name, c.avatar_url, c.epoch, c.owner_id, c.created_at
		FROM conversations c
		JOIN conversation_members m1 ON m1.conversation_id = c.id AND m1.user_id = $1 AND m1.left_at IS NULL
		JOIN conversation_members m2 ON m2.conversation_id = c.id AND m2.user_id = $2 AND m2.left_at IS NULL
		WHERE c.type = 'private'
		LIMIT 1`, userA, userB)
	c, err := scanConversation(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return c, err
}

func (r *Repository) CreatePrivate(ctx context.Context, userA, userB string) (*Conversation, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	row := tx.QueryRow(ctx, `
		INSERT INTO conversations (type) VALUES ('private')
		RETURNING id, type, name, avatar_url, epoch, owner_id, created_at`)
	conv, err := scanConversation(row)
	if err != nil {
		return nil, err
	}

	for _, uid := range []string{userA, userB} {
		if _, err := tx.Exec(ctx, `
			INSERT INTO conversation_members (conversation_id, user_id, joined_epoch)
			VALUES ($1, $2, 0)`, conv.ID, uid); err != nil {
			return nil, err
		}
		if err := r.insertMemberPeriodTx(ctx, tx, conv.ID, uid, 0); err != nil {
			return nil, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return conv, nil
}

func (r *Repository) CreateGroup(ctx context.Context, name, ownerID string, memberIDs []string) (*Conversation, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	row := tx.QueryRow(ctx, `
		INSERT INTO conversations (type, name, owner_id, epoch)
		VALUES ('group', $1, $2, 0)
		RETURNING id, type, name, avatar_url, epoch, owner_id, created_at`, name, ownerID)
	conv, err := scanConversation(row)
	if err != nil {
		return nil, err
	}

	unique := map[string]struct{}{ownerID: {}}
	for _, uid := range memberIDs {
		uid = strings.TrimSpace(uid)
		if uid == "" {
			continue
		}
		unique[uid] = struct{}{}
	}

	for uid := range unique {
		if _, err := tx.Exec(ctx, `
			INSERT INTO conversation_members (conversation_id, user_id, joined_epoch)
			VALUES ($1, $2, 0)`, conv.ID, uid); err != nil {
			return nil, err
		}
		if err := r.insertMemberPeriodTx(ctx, tx, conv.ID, uid, 0); err != nil {
			return nil, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return conv, nil
}

func (r *Repository) GetByID(ctx context.Context, id string) (*Conversation, error) {
	row := r.pool.QueryRow(ctx, `
		SELECT id, type, name, avatar_url, epoch, owner_id, created_at
		FROM conversations WHERE id = $1`, id)
	c, err := scanConversation(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return c, err
}

func (r *Repository) IsActiveMember(ctx context.Context, conversationID, userID string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM conversation_members
			WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL
		)`, conversationID, userID).Scan(&exists)
	return exists, err
}

func (r *Repository) ListMemberUserIDs(ctx context.Context, conversationID string) ([]string, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT user_id FROM conversation_members
		WHERE conversation_id = $1 AND left_at IS NULL`, conversationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func (r *Repository) ListForUser(ctx context.Context, userID string) ([]ListItem, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT c.id, c.type, c.name, c.avatar_url, c.epoch, c.owner_id, c.created_at, m.joined_epoch
		FROM conversations c
		JOIN conversation_members m ON m.conversation_id = c.id AND m.user_id = $1 AND m.left_at IS NULL
		ORDER BY c.created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []ListItem
	joinedEpochs := make(map[string]int)
	for rows.Next() {
		var item ListItem
		var joined int
		if err := rows.Scan(
			&item.ID, &item.Type, &item.Name, &item.AvatarURL,
			&item.Epoch, &item.OwnerID, &item.CreatedAt, &joined,
		); err != nil {
			return nil, err
		}
		items = append(items, item)
		joinedEpochs[item.ID] = joined
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(items) == 0 {
		return []ListItem{}, nil
	}

	convIDs := make([]string, len(items))
	for i := range items {
		convIDs[i] = items[i].ID
	}

	membersByConv, err := r.listMembersMap(ctx, convIDs)
	if err != nil {
		return nil, err
	}
	previewsByConv, err := r.lastMessagesForUser(ctx, userID, convIDs)
	if err != nil {
		return nil, err
	}

	for i := range items {
		id := items[i].ID
		items[i].Members = membersByConv[id]
		if items[i].Members == nil {
			items[i].Members = []Member{}
		}
		items[i].LastMessage = previewsByConv[id]
	}
	return items, nil
}

func (r *Repository) listMembersMap(ctx context.Context, conversationIDs []string) (map[string][]Member, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT m.conversation_id, m.user_id, u.username, u.avatar_url, u.identity_public_key, m.joined_at, m.joined_epoch
		FROM conversation_members m
		JOIN users u ON u.id = m.user_id
		WHERE m.conversation_id = ANY($1) AND m.left_at IS NULL
		ORDER BY m.conversation_id, m.joined_at`, conversationIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make(map[string][]Member)
	for rows.Next() {
		var convID string
		var m Member
		if err := rows.Scan(
			&convID, &m.UserID, &m.Username, &m.AvatarURL,
			&m.IdentityPublicKey, &m.JoinedAt, &m.JoinedEpoch,
		); err != nil {
			return nil, err
		}
		out[convID] = append(out[convID], m)
	}
	return out, rows.Err()
}

func (r *Repository) lastMessagesForUser(
	ctx context.Context,
	userID string,
	conversationIDs []string,
) (map[string]*Preview, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT DISTINCT ON (msg.conversation_id)
			msg.id, msg.conversation_id, msg.sender_id, msg.type, msg.ciphertext, msg.epoch, msg.created_at
		FROM messages msg
		JOIN conversation_members cm
		  ON cm.conversation_id = msg.conversation_id
		 AND cm.user_id = $1
		 AND cm.left_at IS NULL
		 AND msg.epoch >= cm.joined_epoch
		WHERE msg.conversation_id = ANY($2)
		ORDER BY msg.conversation_id, msg.created_at DESC`,
		userID, conversationIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make(map[string]*Preview)
	for rows.Next() {
		var p Preview
		if err := rows.Scan(
			&p.ID, &p.ConversationID, &p.SenderID, &p.Type, &p.Ciphertext, &p.Epoch, &p.CreatedAt,
		); err != nil {
			return nil, err
		}
		out[p.ConversationID] = &p
	}
	return out, rows.Err()
}

func (r *Repository) listMembers(ctx context.Context, conversationID string) ([]Member, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT m.user_id, u.username, u.avatar_url, u.identity_public_key, m.joined_at, m.joined_epoch
		FROM conversation_members m
		JOIN users u ON u.id = m.user_id
		WHERE m.conversation_id = $1 AND m.left_at IS NULL
		ORDER BY m.joined_at`, conversationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var members []Member
	for rows.Next() {
		var m Member
		if err := rows.Scan(&m.UserID, &m.Username, &m.AvatarURL, &m.IdentityPublicKey, &m.JoinedAt, &m.JoinedEpoch); err != nil {
			return nil, err
		}
		members = append(members, m)
	}
	if members == nil {
		members = []Member{}
	}
	return members, rows.Err()
}

// ListMemberDirectory 返回曾在群内出现过的成员（含已退群），供历史消息展示昵称/头像。
func (r *Repository) ListMemberDirectory(ctx context.Context, conversationID string) ([]Member, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT DISTINCT ON (p.user_id)
			p.user_id, u.username, u.avatar_url, u.identity_public_key, p.joined_epoch
		FROM conversation_member_periods p
		JOIN users u ON u.id = p.user_id
		WHERE p.conversation_id = $1
		ORDER BY p.user_id, p.joined_at ASC`, conversationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var members []Member
	for rows.Next() {
		var m Member
		if err := rows.Scan(&m.UserID, &m.Username, &m.AvatarURL, &m.IdentityPublicKey, &m.JoinedEpoch); err != nil {
			return nil, err
		}
		members = append(members, m)
	}
	if members == nil {
		members = []Member{}
	}
	return members, rows.Err()
}

func (r *Repository) HasAnyMembership(
	ctx context.Context,
	conversationID, userID string,
) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM conversation_member_periods
			WHERE conversation_id = $1 AND user_id = $2
		)`, conversationID, userID).Scan(&exists)
	return exists, err
}

func (r *Repository) lastMessage(ctx context.Context, conversationID string) (*Preview, error) {
	row := r.pool.QueryRow(ctx, `
		SELECT id, conversation_id, sender_id, type, ciphertext, epoch, created_at
		FROM messages
		WHERE conversation_id = $1
		ORDER BY created_at DESC
		LIMIT 1`, conversationID)
	return scanPreview(row)
}

func (r *Repository) lastMessageForUser(ctx context.Context, conversationID, userID string) (*Preview, error) {
	joinedEpoch, err := r.GetMemberJoinedEpoch(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	row := r.pool.QueryRow(ctx, `
		SELECT id, conversation_id, sender_id, type, ciphertext, epoch, created_at
		FROM messages
		WHERE conversation_id = $1 AND epoch >= $2
		ORDER BY created_at DESC
		LIMIT 1`, conversationID, joinedEpoch)
	return scanPreview(row)
}

func scanPreview(row scannable) (*Preview, error) {
	var p Preview
	err := row.Scan(&p.ID, &p.ConversationID, &p.SenderID, &p.Type, &p.Ciphertext, &p.Epoch, &p.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &p, nil
}

func (r *Repository) GetMemberJoinedEpoch(ctx context.Context, conversationID, userID string) (int, error) {
	var epoch int
	err := r.pool.QueryRow(ctx, `
		SELECT joined_epoch FROM conversation_members
		WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL`,
		conversationID, userID).Scan(&epoch)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, ErrNotMember
	}
	return epoch, err
}

// MembershipInfo 成员记录（含已退群）。
type MembershipInfo struct {
	JoinedEpoch   int
	LeftAt        *time.Time
	LastLeftAt    *time.Time
}

func (r *Repository) GetMembership(ctx context.Context, conversationID, userID string) (*MembershipInfo, error) {
	var info MembershipInfo
	var leftAt *time.Time
	var lastLeftAt *time.Time
	err := r.pool.QueryRow(ctx, `
		SELECT joined_epoch, left_at, last_left_at FROM conversation_members
		WHERE conversation_id = $1 AND user_id = $2`,
		conversationID, userID).Scan(&info.JoinedEpoch, &leftAt, &lastLeftAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotMember
	}
	if err != nil {
		return nil, err
	}
	info.LeftAt = leftAt
	info.LastLeftAt = lastLeftAt
	return &info, nil
}

func (r *Repository) AddMembers(ctx context.Context, conversationID, actorID string, memberIDs []string) (int, error) {
	conv, err := r.GetByID(ctx, conversationID)
	if err != nil {
		return 0, err
	}
	if conv.Type != "group" {
		return 0, ErrNotGroup
	}
	if conv.OwnerID == nil || *conv.OwnerID != actorID {
		return 0, ErrNotOwner
	}

	unique := make([]string, 0, len(memberIDs))
	seen := map[string]struct{}{}
	for _, id := range memberIDs {
		id = strings.TrimSpace(id)
		if id == "" {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		unique = append(unique, id)
	}
	if len(unique) == 0 {
		return 0, ErrInvalidPeer
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	newEpoch := conv.Epoch + 1
	if _, err := tx.Exec(ctx, `UPDATE conversations SET epoch = $1 WHERE id = $2`, newEpoch, conversationID); err != nil {
		return 0, err
	}

	var active []string
	rows, err := tx.Query(ctx, `
		SELECT user_id FROM conversation_members
		WHERE conversation_id = $1 AND user_id = ANY($2) AND left_at IS NULL`,
		conversationID, unique)
	if err != nil {
		return 0, err
	}
	for rows.Next() {
		var uid string
		if err := rows.Scan(&uid); err != nil {
			rows.Close()
			return 0, err
		}
		active = append(active, uid)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}
	if len(active) > 0 {
		return 0, ErrAlreadyMember
	}

	for _, uid := range unique {
		tag, err := tx.Exec(ctx, `
			INSERT INTO conversation_members (conversation_id, user_id, joined_epoch)
			VALUES ($1, $2, $3)
			ON CONFLICT (conversation_id, user_id) DO UPDATE
			SET left_at = NULL, joined_at = now(), joined_epoch = EXCLUDED.joined_epoch`,
			conversationID, uid, newEpoch)
		if err != nil {
			return 0, err
		}
		if tag.RowsAffected() == 0 {
			return 0, ErrAlreadyMember
		}
		if err := r.insertMemberPeriodTx(ctx, tx, conversationID, uid, newEpoch); err != nil {
			return 0, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return newEpoch, nil
}

func (r *Repository) RemoveMember(ctx context.Context, conversationID, actorID, targetID string) (int, error) {
	conv, err := r.GetByID(ctx, conversationID)
	if err != nil {
		return 0, err
	}
	if conv.Type != "group" {
		return 0, ErrNotGroup
	}

	isOwner := conv.OwnerID != nil && *conv.OwnerID == actorID
	if actorID != targetID && !isOwner {
		return 0, ErrNotOwner
	}

	var active bool
	if err := r.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM conversation_members
			WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL
		)`, conversationID, targetID).Scan(&active); err != nil {
		return 0, err
	}
	if !active {
		return 0, ErrNotMember
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	newEpoch := conv.Epoch + 1
	if _, err := tx.Exec(ctx, `UPDATE conversations SET epoch = $1 WHERE id = $2`, newEpoch, conversationID); err != nil {
		return 0, err
	}
	if _, err := tx.Exec(ctx, `
		UPDATE conversation_members SET left_at = now(), last_left_at = now()
		WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL`,
		conversationID, targetID); err != nil {
		return 0, err
	}
	if _, err := tx.Exec(ctx, `
		UPDATE conversation_member_periods SET left_at = now()
		WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NULL`,
		conversationID, targetID); err != nil {
		return 0, err
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return newEpoch, nil
}

// BumpEpoch 定期轮换 GMK：仅递增 epoch，不改变成员 joined_epoch。
func (r *Repository) BumpEpoch(ctx context.Context, conversationID string) (int, error) {
	conv, err := r.GetByID(ctx, conversationID)
	if err != nil {
		return 0, err
	}
	if conv.Type != "group" {
		return 0, ErrNotGroup
	}
	newEpoch := conv.Epoch + 1
	tag, err := r.pool.Exec(ctx, `
		UPDATE conversations SET epoch = $1 WHERE id = $2 AND epoch = $3`,
		newEpoch, conversationID, conv.Epoch)
	if err != nil {
		return 0, err
	}
	if tag.RowsAffected() == 0 {
		return 0, ErrInvalidInput
	}
	return newEpoch, nil
}

func (r *Repository) TouchMemberLeftAt(ctx context.Context, conversationID, userID string) error {
	if _, err := r.pool.Exec(ctx, `
		UPDATE conversation_members SET left_at = now(), last_left_at = now()
		WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NOT NULL`,
		conversationID, userID); err != nil {
		return err
	}
	_, err := r.pool.Exec(ctx, `
		UPDATE conversation_member_periods SET left_at = now()
		WHERE conversation_id = $1 AND user_id = $2 AND left_at IS NOT NULL`,
		conversationID, userID)
	return err
}

func (r *Repository) DissolveGroup(ctx context.Context, conversationID, actorID string) error {
	conv, err := r.GetByID(ctx, conversationID)
	if err != nil {
		return err
	}
	if conv.Type != "group" {
		return ErrNotGroup
	}
	if conv.OwnerID == nil || *conv.OwnerID != actorID {
		return ErrNotOwner
	}
	_, err = r.pool.Exec(ctx, `DELETE FROM conversations WHERE id = $1`, conversationID)
	return err
}

type scannable interface {
	Scan(dest ...any) error
}

func (r *Repository) UpdateGroupName(ctx context.Context, conversationID, name string) (*Conversation, error) {
	row := r.pool.QueryRow(ctx, `
		UPDATE conversations SET name = $2
		WHERE id = $1 AND type = 'group'
		RETURNING id, type, name, avatar_url, epoch, owner_id, created_at`,
		conversationID, name,
	)
	conv, err := scanConversation(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotGroup
	}
	return conv, err
}

func (r *Repository) UpdateGroupAvatarURL(ctx context.Context, conversationID, avatarURL string) (*Conversation, error) {
	row := r.pool.QueryRow(ctx, `
		UPDATE conversations SET avatar_url = $2
		WHERE id = $1 AND type = 'group'
		RETURNING id, type, name, avatar_url, epoch, owner_id, created_at`,
		conversationID, avatarURL,
	)
	conv, err := scanConversation(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotGroup
	}
	return conv, err
}

func (r *Repository) insertMemberPeriodTx(
	ctx context.Context,
	tx pgx.Tx,
	conversationID, userID string,
	joinedEpoch int,
) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO conversation_member_periods (conversation_id, user_id, joined_epoch)
		VALUES ($1, $2, $3)`,
		conversationID, userID, joinedEpoch,
	)
	return err
}

func scanConversation(row scannable) (*Conversation, error) {
	var c Conversation
	err := row.Scan(&c.ID, &c.Type, &c.Name, &c.AvatarURL, &c.Epoch, &c.OwnerID, &c.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &c, nil
}
