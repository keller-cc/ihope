package upload

import (
	"bytes"
	"fmt"
	"image"
	"io"
	"os"
	"path/filepath"
	"strings"

	_ "image/gif"
	_ "image/png"

	_ "golang.org/x/image/webp"
)

const (
	MaxWallpaperBytes = 10 << 20 // 10 MiB
	wallpaperMaxSide  = 2560
)

// SaveWallpaperJPEG stores a chat background image (kept aspect ratio, downscaled).
func SaveWallpaperJPEG(dir, id, urlPrefix string, r io.Reader) (string, error) {
	limited := io.LimitReader(r, MaxWallpaperBytes+1)
	raw, err := io.ReadAll(limited)
	if err != nil {
		return "", err
	}
	if len(raw) > MaxWallpaperBytes {
		return "", fmt.Errorf("file too large")
	}
	src, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		return "", fmt.Errorf("invalid image")
	}
	out := resizeMax(src, wallpaperMaxSide)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	name := strings.TrimSpace(id) + ".jpg"
	path := filepath.Join(dir, name)
	if err := writeJPEG(path, out, 85); err != nil {
		return "", err
	}
	prefix := strings.TrimRight(urlPrefix, "/")
	return prefix + "/" + name, nil
}
