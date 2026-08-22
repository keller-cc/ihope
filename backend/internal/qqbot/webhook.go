package qqbot

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
)

// WebhookPayload 官方回调（精简字段）。
type WebhookPayload struct {
	Op int             `json:"op"`
	D  json.RawMessage `json:"d"`
	T  string          `json:"t"`
	ID string          `json:"id"`
}

type validationBody struct {
	PlainToken string
	EventTs    string
}

func (v *validationBody) UnmarshalJSON(data []byte) error {
	var raw struct {
		PlainToken string          `json:"plain_token"`
		EventTs    json.RawMessage `json:"event_ts"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	v.PlainToken = raw.PlainToken
	if len(raw.EventTs) == 0 || string(raw.EventTs) == "null" {
		return fmt.Errorf("missing event_ts")
	}
	eventTs, err := parseQQEventTs(raw.EventTs)
	if err != nil {
		return err
	}
	v.EventTs = eventTs
	return nil
}

// parseQQEventTs 保留 JSON 数字的十进制表示（避免 float 科学计数法影响签名）。
func parseQQEventTs(raw json.RawMessage) (string, error) {
	if len(raw) == 0 || string(raw) == "null" {
		return "", fmt.Errorf("missing event_ts")
	}
	if raw[0] == '"' {
		var s string
		if err := json.Unmarshal(raw, &s); err != nil {
			return "", err
		}
		if s == "" {
			return "", fmt.Errorf("empty event_ts")
		}
		return s, nil
	}
	var n json.Number
	if err := json.Unmarshal(raw, &n); err != nil {
		return "", err
	}
	s := n.String()
	if s == "" {
		return "", fmt.Errorf("empty event_ts")
	}
	return s, nil
}

type c2cMessageBody struct {
	Author struct {
		UserOpenID string `json:"user_openid"`
		ID         string `json:"id"`
	} `json:"author"`
	Content string `json:"content"`
	ID      string `json:"id"`
}

// HandleWebhook POST /api/webhooks/qq
func (s *Service) HandleWebhook(w http.ResponseWriter, r *http.Request) {
	if !s.Enabled() {
		http.Error(w, "qq bot disabled", http.StatusServiceUnavailable)
		return
	}
	raw, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		http.Error(w, "bad body", http.StatusBadRequest)
		return
	}

	var payload WebhookPayload
	if err := json.Unmarshal(raw, &payload); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}

	// op=13：开放平台校验回调地址
	if payload.Op == 13 {
		var v validationBody
		if err := json.Unmarshal(payload.D, &v); err != nil || v.PlainToken == "" || v.EventTs == "" {
			log.Printf("qqbot validation parse: err=%v body=%s", err, string(payload.D))
			http.Error(w, "invalid validation", http.StatusBadRequest)
			return
		}
		sig, err := signValidation(s.cfg.QQBotAppSecret, v.EventTs, v.PlainToken)
		if err != nil {
			log.Printf("qqbot validation sign: %v", err)
			http.Error(w, "sign failed", http.StatusInternalServerError)
			return
		}
		rsp, err := json.Marshal(struct {
			PlainToken string `json:"plain_token"`
			Signature  string `json:"signature"`
		}{PlainToken: v.PlainToken, Signature: sig})
		if err != nil {
			http.Error(w, "encode failed", http.StatusInternalServerError)
			return
		}
		log.Printf(
			"qqbot webhook: validation ok appid=%s ua=%s event_ts=%s plain_token=%s… sig=%s",
			r.Header.Get("X-Bot-Appid"),
			r.Header.Get("User-Agent"),
			v.EventTs,
			truncate(v.PlainToken, 8),
			sig,
		)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(rsp)
		return
	}

	log.Printf("qqbot webhook: event t=%s op=%d", payload.T, payload.Op)
	go s.dispatchEvent(payload)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"code":0}`))
}

func (s *Service) dispatchEvent(payload WebhookPayload) {
	ctx := context.Background()
	switch strings.ToUpper(payload.T) {
	case "C2C_MESSAGE_CREATE":
		var msg c2cMessageBody
		if err := json.Unmarshal(payload.D, &msg); err != nil {
			log.Printf("qqbot c2c parse: %v", err)
			return
		}
		openID := strings.TrimSpace(msg.Author.UserOpenID)
		if openID == "" {
			openID = strings.TrimSpace(msg.Author.ID)
		}
		s.HandleInboundText(ctx, openID, msg.Content, msg.ID)
	default:
		// ignore
	}
}

// signValidation：与官方文档一致 — Secret 填充至 32 字节 seed，GenerateKey 后签 event_ts+plain_token。
func signValidation(secret, eventTs, plainToken string) (string, error) {
	secret = strings.TrimSpace(secret)
	if secret == "" {
		return "", fmt.Errorf("empty bot secret")
	}
	seed := secret
	for len(seed) < ed25519.SeedSize {
		seed = strings.Repeat(seed, 2)
	}
	seed = seed[:ed25519.SeedSize]
	_, privateKey, err := ed25519.GenerateKey(strings.NewReader(seed))
	if err != nil {
		return "", fmt.Errorf("ed25519 generate key: %w", err)
	}
	var msg bytes.Buffer
	msg.WriteString(eventTs)
	msg.WriteString(plainToken)
	return hex.EncodeToString(ed25519.Sign(privateKey, msg.Bytes())), nil
}
