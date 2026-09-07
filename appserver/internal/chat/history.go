package chat

import (
	"context"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
)

// ListMessagesOpts filters conversation history.
type ListMessagesOpts struct {
	Limit     int
	Before    string // created_at timestamptz cursor (exclusive)
	Type      string // image | file | text | forward | voice
	SenderID  string // single (legacy)
	SenderIDs []string
	Day       string // YYYY-MM-DD
}

// MessageDay is a day bucket for history browsing.
type MessageDay struct {
	Day   string `json:"day"`
	Count int    `json:"count"`
}

func (s *Service) ListMessages(ctx context.Context, conversationID, userID string, limit int, before string) ([]Message, bool, error) {
	return s.ListMessagesFiltered(ctx, conversationID, userID, ListMessagesOpts{Limit: limit, Before: before})
}

func (s *Service) ListMessagesFiltered(ctx context.Context, conversationID, userID string, opts ListMessagesOpts) ([]Message, bool, error) {
	ok, err := s.CanAccessConversation(ctx, conversationID, userID)
	if err != nil {
		return nil, false, err
	}
	if !ok {
		return nil, false, errors.New("forbidden")
	}
	limit := opts.Limit
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	fetch := limit + 1

	msgType := strings.TrimSpace(opts.Type)
	switch msgType {
	case "", "image", "file", "text", "forward", "voice":
	default:
		return nil, false, errors.New("invalid type")
	}
	senderIDs := normalizeSenderIDs(opts.SenderIDs, opts.SenderID)
	day := strings.TrimSpace(opts.Day)
	if day != "" && len(day) != 10 {
		return nil, false, errors.New("invalid day")
	}

	var ownerID *string
	var convType string
	_ = s.pool.QueryRow(ctx, `SELECT type, owner_id::text FROM conversations WHERE id = $1`, conversationID).
		Scan(&convType, &ownerID)

	args := []any{conversationID}
	where := []string{"m.conversation_id = $1"}
	argN := 2
	if msgType != "" {
		where = append(where, "m.type = $"+strconv.Itoa(argN))
		args = append(args, msgType)
		argN++
	}
	if len(senderIDs) == 1 {
		where = append(where, "m.sender_id = $"+strconv.Itoa(argN)+"::uuid")
		args = append(args, senderIDs[0])
		argN++
	} else if len(senderIDs) > 1 {
		where = append(where, "m.sender_id = ANY($"+strconv.Itoa(argN)+"::uuid[])")
		args = append(args, senderIDs)
		argN++
	}
	if day != "" {
		where = append(where, "(m.created_at AT TIME ZONE 'Asia/Shanghai')::date = $"+strconv.Itoa(argN)+"::date")
		args = append(args, day)
		argN++
	}
	if strings.TrimSpace(opts.Before) != "" {
		where = append(where, "m.created_at < $"+strconv.Itoa(argN)+"::timestamptz")
		args = append(args, opts.Before)
		argN++
	}
	args = append(args, fetch)
	limitPH := "$" + strconv.Itoa(argN)

	q := `
		SELECT m.id::text, m.conversation_id::text, m.sender_id::text, m.type, m.body_sealed, m.created_at::text,
			m.recalled_at::text, m.recalled_by::text, u.username, u.avatar_url,
			COALESCE(cm.role, 'member'), COALESCE(cm.member_title, '')
		FROM messages m
		JOIN users u ON u.id = m.sender_id
		LEFT JOIN conversation_members cm ON cm.conversation_id = m.conversation_id AND cm.user_id = m.sender_id
		WHERE ` + strings.Join(where, " AND ") + `
		ORDER BY m.created_at DESC
		LIMIT ` + limitPH

	rows, err := s.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, false, err
	}
	defer rows.Close()

	out, err := s.scanMessageRows(rows, convType, ownerID)
	if err != nil {
		return nil, false, err
	}
	hasMore := len(out) > limit
	if hasMore {
		out = out[:limit]
	}
	if out == nil {
		out = []Message{}
	}
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out, hasMore, nil
}

