package qqbot

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrNotBound     = errors.New("qq not bound")
	ErrCodeInvalid = errors.New("invalid bind code")
	ErrCodeExpired = errors.New("bind code expired")
)

type Binding struct {
	UserID          string
	QQOpenID        string
	DoorbellEnabled bool
	PoetryEnabled   bool
	QuotesEnabled   bool
	NewsEnabled     bool
	LastDoorbellAt  *time.Time
	BoundAt         time.Time
}

type Store struct {
	pool *pgxpool.Pool
}

func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{pool: pool}
}

func (s *Store) CreateBindCode(ctx context.Context, userID string, ttl time.Duration) (string, time.Time, error) {
	code, err := randomDigits(6)
	if err != nil {
		return "", time.Time{}, err
	}
	expires := time.Now().UTC().Add(ttl)
	_, err = s.pool.Exec(ctx, `
		INSERT INTO qq_bind_codes (code, user_id, expires_at)
		VALUES ($1, $2, $3)
		ON CONFLICT (code) DO UPDATE
		SET user_id = EXCLUDED.user_id, expires_at = EXCLUDED.expires_at, used_at = NULL`,
		code, userID, expires)
	if err != nil {
		return "", time.Time{}, err
	}
	return code, expires, nil
}

func (s *Store) ConsumeBindCode(ctx context.Context, code, openID string) (string, error) {
	code = strings.TrimSpace(code)
	openID = strings.TrimSpace(openID)
	if code == "" || openID == "" {
		return "", ErrCodeInvalid
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)

	var userID string
	var expires time.Time
	var usedAt *time.Time
	err = tx.QueryRow(ctx, `
		SELECT user_id, expires_at, used_at FROM qq_bind_codes WHERE code = $1 FOR UPDATE`, code).
		Scan(&userID, &expires, &usedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrCodeInvalid
	}
	if err != nil {
		return "", err
	}
	if usedAt != nil {
		return "", ErrCodeInvalid
	}
	if time.Now().UTC().After(expires) {
		return "", ErrCodeExpired
	}
	if _, err = tx.Exec(ctx, `UPDATE qq_bind_codes SET used_at = now() WHERE code = $1`, code); err != nil {
		return "", err
	}
	if _, err = tx.Exec(ctx, `DELETE FROM user_qq_bindings WHERE qq_openid = $1`, openID); err != nil {
		return "", err
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO user_qq_bindings (user_id, qq_openid, doorbell_enabled, poetry_enabled, quotes_enabled, news_enabled, bound_at, updated_at)
		VALUES ($1, $2, TRUE, TRUE, TRUE, TRUE, now(), now())
		ON CONFLICT (user_id) DO UPDATE
		SET qq_openid = EXCLUDED.qq_openid, updated_at = now(), bound_at = now()`,
		userID, openID)
	if err != nil {
		return "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return "", err
	}
	return userID, nil
}

func (s *Store) GetByUserID(ctx context.Context, userID string) (*Binding, error) {
	return s.scan(ctx, `SELECT user_id::text, qq_openid, doorbell_enabled, poetry_enabled, quotes_enabled, news_enabled, last_doorbell_at, bound_at
		FROM user_qq_bindings WHERE user_id = $1`, userID)
}

func (s *Store) GetByOpenID(ctx context.Context, openID string) (*Binding, error) {
	return s.scan(ctx, `SELECT user_id::text, qq_openid, doorbell_enabled, poetry_enabled, quotes_enabled, news_enabled, last_doorbell_at, bound_at
		FROM user_qq_bindings WHERE qq_openid = $1`, openID)
}

func (s *Store) scan(ctx context.Context, q string, arg any) (*Binding, error) {
	var b Binding
	err := s.pool.QueryRow(ctx, q, arg).Scan(
		&b.UserID, &b.QQOpenID, &b.DoorbellEnabled, &b.PoetryEnabled, &b.QuotesEnabled, &b.NewsEnabled, &b.LastDoorbellAt, &b.BoundAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotBound
	}
	if err != nil {
		return nil, err
	}
	return &b, nil
}

func (s *Store) UpdateFlags(ctx context.Context, userID string, doorbell, poetry, quotes, news *bool) error {
	b, err := s.GetByUserID(ctx, userID)
	if err != nil {
		return err
	}
	if doorbell != nil {
		b.DoorbellEnabled = *doorbell
	}
	if poetry != nil {
		b.PoetryEnabled = *poetry
	}
	if quotes != nil {
		b.QuotesEnabled = *quotes
	}
	if news != nil {
		b.NewsEnabled = *news
	}
	_, err = s.pool.Exec(ctx, `
		UPDATE user_qq_bindings
		SET doorbell_enabled = $2, poetry_enabled = $3, quotes_enabled = $4, news_enabled = $5, updated_at = now()
		WHERE user_id = $1`,
		userID, b.DoorbellEnabled, b.PoetryEnabled, b.QuotesEnabled, b.NewsEnabled)
	return err
}

func (s *Store) Unbind(ctx context.Context, userID string) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM user_qq_bindings WHERE user_id = $1`, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotBound
	}
	return nil
}

