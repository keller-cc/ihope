package push

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// fcmSender 使用 FCM Legacy HTTP API（单 server key，适合小团队自建）。
type fcmSender struct {
	serverKey string
	client    *http.Client
}

func (f *fcmSender) Send(ctx context.Context, token, platform string, p Payload) error {
	if f.client == nil {
		f.client = &http.Client{Timeout: 10 * time.Second}
	}

	// 仅 data 通道传密文；系统横幅由客户端解密后本地通知展示。
	data := pushExtras(p)
	body := map[string]any{
		"to":       token,
		"priority": "high",
		"data":     data,
	}
	if platform == "android" || platform == "fcm" {
		body["android"] = map[string]any{"priority": "high"}
	}

	raw, err := json.Marshal(body)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		"https://fcm.googleapis.com/fcm/send",
		bytes.NewReader(raw),
	)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "key="+f.serverKey)
	req.Header.Set("Content-Type", "application/json")

	res, err := f.client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()

	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return fmt.Errorf("fcm: http %d", res.StatusCode)
	}
	return nil
}
