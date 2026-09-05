package upload

import (
	"bytes"
	"fmt"
	"image"
	"image/jpeg"
	_ "image/gif"
	_ "image/png"
	"io"
	"os"
	"path/filepath"
	"strings"

	_ "golang.org/x/image/webp"
)

const MaxAvatarBytes = 10 << 20 // 10 MiB

// SaveSquareJPEGFrom crops and saves; urlPrefix e.g. /uploads/avatars
func SaveSquareJPEGFrom(dir, id, urlPrefix string, r io.Reader) (string, error) {
	limited := io.LimitReader(r, MaxAvatarBytes+1)
	raw, err := io.ReadAll(limited)
	if err != nil {
		return "", err
	}
	if len(raw) > MaxAvatarBytes {
		return "", fmt.Errorf("file too large")
	}
	img, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		return "", fmt.Errorf("invalid image")
	}
	sq := cropSquare(img)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	name := strings.TrimSpace(id) + ".jpg"
	path := filepath.Join(dir, name)
	f, err := os.Create(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	if err := jpeg.Encode(f, sq, &jpeg.Options{Quality: 85}); err != nil {
		return "", err
	}
	prefix := strings.TrimRight(urlPrefix, "/")
	return prefix + "/" + name, nil
}

func cropSquare(src image.Image) image.Image {
	b := src.Bounds()
	w, h := b.Dx(), b.Dy()
	side := w
	if h < side {
		side = h
	}
	x0 := b.Min.X + (w-side)/2
	y0 := b.Min.Y + (h-side)/2
	type subImager interface {
		SubImage(r image.Rectangle) image.Image
	}
	if s, ok := src.(subImager); ok {
		return s.SubImage(image.Rect(x0, y0, x0+side, y0+side))
	}
	dst := image.NewRGBA(image.Rect(0, 0, side, side))
	for y := 0; y < side; y++ {
		for x := 0; x < side; x++ {
			dst.Set(x, y, src.At(x0+x, y0+y))
		}
	}
	return dst
}
