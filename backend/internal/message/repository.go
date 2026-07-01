package message

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("message not found")

type Message struct {
	ID             string    `json:"id"`
	ConversationID string    `json:"conversation_id"`
	SenderID       string    `json:"sender_id"`
	Type           string    `json:"type"`
	Ciphertext     string    `json:"ciphertext"`
	Epoch          int       `json:"epoch"`
	FileID         *string   `json:"file_id,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) Create(ctx context.Context, conversationID, senderID, msgType, ciphertext string, epoch int) (*Message, error) {
	row := r.pool.QueryRow(ctx, `
		INSERT INTO messages (conversation_id, sender_id, type, ciphertext, epoch)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, conversation_id, sender_id, type, ciphertext, epoch, file_id, created_at`,
		conversationID, senderID, msgType, ciphertext, epoch,
	)
	return scanMessage(row)
}

func (r *Repository) List(ctx context.Context, conversationID string, minEpoch int, before, maxCreatedAt, priorHistoryBefore *time.Time, limit int) ([]Message, error) {
	var rows pgx.Rows
	var err error

	usePriorHistory := priorHistoryBefore != nil && maxCreatedAt == nil

	switch {
	case usePriorHistory && before != nil:
		rows, err = r.pool.Query(ctx, `
			SELECT id, conversation_id, sender_id, type, ciphertext, epoch, file_id, created_at
			FROM messages
			WHERE conversation_id = $1
			  AND (epoch >= $2 OR created_at <= $3)
			  AND created_at < $4
			ORDER BY created_at DESC
			LIMIT $5`, conversationID, minEpoch, *priorHistoryBefore, *before, limit)
	case usePriorHistory:
		rows, err = r.pool.Query(ctx, `
			SELECT id, conversation_id, sender_id, type, ciphertext, epoch, file_id, created_at
			FROM messages
			WHERE conversation_id = $1
			  AND (epoch >= $2 OR created_at <= $3)
			ORDER BY created_at DESC
			LIMIT $4`, conversationID, minEpoch, *priorHistoryBefore, limit)
	case before != nil && maxCreatedAt != nil:
		rows, err = r.pool.Query(ctx, `
			SELECT id, conversation_id, sender_id, type, ciphertext, epoch, file_id, created_at
			FROM messages
			WHERE conversation_id = $1 AND epoch >= $2 AND created_at <= $3 AND created_at < $4
			ORDER BY created_at DESC
			LIMIT $5`, conversationID, minEpoch, *maxCreatedAt, *before, limit)
	case maxCreatedAt != nil:
		rows, err = r.pool.Query(ctx, `
			SELECT id, conversation_id, sender_id, type, ciphertext, epoch, file_id, created_at
			FROM messages
			WHERE conversation_id = $1 AND epoch >= $2 AND created_at <= $3
			ORDER BY created_at DESC
			LIMIT $4`, conversationID, minEpoch, *maxCreatedAt, limit)
	case before != nil:
		rows, err = r.pool.Query(ctx, `
			SELECT id, conversation_id, sender_id, type, ciphertext, epoch, file_id, created_at
			FROM messages
			WHERE conversation_id = $1 AND epoch >= $2 AND created_at < $3
			ORDER BY created_at DESC
			LIMIT $4`, conversationID, minEpoch, *before, limit)
	default:
		rows, err = r.pool.Query(ctx, `
			SELECT id, conversation_id, sender_id, type, ciphertext, epoch, file_id, created_at
			FROM messages
			WHERE conversation_id = $1 AND epoch >= $2
			ORDER BY created_at DESC
			LIMIT $3`, conversationID, minEpoch, limit)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var msgs []Message
	for rows.Next() {
		m, err := scanMessage(rows)
		if err != nil {
			return nil, err
		}
		msgs = append(msgs, *m)
	}
	if msgs == nil {
		msgs = []Message{}
	}
	return msgs, rows.Err()
}

func (r *Repository) ListForMember(
	ctx context.Context,
	conversationID, userID string,
	before *time.Time,
	limit int,
) ([]Message, error) {
	const periodFilter = `
		EXISTS (
			SELECT 1 FROM conversation_member_periods p
			WHERE p.conversation_id = m.conversation_id
			  AND p.user_id = $2
			  AND p.left_at IS NULL
			  AND m.created_at >= p.joined_at
			  AND m.epoch >= p.joined_epoch
		)`

	var rows pgx.Rows
	var err error
	switch {
	case before != nil:
		rows, err = r.pool.Query(ctx, `
			SELECT m.id, m.conversation_id, m.sender_id, m.type, m.ciphertext, m.epoch, m.file_id, m.created_at
			FROM messages m
			WHERE m.conversation_id = $1
			  AND `+periodFilter+`
			  AND m.created_at < $3
			ORDER BY m.created_at DESC
			LIMIT $4`, conversationID, userID, *before, limit)
	default:
		rows, err = r.pool.Query(ctx, `
			SELECT m.id, m.conversation_id, m.sender_id, m.type, m.ciphertext, m.epoch, m.file_id, m.created_at
			FROM messages m
			WHERE m.conversation_id = $1
			  AND `+periodFilter+`
			ORDER BY m.created_at DESC
			LIMIT $3`, conversationID, userID, limit)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var msgs []Message
	for rows.Next() {
		m, err := scanMessage(rows)
		if err != nil {
			return nil, err
		}
		msgs = append(msgs, *m)
	}
	if msgs == nil {
		msgs = []Message{}
	}
	return msgs, rows.Err()
}

func (r *Repository) GetCreatedAt(ctx context.Context, id string) (time.Time, error) {
	var t time.Time
	err := r.pool.QueryRow(ctx, `SELECT created_at FROM messages WHERE id = $1`, id).Scan(&t)
	if errors.Is(err, pgx.ErrNoRows) {
		return time.Time{}, ErrNotFound
	}
	return t, err
}

type scannable interface {
	Scan(dest ...any) error
}

func scanMessage(row scannable) (*Message, error) {
	var m Message
	err := row.Scan(&m.ID, &m.ConversationID, &m.SenderID, &m.Type, &m.Ciphertext, &m.Epoch, &m.FileID, &m.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &m, nil
}
