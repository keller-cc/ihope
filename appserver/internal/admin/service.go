package admin

import (
	"context"
	"errors"

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
	ID          string `json:"id"`
	Type        string `json:"type"`
	Title       string `json:"title"`
	MemberCount int    `json:"memberCount"`
	CreatedAt   string `json:"createdAt"`
	Members     string `json:"members"` // usernames joined
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
			(SELECT COUNT(*)::int FROM conversation_members cm WHERE cm.conversation_id = c.id),
			COALESCE((
				SELECT string_agg(u.username, ', ' ORDER BY u.username)
				FROM conversation_members cm2
				JOIN users u ON u.id = cm2.user_id
				WHERE cm2.conversation_id = c.id
			), '')
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
		if err := rows.Scan(&c.ID, &c.Type, &c.Title, &c.CreatedAt, &c.MemberCount, &c.Members); err != nil {
			return nil, err
		}
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
