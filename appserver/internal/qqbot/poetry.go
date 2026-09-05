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
	"unicode"
	"unicode/utf8"

	"golang.org/x/image/font"
	"golang.org/x/image/font/opentype"
	"golang.org/x/image/font/sfnt"
	"golang.org/x/image/math/fixed"
)

var (
	cardBg    = color.RGBA{R: 245, G: 240, B: 230, A: 255}
	cardText  = color.RGBA{R: 60, G: 48, B: 36, A: 255}
	cardMuted = color.RGBA{R: 110, G: 95, B: 80, A: 255}
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

func RenderPoetryCard(quote PoetryQuote, fontPath string) ([]byte, error) {
	sub := poetrySourceLine(quote)
	return renderVerticalPoetryCard(quote.Hitokoto, sub, fontPath)
}

func poetrySourceLine(q PoetryQuote) string {
	from := strings.TrimSpace(q.From)
	if who := strings.TrimSpace(q.FromWho); who != "" {
		if from != "" {
			from = from + " · " + who
		} else {
			from = who
		}
	}
	if from == "" {
		return ""
	}
	return "—— " + from
}

func renderLiteraryCard(mainText, subLine, fontPath string) ([]byte, error) {
	mainText = strings.TrimSpace(mainText)
	if mainText == "" {
		return nil, fmt.Errorf("正文为空")
	}
	face, err := loadFace(fontPath, 28)
	if err != nil {
		return nil, err
	}
	small, err := loadFace(fontPath, 20)
	if err != nil {
		return nil, err
	}

	const W = 720
	const padX = 48
	lines := layoutLiteraryLines(mainText, 18)
	const maxBodyLines = 18
	if len(lines) > maxBodyLines {
		lines = lines[:maxBodyLines]
		last := lines[maxBodyLines-1]
		if len(last) > 3 {
			lines[maxBodyLines-1] = last[:len(last)-1] + "…"
		}
	}

	lineHeight := 40
	subPad := 0
	if strings.TrimSpace(subLine) != "" {
		subPad = 64
	}
	H := 120 + len(lines)*lineHeight + subPad + 80
	if H < 480 {
		H = 480
	}
	if H > 1440 {
		H = 1440
	}

	img := image.NewRGBA(image.Rect(0, 0, W, H))
	draw.Draw(img, img.Bounds(), &image.Uniform{C: cardBg}, image.Point{}, draw.Src)

	y := 96
	for _, line := range lines {
		if line == "" {
			y += lineHeight / 2
			continue
		}
		drawString(img, face, line, padX, y, cardText)
		y += lineHeight
	}
	if sub := strings.TrimSpace(subLine); sub != "" {
		drawString(img, small, sub, padX, H-48, cardMuted)
	}

	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func renderVerticalPoetryCard(mainText, subLine, fontPath string) ([]byte, error) {
	mainText = strings.TrimSpace(mainText)
	if mainText == "" {
		return nil, fmt.Errorf("正文为空")
	}
	face, err := loadFace(fontPath, 38)
	if err != nil {
		return nil, err
	}
	small, err := loadFace(fontPath, 22)
	if err != nil {
		return nil, err
	}

	cols := poetryColumnsFromText(mainText)
	if len(cols) == 0 {
		return nil, fmt.Errorf("正文为空")
	}
	const maxCols = 12
	if len(cols) > maxCols {
		cols = cols[:maxCols]
		last := cols[maxCols-1]
		if utf8.RuneCountInString(last) > 4 {
			runes := []rune(last)
			cols[maxCols-1] = string(runes[:len(runes)-1]) + "…"
		}
	}

	const charW = 44
	const charH = 46
	const colGap = 18
	const pad = 56

	maxRunes := 0
	for _, col := range cols {
		n := utf8.RuneCountInString(col)
		if n > maxRunes {
			maxRunes = n
		}
	}

	subPad := 0
	if strings.TrimSpace(subLine) != "" {
		subPad = 48
	}
	W := pad*2 + len(cols)*charW + (len(cols)-1)*colGap
	H := pad*2 + maxRunes*charH + subPad + 32
	if W < 520 {
		W = 520
	}
	if H < 640 {
		H = 640
	}
	if W > 1080 {
		W = 1080
	}
	if H > 1600 {
		H = 1600
	}

	img := image.NewRGBA(image.Rect(0, 0, W, H))
	draw.Draw(img, img.Bounds(), &image.Uniform{C: cardBg}, image.Point{}, draw.Src)

	for i, colText := range cols {
		x := W - pad - charW - i*(charW+colGap)
		y := pad
		for _, r := range colText {
			if unicode.IsSpace(r) {
				continue
			}
			drawString(img, face, string(r), x, y, cardText)
			y += charH
		}
	}
	if sub := strings.TrimSpace(subLine); sub != "" {
		drawString(img, small, sub, pad, H-pad-8, cardMuted)
	}

	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func poetryColumnsFromText(text string) []string {
	text = strings.TrimSpace(text)
	if text == "" {
		return nil
	}
	if strings.Contains(text, "\n") {
		var cols []string
		for _, line := range strings.Split(text, "\n") {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			for _, seg := range splitPoetrySegments(line) {
				if seg != "" {
					cols = append(cols, seg)
				}
			}
		}
		if len(cols) > 0 {
			return cols
		}
	}
	return splitPoetrySegments(text)
}

func splitPoetrySegments(line string) []string {
	line = strings.TrimSpace(line)
	if line == "" {
		return nil
	}
	var segs []string
	var current strings.Builder
	for _, r := range line {
		current.WriteRune(r)
		if isPoetryBreakRune(r) {
			segs = append(segs, strings.TrimSpace(current.String()))
			current.Reset()
		}
	}
	if tail := strings.TrimSpace(current.String()); tail != "" {
		segs = append(segs, tail)
	}
	if len(segs) == 0 {
		return []string{line}
	}
	return segs
}

func isPoetryBreakRune(r rune) bool {
	switch r {
	case '，', '。', '；', '！', '？', '、', '：', '…':
		return true
	default:
		return false
	}
}

func layoutLiteraryLines(text string, maxPerLine int) []string {
	parts := strings.Split(text, "\n")
	var out []string
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part == "" {
			if len(out) > 0 {
				out = append(out, "")
			}
			continue
		}
		out = append(out, wrapRunes(part, maxPerLine)...)
	}
	if len(out) == 0 {
		return []string{text}
	}
	return out
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
	face, err := faceFromFontBytes(raw, size)
	if err != nil {
		return nil, fmt.Errorf("parse font %s: %w", path, err)
	}
	return face, nil
}

func faceFromFontBytes(raw []byte, size float64) (font.Face, error) {
	opts := &opentype.FaceOptions{
		Size:    size,
		DPI:     72,
		Hinting: font.HintingFull,
	}
	if coll, err := sfnt.ParseCollection(raw); err == nil && coll.NumFonts() > 0 {
		f, err := coll.Font(0)
		if err != nil {
			return nil, err
		}
		return opentype.NewFace(f, opts)
	}
	ft, err := opentype.Parse(raw)
	if err != nil {
		return nil, err
	}
	return opentype.NewFace(ft, opts)
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

func drawString(img *image.RGBA, face font.Face, s string, x, y int, col color.Color) {
	d := &font.Drawer{
		Dst:  img,
		Src:  image.NewUniform(col),
		Face: face,
		Dot:  fixed.P(x, y),
	}
	d.DrawString(s)
}
