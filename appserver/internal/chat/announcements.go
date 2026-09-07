package chat

import (
	"context"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5"
)

// GroupAnnouncement is one QQ-style group notice (many per group).
type GroupAnnouncement struct {
	ID              string  `json:"id"`
	ConversationID  string  `json:"conversationId"`
	Body            string  `json:"body"`
	AuthorID        string  `json:"authorId"`
	AuthorName      string  `json:"authorName,omitempty"`
	AuthorAvatarURL *string `json:"authorAvatarUrl,omitempty"`
	RequireConfirm  bool    `json:"requireConfirm"`
	CreatedAt       string  `json:"createdAt"`
	UpdatedAt       string  `json:"updatedAt"`
	Acked           bool    `json:"acked"`
	AckCount        int     `json:"ackCount,omitempty"`
}

func (s *Service) ListAnnouncements(ctx context.Context, conversationID, userID string) ([]GroupAnnouncement, error) {
	ok, err := s.CanAccessConversation(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	rows, err := s.pool.Query(ctx, `
		SELECT a.id::text, a.conversation_id::text, a.body, a.author_id::text,
			u.username, u.avatar_url, a.require_confirm,
			a.created_at::text, a.updated_at::text,
			EXISTS(
				SELECT 1 FROM group_announcement_acks k
				WHERE k.announcement_id = a.id AND k.user_id = $2
			),
			(SELECT COUNT(*)::int FROM group_announcement_acks k WHERE k.announcement_id = a.id)
		FROM group_announcements a
		JOIN users u ON u.id = a.author_id
		WHERE a.conversation_id = $1
		ORDER BY a.created_at DESC
	`, conversationID, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []GroupAnnouncement
	for rows.Next() {
		var a GroupAnnouncement
		if err := rows.Scan(
			&a.ID, &a.ConversationID, &a.Body, &a.AuthorID,
			&a.AuthorName, &a.AuthorAvatarURL, &a.RequireConfirm,
			&a.CreatedAt, &a.UpdatedAt, &a.Acked, &a.AckCount,
		); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	if out == nil {
		out = []GroupAnnouncement{}
	}
	return out, rows.Err()
}

func (s *Service) GetAnnouncement(ctx context.Context, conversationID, announcementID, userID string) (*GroupAnnouncement, error) {
	ok, err := s.CanAccessConversation(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	var a GroupAnnouncement
	err = s.pool.QueryRow(ctx, `
		SELECT a.id::text, a.conversation_id::text, a.body, a.author_id::text,
			u.username, u.avatar_url, a.require_confirm,
			a.created_at::text, a.updated_at::text,
			EXISTS(
				SELECT 1 FROM group_announcement_acks k
				WHERE k.announcement_id = a.id AND k.user_id = $3
			),
			(SELECT COUNT(*)::int FROM group_announcement_acks k WHERE k.announcement_id = a.id)
		FROM group_announcements a
		JOIN users u ON u.id = a.author_id
		WHERE a.id = $1 AND a.conversation_id = $2
	`, announcementID, conversationID, userID).Scan(
		&a.ID, &a.ConversationID, &a.Body, &a.AuthorID,
		&a.AuthorName, &a.AuthorAvatarURL, &a.RequireConfirm,
		&a.CreatedAt, &a.UpdatedAt, &a.Acked, &a.AckCount,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("announcement not found")
		}
		return nil, err
	}
	return &a, nil
}

func (s *Service) CreateAnnouncement(
	ctx context.Context,
	conversationID, userID, body string,
	requireConfirm bool,
) (*GroupAnnouncement, error) {
	body = strings.TrimSpace(body)
	if body == "" {
		return nil, errors.New("empty announcement")
	}
	if utf8Len(body) > 1000 {
		return nil, errors.New("announcement too long")
	}
	ok, err := s.canManageGroup(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	var a GroupAnnouncement
	err = s.pool.QueryRow(ctx, `
		INSERT INTO group_announcements (conversation_id, author_id, body, require_confirm)
		VALUES ($1, $2, $3, $4)
		RETURNING id::text, conversation_id::text, body, author_id::text, require_confirm,
			created_at::text, updated_at::text
	`, conversationID, userID, body, requireConfirm).Scan(
		&a.ID, &a.ConversationID, &a.Body, &a.AuthorID, &a.RequireConfirm, &a.CreatedAt, &a.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	a.AuthorName = s.UsernameByID(ctx, userID)
	a.Acked = false
	a.AckCount = 0
	// Publisher has already "seen" it
	_, _ = s.pool.Exec(ctx, `
		INSERT INTO group_announcement_acks (announcement_id, user_id)
		VALUES ($1, $2)
		ON CONFLICT DO NOTHING
	`, a.ID, userID)
	a.Acked = true
	a.AckCount = 1
	return &a, nil
}

func (s *Service) UpdateAnnouncement(
	ctx context.Context,
	conversationID, announcementID, userID, body string,
) (*GroupAnnouncement, error) {
	body = strings.TrimSpace(body)
	if body == "" {
		return nil, errors.New("empty announcement")
	}
	if utf8Len(body) > 1000 {
		return nil, errors.New("announcement too long")
	}
	ok, err := s.canManageGroup(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	tag, err := s.pool.Exec(ctx, `
		UPDATE group_announcements
		SET body = $1, updated_at = now()
		WHERE id = $2 AND conversation_id = $3
	`, body, announcementID, conversationID)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, errors.New("announcement not found")
	}
	return s.GetAnnouncement(ctx, conversationID, announcementID, userID)
}

func (s *Service) DeleteAnnouncement(ctx context.Context, conversationID, announcementID, userID string) error {
	ok, err := s.canManageGroup(ctx, conversationID, userID)
	if err != nil {
		return err
	}
	if !ok {
		return errors.New("forbidden")
	}
	tag, err := s.pool.Exec(ctx, `
		DELETE FROM group_announcements WHERE id = $1 AND conversation_id = $2
	`, announcementID, conversationID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("announcement not found")
	}
	return nil
}

// AckAnnouncement marks the notice as confirmed/read for the viewer (QQ「确认收到」).
func (s *Service) AckAnnouncement(ctx context.Context, conversationID, announcementID, userID string) (*GroupAnnouncement, error) {
	ok, err := s.CanAccessConversation(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	var exists bool
	_ = s.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM group_announcements WHERE id = $1 AND conversation_id = $2
		)
	`, announcementID, conversationID).Scan(&exists)
	if !exists {
		return nil, errors.New("announcement not found")
	}
	_, err = s.pool.Exec(ctx, `
		INSERT INTO group_announcement_acks (announcement_id, user_id)
		VALUES ($1, $2)
		ON CONFLICT DO NOTHING
	`, announcementID, userID)
	if err != nil {
		return nil, err
	}
	return s.GetAnnouncement(ctx, conversationID, announcementID, userID)
}

func (s *Service) PendingAnnouncement(ctx context.Context, conversationID, userID string) (*GroupAnnouncement, error) {
	var a GroupAnnouncement
	err := s.pool.QueryRow(ctx, `
		SELECT a.id::text, a.conversation_id::text, a.body, a.author_id::text,
			u.username, u.avatar_url, a.require_confirm,
			a.created_at::text, a.updated_at::text
		FROM group_announcements a
		JOIN users u ON u.id = a.author_id
		WHERE a.conversation_id = $1
		  AND NOT EXISTS (
			SELECT 1 FROM group_announcement_acks k
			WHERE k.announcement_id = a.id AND k.user_id = $2
		  )
		ORDER BY a.created_at DESC
		LIMIT 1
	`, conversationID, userID).Scan(
		&a.ID, &a.ConversationID, &a.Body, &a.AuthorID,
		&a.AuthorName, &a.AuthorAvatarURL, &a.RequireConfirm,
		&a.CreatedAt, &a.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	a.Acked = false
	return &a, nil
}

func (s *Service) fillAnnouncementMeta(ctx context.Context, c *Conversation, userID string) {
	if c == nil || c.Type != "group" {
		return
	}
	_ = s.pool.QueryRow(ctx, `
		SELECT COUNT(*)::int FROM group_announcements WHERE conversation_id = $1
	`, c.ID).Scan(&c.AnnouncementCount)
	var latest string
	_ = s.pool.QueryRow(ctx, `
		SELECT body FROM group_announcements
		WHERE conversation_id = $1
		ORDER BY created_at DESC LIMIT 1
	`, c.ID).Scan(&latest)
	c.Announcement = latest
	pending, err := s.PendingAnnouncement(ctx, c.ID, userID)
	if err == nil && pending != nil {
		c.PendingAnnouncement = pending
	}
}
