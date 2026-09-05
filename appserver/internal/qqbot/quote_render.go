package qqbot

import (
	"fmt"
	"strings"

	"github.com/keller-cc/ihope/appserver/internal/quotes"
)

// RenderQuoteCard 渲染金句横排 PNG（与诗词共用文学风底图）。
func RenderQuoteCard(entry quotes.QuoteEntry, fontPath string) ([]byte, error) {
	body := strings.TrimSpace(entry.Body)
	if body == "" {
		return nil, fmt.Errorf("金句内容为空")
	}
	sub := ""
	if a := strings.TrimSpace(entry.Author); a != "" {
		sub = "—— 来自@" + a
	}
	return renderLiteraryCard(body, sub, fontPath)
}
