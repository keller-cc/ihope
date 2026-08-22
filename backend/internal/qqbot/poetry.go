package qqbot

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"io"
	"net/http"
	"os"
	"strings"
	"unicode/utf8"

	"golang.org/x/image/font"
	"golang.org/x/image/font/opentype"
	"golang.org/x/image/math/fixed"
)

type PoetryQuote struct {
	Hitokoto string `json:"hitokoto"`
	From     string `json:"from"`
	FromWho  string `json:"from_who"`
}

func FetchPoetry(ctx context.Context, apiURL string) (PoetryQuote, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, apiURL, nil)
	if err != nil {
		return PoetryQuote{}, err
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return PoetryQuote{}, err
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return PoetryQuote{}, fmt.Errorf("poetry api: http %d", res.StatusCode)
	}
	var q PoetryQuote
	if err := json.Unmarshal(raw, &q); err != nil {
		return PoetryQuote{}, err
	}
	q.Hitokoto = strings.TrimSpace(q.Hitokoto)
	if q.Hitokoto == "" {
		return PoetryQuote{}, fmt.Errorf("poetry api: empty")
	}
	return q, nil
}

// RenderPoetryCard 将诗词渲染为 PNG 图卡。
func RenderPoetryCard(quote PoetryQuote, fontPath string) ([]byte, error) {
	face, err := loadFace(fontPath, 36)
	if err != nil {
		return nil, err
	}
	small, err := loadFace(fontPath, 22)
	if err != nil {
		return nil, err
	}

	const W, H = 720, 960
	img := image.NewRGBA(image.Rect(0, 0, W, H))
	bg := color.RGBA{R: 245, G: 240, B: 230, A: 255}
	draw.Draw(img, img.Bounds(), &image.Uniform{C: bg}, image.Point{}, draw.Src)

	accent := color.RGBA{R: 60, G: 48, B: 36, A: 255}
	muted := color.RGBA{R: 110, G: 95, B: 80, A: 255}

	lines := wrapRunes(quote.Hitokoto, 12)
	y := 280
	for _, line := range lines {
		drawString(img, face, line, (W-measure(face, line))/2, y, accent)
		y += 56
	}

	from := strings.TrimSpace(quote.From)
	if who := strings.TrimSpace(quote.FromWho); who != "" {
		if from != "" {
			from = from + " · " + who
		} else {
			from = who
		}
	}
	if from != "" {
		label := "—— " + from
		drawString(img, small, label, (W-measure(small, label))/2, H-160, muted)
	}
	footer := "IHope · 每日金句"
	drawString(img, small, footer, (W-measure(small, footer))/2, H-80, muted)

	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func loadFace(path string, size float64) (font.Face, error) {
	path = strings.TrimSpace(path)
	if path == "" {
		return nil, fmt.Errorf("QQ_POETRY_FONT_PATH 未配置：诗词图卡需要中文字体")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read font: %w", err)
	}
	ft, err := opentype.Parse(raw)
	if err != nil {
		return nil, err
	}
	return opentype.NewFace(ft, &opentype.FaceOptions{
		Size:    size,
		DPI:     72,
		Hinting: font.HintingFull,
	})
}

func wrapRunes(s string, maxPerLine int) []string {
	runes := []rune(s)
	if maxPerLine <= 0 {
		return []string{s}
	}
	var lines []string
	for len(runes) > 0 {
		n := maxPerLine
		if n > len(runes) {
			n = len(runes)
		}
		lines = append(lines, string(runes[:n]))
		runes = runes[n:]
	}
	if len(lines) == 0 {
		return []string{s}
	}
	return lines
}

func measure(face font.Face, s string) int {
	d := &font.Drawer{Face: face}
	return d.MeasureString(s).Round()
}

func drawString(img *image.RGBA, face font.Face, s string, x, y int, col color.Color) {
	d := &font.Drawer{
		Dst:  img,
		Src:  image.NewUniform(col),
		Face: face,
		Dot:  fixed.P(x, y),
	}
	d.DrawString(s)
	_ = utf8.RuneCountInString(s)
}
