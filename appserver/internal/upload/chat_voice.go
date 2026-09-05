package upload

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

const MaxChatVoiceBytes = 5 << 20 // 5 MiB
const MaxChatVoiceSec = 60

// ChatVoice is a stored voice clip.
type ChatVoice struct {
	URL  string
	Size int64
	Mime string
}

// SaveChatVoice stores a short audio clip (webm/ogg/mp4/mpeg).
func SaveChatVoice(dir, id, mime string, r io.Reader) (*ChatVoice, error) {
	limited := io.LimitReader(r, MaxChatVoiceBytes+1)
	raw, err := io.ReadAll(limited)
	if err != nil {
		return nil, err
	}
	if len(raw) == 0 {
		return nil, fmt.Errorf("empty voice")
	}
	if len(raw) > MaxChatVoiceBytes {
		return nil, fmt.Errorf("voice too large")
	}
	mime = strings.ToLower(strings.TrimSpace(mime))
	ext := ".webm"
	switch {
	case strings.Contains(mime, "ogg"):
		ext = ".ogg"
		mime = "audio/ogg"
	case strings.Contains(mime, "mp4"), strings.Contains(mime, "m4a"), strings.Contains(mime, "aac"):
		ext = ".m4a"
		mime = "audio/mp4"
	case strings.Contains(mime, "mpeg"), strings.Contains(mime, "mp3"):
		ext = ".mp3"
		mime = "audio/mpeg"
	case strings.Contains(mime, "webm"), mime == "":
		ext = ".webm"
		mime = "audio/webm"
	default:
		return nil, fmt.Errorf("unsupported audio type")
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	stored := id + ext
	path := filepath.Join(dir, stored)
	if err := os.WriteFile(path, raw, 0o644); err != nil {
		return nil, err
	}
	return &ChatVoice{
		URL:  "/uploads/chat/" + stored,
		Size: int64(len(raw)),
		Mime: mime,
	}, nil
}
