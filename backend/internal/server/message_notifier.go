package server

import (
	"context"

	"github.com/ihope/ihope/internal/message"
	"github.com/ihope/ihope/internal/push"
	"github.com/ihope/ihope/internal/ws"
)

// messageNotifier WebSocket 广播 + 离线推送。
type messageNotifier struct {
	hub  *ws.Hub
	push *push.Dispatcher
}

func NewMessageNotifier(hub *ws.Hub, dispatcher *push.Dispatcher) message.Notifier {
	return &messageNotifier{hub: hub, push: dispatcher}
}

func (n *messageNotifier) NotifyMessage(memberUserIDs []string, msg *message.Message) {
	if n == nil {
		return
	}
	if n.hub != nil {
		n.hub.NotifyMessage(memberUserIDs, msg)
	}
	if n.push != nil && msg != nil {
		go n.push.NotifyNewMessage(context.Background(), memberUserIDs, msg)
	}
}
