package auth

import (
	"encoding/json"
	"errors"
	"math"
	"regexp"
	"strings"
)

// ChatBg is the chat wallpaper (background layer of 随心调).
type ChatBg struct {
	Kind string `json:"kind"`          // default | gradient | color | image
	ID   string `json:"id,omitempty"`  // gradient / chinese-color preset id
	Hex  string `json:"hex,omitempty"` // #RRGGBB for kind=color
	URL  string `json:"url,omitempty"` // image url
}

// ChatTheme is QQ-style 随心调：主题色 / 气泡 / 背景 / 纹理 / 透明度 / 毛玻璃.
type ChatTheme struct {
	Accent     string   `json:"accent,omitempty"`
	BubbleMine string   `json:"bubbleMine,omitempty"`
	BubblePeer string   `json:"bubblePeer,omitempty"`
	Background *ChatBg  `json:"background,omitempty"`
	Texture    string   `json:"texture,omitempty"` // none | dots | grid | paper | diagonal
	Opacity    *float64 `json:"opacity,omitempty"` // 0–1.0 面板透明度（不含气泡）
	Blur       *float64 `json:"blur,omitempty"`    // 0–1.0 毛玻璃模糊强度
}

var hexColorRe = regexp.MustCompile(`(?i)^#[0-9a-f]{6}$`)

func normalizeHex(hex string) (string, error) {
	hex = strings.ToUpper(strings.TrimSpace(hex))
	if !hexColorRe.MatchString(hex) {
		return "", errors.New("invalid color")
	}
	return hex, nil
}

func normalizeOpacity(v float64) float64 {
	if v < 0 {
		return 0
	}
	if v > 1 {
		return 1
	}
	return math.Round(v*100) / 100
}

func normalizeBlur(v float64) float64 {
	return normalizeOpacity(v)
}

func normalizeTexture(t string) string {
	switch strings.ToLower(strings.TrimSpace(t)) {
	case "", "none":
		return ""
	case "dots", "grid", "paper", "diagonal":
		return strings.ToLower(strings.TrimSpace(t))
	default:
		return ""
	}
}

func normalizeBackground(bg *ChatBg) (*ChatBg, error) {
	if bg == nil {
		return nil, nil
	}
	kind := strings.TrimSpace(bg.Kind)
	if kind == "" || kind == "default" {
		return nil, nil
	}
	switch kind {
	case "gradient":
		id := strings.TrimSpace(bg.ID)
		if id == "" {
			return nil, errors.New("gradient id required")
		}
		return &ChatBg{Kind: "gradient", ID: id}, nil
	case "color":
		hex, err := normalizeHex(bg.Hex)
		if err != nil {
			return nil, err
		}
		out := &ChatBg{Kind: "color", Hex: hex}
		if id := strings.TrimSpace(bg.ID); id != "" {
			out.ID = id
		}
		return out, nil
	case "image":
		url := strings.TrimSpace(bg.URL)
		if url == "" || !strings.HasPrefix(url, "/uploads/") {
			return nil, errors.New("invalid image url")
		}
		return &ChatBg{Kind: "image", URL: url}, nil
	default:
		return nil, errors.New("invalid chat bg")
	}
}

func themeIsEmpty(t *ChatTheme) bool {
	if t == nil {
		return true
	}
	return strings.TrimSpace(t.Accent) == "" &&
		strings.TrimSpace(t.BubbleMine) == "" &&
		strings.TrimSpace(t.BubblePeer) == "" &&
		t.Background == nil &&
		normalizeTexture(t.Texture) == "" &&
		t.Opacity == nil &&
		t.Blur == nil
}