type BindingRow struct {
	UserID          string    `json:"userId"`
	Username        string    `json:"username"`
	Email           string    `json:"email"`
	HopeID          *string   `json:"hopeId,omitempty"`
	QQOpenID        string    `json:"qqOpenId"`
	DoorbellEnabled bool      `json:"doorbellEnabled"`
	BoundAt         time.Time `json:"boundAt"`
}

func (s *Store) ListBindings(ctx context.Context) ([]BindingRow, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT b.user_id::text, u.username, u.email, u.hope_id, b.qq_openid, b.doorbell_enabled, b.bound_at
		FROM user_qq_bindings b
		JOIN users u ON u.id = b.user_id
		ORDER BY b.bound_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []BindingRow
	for rows.Next() {
		var r BindingRow
		if err := rows.Scan(
			&r.UserID, &r.Username, &r.Email, &r.HopeID, &r.QQOpenID, &r.DoorbellEnabled, &r.BoundAt,
		); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	if out == nil {
		out = []BindingRow{}
	}
	return out, rows.Err()
}

func (s *Store) TouchDoorbell(ctx context.Context, userID string) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE user_qq_bindings SET last_doorbell_at = now(), updated_at = now() WHERE user_id = $1`, userID)
	return err
}

func (s *Store) ListPoetrySubscribers(ctx context.Context) ([]Binding, error) {
	return s.listByFlag(ctx, `poetry_enabled`)
}

func (s *Store) ListQuoteSubscribers(ctx context.Context) ([]Binding, error) {
	return s.listByFlag(ctx, `quotes_enabled`)
}

func (s *Store) ListNewsSubscribers(ctx context.Context) ([]Binding, error) {
	return s.listByFlag(ctx, `news_enabled`)
}

func (s *Store) listByFlag(ctx context.Context, col string) ([]Binding, error) {
	q := fmt.Sprintf(`
		SELECT user_id::text, qq_openid, doorbell_enabled, poetry_enabled, quotes_enabled, news_enabled, last_doorbell_at, bound_at
		FROM user_qq_bindings WHERE %s = TRUE`, col)
	rows, err := s.pool.Query(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Binding
	for rows.Next() {
		var b Binding
		if err := rows.Scan(&b.UserID, &b.QQOpenID, &b.DoorbellEnabled, &b.PoetryEnabled, &b.QuotesEnabled, &b.NewsEnabled, &b.LastDoorbellAt, &b.BoundAt); err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

func randomDigits(n int) (string, error) {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	var b strings.Builder
	for _, x := range buf {
		b.WriteByte('0' + (x % 10))
	}
	return b.String(), nil
}

func randomHex(nBytes int) (string, error) {
	buf := make([]byte, nBytes)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}
