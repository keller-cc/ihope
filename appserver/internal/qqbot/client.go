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
