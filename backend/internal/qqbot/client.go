package qqbot

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	tokenURL   = "https://bots.qq.com/app/getAppAccessToken"
	apiBaseURL = "https://api.bot.qq.com"
)

// Client 官方 QQ 机器人 OpenAPI。
type Client struct {
	appID     string
	appSecret string
	http      *http.Client

	mu        sync.Mutex
	token     string
	tokenExp  time.Time
}

func NewClient(appID, appSecret string) *Client {
	return &Client{
		appID:     appID,
		appSecret: appSecret,
		http:      &http.Client{Timeout: 30 * time.Second},
	}
}

func (c *Client) accessToken(ctx context.Context) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.token != "" && time.Now().Before(c.tokenExp.Add(-60*time.Second)) {
		return c.token, nil
	}
	body, _ := json.Marshal(map[string]string{
		"appId":        c.appID,
		"clientSecret": c.appSecret,
	})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, tokenURL, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	res, err := c.http.Do(req)
	if err != nil {
		return "", err
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(res.Body, 4096))
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return "", fmt.Errorf("qq token: http %d: %s", res.StatusCode, string(raw))
	}
	var parsed struct {
		AccessToken string          `json:"access_token"`
		ExpiresIn   json.RawMessage `json:"expires_in"`
	}
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return "", err
	}
	if parsed.AccessToken == "" {
		return "", fmt.Errorf("qq token: empty")
	}
	c.token = parsed.AccessToken
	exp := parseExpiresIn(parsed.ExpiresIn)
	if exp <= 0 {
		exp = 7200
	}
	c.tokenExp = time.Now().Add(time.Duration(exp) * time.Second)
	return c.token, nil
}

// parseExpiresIn 兼容官方返回数字或字符串（如 "7200"）。
func parseExpiresIn(raw json.RawMessage) int {
	if len(raw) == 0 || string(raw) == "null" {
		return 0
	}
	var n int
	if err := json.Unmarshal(raw, &n); err == nil {
		return n
	}
	var s string
	if err := json.Unmarshal(raw, &s); err != nil {
		return 0
	}
	n, err := strconv.Atoi(strings.TrimSpace(s))
	if err != nil {
		return 0
	}
	return n
}

// ProbeCredentials 用 AppID+Secret 向官方换 token，用于确认密钥是否与开放平台一致。
func (c *Client) ProbeCredentials(ctx context.Context) error {
	_, err := c.accessToken(ctx)
	return err
}

func (c *Client) doJSON(ctx context.Context, method, path string, payload any) ([]byte, error) {
	token, err := c.accessToken(ctx)
	if err != nil {
		return nil, err
	}
	var body io.Reader
	if payload != nil {
		raw, err := json.Marshal(payload)
		if err != nil {
			return nil, err
		}
		body = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, apiBaseURL+path, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "QQBot "+token)
	req.Header.Set("Content-Type", "application/json")
	res, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return nil, fmt.Errorf("qq api %s: http %d: %s", path, res.StatusCode, string(raw))
	}
	return raw, nil
}

// SendText 单聊文本；msgID 非空时为被动回复。
func (c *Client) SendText(ctx context.Context, openID, content, msgID string, msgSeq int) error {
	payload := map[string]any{
		"content":  content,
		"msg_type": 0,
	}
	if msgID != "" {
		payload["msg_id"] = msgID
		if msgSeq > 0 {
			payload["msg_seq"] = msgSeq
		}
	}
	_, err := c.doJSON(ctx, http.MethodPost, "/v2/users/"+openID+"/messages", payload)
	return err
}

// SendImagePNG 上传 PNG 并以富媒体发出。优先 base64；失败时用 publicURL。
func (c *Client) SendImagePNG(ctx context.Context, openID string, png []byte, publicURL, msgID string, msgSeq int) error {
	fileInfo, err := c.uploadImage(ctx, openID, png, publicURL)
	if err != nil {
		return err
	}
	payload := map[string]any{
		"msg_type": 7,
		"media": map[string]any{
			"file_info": fileInfo,
		},
	}
	if msgID != "" {
		payload["msg_id"] = msgID
		if msgSeq > 0 {
			payload["msg_seq"] = msgSeq
		}
	}
	_, err = c.doJSON(ctx, http.MethodPost, "/v2/users/"+openID+"/messages", payload)
	return err
}

func (c *Client) uploadImage(ctx context.Context, openID string, png []byte, publicURL string) (string, error) {
	// 先试 base64（部分环境支持）
	if len(png) > 0 {
		payload := map[string]any{
			"file_type":    1,
			"file_data":    base64.StdEncoding.EncodeToString(png),
			"srv_send_msg": false,
		}
		raw, err := c.doJSON(ctx, http.MethodPost, "/v2/users/"+openID+"/files", payload)
		if err == nil {
			var parsed struct {
				FileInfo string `json:"file_info"`
			}
			if json.Unmarshal(raw, &parsed) == nil && parsed.FileInfo != "" {
				return parsed.FileInfo, nil
			}
		}
	}
	if publicURL == "" {
		return "", fmt.Errorf("qq upload: no public url and base64 failed")
	}
	payload := map[string]any{
		"file_type":    1,
		"url":          publicURL,
		"srv_send_msg": false,
	}
	raw, err := c.doJSON(ctx, http.MethodPost, "/v2/users/"+openID+"/files", payload)
	if err != nil {
		return "", err
	}
	var parsed struct {
		FileInfo string `json:"file_info"`
	}
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return "", err
	}
	if parsed.FileInfo == "" {
		return "", fmt.Errorf("qq upload: empty file_info")
	}
	return parsed.FileInfo, nil
}

func (c *Client) UpdateMenu(ctx context.Context, menu Menu) error {
	_, err := c.doJSON(ctx, http.MethodPut, "/v2/menu", map[string]any{"menu": menu})
	return err
}

func (c *Client) ListPanels(ctx context.Context, scope string) ([]PanelRecord, error) {
	path := "/v2/panels?scope=" + scope + "&limit=50"
	raw, err := c.doJSON(ctx, http.MethodGet, path, nil)
	if err != nil {
		return nil, err
	}
	return decodePanelList(raw)
}

func (c *Client) CreatePanel(ctx context.Context, payload createPanelPayload) (string, error) {
	raw, err := c.doJSON(ctx, http.MethodPost, "/v2/panels", payload)
	if err != nil {
		return "", err
	}
	var parsed struct {
		PanelID string `json:"panel_id"`
	}
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return "", err
	}
	if parsed.PanelID == "" {
		return "", fmt.Errorf("qq create panel: empty panel_id")
	}
	return parsed.PanelID, nil
}

func (c *Client) UpdatePanel(ctx context.Context, panelID string, panel Panel) error {
	_, err := c.doJSON(ctx, http.MethodPut, "/v2/panels/"+panelID, map[string]any{"panel": panel})
	return err
}
