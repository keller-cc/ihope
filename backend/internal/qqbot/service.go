package qqbot

import (
	"context"
	"fmt"
	"log"
	"strings"
	"time"
	"unicode"

	"github.com/ihope/ihope/internal/config"
)

// OnlineUserCheck 用户是否有任意设备在线。
type OnlineUserCheck interface {
	IsUserOnline(userID string) bool
}

// Service QQ 门铃与增值推送。
type Service struct {
	cfg    config.Config
	store  *Store
	client *Client
	media  *MediaHost
	online OnlineUserCheck
}

func NewService(cfg config.Config, store *Store, client *Client, media *MediaHost, online OnlineUserCheck) *Service {
	return &Service{cfg: cfg, store: store, client: client, media: media, online: online}
}

func (s *Service) Enabled() bool {
	return s != nil && s.cfg.QQBotEnabled && s.client != nil &&
		strings.TrimSpace(s.cfg.QQBotAppID) != "" &&
		strings.TrimSpace(s.cfg.QQBotAppSecret) != ""
}

// NotifyDoorbell 用户完全离线且已绑定门铃时发送占位文本。
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
	text := fmt.Sprintf("%s 发来一条消息，请打开 IHope 查看。", senderHint)
	if err := s.client.SendText(ctx, b.QQOpenID, text, "", 0); err != nil {
		log.Printf("qqbot doorbell user=%s: %v", userID, err)
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

	// 绑定码：全数字 6～8 位
	if isBindCode(content) {
		userID, err := s.store.ConsumeBindCode(ctx, content, openID)
		if err != nil {
			_ = s.client.SendText(ctx, openID, "绑定失败："+bindErrText(err)+"。请在 App 重新获取绑定码。", msgID, 1)
			return
		}
		_ = s.client.SendText(ctx, openID,
			"绑定成功。可用指令：帮助 / 金句 / 新闻 / 门铃开|关 / 金句开|关 / 新闻开|关 / 解绑",
			msgID, 1)
		log.Printf("qqbot bound user=%s openid=%s…", userID, truncate(openID, 8))
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
		_ = s.client.SendText(ctx, openID, helpText(), msgID, 1)
	case "金句", "诗词":
		s.replyPoetry(ctx, b.QQOpenID, msgID)
	case "新闻", "60s", "读世界":
		s.replyNews(ctx, b.QQOpenID, msgID)
	case "门铃开":
		t := true
		_ = s.store.UpdateFlags(ctx, b.UserID, &t, nil, nil)
		_ = s.client.SendText(ctx, openID, "已开启离线门铃。", msgID, 1)
	case "门铃关":
		f := false
		_ = s.store.UpdateFlags(ctx, b.UserID, &f, nil, nil)
		_ = s.client.SendText(ctx, openID, "已关闭离线门铃。", msgID, 1)
	case "金句开":
		t := true
		_ = s.store.UpdateFlags(ctx, b.UserID, nil, &t, nil)
		_ = s.client.SendText(ctx, openID, "已开启每日金句图片。", msgID, 1)
	case "金句关":
		f := false
		_ = s.store.UpdateFlags(ctx, b.UserID, nil, &f, nil)
		_ = s.client.SendText(ctx, openID, "已关闭每日金句。", msgID, 1)
	case "新闻开":
		t := true
		_ = s.store.UpdateFlags(ctx, b.UserID, nil, nil, &t)
		_ = s.client.SendText(ctx, openID, "已开启每日 60s 读世界图片。", msgID, 1)
	case "新闻关":
		f := false
		_ = s.store.UpdateFlags(ctx, b.UserID, nil, nil, &f)
		_ = s.client.SendText(ctx, openID, "已关闭每日新闻。", msgID, 1)
	case "解绑":
		_ = s.store.Unbind(ctx, b.UserID)
		_ = s.client.SendText(ctx, openID, "已解绑。如需再次使用请重新绑定。", msgID, 1)
	default:
		_ = s.client.SendText(ctx, openID, "未识别指令。发送「帮助」查看用法。", msgID, 1)
	}
}