func (s *Service) ListMessageDays(ctx context.Context, conversationID, userID string) ([]MessageDay, error) {
	ok, err := s.CanAccessConversation(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	rows, err := s.pool.Query(ctx, `
		SELECT to_char((created_at AT TIME ZONE 'Asia/Shanghai')::date, 'YYYY-MM-DD') AS day, COUNT(*)::int
		FROM messages
		WHERE conversation_id = $1 AND recalled_at IS NULL
		GROUP BY 1
		ORDER BY 1 DESC
	`, conversationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []MessageDay
	for rows.Next() {
		var d MessageDay
		if err := rows.Scan(&d.Day, &d.Count); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	if out == nil {
		out = []MessageDay{}
	}
	return out, rows.Err()
}

func (s *Service) SearchMessages(ctx context.Context, conversationID, userID string, opts ListMessagesOpts, q string) ([]Message, bool, error) {
	ok, err := s.CanAccessConversation(ctx, conversationID, userID)
	if err != nil {
		return nil, false, err
	}
	if !ok {
		return nil, false, errors.New("forbidden")
	}
	q = strings.TrimSpace(q)
	if q == "" {
		return nil, false, errors.New("query required")
	}
	if utf8.RuneCountInString(q) > 64 {
		return nil, false, errors.New("query too long")
	}
	limit := opts.Limit
	if limit <= 0 || limit > 50 {
		limit = 30
	}
	day := strings.TrimSpace(opts.Day)
	if day != "" && len(day) != 10 {
		return nil, false, errors.New("invalid day")
	}
	senderIDs := normalizeSenderIDs(opts.SenderIDs, opts.SenderID)

	var ownerID *string
	var convType string
	_ = s.pool.QueryRow(ctx, `SELECT type, owner_id::text FROM conversations WHERE id = $1`, conversationID).
		Scan(&convType, &ownerID)

	ql := strings.ToLower(q)
	var matched []Message
	cursor := strings.TrimSpace(opts.Before)
	const batch = 120
	const maxBatches = 40

	for batchN := 0; batchN < maxBatches && len(matched) <= limit; batchN++ {
		args := []any{conversationID}
		where := []string{
			"m.conversation_id = $1",
			"m.recalled_at IS NULL",
			"m.type IN ('text', 'file')",
		}
		argN := 2
		if day != "" {
			where = append(where, "(m.created_at AT TIME ZONE 'Asia/Shanghai')::date = $"+strconv.Itoa(argN)+"::date")
			args = append(args, day)
			argN++
		}
		if len(senderIDs) == 1 {
			where = append(where, "m.sender_id = $"+strconv.Itoa(argN)+"::uuid")
			args = append(args, senderIDs[0])
			argN++
		} else if len(senderIDs) > 1 {
			where = append(where, "m.sender_id = ANY($"+strconv.Itoa(argN)+"::uuid[])")
			args = append(args, senderIDs)
			argN++
		}
		if cursor != "" {
			where = append(where, "m.created_at < $"+strconv.Itoa(argN)+"::timestamptz")
			args = append(args, cursor)
			argN++
		}
		args = append(args, batch)
		limitPH := "$" + strconv.Itoa(argN)

		rows, err := s.pool.Query(ctx, `
			SELECT m.id::text, m.conversation_id::text, m.sender_id::text, m.type, m.body_sealed, m.created_at::text,
				m.recalled_at::text, m.recalled_by::text, u.username, u.avatar_url,
				COALESCE(cm.role, 'member'), COALESCE(cm.member_title, '')
			FROM messages m
			JOIN users u ON u.id = m.sender_id
			LEFT JOIN conversation_members cm ON cm.conversation_id = m.conversation_id AND cm.user_id = m.sender_id
			WHERE `+strings.Join(where, " AND ")+`
			ORDER BY m.created_at DESC
			LIMIT `+limitPH, args...)
		if err != nil {
			return nil, false, err
		}
		batchMsgs, err := s.scanMessageRows(rows, convType, ownerID)
		rows.Close()
		if err != nil {
			return nil, false, err
		}
		if len(batchMsgs) == 0 {
			break
		}
		for _, m := range batchMsgs {
			cursor = m.CreatedAt
			if messageMatchesQuery(m, ql) {
				matched = append(matched, m)
				if len(matched) > limit {
					break
				}
			}
		}
		if len(batchMsgs) < batch {
			break
		}
	}

	hasMore := len(matched) > limit
	if hasMore {
		matched = matched[:limit]
	}
	if matched == nil {
		matched = []Message{}
	}
	return matched, hasMore, nil
}

func normalizeSenderIDs(ids []string, single string) []string {
	seen := map[string]struct{}{}
	var out []string
	add := func(raw string) {
		id := strings.TrimSpace(raw)
		if id == "" {
			return
		}
		if _, ok := seen[id]; ok {
			return
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	for _, id := range ids {
		add(id)
	}
	add(single)
	return out
}

func messageMatchesQuery(m Message, qLower string) bool {
	if m.Type == "text" {
		return strings.Contains(strings.ToLower(m.Body), qLower)
	}
	if m.Type == "file" {
		var f FileBody
		if json.Unmarshal([]byte(m.Body), &f) != nil {
			return false
		}
		return strings.Contains(strings.ToLower(f.Name), qLower)
	}
	return false
}

// MessageContext returns messages around a target id (oldest → newest).
func (s *Service) MessageContext(ctx context.Context, conversationID, userID, messageID string, beforeN, afterN int) ([]Message, error) {
	ok, err := s.CanAccessConversation(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("forbidden")
	}
	if beforeN <= 0 || beforeN > 50 {
		beforeN = 25
	}
	if afterN <= 0 || afterN > 50 {
		afterN = 25
	}
	var createdAt string
	err = s.pool.QueryRow(ctx, `
		SELECT created_at::text FROM messages WHERE id = $1 AND conversation_id = $2
	`, messageID, conversationID).Scan(&createdAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("message not found")
		}
		return nil, err
	}

	var ownerID *string
	var convType string
	_ = s.pool.QueryRow(ctx, `SELECT type, owner_id::text FROM conversations WHERE id = $1`, conversationID).
		Scan(&convType, &ownerID)

	beforeRows, err := s.pool.Query(ctx, `
		SELECT m.id::text, m.conversation_id::text, m.sender_id::text, m.type, m.body_sealed, m.created_at::text,
			m.recalled_at::text, m.recalled_by::text, u.username, u.avatar_url,
			COALESCE(cm.role, 'member'), COALESCE(cm.member_title, '')
		FROM messages m
		JOIN users u ON u.id = m.sender_id
		LEFT JOIN conversation_members cm ON cm.conversation_id = m.conversation_id AND cm.user_id = m.sender_id
		WHERE m.conversation_id = $1 AND m.created_at < $2::timestamptz
		ORDER BY m.created_at DESC
		LIMIT $3
	`, conversationID, createdAt, beforeN)
	if err != nil {
		return nil, err
	}
	beforeMsgs, err := s.scanMessageRows(beforeRows, convType, ownerID)
	beforeRows.Close()
	if err != nil {
		return nil, err
	}
	for i, j := 0, len(beforeMsgs)-1; i < j; i, j = i+1, j-1 {
		beforeMsgs[i], beforeMsgs[j] = beforeMsgs[j], beforeMsgs[i]
	}

	afterRows, err := s.pool.Query(ctx, `
		SELECT m.id::text, m.conversation_id::text, m.sender_id::text, m.type, m.body_sealed, m.created_at::text,
			m.recalled_at::text, m.recalled_by::text, u.username, u.avatar_url,
			COALESCE(cm.role, 'member'), COALESCE(cm.member_title, '')
		FROM messages m
		JOIN users u ON u.id = m.sender_id
		LEFT JOIN conversation_members cm ON cm.conversation_id = m.conversation_id AND cm.user_id = m.sender_id
		WHERE m.conversation_id = $1 AND m.created_at >= $2::timestamptz
		ORDER BY m.created_at ASC
		LIMIT $3
	`, conversationID, createdAt, afterN+1)
	if err != nil {
		return nil, err
	}
	afterMsgs, err := s.scanMessageRows(afterRows, convType, ownerID)
	afterRows.Close()
	if err != nil {
		return nil, err
	}

	out := append(beforeMsgs, afterMsgs...)
	if out == nil {
		out = []Message{}
	}
	return out, nil
}

func (s *Service) scanMessageRows(rows pgx.Rows, convType string, ownerID *string) ([]Message, error) {
	var out []Message
	for rows.Next() {
		var m Message
		var sealed string
		var recalledAt, recalledBy *string
		var role, customTitle string
		if err := rows.Scan(
			&m.ID, &m.ConversationID, &m.SenderID, &m.Type, &sealed, &m.CreatedAt,
			&recalledAt, &recalledBy, &m.SenderUsername, &m.SenderAvatarURL, &role, &customTitle,
		); err != nil {
			return nil, err
		}
		applyMessageBody(&m, sealed, recalledAt, recalledBy, s.key)
		if convType == "group" {
			m.SenderTitle = resolveMemberTitle(ownerID, m.SenderID, role, customTitle)
		}
		out = append(out, m)
	}
	return out, rows.Err()
}
