package conversation

import (
	"context"
	"time"
)

// ChatMessage 用于 WS 推送与会话侧系统消息（避免依赖 message 包）。
type ChatMessage struct {
	ID             string    `json:"id"`
	ConversationID string    `json:"conversation_id"`
	SenderID       string    `json:"sender_id"`
	Type           string    `json:"type"`
	Ciphertext     string    `json:"ciphertext"`
	Epoch          int       `json:"epoch"`
	CreatedAt      time.Time `json:"created_at"`
}

// SystemMessenger 写入群系统提示消息。
type SystemMessenger interface {
	SendSystem(ctx context.Context, conversationID, senderID, text string) (*ChatMessage, error)
	SendSystemAtEpoch(ctx context.Context, conversationID, senderID, text string, epoch int) (*ChatMessage, error)
}

// RealtimeNotifier 会话/群相关实时通知。
type RealtimeNotifier interface {
	NotifyEpochUpdated(memberUserIDs []string, conversationID string, epoch int)
	NotifyGroupDissolved(memberUserIDs []string, conversationID, groupName, dissolvedBy string)
	NotifyMessage(memberUserIDs []string, msg *ChatMessage)
	NotifyConversationAdded(userIDs []string, conversation map[string]any)
	NotifyConversationRemoved(userIDs []string, conversationID string)
	NotifyConversationUpdated(userIDs []string, conversation map[string]any)
}
