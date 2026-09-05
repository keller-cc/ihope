package auth

import (
	"encoding/json"
	"errors"
	"regexp"
	"strings"
)

// ChatBg is the account-wide chat wallpaper preference.
type ChatBg struct {
	Kind string `json:"kind"`          // default | gradient | color | image
	ID   string `json:"id,omitempty"`  // gradient / chinese-color preset id
	Hex  string `json:"hex,omitempty"` // #RRGGBB for kind=color
	URL  string `json:"url,omitempty"` // image url
}

var hexColorRe = regexp.MustCompile(`(?i)^#[0-9a-f]{6}$`)

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
	switch bg.Kind {
	case "gradient", "image", "color":
		return &bg
	default:
		return nil
	}
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
	case "color":
		hex := strings.ToUpper(strings.TrimSpace(bg.Hex))
		if !hexColorRe.MatchString(hex) {
			return "", errors.New("invalid color")
		}
		id := strings.TrimSpace(bg.ID)
		out := ChatBg{Kind: "color", Hex: hex}
		if id != "" {
			out.ID = id
		}
		b, err := json.Marshal(out)
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
