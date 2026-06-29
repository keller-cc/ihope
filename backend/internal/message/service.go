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
	ok, err := s.conv.IsActiveMember(ctx, conversationID, userID)
	if err != nil {
		return nil, false, err
	}
	if !ok {
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

	msgs, err := s.messages.List(ctx, conversationID, before, limit+1)
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
	case "text", "image", "file", "announcement":
		return true
	default:
		return false
	}
}
