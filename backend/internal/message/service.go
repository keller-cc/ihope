package message

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/ihope/ihope/internal/conversation"
)

var (
	ErrInvalidInput = errors.New("invalid message")
	ErrNotMember    = conversation.ErrNotMember
)

const (
	DefaultLimit = 50
	MaxLimit     = 100
)

type Service struct {
	messages *Repository
	conv     *conversation.Repository
}

func NewService(messages *Repository, conv *conversation.Repository) *Service {
	return &Service{messages: messages, conv: conv}
}

type SendInput struct {
	ConversationID string
	SenderID       string
	Type           string
	Ciphertext     string
}

func (s *Service) Send(ctx context.Context, in SendInput) (*Message, error) {
	msgType := strings.TrimSpace(in.Type)
	content := strings.TrimSpace(in.Ciphertext)
	if msgType == "" {
		msgType = "text"
	}
	if content == "" || !isAllowedType(msgType) {
		return nil, ErrInvalidInput
	}

	ok, err := s.conv.IsActiveMember(ctx, in.ConversationID, in.SenderID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrNotMember
	}

	conv, err := s.conv.GetByID(ctx, in.ConversationID)
	if err != nil {
		return nil, err
	}

	epoch := 0
	if conv.Type == "group" {
		epoch = conv.Epoch
	}

	return s.messages.Create(ctx, in.ConversationID, in.SenderID, msgType, content, epoch)
}

func (s *Service) List(ctx context.Context, conversationID, userID string, beforeMessageID string, limit int) ([]Message, bool, error) {
	if _, err := s.conv.GetMembership(ctx, conversationID, userID); err != nil {
		return nil, false, ErrNotMember
	}

	if limit <= 0 {
		limit = DefaultLimit
	}
	if limit > MaxLimit {
		limit = MaxLimit
	}

	var before *time.Time
	if beforeMessageID != "" {
		t, err := s.messages.GetCreatedAt(ctx, beforeMessageID)
		if err != nil {
			return nil, false, err
		}
		before = &t
	}

	msgs, err := s.messages.ListForMember(ctx, conversationID, userID, before, limit+1)
	if err != nil {
		return nil, false, err
	}

	hasMore := len(msgs) > limit
	if hasMore {
		msgs = msgs[:limit]
	}
	return msgs, hasMore, nil
}

func isAllowedType(t string) bool {
	switch t {
	case "text", "image", "file", "announcement", "system":
		return true
	default:
		return false
	}
}

// SendSystem 写入群系统提示（明文 ciphertext，不经 E2EE）。
// 仅由会话 membership 钩子调用；sender 可能刚退群，故不校验仍为活跃成员。
func (s *Service) SendSystem(ctx context.Context, conversationID, senderID, text string) (*Message, error) {
	return s.SendSystemAtEpoch(ctx, conversationID, senderID, text, -1)
}

// SendSystemAtEpoch 写入指定 epoch 的系统提示；epoch < 0 时使用当前会话 epoch。
func (s *Service) SendSystemAtEpoch(
	ctx context.Context,
	conversationID, senderID, text string,
	epoch int,
) (*Message, error) {
	text = strings.TrimSpace(text)
	if text == "" || senderID == "" {
		return nil, ErrInvalidInput
	}

	if epoch < 0 {
		conv, err := s.conv.GetByID(ctx, conversationID)
		if err != nil {
			return nil, err
		}
		epoch = 0
		if conv.Type == "group" {
			epoch = conv.Epoch
		}
	}

	return s.messages.Create(ctx, conversationID, senderID, "system", text, epoch)
}
