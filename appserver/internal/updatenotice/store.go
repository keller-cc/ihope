package updatenotice

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Notice struct {
	ID          string  `json:"id"`
	Title       string  `json:"title"`
	Body        string  `json:"body"`
	Published   bool    `json:"published"`
	PublishedAt *string `json:"publishedAt,omitempty"`
	CreatedAt   string  `json:"createdAt"`
	UpdatedAt   string  `json:"updatedAt"`
}

type Store struct {
	pool *pgxpool.Pool
}

func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{pool: pool}
}

func (s *Store) ListAll(ctx context.Context) ([]Notice, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id::text, title, body, published,
		       published_at::text, created_at::text, updated_at::text
		FROM update_notices
		ORDER BY COALESCE(published_at, created_at) DESC, created_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanNotices(rows)
}

func (s *Store) ListPublished(ctx context.Context, limit int) ([]Notice, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	rows, err := s.pool.Query(ctx, `
		SELECT id::text, title, body, published,
		       published_at::text, created_at::text, updated_at::text
		FROM update_notices
		WHERE published = TRUE
		ORDER BY published_at DESC NULLS LAST, created_at DESC
		LIMIT $1
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanNotices(rows)
}

func (s *Store) Get(ctx context.Context, id string) (*Notice, error) {
	row := s.pool.QueryRow(ctx, `
		SELECT id::text, title, body, published,
		       published_at::text, created_at::text, updated_at::text
		FROM update_notices WHERE id = $1::uuid
	`, id)
	n, err := scanNotice(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, errors.New("not found")
	}
	return n, err
}

func (s *Store) Create(ctx context.Context, title, body string, publish bool) (*Notice, error) {
	title = strings.TrimSpace(title)
	body = strings.TrimSpace(body)
	if title == "" {
		return nil, errors.New("title required")
	}
	if body == "" {
		return nil, errors.New("body required")
	}
	var id string
	err := s.pool.QueryRow(ctx, `
		INSERT INTO update_notices (title, body, published, published_at, created_at, updated_at)
		VALUES ($1, $2, $3, CASE WHEN $3 THEN now() ELSE NULL END, now(), now())
		RETURNING id::text
	`, title, body, publish).Scan(&id)
	if err != nil {
		return nil, err
	}
	return s.Get(ctx, id)
}

func (s *Store) Update(ctx context.Context, id, title, body string, published *bool) (*Notice, error) {
	cur, err := s.Get(ctx, id)
	if err != nil {
		return nil, err
	}
	if t := strings.TrimSpace(title); t != "" {
		cur.Title = t
	}
	if b := strings.TrimSpace(body); b != "" {
		cur.Body = b
	}
	wasPub := cur.Published
	if published != nil {
		cur.Published = *published
	}
	_, err = s.pool.Exec(ctx, `
		UPDATE update_notices
		SET title = $2,
		    body = $3,
		    published = $4,
		    published_at = CASE
		      WHEN $4 AND NOT $5 THEN now()
		      WHEN NOT $4 THEN NULL
		      ELSE published_at
		    END,
		    updated_at = now()
		WHERE id = $1::uuid
	`, id, cur.Title, cur.Body, cur.Published, wasPub)
	if err != nil {
		return nil, err
	}
	return s.Get(ctx, id)
}

func (s *Store) Delete(ctx context.Context, id string) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM update_notices WHERE id = $1::uuid`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("not found")
	}
	return nil
}

// PendingLatest returns the newest published notice the user has not acked.
func (s *Store) PendingLatest(ctx context.Context, userID string) (*Notice, error) {
	row := s.pool.QueryRow(ctx, `
		SELECT n.id::text, n.title, n.body, n.published,
		       n.published_at::text, n.created_at::text, n.updated_at::text
		FROM update_notices n
		WHERE n.published = TRUE
		  AND NOT EXISTS (
		    SELECT 1 FROM update_notice_acks a
		    WHERE a.notice_id = n.id AND a.user_id = $1::uuid
		  )
		ORDER BY n.published_at DESC NULLS LAST, n.created_at DESC
		LIMIT 1
	`, userID)
	n, err := scanNotice(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return n, err
}

func (s *Store) Ack(ctx context.Context, userID, noticeID string) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO update_notice_acks (user_id, notice_id, acked_at)
		VALUES ($1::uuid, $2::uuid, $3)
		ON CONFLICT (user_id, notice_id) DO NOTHING
	`, userID, noticeID, time.Now().UTC())
	return err
}

type scannable interface {
	Scan(dest ...any) error
}

type rowSet interface {
	Next() bool
	Scan(dest ...any) error
	Err() error
}

func scanNotice(row scannable) (*Notice, error) {
	var n Notice
	var pubAt *string
	err := row.Scan(&n.ID, &n.Title, &n.Body, &n.Published, &pubAt, &n.CreatedAt, &n.UpdatedAt)
	if err != nil {
		return nil, err
	}
	n.PublishedAt = pubAt
	return &n, nil
}

func scanNotices(rows rowSet) ([]Notice, error) {
	var out []Notice
	for rows.Next() {
		n, err := scanNotice(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *n)
	}
	return out, rows.Err()
}
