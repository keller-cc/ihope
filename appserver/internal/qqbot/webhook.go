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
	if raw.EventTs[0] == '"' {
		var s string
		if err := json.Unmarshal(raw.EventTs, &s); err != nil {
			return err
		}
		v.EventTs = s
		return nil
	}
	var n json.Number
	if err := json.Unmarshal(raw.EventTs, &n); err != nil {
		return err
	}
	v.EventTs = n.String()
	return nil
}

type c2cMessageBody struct {
	Author struct {
		UserOpenID string `json:"user_openid"`
		ID         string `json:"id"`
	} `json:"author"`
	Content string `json:"content"`
	ID      string `json:"id"`
}

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
	if payload.Op == 13 {
		var v validationBody
		if err := json.Unmarshal(payload.D, &v); err != nil || v.PlainToken == "" || v.EventTs == "" {
			http.Error(w, "invalid validation", http.StatusBadRequest)
			return
		}
		sig, err := signValidation(s.cfg.QQBotAppSecret, v.EventTs, v.PlainToken)
		if err != nil {
			http.Error(w, "sign failed", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"plain_token": v.PlainToken,
			"signature":   sig,
		})
		return
	}
	go s.dispatchEvent(payload)
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"code":0}`))
}

func (s *Service) dispatchEvent(payload WebhookPayload) {
	ctx := context.Background()
	if strings.ToUpper(payload.T) != "C2C_MESSAGE_CREATE" {
		return
	}
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
}

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
		return "", err
	}
	var msg bytes.Buffer
	msg.WriteString(eventTs)
	msg.WriteString(plainToken)
	return hex.EncodeToString(ed25519.Sign(privateKey, msg.Bytes())), nil
}
