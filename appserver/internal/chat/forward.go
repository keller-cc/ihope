package chat

import (
	"context"
	"encoding/json"
	"errors"
	"unicode/utf8"

	"github.com/keller-cc/ihope/appserver/internal/crypto"
)

const maxForwardMessages = 30
const maxForwardTextRunes = 200

// ForwardMode is one_by_one or merge.
type ForwardMode string

const (
	ForwardOneByOne ForwardMode = "one_by_one"
	ForwardMerge    ForwardMode = "merge"
)

// ForwardItem is one line inside a merged forward card.
type ForwardItem struct {
	SenderName string `json:"senderName"`
	Type       string `json:"type"`
	Body       string `json:"body,omitempty"`
	ThumbURL   string `json:"thumbUrl,omitempty"`
	URL        string `json:"url,omitempty"`
	Name       string  `json:"name,omitempty"`
	Size       int64   `json:"size,omitempty"`
	Duration   float64 `json:"duration,omitempty"`
	CreatedAt  string  `json:"createdAt"`
}

// ForwardBody is sealed JSON for type=forward.
type ForwardBody struct {
	FromTitle string        `json:"fromTitle"`
	FromType  string        `json:"fromType"`
	Items     []ForwardItem `json:"items"`
}

// ForwardMessages copies messages from source into target.
func (s *Service) ForwardMessages(
	ctx context.Context,
	targetID, userID, sourceID string,
	messageIDs []string,
	mode ForwardMode,
) ([]Message, error) {
	if mode != ForwardOneByOne && mode != ForwardMerge {
		return nil, errors.New("invalid mode")
	}
	if len(messageIDs) == 0 {
		return nil, errors.New("messageIds required")
	}
	if len(messageIDs) > maxForwardMessages {
		return nil, errors.New("too many messages")
	}

	okSrc, err := s.IsMember(ctx, sourceID, userID)
	if err != nil {
		return nil, err
	}
	if !okSrc {
		return nil, errors.New("forbidden")
	}
	okDst, err := s.IsMember(ctx, targetID, userID)
	if err != nil {
		return nil, err
	}
	if !okDst {
		return nil, errors.New("forbidden")
	}

	srcConv, err := s.getConversation(ctx, sourceID)
	if err != nil {
		return nil, err
	}
	fromTitle := srcConv.Title
	if srcConv.Type == "dm" {
		var peer string
		_ = s.pool.QueryRow(ctx, `
			SELECT u.username FROM conversation_members cm
			JOIN users u ON u.id = cm.user_id
			WHERE cm.conversation_id = $1 AND cm.user_id <> $2
			LIMIT 1
		`, sourceID, userID).Scan(&peer)
		if peer != "" {
			fromTitle = peer
		}
	}

	msgs, err := s.loadForwardSources(ctx, sourceID, messageIDs)
	if err != nil {
		return nil, err
	}

	if mode == ForwardOneByOne {
		var out []Message
		for _, src := range msgs {
			m, err := s.copyMessageTo(ctx, targetID, userID, src)
			if err != nil {
				return nil, err
			}
			out = append(out, *m)
		}
		_, _ = s.pool.Exec(ctx, `
			UPDATE conversation_members SET hidden_at = NULL
			WHERE conversation_id = $1 AND hidden_at IS NOT NULL
		`, targetID)
		return out, nil
	}

	items := make([]ForwardItem, 0, len(msgs))
	for _, src := range msgs {
		item, err := forwardItemFrom(src)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	payload, err := json.Marshal(ForwardBody{
		FromTitle: fromTitle,
		FromType:  srcConv.Type,
		Items:     items,
	})
	if err != nil {
		return nil, err
	}
	sealed, err := crypto.Seal(s.key, payload)
	if err != nil {
		return nil, err
	}
	var m Message
	var sealedOut string
	err = s.pool.QueryRow(ctx, `
		INSERT INTO messages (conversation_id, sender_id, type, body_sealed)
		VALUES ($1, $2, 'forward', $3)
		RETURNING id::text, conversation_id::text, sender_id::text, type, body_sealed, created_at::text
	`, targetID, userID, sealed).Scan(
		&m.ID, &m.ConversationID, &m.SenderID, &m.Type, &sealedOut, &m.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	m.Body = string(payload)
	s.fillSenderMeta(ctx, &m, userID)
	_, _ = s.pool.Exec(ctx, `
		UPDATE conversation_members SET hidden_at = NULL
		WHERE conversation_id = $1 AND hidden_at IS NOT NULL
	`, targetID)
	return []Message{m}, nil
}

type forwardSource struct {
	ID        string
	Type      string
	Sealed    string
	Body      string
	CreatedAt string
	Username  string
}

func (s *Service) loadForwardSources(ctx context.Context, conversationID string, ids []string) ([]forwardSource, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT m.id::text, m.type, m.body_sealed, m.created_at::text, u.username,
			m.recalled_at IS NOT NULL
		FROM messages m
		JOIN users u ON u.id = m.sender_id
		WHERE m.conversation_id = $1 AND m.id = ANY($2::uuid[])
		ORDER BY m.created_at ASC
	`, conversationID, ids)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []forwardSource
	seen := map[string]struct{}{}
	for rows.Next() {
		var src forwardSource
		var recalled bool
		if err := rows.Scan(&src.ID, &src.Type, &src.Sealed, &src.CreatedAt, &src.Username, &recalled); err != nil {
			return nil, err
		}
		if recalled {
			return nil, errors.New("cannot forward recalled")
		}
		switch src.Type {
		case "text", "image", "file", "voice":
		default:
			return nil, errors.New("unsupported message type")
		}
		plain, err := crypto.Open(s.key, src.Sealed)
		if err != nil {
			return nil, errors.New("decrypt failed")
		}
		src.Body = string(plain)
		out = append(out, src)
		seen[src.ID] = struct{}{}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for _, id := range ids {
		if _, ok := seen[id]; !ok {
			return nil, errors.New("message not found")
		}
	}
	return out, nil
}

func (s *Service) copyMessageTo(ctx context.Context, targetID, userID string, src forwardSource) (*Message, error) {
	var m Message
	var sealedOut string
	err := s.pool.QueryRow(ctx, `
		INSERT INTO messages (conversation_id, sender_id, type, body_sealed)
		VALUES ($1, $2, $3, $4)
		RETURNING id::text, conversation_id::text, sender_id::text, type, body_sealed, created_at::text
	`, targetID, userID, src.Type, src.Sealed).Scan(
		&m.ID, &m.ConversationID, &m.SenderID, &m.Type, &sealedOut, &m.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	m.Body = src.Body
	s.fillSenderMeta(ctx, &m, userID)
	return &m, nil
}

func forwardItemFrom(src forwardSource) (ForwardItem, error) {
	item := ForwardItem{
		SenderName: src.Username,
		Type:       src.Type,
		CreatedAt:  src.CreatedAt,
	}
	switch src.Type {
	case "text":
		item.Body = truncateRunes(src.Body, maxForwardTextRunes)
	case "image":
		var img ImageBody
		if err := json.Unmarshal([]byte(src.Body), &img); err != nil {
			return item, errors.New("invalid image body")
		}
		item.ThumbURL = img.ThumbURL
		item.URL = img.URL
	case "file":
		var f FileBody
		if err := json.Unmarshal([]byte(src.Body), &f); err != nil {
			return item, errors.New("invalid file body")
		}
		item.Name = f.Name
		item.Size = f.Size
		item.URL = f.URL
	case "voice":
		var v VoiceBody
		if err := json.Unmarshal([]byte(src.Body), &v); err != nil {
			return item, errors.New("invalid voice body")
		}
		item.URL = v.URL
		item.Duration = v.Duration
		item.Size = v.Size
	default:
		return item, errors.New("unsupported message type")
	}
	return item, nil
}

func truncateRunes(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	r := []rune(s)
	return string(r[:n]) + "…"
}
