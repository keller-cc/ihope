package chat

import (
	"context"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5"
)

// SendTextOpts carries optional @ mention payload for group text messages.
type SendTextOpts struct {
	MentionUserIDs []string
	MentionAll     bool
}

// MentionJumpResult is the next unvisited @ for the viewer (newest first).
type MentionJumpResult struct {
	MessageID string `json:"messageId"`
	HasMore   bool   `json:"hasMore"`
}

func normalizeMentionIDs(ids []string, selfID string) []string {
	seen := map[string]bool{}
	var out []string
	for _, id := range ids {
		id = strings.TrimSpace(id)
		if id == "" || id == selfID || seen[id] {
			continue
		}
		seen[id] = true
		out = append(out, id)
	}
	return out
}

func (s *Service) attachMentions(ctx context.Context, msgs []Message) error {
	if len(msgs) == 0 {
		return nil
	}
	ids := make([]string, 0, len(msgs))
	idx := map[string]int{}
	for i := range msgs {
		ids = append(ids, msgs[i].ID)
		idx[msgs[i].ID] = i
		msgs[i].Mentions = nil
	}
	rows, err := s.pool.Query(ctx, `
		SELECT message_id::text, user_id::text FROM message_mentions
		WHERE message_id = ANY($1::uuid[])
		ORDER BY message_id, user_id
	`, ids)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var mid, uid string
		if err := rows.Scan(&mid, &uid); err != nil {
			return err
		}
		i, ok := idx[mid]
		if !ok {
			continue
		}
		msgs[i].Mentions = append(msgs[i].Mentions, uid)
	}
	return rows.Err()
}

func (s *Service) saveMentions(ctx context.Context, messageID string, userIDs []string) error {
	if len(userIDs) == 0 {
		return nil
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO message_mentions (message_id, user_id)
		SELECT $1, x FROM unnest($2::uuid[]) AS x
		ON CONFLICT DO NOTHING
	`, messageID, userIDs)
	if err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx, `
		UPDATE conversation_members
		SET mention_home_tip = TRUE
		WHERE conversation_id = (SELECT conversation_id FROM messages WHERE id = $1)
		  AND user_id = ANY($2::uuid[])
		  AND removed_at IS NULL
	`, messageID, userIDs)
	return err
}

func (s *Service) resolveMentionTargets(
	ctx context.Context,
	conversationID, senderID string,
	mentionUserIDs []string,
	mentionAll bool,
) (ids []string, all bool, err error) {
	var typ string
	err = s.pool.QueryRow(ctx, `SELECT type FROM conversations WHERE id = $1`, conversationID).Scan(&typ)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, false, errors.New("conversation not found")
		}
		return nil, false, err
	}
	if typ != "group" {
		if mentionAll || len(mentionUserIDs) > 0 {
			return nil, false, errors.New("mentions only in groups")
		}
		return nil, false, nil
	}
	if mentionAll {
		rows, err := s.pool.Query(ctx, `
			SELECT user_id::text FROM conversation_members
			WHERE conversation_id = $1 AND removed_at IS NULL AND user_id <> $2
		`, conversationID, senderID)
		if err != nil {
			return nil, false, err
		}
		defer rows.Close()
		for rows.Next() {
			var id string
			if err := rows.Scan(&id); err != nil {
				return nil, false, err
			}
			ids = append(ids, id)
		}
		if err := rows.Err(); err != nil {
			return nil, false, err
		}
		return ids, true, nil
	}
	ids = normalizeMentionIDs(mentionUserIDs, senderID)
	if len(ids) == 0 {
		return nil, false, nil
	}
	var n int
	err = s.pool.QueryRow(ctx, `
		SELECT COUNT(*)::int FROM conversation_members
		WHERE conversation_id = $1 AND removed_at IS NULL AND user_id = ANY($2::uuid[])
	`, conversationID, ids).Scan(&n)
	if err != nil {
		return nil, false, err
	}
	if n != len(ids) {
		return nil, false, errors.New("mention target not in group")
	}
	return ids, false, nil
}

// JumpNextMention jumps to the newest unvisited @ for the user and marks it visited.
// Also clears the home-list red tip (first click).
func (s *Service) JumpNextMention(ctx context.Context, conversationID, userID string) (*MentionJumpResult, error) {
	ok, err := s.CanAccessConversation(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	_, _ = s.pool.Exec(ctx, `
		UPDATE conversation_members SET mention_home_tip = FALSE
		WHERE conversation_id = $1 AND user_id = $2
	`, conversationID, userID)

	rows, err := s.pool.Query(ctx, `
		SELECT m.id::text
		FROM messages m
		JOIN message_mentions mm ON mm.message_id = m.id AND mm.user_id = $2
		LEFT JOIN message_mention_visits v ON v.message_id = m.id AND v.user_id = $2
		WHERE m.conversation_id = $1 AND v.message_id IS NULL AND m.recalled_at IS NULL
		ORDER BY m.created_at DESC
		LIMIT 2
	`, conversationID, userID)
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
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(ids) == 0 {
		return &MentionJumpResult{MessageID: "", HasMore: false}, nil
	}
	messageID := ids[0]
	_, err = s.pool.Exec(ctx, `
		INSERT INTO message_mention_visits (message_id, user_id)
		VALUES ($1, $2)
		ON CONFLICT DO NOTHING
	`, messageID, userID)
	if err != nil {
		return nil, err
	}
	return &MentionJumpResult{MessageID: messageID, HasMore: len(ids) > 1}, nil
}

func (s *Service) HasUnvisitedMentions(ctx context.Context, conversationID, userID string) (bool, error) {
	var ok bool
	err := s.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1
			FROM messages m
			JOIN message_mentions mm ON mm.message_id = m.id AND mm.user_id = $2
			LEFT JOIN message_mention_visits v ON v.message_id = m.id AND v.user_id = $2
			WHERE m.conversation_id = $1 AND v.message_id IS NULL AND m.recalled_at IS NULL
		)
	`, conversationID, userID).Scan(&ok)
	return ok, err
}