func (s *Service) replyPoetry(ctx context.Context, openID, msgID string) {
	q, err := FetchPoetry(ctx, s.cfg.QQPoetryAPIURL)
	if err != nil {
		_ = s.client.SendText(ctx, openID, "金句获取失败，请稍后再试。", msgID, 1)
		return
	}
	png, err := RenderPoetryCard(q, s.cfg.QQPoetryFontPath)
	if err != nil {
		_ = s.client.SendText(ctx, openID, "金句图片生成失败（请检查字体配置）。", msgID, 1)
		log.Printf("qqbot poetry render: %v", err)
		return
	}
	url, err := s.media.Put(png, time.Hour)
	if err != nil {
		_ = s.client.SendText(ctx, openID, "金句图片暂存失败。", msgID, 1)
		return
	}
	if err := s.client.SendImagePNG(ctx, openID, png, url, msgID, 1); err != nil {
		log.Printf("qqbot poetry send: %v", err)
		_ = s.client.SendText(ctx, openID, "金句图片发送失败。", msgID, 1)
	}
}

func (s *Service) replyNews(ctx context.Context, openID, msgID string) {
	png, err := Fetch60sImage(ctx, s.cfg.QQNews60sAPIURL)
	if err != nil {
		log.Printf("qqbot 60s fetch: %v", err)
		_ = s.client.SendText(ctx, openID, "60s 读世界获取失败，请稍后再试。", msgID, 1)
		return
	}
	url, err := s.media.Put(png, time.Hour)
	if err != nil {
		_ = s.client.SendText(ctx, openID, "新闻图片暂存失败。", msgID, 1)
		return
	}
	if err := s.client.SendImagePNG(ctx, openID, png, url, msgID, 1); err != nil {
		log.Printf("qqbot 60s send: %v", err)
		_ = s.client.SendText(ctx, openID, "新闻图片发送失败。", msgID, 1)
	}
}

func (s *Service) BroadcastPoetry(ctx context.Context) {
	if !s.Enabled() {
		return
	}
	q, err := FetchPoetry(ctx, s.cfg.QQPoetryAPIURL)
	if err != nil {
		log.Printf("qqbot daily poetry fetch: %v", err)
		return
	}
	png, err := RenderPoetryCard(q, s.cfg.QQPoetryFontPath)
	if err != nil {
		log.Printf("qqbot daily poetry render: %v", err)
		return
	}
	url, err := s.media.Put(png, 2*time.Hour)
	if err != nil {
		log.Printf("qqbot daily poetry media: %v", err)
		return
	}
	list, err := s.store.ListPoetrySubscribers(ctx)
	if err != nil {
		log.Printf("qqbot daily poetry list: %v", err)
		return
	}
	for _, b := range list {
		if err := s.client.SendImagePNG(ctx, b.QQOpenID, png, url, "", 0); err != nil {
			log.Printf("qqbot daily poetry to %s: %v", truncate(b.QQOpenID, 8), err)
		}
		time.Sleep(200 * time.Millisecond)
	}
}

func (s *Service) BroadcastNews(ctx context.Context) {
	if !s.Enabled() {
		return
	}
	png, err := Fetch60sImage(ctx, s.cfg.QQNews60sAPIURL)
	if err != nil {
		log.Printf("qqbot daily 60s fetch: %v", err)
		return
	}
	url, err := s.media.Put(png, 2*time.Hour)
	if err != nil {
		log.Printf("qqbot daily 60s media: %v", err)
		return
	}
	list, err := s.store.ListNewsSubscribers(ctx)
	if err != nil {
		log.Printf("qqbot daily 60s list: %v", err)
		return
	}
	for _, b := range list {
		if err := s.client.SendImagePNG(ctx, b.QQOpenID, png, url, "", 0); err != nil {
			log.Printf("qqbot daily 60s to %s: %v", truncate(b.QQOpenID, 8), err)
		}
		time.Sleep(200 * time.Millisecond)
	}
}

func helpText() string {
	return strings.TrimSpace(`
IHope QQ 助手
· 离线门铃：有人发消息时提醒你打开 App
· 金句 / 诗词：立即发送诗词图卡
· 新闻 / 60s / 读世界：每天60秒读懂世界图片
· 门铃开|关　金句开|关　新闻开|关
· 解绑
`)
}

func isBindCode(s string) bool {
	if len(s) < 6 || len(s) > 8 {
		return false
	}
	for _, r := range s {
		if !unicode.IsDigit(r) {
			return false
		}
	}
	return true
}

func normalizeCmd(s string) string {
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(s, "/")
	return strings.ToLower(s)
}

func bindErrText(err error) string {
	switch err {
	case ErrCodeExpired:
		return "绑定码已过期"
	case ErrCodeInvalid:
		return "绑定码无效"
	default:
		return "请稍后重试"
	}
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}
