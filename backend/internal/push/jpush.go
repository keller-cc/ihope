package push

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// jpushSender 极光推送（国内 Android 主通道）。
type jpushSender struct {
	appKey       string
	masterSecret string
	client       *http.Client
}

func (j *jpushSender) Send(ctx context.Context, token, platform string, p Payload) error {
	if j.client == nil {
		j.client = &http.Client{Timeout: 10 * time.Second}
	}

	// 自定义消息 + 系统通知：进程被杀时靠 notification 唤醒；extras 仅含密文。
	extras := pushExtras(p)
	body := map[string]any{
		"platform": "android",
		"audience": map[string]any{
			"registration_id": []string{token},
		},
		"notification": map[string]any{
			"android": map[string]any{
				"title":  p.Title,
				"alert":  p.Body,
				"extras": extras,
			},
		},
		"message": map[string]any{
			"msg_content": "new_message",
			"extras":      extras,
		},
		"options": map[string]any{
			"time_to_live": 86400,
		},
	}

	raw, err := json.Marshal(body)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		"https://api.jpush.cn/v3/push",
		bytes.NewReader(raw),
	)
	if err != nil {
		return err
	}
	auth := base64.StdEncoding.EncodeToString([]byte(j.appKey + ":" + j.masterSecret))
	req.Header.Set("Authorization", "Basic "+auth)
	req.Header.Set("Content-Type", "application/json")

	res, err := j.client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()

	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return fmt.Errorf("jpush: http %d", res.StatusCode)
	}
	return nil
}

func pushExtras(p Payload) map[string]string {
	return map[string]string{
		"conversation_id": p.ConversationID,
		"message_id":      p.MessageID,
		"type":            p.MessageType,
		"sender_id":       p.SenderID,
		"ciphertext":      p.Ciphertext,
		"epoch":           strconv.Itoa(p.Epoch),
		"title_hint":      p.Title,
	}
}

// multiSender 按设备 platform 字段路由：android_cn→极光，android/ios→FCM，否则日志。
type multiSender struct {
	jpush    *jpushSender
	fcm      *fcmSender
	fallback Sender
}

func (m *multiSender) Send(ctx context.Context, token, platform string, p Payload) error {
	switch strings.ToLower(strings.TrimSpace(platform)) {
	case "android_cn", "jpush":
		if m.jpush != nil {
			return m.jpush.Send(ctx, token, platform, p)
		}
	case "android", "ios", "fcm":
		if m.fcm != nil {
			return m.fcm.Send(ctx, token, platform, p)
		}
	}
	if m.fallback != nil {
		return m.fallback.Send(ctx, token, platform, p)
	}
	return nil
}
