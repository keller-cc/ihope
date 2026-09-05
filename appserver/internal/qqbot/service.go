package qqbot

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
	"time"
	"unicode"

	"github.com/keller-cc/ihope/appserver/internal/config"
)

type OnlineCheck interface {
	IsUserOnline(userID string) bool
}

type Service struct {
	cfg    config.Config
	store  *Store
	client *Client
	online OnlineCheck
}

func NewService(cfg config.Config, store *Store, client *Client, online OnlineCheck) *Service {
	return &Service{cfg: cfg, store: store, client: client, online: online}
}

func (s *Service) Enabled() bool {
	return s != nil && s.cfg.QQBotEnabled && s.client != nil &&
		strings.TrimSpace(s.cfg.QQBotAppID) != "" &&
		strings.TrimSpace(s.cfg.QQBotAppSecret) != ""
}

func (s *Service) Store() *Store { return s.store }

func (s *Service) AddHint() string { return s.cfg.QQBotAddHint }

func (s *Service) NotifyDoorbell(ctx context.Context, userID, senderHint string) {
	if !s.Enabled() {
		return
	}
	if s.online != nil && s.online.IsUserOnline(userID) {
		return
	}
	b, err := s.store.GetByUserID(ctx, userID)
	if err != nil || !b.DoorbellEnabled {
		return
	}
	cooldown := time.Duration(s.cfg.QQDoorbellCooldownSec) * time.Second
	if cooldown > 0 && b.LastDoorbellAt != nil && time.Since(*b.LastDoorbellAt) < cooldown {
		return
	}
	senderHint = strings.TrimSpace(senderHint)
	if senderHint == "" {
		senderHint = "有人"
	}
	text := fmt.Sprintf("您有新的聊天消息（%s），请打开 IHope 查看。", senderHint)
	if err := s.client.SendText(ctx, b.QQOpenID, text, "", 0); err != nil {
		log.Printf("qqbot notify user=%s: %v", userID, err)
		return
	}
	_ = s.store.TouchDoorbell(ctx, userID)
}

func (s *Service) HandleInboundText(ctx context.Context, openID, content, msgID string) {
	if !s.Enabled() {
		return
	}
	content = strings.TrimSpace(content)
	if content == "" {
		return
	}
	if isBindCode(content) {
		_, err := s.store.ConsumeBindCode(ctx, content, openID)
		if err != nil {
			_ = s.client.SendText(ctx, openID, "绑定失败："+bindErrText(err)+"。请重新获取绑定码。", msgID, 1)
			return
		}
		_ = s.client.SendText(ctx, openID,
			"绑定成功。发送「帮助」查看指令：消息提醒开|关、解绑。",
			msgID, 1)
		return
	}
	b, err := s.store.GetByOpenID(ctx, openID)
	cmd := normalizeCmd(content)
	if err != nil {
		_ = s.client.SendText(ctx, openID, "尚未绑定。请打开 IHope → 设置 → QQ 提醒，获取绑定码后发给我。", msgID, 1)
		return
	}
	switch cmd {
	case "帮助", "help":
		_ = s.client.SendText(ctx, openID, "指令：消息提醒开 / 消息提醒关 / 解绑 / 帮助", msgID, 1)
	case "消息提醒开", "门铃开":
		t := true
		_ = s.store.UpdateFlags(ctx, b.UserID, &t, nil, nil, nil)
		_ = s.client.SendText(ctx, openID, "已开启离线消息提醒。", msgID, 1)
	case "消息提醒关", "门铃关":
		f := false
		_ = s.store.UpdateFlags(ctx, b.UserID, &f, nil, nil, nil)
		_ = s.client.SendText(ctx, openID, "已关闭离线消息提醒。", msgID, 1)
	case "解绑":
		_ = s.store.Unbind(ctx, b.UserID)
		_ = s.client.SendText(ctx, openID, "已解除绑定。", msgID, 1)
	default:
		_ = s.client.SendText(ctx, openID, "未识别指令。发送「帮助」查看可用指令。", msgID, 1)
	}
}

func isBindCode(s string) bool {
	if len(s) != 6 {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

func bindErrText(err error) string {
	switch {
	case errors.Is(err, ErrCodeExpired):
		return "绑定码已过期"
	case errors.Is(err, ErrCodeInvalid):
		return "绑定码无效"
	default:
		return "请稍后重试"
	}
}

func normalizeCmd(s string) string {
	s = strings.TrimSpace(s)
	var b strings.Builder
	for _, r := range s {
		if unicode.IsSpace(r) {
			continue
		}
		b.WriteRune(r)
	}
	return strings.ToLower(b.String())
}
