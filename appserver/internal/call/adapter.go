package call

import (
	"context"

	"github.com/keller-cc/ihope/appserver/internal/chat"
	"github.com/keller-cc/ihope/appserver/internal/hub"
)

// ChatMembership adapts chat.Service to call.Membership.
type ChatMembership struct {
	Chat *chat.Service
	Hub  *hub.Hub
}

func (a ChatMembership) IsMember(ctx context.Context, conversationID, userID string) (bool, error) {
	return a.Chat.IsMember(ctx, conversationID, userID)
}

func (a ChatMembership) ConversationType(ctx context.Context, conversationID string) (string, error) {
	return a.Chat.ConversationType(ctx, conversationID)
}

func (a ChatMembership) ListMembers(ctx context.Context, conversationID, userID string) ([]MemberInfo, error) {
	list, err := a.Chat.ListGroupMembers(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	out := make([]MemberInfo, 0, len(list))
	for _, c := range list {
		out = append(out, MemberInfo{
			ID:        c.ID,
			Username:  c.Username,
			AvatarURL: c.AvatarURL,
		})
	}
	return out, nil
}

func (a ChatMembership) PostCallMessage(ctx context.Context, conversationID, senderID string, body CallMessageBody, markReadUserIDs []string) error {
	m, err := a.Chat.SendCallMessage(ctx, conversationID, senderID, chat.CallBody{
		Kind:        body.Kind,
		Status:      body.Status,
		DurationSec: body.DurationSec,
	})
	if err != nil {
		return err
	}
	_ = a.Chat.MarkReadUsers(ctx, conversationID, markReadUserIDs)
	if a.Hub != nil {
		a.Hub.Publish(conversationID, map[string]any{"type": "message", "message": m})
	}
	return nil
}
