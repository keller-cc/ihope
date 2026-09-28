package emailnotify

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Store struct {
	pool *pgxpool.Pool
}

func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{pool: pool}
}

type Status struct {
	Prefs
	Effective     string `json:"effective"` // active | paused_by_qq | disabled
	EmailVerified bool   `json:"emailVerified"`
}

func (s *Store) GetPrefs(ctx context.Context, userID string) (Prefs, error) {
	p := DefaultPrefs()
	var (
		enabled bool
		mode    string
		batch   int
		minSec  int
		scope   string
	)
	err := s.pool.QueryRow(ctx, `
		SELECT enabled, mode, batch_size, min_interval_sec, scope
		FROM user_email_notify_prefs WHERE user_id = $1
	`, userID).Scan(&enabled, &mode, &batch, &minSec, &scope)
	if errors.Is(err, pgx.ErrNoRows) {
		ids, ierr := s.listConversationIDs(ctx, userID)
		if ierr != nil {
			return p, ierr
		}
		p.ConversationIDs = ids
		return p, nil
	}
	if err != nil {
		return p, err
	}
	p.Enabled = enabled
	p.Mode = mode
	p.BatchSize = batch
	p.MinIntervalSec = minSec
	p.Scope = scope
	ids, err := s.listConversationIDs(ctx, userID)
	if err != nil {
		return p, err
	}
	p.ConversationIDs = ids
	return NormalizePrefs(p), nil
}

func (s *Store) listConversationIDs(ctx context.Context, userID string) ([]string, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT conversation_id::text FROM user_email_notify_conversations
		WHERE user_id = $1 ORDER BY conversation_id
	`, userID)
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

func (s *Store) SavePrefs(ctx context.Context, userID string, p Prefs) (Prefs, error) {
	p = NormalizePrefs(p)
	_, err := s.pool.Exec(ctx, `
		INSERT INTO user_email_notify_prefs
		  (user_id, enabled, mode, batch_size, min_interval_sec, scope, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, now())
		ON CONFLICT (user_id) DO UPDATE SET
		  enabled = EXCLUDED.enabled,
		  mode = EXCLUDED.mode,
		  batch_size = EXCLUDED.batch_size,
		  min_interval_sec = EXCLUDED.min_interval_sec,
		  scope = EXCLUDED.scope,
		  updated_at = now()
	`, userID, p.Enabled, p.Mode, p.BatchSize, p.MinIntervalSec, p.Scope)
	if err != nil {
		return Prefs{}, err
	}
	if err := s.replaceConversations(ctx, userID, p.ConversationIDs); err != nil {
		return Prefs{}, err
	}
	return s.GetPrefs(ctx, userID)
}

func (s *Store) replaceConversations(ctx context.Context, userID string, ids []string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `DELETE FROM user_email_notify_conversations WHERE user_id = $1`, userID); err != nil {
		return err
	}
	for _, id := range ids {
		var ok bool
		err := tx.QueryRow(ctx, `
			SELECT EXISTS(
			  SELECT 1 FROM conversation_members
			  WHERE conversation_id = $1::uuid AND user_id = $2::uuid
			)
		`, id, userID).Scan(&ok)
		if err != nil {
			return err
		}
		if !ok {
			continue
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO user_email_notify_conversations (user_id, conversation_id)
			VALUES ($1::uuid, $2::uuid) ON CONFLICT DO NOTHING
		`, userID, id); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

func (s *Store) EmailVerified(ctx context.Context, userID string) (bool, error) {
	var v bool
	err := s.pool.QueryRow(ctx, `SELECT email_verified FROM users WHERE id = $1`, userID).Scan(&v)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	return v, err
}

type chatAcquire struct {
	Send   bool
	Email  string
	Kind   string // single | batch
	Count  int
	Hints  []string
	Hint   string
}

