package quotes

import (
	"fmt"
	"os"
	"regexp"
	"strings"
	"time"
)

// QuoteEntry 金句正文与可选署名。
type QuoteEntry struct {
	Body   string
	Author string
}

var attributionLineRe = regexp.MustCompile(`^\s*(?:来自|来.{0,3})@(.+?)\s*$`)

// ReadQuoteEntries 读取金句文件（--- 分隔块，或旧版「来自@」结尾格式）。
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
	body := collapseBodySoftBreaks(strings.Join(bodyLines, "\n"))
	if body == "" {
		return QuoteEntry{}, false
	}
	return QuoteEntry{Body: body, Author: author}, true
}

func collapseBodySoftBreaks(body string) string {
	body = strings.TrimSpace(body)
	if body == "" {
		return ""
	}
	var paragraphs []string
	var current strings.Builder
	flush := func() {
		if current.Len() == 0 {
			return
		}
		paragraphs = append(paragraphs, strings.TrimSpace(current.String()))
		current.Reset()
	}
	for _, line := range strings.Split(body, "\n") {
		t := strings.TrimSpace(line)
		if t == "" {
			flush()
			continue
		}
		current.WriteString(t)
	}
	flush()
	return strings.Join(paragraphs, "\n\n")
}

func parseLegacyAttributionQuotes(text string) ([]QuoteEntry, error) {
	lines := strings.Split(text, "\n")
	var out []QuoteEntry
	var bodyLines []string
	var author string

	flush := func() {
		body := collapseBodySoftBreaks(strings.Join(bodyLines, "\n"))
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

func quoteDayNumber(day time.Time) int {
	y, m, d := day.Date()
	loc := day.Location()
	midnight := time.Date(y, m, d, 0, 0, 0, 0, loc)
	return int(midnight.Unix() / 86400)
}

// PickDailyQuoteEntry 按日历日顺序轮换，同一天各处展示同一条。
func PickDailyQuoteEntry(path string, day time.Time) (QuoteEntry, error) {
	entries, err := ReadQuoteEntries(path)
	if err != nil {
		return QuoteEntry{}, err
	}
	idx := quoteDayNumber(day) % len(entries)
	return entries[idx], nil
}
