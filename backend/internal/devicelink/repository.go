package devicelink

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrNotFound    = errors.New("device link not found")
	ErrExpired     = errors.New("device link expired")
	ErrNotReady    = errors.New("device link payload not ready")
	ErrAlreadyUsed = errors.New("device link already used")
	ErrForbidden   = errors.New("device link forbidden")
)

type Session struct {
	ID                string
	UserID            string
	InitiatorDeviceID string
	Ciphertext        *string
	Status            string
	ExpiresAt         time.Time
	CompletedDeviceID *string
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) Create(
	ctx context.Context,
	userID, initiatorDeviceID, tokenHash string,
	expiresAt time.Time,
) (string, error) {
	var id string
	err := r.pool.QueryRow(ctx, `
		INSERT INTO device_link_sessions (user_id, token_hash, initiator_device_id, expires_at)
		VALUES ($1, $2, $3, $4)
		RETURNING id`, userID, tokenHash, initiatorDeviceID, expiresAt).Scan(&id)
	return id, err
}

func (r *Repository) GetByID(ctx context.Context, id, userID string) (*Session, error) {
	return r.scanSession(r.pool.QueryRow(ctx, `
		SELECT id, user_id, initiator_device_id, ciphertext, status, expires_at, completed_device_id
		FROM device_link_sessions
		WHERE id = $1 AND user_id = $2`, id, userID))
}

func (r *Repository) GetByTokenHash(ctx context.Context, tokenHash, userID string) (*Session, error) {
	return r.scanSession(r.pool.QueryRow(ctx, `
		SELECT id, user_id, initiator_device_id, ciphertext, status, expires_at, completed_device_id
		FROM device_link_sessions
		WHERE token_hash = $1 AND user_id = $2`, tokenHash, userID))
}

func (r *Repository) SetPayload(ctx context.Context, id, userID, deviceID, ciphertext string) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE device_link_sessions
		SET ciphertext = $4, status = 'ready'
		WHERE id = $1 AND user_id = $2 AND initiator_device_id = $3
		  AND status IN ('pending', 'ready') AND expires_at > now()`, id, userID, deviceID, ciphertext)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		s, err := r.GetByID(ctx, id, userID)
		if err != nil {
			return err
		}
		if time.Now().After(s.ExpiresAt) {
			return ErrExpired
		}
		if s.InitiatorDeviceID != deviceID {
			return ErrForbidden
		}
		return ErrNotFound
	}
	return nil
}

func (r *Repository) Complete(ctx context.Context, tokenHash, userID, deviceID string) (string, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)

	s, err := r.scanSession(tx.QueryRow(ctx, `
		SELECT id, user_id, initiator_device_id, ciphertext, status, expires_at, completed_device_id
		FROM device_link_sessions
		WHERE token_hash = $1 AND user_id = $2
		FOR UPDATE`, tokenHash, userID))
	if err != nil {
		return "", err
	}
	if time.Now().After(s.ExpiresAt) {
		return "", ErrExpired
	}
	if s.Status == "completed" {
		return "", ErrAlreadyUsed
	}
	if s.Ciphertext == nil || *s.Ciphertext == "" {
		return "", ErrNotReady
	}
	if s.InitiatorDeviceID == deviceID {
		return "", ErrForbidden
	}

	tag, err := tx.Exec(ctx, `
		UPDATE device_link_sessions
		SET status = 'completed', completed_device_id = $3
		WHERE id = $1 AND user_id = $2 AND status <> 'completed'`,
		s.ID, userID, deviceID)
	if err != nil {
		return "", err
	}
	if tag.RowsAffected() == 0 {
		return "", ErrAlreadyUsed
	}
	if err := tx.Commit(ctx); err != nil {
		return "", err
	}
	return *s.Ciphertext, nil
}

func (r *Repository) scanSession(row pgx.Row) (*Session, error) {
	var s Session
	err := row.Scan(
		&s.ID, &s.UserID, &s.InitiatorDeviceID, &s.Ciphertext,
		&s.Status, &s.ExpiresAt, &s.CompletedDeviceID,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}
