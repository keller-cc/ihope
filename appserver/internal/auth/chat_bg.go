package auth

import (
	"encoding/json"
	"errors"
	"strings"
)

// ChatBg is the account-wide chat wallpaper preference.
type ChatBg struct {
	Kind string `json:"kind"`          // default | gradient | image
	ID   string `json:"id,omitempty"`  // gradient preset id
	URL  string `json:"url,omitempty"` // image url
}

func ParseChatBg(raw string) *ChatBg {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	var bg ChatBg
	if err := json.Unmarshal([]byte(raw), &bg); err != nil {
		return nil
	}
	bg.Kind = strings.TrimSpace(bg.Kind)
	if bg.Kind == "" || bg.Kind == "default" {
		return nil
	}
	if bg.Kind != "gradient" && bg.Kind != "image" {
		return nil
	}
	return &bg
}

func EncodeChatBg(bg *ChatBg) (string, error) {
	if bg == nil || strings.TrimSpace(bg.Kind) == "" || bg.Kind == "default" {
		return "", nil
	}
	kind := strings.TrimSpace(bg.Kind)
	switch kind {
	case "gradient":
		id := strings.TrimSpace(bg.ID)
		if id == "" {
			return "", errors.New("gradient id required")
		}
		b, err := json.Marshal(ChatBg{Kind: "gradient", ID: id})
		return string(b), err
	case "image":
		url := strings.TrimSpace(bg.URL)
		if url == "" || !strings.HasPrefix(url, "/uploads/") {
			return "", errors.New("invalid image url")
		}
		b, err := json.Marshal(ChatBg{Kind: "image", URL: url})
		return string(b), err
	default:
		return "", errors.New("invalid chat bg")
	}
}
