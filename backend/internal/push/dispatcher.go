package push

import (
	"context"
	"log"

	"github.com/ihope/ihope/internal/conversation"
	"github.com/ihope/ihope/internal/message"
	"github.com/ihope/ihope/internal/user"
)

// OnlineCheck 判断某设备是否已通过 WebSocket 在线。
type OnlineCheck interface {
	IsDeviceOnline(userID, deviceID string) bool
}

// Dispatcher 在新消息写入后，向离线设备发送推送。
type Dispatcher struct {
	push    *Service
	users   *user.Repository
	conv    *conversation.Repository
	online  OnlineCheck
}

func NewDispatcher(
	push *Service,
	users *user.Repository,
	conv *conversation.Repository,
	online OnlineCheck,
) *Dispatcher {
	return &Dispatcher{push: push, users: users, conv: conv, online: online}
}

func (d *Dispatcher) NotifyNewMessage(ctx context.Context, memberUserIDs []string, msg *message.Message) {
	if d == nil || d.push == nil || msg == nil {
		return
	}

	conv, err := d.conv.GetByID(ctx, msg.ConversationID)
	if err != nil {
		log.Printf("push: load conversation: %v", err)
		return
	}

	senderName := "新消息"
	if u, err := d.users.GetByID(ctx, msg.SenderID); err == nil && u.Username != "" {
		senderName = u.Username
	}

	title := senderName
	if conv.Type == "group" && conv.Name != nil && *conv.Name != "" {
		title = *conv.Name
	}

	payload := Payload{
		ConversationID: msg.ConversationID,
		MessageID:      msg.ID,
		MessageType:    msg.Type,
		SenderID:       msg.SenderID,
		Ciphertext:     msg.Ciphertext,
		Epoch:          msg.Epoch,
		Title:          title,
		Body:           bodyForType(msg.Type),
	}

	for _, uid := range memberUserIDs {
		if uid == msg.SenderID {
			continue
		}
		targets, err := d.users.ListPushTargets(ctx, uid)
		if err != nil {
			log.Printf("push: list targets user=%s: %v", uid, err)
			continue
		}
		for _, t := range targets {
			if d.online != nil && d.online.IsDeviceOnline(uid, t.DeviceID) {
				continue
			}
			if err := d.push.Send(ctx, t.PushToken, t.Platform, payload); err != nil {
				log.Printf("push: send user=%s device=%s: %v", uid, t.DeviceID, err)
			}
		}
	}
}