// AcquireChatSend applies mode throttling and returns whether/how to email.
func (s *Store) AcquireChatSend(ctx context.Context, userID string, prefs Prefs, now time.Time, hint string) (chatAcquire, error) {
	prefs = NormalizePrefs(prefs)
	hint = strings.TrimSpace(hint)
	if hint == "" {
		hint = "有人"
	}
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	dayStr := today.Format("2006-01-02")

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return chatAcquire{}, err
	}
	defer tx.Rollback(ctx)

	var email string
	var verified bool
	err = tx.QueryRow(ctx, `SELECT email, email_verified FROM users WHERE id = $1::uuid FOR UPDATE`, userID).
		Scan(&email, &verified)
	if errors.Is(err, pgx.ErrNoRows) || !verified || email == "" {
		return chatAcquire{}, nil
	}
	if err != nil {
		return chatAcquire{}, err
	}

	var lastAt *time.Time
	var lastOn *time.Time
	var pending int
	var hints []string
	err = tx.QueryRow(ctx, `
		SELECT last_sent_at, last_sent_on, pending_count, pending_hints
		FROM user_email_notify_state WHERE user_id = $1::uuid FOR UPDATE
	`, userID).Scan(&lastAt, &lastOn, &pending, &hints)
	if errors.Is(err, pgx.ErrNoRows) {
		_, err = tx.Exec(ctx, `
			INSERT INTO user_email_notify_state (user_id, pending_count, pending_hints, updated_at)
			VALUES ($1::uuid, 0, '{}', now())
		`, userID)
		if err != nil {
			return chatAcquire{}, err
		}
		pending = 0
		hints = nil
	} else if err != nil {
		return chatAcquire{}, err
	}

	out := chatAcquire{Email: email, Hint: hint}

	switch prefs.Mode {
	case ModeFirstDaily:
		if lastOn != nil {
			lo := time.Date(lastOn.Year(), lastOn.Month(), lastOn.Day(), 0, 0, 0, 0, today.Location())
			if !lo.Before(today) {
				return chatAcquire{}, nil
			}
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO user_email_notify_state (user_id, last_sent_at, last_sent_on, pending_count, pending_hints, updated_at)
			VALUES ($1::uuid, $2, $3::date, 0, '{}', now())
			ON CONFLICT (user_id) DO UPDATE SET
			  last_sent_at = EXCLUDED.last_sent_at,
			  last_sent_on = EXCLUDED.last_sent_on,
			  pending_count = 0,
			  pending_hints = '{}',
			  updated_at = now()
		`, userID, now.UTC(), dayStr); err != nil {
			return chatAcquire{}, err
		}
		out.Send = true
		out.Kind = "single"

	case ModeEvery:
		min := time.Duration(prefs.MinIntervalSec) * time.Second
		if lastAt != nil && now.Sub(lastAt.UTC()) < min {
			return chatAcquire{}, nil
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO user_email_notify_state (user_id, last_sent_at, last_sent_on, pending_count, pending_hints, updated_at)
			VALUES ($1::uuid, $2, $3::date, 0, '{}', now())
			ON CONFLICT (user_id) DO UPDATE SET
			  last_sent_at = EXCLUDED.last_sent_at,
			  last_sent_on = EXCLUDED.last_sent_on,
			  pending_count = 0,
			  pending_hints = '{}',
			  updated_at = now()
		`, userID, now.UTC(), dayStr); err != nil {
			return chatAcquire{}, err
		}
		out.Send = true
		out.Kind = "single"

	case ModeBatch:
		pending++
		hints = appendHint(hints, hint, 8)
		if pending < prefs.BatchSize {
			if _, err := tx.Exec(ctx, `
				INSERT INTO user_email_notify_state (user_id, pending_count, pending_hints, updated_at)
				VALUES ($1::uuid, $2, $3, now())
				ON CONFLICT (user_id) DO UPDATE SET
				  pending_count = EXCLUDED.pending_count,
				  pending_hints = EXCLUDED.pending_hints,
				  updated_at = now()
			`, userID, pending, hints); err != nil {
				return chatAcquire{}, err
			}
			if err := tx.Commit(ctx); err != nil {
				return chatAcquire{}, err
			}
			return chatAcquire{}, nil
		}
		out.Send = true
		out.Kind = "batch"
		out.Count = pending
		out.Hints = hints
		if _, err := tx.Exec(ctx, `
			INSERT INTO user_email_notify_state (user_id, last_sent_at, last_sent_on, pending_count, pending_hints, updated_at)
			VALUES ($1::uuid, $2, $3::date, 0, '{}', now())
			ON CONFLICT (user_id) DO UPDATE SET
			  last_sent_at = EXCLUDED.last_sent_at,
			  last_sent_on = EXCLUDED.last_sent_on,
			  pending_count = 0,
			  pending_hints = '{}',
			  updated_at = now()
		`, userID, now.UTC(), dayStr); err != nil {
			return chatAcquire{}, err
		}

	default:
		return chatAcquire{}, nil
	}

	if err := tx.Commit(ctx); err != nil {
		return chatAcquire{}, err
	}
	return out, nil
}

