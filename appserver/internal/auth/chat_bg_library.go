package auth

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"

	"github.com/jackc/pgx/v5"
)

const maxChatBackgrounds = 24

type ChatBackgroundItem struct {
	ID        string `json:"id"`
	URL       string `json:"url"`
	CreatedAt string `json:"createdAt"`
}

// EnsureChatBackgroundTracked inserts the current theme image into the library if missing.
func (s *Service) EnsureChatBackgroundTracked(ctx context.Context, userID, url string) error {
	url = strings.TrimSpace(url)
	if url == "" || !strings.HasPrefix(url, "/uploads/chat-bg/") {
		return nil
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO user_chat_backgrounds (user_id, url)
		VALUES ($1::uuid, $2)
		ON CONFLICT (user_id, url) DO NOTHING
	`, userID, url)
	return err
}

func (s *Service) ListChatBackgrounds(ctx context.Context, userID string) ([]ChatBackgroundItem, error) {
	// 把当前主题里的图片补进图库，方便「以前上传过」可见
	u, err := s.UserByID(ctx, userID)
	if err == nil && u.ChatTheme != nil && u.ChatTheme.Background != nil {
		bg := u.ChatTheme.Background
		if bg.Kind == "image" && strings.TrimSpace(bg.URL) != "" {
			_ = s.EnsureChatBackgroundTracked(ctx, userID, bg.URL)
		}
	}

	rows, err := s.pool.Query(ctx, `
		SELECT id::text, url, created_at::text
		FROM user_chat_backgrounds
		WHERE user_id = $1::uuid
		ORDER BY created_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ChatBackgroundItem{}
	for rows.Next() {
		var it ChatBackgroundItem
		if err := rows.Scan(&it.ID, &it.URL, &it.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

// AddChatBackground records a newly uploaded wallpaper URL and prunes old ones.
func (s *Service) AddChatBackground(ctx context.Context, userID, url, uploadDir string) (*ChatBackgroundItem, error) {
	url = strings.TrimSpace(url)
	if url == "" {
		return nil, errors.New("url required")
	}
	var it ChatBackgroundItem
	err := s.pool.QueryRow(ctx, `
		INSERT INTO user_chat_backgrounds (user_id, url)
		VALUES ($1::uuid, $2)
		ON CONFLICT (user_id, url) DO UPDATE SET created_at = now()
		RETURNING id::text, url, created_at::text
	`, userID, url).Scan(&it.ID, &it.URL, &it.CreatedAt)
	if err != nil {
		return nil, err
	}
	_ = s.pruneChatBackgrounds(ctx, userID, uploadDir)
	return &it, nil
}

func (s *Service) pruneChatBackgrounds(ctx context.Context, userID, uploadDir string) error {
	rows, err := s.pool.Query(ctx, `
		SELECT id::text, url FROM user_chat_backgrounds
		WHERE user_id = $1::uuid
		ORDER BY created_at DESC
		OFFSET $2
	`, userID, maxChatBackgrounds)
	if err != nil {
		return err
	}
	defer rows.Close()
	var stale []ChatBackgroundItem
	for rows.Next() {
		var it ChatBackgroundItem
		if err := rows.Scan(&it.ID, &it.URL); err != nil {
			return err
		}
		stale = append(stale, it)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	for _, it := range stale {
		_, _ = s.pool.Exec(ctx, `DELETE FROM user_chat_backgrounds WHERE id = $1::uuid AND user_id = $2::uuid`, it.ID, userID)
		removeChatBgFile(uploadDir, it.URL)
	}
	return nil
}

// DeleteChatBackground removes a library item and its file. If it is the active
// wallpaper, clears the theme background layer.
func (s *Service) DeleteChatBackground(ctx context.Context, userID, id, uploadDir string) (*User, error) {
	id = strings.TrimSpace(id)
	var url string
	err := s.pool.QueryRow(ctx, `
		SELECT url FROM user_chat_backgrounds
		WHERE id = $1::uuid AND user_id = $2::uuid
	`, id, userID).Scan(&url)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, errors.New("not found")
	}
	if err != nil {
		return nil, err
	}
	_, err = s.pool.Exec(ctx, `
		DELETE FROM user_chat_backgrounds WHERE id = $1::uuid AND user_id = $2::uuid
	`, id, userID)
	if err != nil {
		return nil, err
	}
	removeChatBgFile(uploadDir, url)

	u, err := s.UserByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	if u.ChatTheme != nil && u.ChatTheme.Background != nil {
		bg := u.ChatTheme.Background
		if bg.Kind == "image" && bg.URL == url {
			cleared := "default"
			return s.SetChatTheme(ctx, userID, &ChatTheme{Background: &ChatBg{Kind: cleared}})
		}
	}
	return u, nil
}

func removeChatBgFile(uploadDir, url string) {
	const prefix = "/uploads/chat-bg/"
	if !strings.HasPrefix(url, prefix) {
		return
	}
	name := filepath.Base(url)
	if name == "" || name == "." || name == string(filepath.Separator) {
		return
	}
	_ = os.Remove(filepath.Join(uploadDir, "chat-bg", name))
}
