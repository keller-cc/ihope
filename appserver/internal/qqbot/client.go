package qqbot

import (
	"bytes"
	"context"
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

func (c *Client) SendText(ctx context.Context, openID, content, msgID string, msgSeq int) error {
	token, err := c.accessToken(ctx)
	if err != nil {
		return err
	}
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
	raw, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, apiBaseURL+"/v2/users/"+openID+"/messages", bytes.NewReader(raw))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "QQBot "+token)
	req.Header.Set("Content-Type", "application/json")
	res, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return fmt.Errorf("qq send: http %d: %s", res.StatusCode, string(body))
	}
	return nil
}