// ParseChatTheme reads users.chat_bg JSON.
// Supports legacy wallpaper-only payloads: {"kind":"gradient","id":"sky"}.
func ParseChatTheme(raw string) *ChatTheme {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	var probe map[string]json.RawMessage
	if err := json.Unmarshal([]byte(raw), &probe); err != nil {
		return nil
	}
	// Legacy: top-level "kind" wallpaper.
	if _, ok := probe["kind"]; ok {
		if _, hasBg := probe["background"]; !hasBg {
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
				return &ChatTheme{Background: &bg}
			default:
				return nil
			}
		}
	}
	var theme ChatTheme
	if err := json.Unmarshal([]byte(raw), &theme); err != nil {
		return nil
	}
	if bg, err := normalizeBackground(theme.Background); err == nil {
		theme.Background = bg
	} else {
		theme.Background = nil
	}
	if hex, err := normalizeHex(theme.Accent); err == nil {
		theme.Accent = hex
	} else {
		theme.Accent = ""
	}
	if hex, err := normalizeHex(theme.BubbleMine); err == nil {
		theme.BubbleMine = hex
	} else {
		theme.BubbleMine = ""
	}
	if hex, err := normalizeHex(theme.BubblePeer); err == nil {
		theme.BubblePeer = hex
	} else {
		theme.BubblePeer = ""
	}
	theme.Texture = normalizeTexture(theme.Texture)
	if theme.Opacity != nil {
		o := normalizeOpacity(*theme.Opacity)
		theme.Opacity = &o
	}
	if theme.Blur != nil {
		b := normalizeBlur(*theme.Blur)
		theme.Blur = &b
	}
	if themeIsEmpty(&theme) {
		return nil
	}
	return &theme
}

// EncodeChatTheme serializes a full theme for storage.
func EncodeChatTheme(theme *ChatTheme) (string, error) {
	if themeIsEmpty(theme) {
		return "", nil
	}
	out := ChatTheme{}
	if theme != nil {
		if hex, err := normalizeHex(theme.Accent); err == nil {
			out.Accent = hex
		} else if strings.TrimSpace(theme.Accent) != "" {
			return "", err
		}
		if hex, err := normalizeHex(theme.BubbleMine); err == nil {
			out.BubbleMine = hex
		} else if strings.TrimSpace(theme.BubbleMine) != "" {
			return "", err
		}
		if hex, err := normalizeHex(theme.BubblePeer); err == nil {
			out.BubblePeer = hex
		} else if strings.TrimSpace(theme.BubblePeer) != "" {
			return "", err
		}
		bg, err := normalizeBackground(theme.Background)
		if err != nil {
			return "", err
		}
		out.Background = bg
		out.Texture = normalizeTexture(theme.Texture)
		if theme.Opacity != nil {
			o := normalizeOpacity(*theme.Opacity)
			out.Opacity = &o
		}
		if theme.Blur != nil {
			b := normalizeBlur(*theme.Blur)
			out.Blur = &b
		}
	}
	if themeIsEmpty(&out) {
		return "", nil
	}
	b, err := json.Marshal(out)
	return string(b), err
}

// MergeChatTheme overlays patch onto base (nil / empty keep base; "default" clears).
func MergeChatTheme(base, patch *ChatTheme) *ChatTheme {
	out := ChatTheme{}
	if base != nil {
		out = *base
		if base.Background != nil {
			cp := *base.Background
			out.Background = &cp
		}
		if base.Opacity != nil {
			o := *base.Opacity
			out.Opacity = &o
		}
		if base.Blur != nil {
			b := *base.Blur
			out.Blur = &b
		}
	}
	if patch == nil {
		if themeIsEmpty(&out) {
			return nil
		}
		return &out
	}
	if patch.Accent != "" {
		if patch.Accent == "default" {
			out.Accent = ""
		} else {
			out.Accent = patch.Accent
		}
	}
	if patch.BubbleMine != "" {
		if patch.BubbleMine == "default" {
			out.BubbleMine = ""
		} else {
			out.BubbleMine = patch.BubbleMine
		}
	}
	if patch.BubblePeer != "" {
		if patch.BubblePeer == "default" {
			out.BubblePeer = ""
		} else {
			out.BubblePeer = patch.BubblePeer
		}
	}
	if patch.Background != nil {
		if patch.Background.Kind == "default" {
			out.Background = nil
		} else {
			cp := *patch.Background
			out.Background = &cp
		}
	}
	if patch.Texture != "" {
		if patch.Texture == "none" || patch.Texture == "default" {
			out.Texture = ""
		} else {
			out.Texture = patch.Texture
		}
	}
	if patch.Opacity != nil {
		o := *patch.Opacity
		if o < 0 {
			out.Opacity = nil
		} else {
			out.Opacity = &o
		}
	}
	if patch.Blur != nil {
		b := *patch.Blur
		if b < 0 {
			out.Blur = nil
		} else {
			out.Blur = &b
		}
	}
	if themeIsEmpty(&out) {
		return nil
	}
	return &out
}
