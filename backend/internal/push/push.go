// Package push 向离线设备发送推送：第三方通道仅携带密文，明文由客户端解密展示。
package push

import (
	"context"
	"log"
	"strings"

	"github.com/ihope/ihope/internal/config"
)

// Payload 推送到客户端的数据（E2EE：消息体为 ciphertext，不含明文）。
type Payload struct {
	ConversationID string
	MessageID      string
	MessageType    string
	SenderID       string
	Ciphertext     string
	Epoch          int
	Title          string // 会话/发送者展示 hint（非消息明文）
	Body           string // 仅日志驱动占位
}

// Sender 底层推送通道（极光 / FCM / 日志）。
type Sender interface {
	Send(ctx context.Context, token, platform string, p Payload) error
}

// Service 按设备 platform 路由到极光或 FCM；未配置密钥时仅打日志。
type Service struct {
	sender Sender
}

func New(cfg config.Config) *Service {
	m := &multiSender{fallback: logSender{}}

	if key := strings.TrimSpace(cfg.JPushAppKey); key != "" &&
		strings.TrimSpace(cfg.JPushMasterSecret) != "" {
		m.jpush = &jpushSender{appKey: key, masterSecret: cfg.JPushMasterSecret}
		log.Printf("push: jpush enabled (android_cn)")
	}
	if key := strings.TrimSpace(cfg.FCMServerKey); key != "" {
		m.fcm = &fcmSender{serverKey: key}
		log.Printf("push: fcm enabled (android/ios)")
	}

	if m.jpush == nil && m.fcm == nil {
		log.Printf("push: no JPUSH_* or FCM_SERVER_KEY; using log driver only")
	}

	// 显式 PUSH_DRIVER=log 时仍走路由，只是没有密钥则全部落日志。
	_ = cfg.PushDriver

	return &Service{sender: m}
}

func (s *Service) Send(ctx context.Context, token, platform string, p Payload) error {
	if s == nil || s.sender == nil || strings.TrimSpace(token) == "" {
		return nil
	}
	return s.sender.Send(ctx, token, platform, p)
}

type logSender struct{}

func (logSender) Send(_ context.Context, token, platform string, p Payload) error {
	log.Printf("[push] platform=%s token=%s… title_hint=%q type=%s conv=%s msg=%s ciphertext_len=%d",
		platform, truncate(token, 12), p.Title, p.MessageType, p.ConversationID, p.MessageID, len(p.Ciphertext))
	return nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

func bodyForType(msgType string) string {
	switch msgType {
	case "image":
		return "[图片]"
	case "audio":
		return "[语音]"
	case "file":
		return "[文件]"
	case "announcement":
		return "[群公告]"
	case "system":
		return "[系统消息]"
	default:
		return "新消息"
	}
}
