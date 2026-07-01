package server

import (
	"context"

	"github.com/ihope/ihope/internal/conversation"
	"github.com/ihope/ihope/internal/message"
	"github.com/ihope/ihope/internal/ws"
)

type convRealtime struct {
	hub *ws.Hub
}

func NewConvRealtime(hub *ws.Hub) conversation.RealtimeNotifier {
	return &convRealtime{hub: hub}
}

func (n *convRealtime) NotifyEpochUpdated(memberUserIDs []string, conversationID string, epoch int) {
	n.hub.NotifyEpochUpdated(memberUserIDs, conversationID, epoch)
}

func (n *convRealtime) NotifyGmkUpdated(
	memberUserIDs []string,
	conversationID, senderID string,
	epochs []int,
) {
	n.hub.NotifyGmkUpdated(memberUserIDs, conversationID, senderID, epochs)
}

func (n *convRealtime) NotifyGroupDissolved(
	memberUserIDs []string,
	conversationID, groupName, dissolvedBy string,
) {
	n.hub.NotifyGroupDissolved(memberUserIDs, conversationID, groupName, dissolvedBy)
}

func (n *convRealtime) NotifyMessage(memberUserIDs []string, msg *conversation.ChatMessage) {
	n.hub.NotifyMessage(memberUserIDs, toMessageMsg(msg))
}

func (n *convRealtime) NotifyConversationAdded(userIDs []string, conv map[string]any) {
	n.hub.NotifyConversationAdded(userIDs, conv)
}

func (n *convRealtime) NotifyConversationRemoved(userIDs []string, conversationID string) {
	n.hub.NotifyConversationRemoved(userIDs, conversationID)
}

func (n *convRealtime) NotifyConversationUpdated(userIDs []string, conv map[string]any) {
	n.hub.NotifyConversationUpdated(userIDs, conv)
}

type convSystemMessenger struct {
	svc *message.Service
}

func NewConvSystemMessenger(svc *message.Service) conversation.SystemMessenger {
	return &convSystemMessenger{svc: svc}
}

func (s *convSystemMessenger) SendSystem(
	ctx context.Context,
	conversationID, senderID, text string,
) (*conversation.ChatMessage, error) {
	msg, err := s.svc.SendSystem(ctx, conversationID, senderID, text)
	if err != nil {
		return nil, err
	}
	return toConvMsg(msg), nil
}

func (s *convSystemMessenger) SendSystemAtEpoch(
	ctx context.Context,
	conversationID, senderID, text string,
	epoch int,
) (*conversation.ChatMessage, error) {
	msg, err := s.svc.SendSystemAtEpoch(ctx, conversationID, senderID, text, epoch)
	if err != nil {
		return nil, err
	}
	return toConvMsg(msg), nil
}

func toMessageMsg(m *conversation.ChatMessage) *message.Message {
	if m == nil {
		return nil
	}
	return &message.Message{
		ID:             m.ID,
		ConversationID: m.ConversationID,
		SenderID:       m.SenderID,
		Type:           m.Type,
		Ciphertext:     m.Ciphertext,
		Epoch:          m.Epoch,
		CreatedAt:      m.CreatedAt,
	}
}

func toConvMsg(m *message.Message) *conversation.ChatMessage {
	if m == nil {
		return nil
	}
	return &conversation.ChatMessage{
		ID:             m.ID,
		ConversationID: m.ConversationID,
		SenderID:       m.SenderID,
		Type:           m.Type,
		Ciphertext:     m.Ciphertext,
		Epoch:          m.Epoch,
		CreatedAt:      m.CreatedAt,
	}
}
