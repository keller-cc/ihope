package qqbot

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strings"
	"time"
)

// QuoteEntry 一条金句：正文可多行；Author 来自「来自@昵称」行。
type QuoteEntry struct {
	Body   string
	Author string
}

var attributionLineRe = regexp.MustCompile(`^\s*(?:来自|来.{0,3})@(.+?)\s*$`)

// ReadQuoteEntries 读取金句文件。
//
// 支持两种格式（自动识别）：
//  1. 新格式：条目之间单独一行 --- 分隔；正文可多行；可选末尾「来自@昵称」
//  2. 旧格式：连续正文 + 「来自@昵称」作为条目结尾（兼容历史文件）
func ReadQuoteEntries(path string) ([]QuoteEntry, error) {
	path = strings.TrimSpace(path)
	if path == "" {
		return nil, fmt.Errorf("QQ_QUOTES_FILE_PATH 未配置")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	text := strings.ReplaceAll(string(raw), "\r\n", "\n")
	if strings.Contains(text, "\n---\n") || strings.HasPrefix(strings.TrimSpace(text), "---\n") {
		return parseQuoteBlocks(splitQuoteBlocks(text))
	}
	return parseLegacyAttributionQuotes(text)
}

func splitQuoteBlocks(text string) []string {
	text = strings.TrimSpace(text)
	if strings.HasPrefix(text, "---") {
		text = strings.TrimPrefix(text, "---")
		text = strings.TrimLeft(text, "\n")
	}
	parts := strings.Split(text, "\n---\n")
	var blocks []string
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" || isCommentOnlyBlock(p) {
			continue
		}
		blocks = append(blocks, p)
	}
	return blocks
}

func isCommentOnlyBlock(s string) bool {
	for _, line := range strings.Split(s, "\n") {
		t := strings.TrimSpace(line)
		if t != "" && !strings.HasPrefix(t, "#") {
			return false
		}
	}
	return true
}

func parseQuoteBlocks(blocks []string) ([]QuoteEntry, error) {
	var out []QuoteEntry
	for _, block := range blocks {
		e, ok := entryFromBlock(block)
		if ok {
			out = append(out, e)
		}
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("金句文件无有效条目")
	}
	return out, nil
}

func entryFromBlock(block string) (QuoteEntry, bool) {
	lines := strings.Split(block, "\n")
	var bodyLines []string
	var author string
	for _, line := range lines {
		if m := attributionLineRe.FindStringSubmatch(line); m != nil {
			author = strings.TrimSpace(m[1])
			continue
		}
		if strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		bodyLines = append(bodyLines, line)
	}
	body := strings.TrimSpace(strings.Join(bodyLines, "\n"))
	if body == "" {
		return QuoteEntry{}, false
	}
	return QuoteEntry{Body: body, Author: author}, true
}

func parseLegacyAttributionQuotes(text string) ([]QuoteEntry, error) {
	lines := strings.Split(text, "\n")
	var out []QuoteEntry
	var bodyLines []string
	var author string

	flush := func() {
		body := strings.TrimSpace(strings.Join(bodyLines, "\n"))
		if body == "" {
			bodyLines = nil
			author = ""
			return
		}
		out = append(out, QuoteEntry{Body: body, Author: author})
		bodyLines = nil
		author = ""
	}

	for _, line := range lines {
		if m := attributionLineRe.FindStringSubmatch(line); m != nil {
			author = strings.TrimSpace(m[1])
			flush()
			continue
		}
		if strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		bodyLines = append(bodyLines, line)
	}
	flush()

	if len(out) == 0 {
		return nil, fmt.Errorf("金句文件无有效条目")
	}
	return out, nil
}

// quoteDayNumber 日历日在当前时区下的序号（用于按日轮换，避免随机重复）。
func quoteDayNumber(day time.Time) int {
	y, m, d := day.Date()
	loc := day.Location()
	midnight := time.Date(y, m, d, 0, 0, 0, 0, loc)
	return int(midnight.Unix() / 86400)
}

// PickDailyQuoteEntry 按日历日轮换选取：文件顺序逐条推进，走完一轮后才重复。
// 同一天内（QQ 手动「金句」、每日推送、App 今日金句）均为同一条。
func PickDailyQuoteEntry(path string, day time.Time) (QuoteEntry, error) {
	entries, err := ReadQuoteEntries(path)
	if err != nil {
		return QuoteEntry{}, err
	}
	idx := quoteDayNumber(day) % len(entries)
	return entries[idx], nil
}

// PickRandomQuoteEntry 返回当日金句（与 PickDailyQuoteEntry 相同，已取消随机）。
func PickRandomQuoteEntry(path string) (QuoteEntry, error) {
	return PickDailyQuoteEntry(path, time.Now())
}

// FormatQuoteBlocks 将条目格式化为 --- 分隔的标准文件内容。
func FormatQuoteBlocks(entries []QuoteEntry) string {
	var b strings.Builder
	b.WriteString("# IHope 金句库\n")
	b.WriteString("# 条目之间用单独一行 --- 分隔；正文保留换行；可选末尾「来自@昵称」\n\n")
	for i, e := range entries {
		if i > 0 {
			b.WriteString("\n---\n\n")
		}
		b.WriteString(strings.TrimSpace(e.Body))
		if a := strings.TrimSpace(e.Author); a != "" {
			b.WriteString("\n\n来自@" + a)
		}
	}
	b.WriteByte('\n')
	return b.String()
}

// ReformatQuotesFile 将文件转为 --- 分隔格式（原地覆盖）。
func ReformatQuotesFile(path string) (int, error) {
	entries, err := ReadQuoteEntries(path)
	if err != nil {
		return 0, err
	}
	formatted := FormatQuoteBlocks(entries)
	if err := os.WriteFile(path, []byte(formatted), 0o644); err != nil {
		return 0, err
	}
	return len(entries), nil
}

// RenderQuoteCard 将金句渲染为 PNG 图卡。
func RenderQuoteCard(entry QuoteEntry, fontPath string) ([]byte, error) {
	body := strings.TrimSpace(entry.Body)
	if body == "" {
		return nil, fmt.Errorf("金句内容为空")
	}
	sub := ""
	if a := strings.TrimSpace(entry.Author); a != "" {
		sub = "—— 来自@" + a
	}
	return renderLiteraryCard(body, sub, "IHope · 金句", fontPath)
}

// PickRandomQuote 兼容旧调用：仅返回正文。
func PickRandomQuote(path string) (string, error) {
	e, err := PickRandomQuoteEntry(path)
	if err != nil {
		return "", err
	}
	return e.Body, nil
}

// ReadQuoteLines 已废弃：返回各条正文（不含署名）。
func ReadQuoteLines(path string) ([]string, error) {
	entries, err := ReadQuoteEntries(path)
	if err != nil {
		return nil, err
	}
	lines := make([]string, len(entries))
	for i, e := range entries {
		lines[i] = e.Body
	}
	return lines, nil
}

// CountQuoteEntries 统计有效条目数。
func CountQuoteEntries(path string) (int, error) {
	entries, err := ReadQuoteEntries(path)
	if err != nil {
		return 0, err
	}
	return len(entries), nil
}

// PreviewQuoteFile 读取文件前几行用于日志。
func PreviewQuoteFile(path string) string {
	path = strings.TrimSpace(path)
	if path == "" {
		return ""
	}
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	const max = 3
	var lines []string
	for sc.Scan() && len(lines) < max {
		lines = append(lines, sc.Text())
	}
	return strings.Join(lines, "\n")
}
