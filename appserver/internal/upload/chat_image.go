package upload

import (
	"bytes"
	"fmt"
	"image"
	"image/jpeg"
	"io"
	"os"
	"path/filepath"

	"golang.org/x/image/draw"
)

const (
	MaxChatImageBytes = 10 << 20 // 10 MiB
	chatThumbMaxSide  = 400
	chatOrigMaxSide   = 4096
)

// ChatImageFiles holds public URLs and pixel size of the original.
type ChatImageFiles struct {
	ThumbURL string
	URL      string
	Width    int
	Height   int
}

// SaveChatImage writes a thumbnail (for bubble) and a larger original (for lightbox).
func SaveChatImage(dir, id string, r io.Reader) (*ChatImageFiles, error) {
	limited := io.LimitReader(r, MaxChatImageBytes+1)
	raw, err := io.ReadAll(limited)
	if err != nil {
		return nil, err
	}
	if len(raw) > MaxChatImageBytes {
		return nil, fmt.Errorf("file too large")
	}
	src, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		return nil, fmt.Errorf("invalid image")
	}
	b := src.Bounds()
	ow, oh := b.Dx(), b.Dy()
	if ow < 1 || oh < 1 {
		return nil, fmt.Errorf("invalid image")
	}

	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}

	orig := resizeMax(src, chatOrigMaxSide)
	thumb := resizeMax(src, chatThumbMaxSide)

	origName := id + "_o.jpg"
	thumbName := id + "_t.jpg"
	if err := writeJPEG(filepath.Join(dir, origName), orig, 88); err != nil {
		return nil, err
	}
	if err := writeJPEG(filepath.Join(dir, thumbName), thumb, 72); err != nil {
		_ = os.Remove(filepath.Join(dir, origName))
		return nil, err
	}

	ob := orig.Bounds()
	return &ChatImageFiles{
		ThumbURL: "/uploads/chat/" + thumbName,
		URL:      "/uploads/chat/" + origName,
		Width:    ob.Dx(),
		Height:   ob.Dy(),
	}, nil
}

func writeJPEG(path string, img image.Image, quality int) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return jpeg.Encode(f, img, &jpeg.Options{Quality: quality})
}

func resizeMax(src image.Image, maxSide int) image.Image {
	b := src.Bounds()
	w, h := b.Dx(), b.Dy()
	if w <= maxSide && h <= maxSide {
		return src
	}
	scale := float64(maxSide) / float64(w)
	if h > w {
		scale = float64(maxSide) / float64(h)
	}
	nw := int(float64(w)*scale + 0.5)
	nh := int(float64(h)*scale + 0.5)
	if nw < 1 {
		nw = 1
	}
	if nh < 1 {
		nh = 1
	}
	dst := image.NewRGBA(image.Rect(0, 0, nw, nh))
	draw.CatmullRom.Scale(dst, dst.Bounds(), src, b, draw.Over, nil)
	return dst
}