type socialAcquire struct {
	Send  bool
	Email string
}

// AcquireSocialSend for first_daily shares the daily slot; every/batch send with min_interval.
func (s *Store) AcquireSocialSend(ctx context.Context, userID string, prefs Prefs, now time.Time) (socialAcquire, error) {
	prefs = NormalizePrefs(prefs)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	dayStr := today.Format("2006-01-02")

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return socialAcquire{}, err
	}
	defer tx.Rollback(ctx)

	var email string
	var verified bool
	err = tx.QueryRow(ctx, `SELECT email, email_verified FROM users WHERE id = $1::uuid FOR UPDATE`, userID).
		Scan(&email, &verified)
	if errors.Is(err, pgx.ErrNoRows) || !verified || email == "" {
		return socialAcquire{}, nil
	}
	if err != nil {
		return socialAcquire{}, err
	}

	var lastAt *time.Time
	var lastOn *time.Time
	err = tx.QueryRow(ctx, `
		SELECT last_sent_at, last_sent_on FROM user_email_notify_state WHERE user_id = $1::uuid FOR UPDATE
	`, userID).Scan(&lastAt, &lastOn)
	if errors.Is(err, pgx.ErrNoRows) {
		_, err = tx.Exec(ctx, `
			INSERT INTO user_email_notify_state (user_id, pending_count, pending_hints, updated_at)
			VALUES ($1::uuid, 0, '{}', now())
		`, userID)
		if err != nil {
			return socialAcquire{}, err
		}
	} else if err != nil {
		return socialAcquire{}, err
	}

	switch prefs.Mode {
	case ModeFirstDaily:
		if lastOn != nil {
			lo := time.Date(lastOn.Year(), lastOn.Month(), lastOn.Day(), 0, 0, 0, 0, today.Location())
			if !lo.Before(today) {
				return socialAcquire{}, nil
			}
		}
	case ModeEvery, ModeBatch:
		min := time.Duration(prefs.MinIntervalSec) * time.Second
		if lastAt != nil && now.Sub(lastAt.UTC()) < min {
			return socialAcquire{}, nil
		}
	default:
		return socialAcquire{}, nil
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO user_email_notify_state (user_id, last_sent_at, last_sent_on, updated_at)
		VALUES ($1::uuid, $2, $3::date, now())
		ON CONFLICT (user_id) DO UPDATE SET
		  last_sent_at = EXCLUDED.last_sent_at,
		  last_sent_on = EXCLUDED.last_sent_on,
		  updated_at = now()
	`, userID, now.UTC(), dayStr); err != nil {
		return socialAcquire{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return socialAcquire{}, err
	}
	return socialAcquire{Send: true, Email: email}, nil
}

// ReleaseLastSend clears today's send markers after a delivery failure (best-effort).
func (s *Store) ReleaseLastSend(ctx context.Context, userID string, today time.Time) error {
	day := today.Format("2006-01-02")
	_, err := s.pool.Exec(ctx, `
		UPDATE user_email_notify_state
		SET last_sent_at = NULL,
		    last_sent_on = CASE WHEN last_sent_on = $2::date THEN NULL ELSE last_sent_on END,
		    updated_at = now()
		WHERE user_id = $1::uuid
	`, userID, day)
	return err
}

func appendHint(hints []string, hint string, max int) []string {
	for _, h := range hints {
		if h == hint {
			return hints
		}
	}
	hints = append(hints, hint)
	if len(hints) > max {
		hints = hints[len(hints)-max:]
	}
	return hints
}
