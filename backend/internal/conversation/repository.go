package conversation

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrNotFound    = errors.New("conversation not found")
	ErrNotMember   = errors.New("not a conversation member")
	ErrInvalidPeer = errors.New("invalid peer user")
)

type Conversation struct {
	ID        string    `json:"id"`
	Type      string    `json:"type"`
	Name      *string   `json:"name,omitempty"`
	Epoch     int       `json:"epoch"`
	OwnerID   *string   `json:"owner_id,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

type Member struct {
	UserID             string    `json:"user_id"`
	Username           string    `json:"username"`
	AvatarURL          *string   `json:"avatar_url,omitempty"`
	IdentityPublicKey  string    `json:"identity_public_key"`
	JoinedAt           time.Time `json:"joined_at"`
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
		SELECT c.id, c.type, c.name, c.epoch, c.owner_id, c.created_at
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
		RETURNING id, type, name, epoch, owner_id, created_at`)
	conv, err := scanConversation(row)
	if err != nil {
		return nil, err
	}

	for _, uid := range []string{userA, userB} {
		if _, err := tx.Exec(ctx, `
			INSERT INTO conversation_members (conversation_id, user_id)
			VALUES ($1, $2)`, conv.ID, uid); err != nil {
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
		VALUES ('group', $1, $2, 1)
		RETURNING id, type, name, epoch, owner_id, created_at`, name, ownerID)
	conv, err := scanConversation(row)
	if err != nil {
		return nil, err
	}

	for _, uid := range memberIDs {
		if _, err := tx.Exec(ctx, `
			INSERT INTO conversation_members (conversation_id, user_id)
			VALUES ($1, $2)`, conv.ID, uid); err != nil {
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
		SELECT id, type, name, epoch, owner_id, created_at
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
		SELECT c.id, c.type, c.name, c.epoch, c.owner_id, c.created_at
		FROM conversations c
		JOIN conversation_members m ON m.conversation_id = c.id
		WHERE m.user_id = $1 AND m.left_at IS NULL
		ORDER BY c.created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []ListItem
	for rows.Next() {
		var item ListItem
		if err := rows.Scan(&item.ID, &item.Type, &item.Name, &item.Epoch, &item.OwnerID, &item.CreatedAt); err != nil {
			return nil, err
		}
		members, err := r.listMembers(ctx, item.ID)
		if err != nil {
			return nil, err
		}
		item.Members = members
		preview, err := r.lastMessage(ctx, item.ID)
		if err != nil {
			return nil, err
		}
		item.LastMessage = preview
		items = append(items, item)
	}
	if items == nil {
		items = []ListItem{}
	}
	return items, rows.Err()
}

func (r *Repository) listMembers(ctx context.Context, conversationID string) ([]Member, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT m.user_id, u.username, u.avatar_url, u.identity_public_key, m.joined_at
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
		if err := rows.Scan(&m.UserID, &m.Username, &m.AvatarURL, &m.IdentityPublicKey, &m.JoinedAt); err != nil {
			return nil, err
		}
		members = append(members, m)
	}
	if members == nil {
		members = []Member{}
	}
	return members, rows.Err()
}

func (r *Repository) lastMessage(ctx context.Context, conversationID string) (*Preview, error) {
	row := r.pool.QueryRow(ctx, `
		SELECT id, conversation_id, sender_id, type, ciphertext, created_at
		FROM messages
		WHERE conversation_id = $1
		ORDER BY created_at DESC
		LIMIT 1`, conversationID)
	var p Preview
	err := row.Scan(&p.ID, &p.ConversationID, &p.SenderID, &p.Type, &p.Ciphertext, &p.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &p, nil
}

type scannable interface {
	Scan(dest ...any) error
}

func scanConversation(row scannable) (*Conversation, error) {
	var c Conversation
	err := row.Scan(&c.ID, &c.Type, &c.Name, &c.Epoch, &c.OwnerID, &c.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &c, nil
}
