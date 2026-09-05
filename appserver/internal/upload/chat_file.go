package upload

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"unicode/utf8"
)

const MaxChatFileBytes = 20 << 20 // 20 MiB

var unsafeName = regexp.MustCompile(`[^\p{L}\p{N}\-_. ()\[\]]+`)

// ChatFile holds a stored attachment.
type ChatFile struct {
	URL  string
	Name string
	Size int64
	Mime string
}

// SaveChatFile stores the raw bytes under a unique id, preserving a safe display name.
func SaveChatFile(dir, id, originalName, mime string, r io.Reader) (*ChatFile, error) {
	limited := io.LimitReader(r, MaxChatFileBytes+1)
	raw, err := io.ReadAll(limited)
	if err != nil {
		return nil, err
	}
	if len(raw) > MaxChatFileBytes {
		return nil, fmt.Errorf("file too large")
	}
	name := sanitizeFileName(originalName)
	ext := filepath.Ext(name)
	if utf8.RuneCountInString(ext) > 16 {
		ext = ""
	}
	stored := id + ext
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	path := filepath.Join(dir, stored)
	if err := os.WriteFile(path, raw, 0o644); err != nil {
		return nil, err
	}
	mime = strings.TrimSpace(mime)
	if mime == "" {
		mime = "application/octet-stream"
	}
	return &ChatFile{
		URL:  "/uploads/chat/" + stored,
		Name: name,
		Size: int64(len(raw)),
		Mime: mime,
	}, nil
}

func sanitizeFileName(name string) string {
	name = filepath.Base(strings.TrimSpace(name))
	name = strings.ReplaceAll(name, "..", ".")
	name = unsafeName.ReplaceAllString(name, "_")
	if name == "" || name == "." {
		name = "file"
	}
	runes := []rune(name)
	if len(runes) > 80 {
		name = string(runes[:80])
	}
	return name
}
