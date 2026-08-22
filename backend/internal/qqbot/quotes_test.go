package qqbot

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestReadQuoteEntriesLegacy(t *testing.T) {
	dir := t.TempDir()
	path := dir + "/quotes.txt"
	content := "第一段\n第二段\n\n来自@燕子\n\n另一条金句\n来自@测试"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	entries, err := ReadQuoteEntries(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 2 {
		t.Fatalf("entries=%d", len(entries))
	}
	if entries[0].Body != "第一段\n第二段" || entries[0].Author != "燕子" {
		t.Fatalf("first=%+v", entries[0])
	}
	if entries[1].Body != "另一条金句" || entries[1].Author != "测试" {
		t.Fatalf("second=%+v", entries[1])
	}
}

func TestReadQuoteEntriesBlocks(t *testing.T) {
	dir := t.TempDir()
	path := dir + "/quotes.txt"
	content := "# header\n\n---\n\n行一\n行二\n\n来自@作者A\n\n---\n\n只有正文"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	entries, err := ReadQuoteEntries(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 2 {
		t.Fatalf("entries=%d", len(entries))
	}
	if entries[0].Body != "行一\n行二" || entries[0].Author != "作者A" {
		t.Fatalf("first=%+v", entries[0])
	}
	if entries[1].Body != "只有正文" || entries[1].Author != "" {
		t.Fatalf("second=%+v", entries[1])
	}
}

func TestPickDailyQuoteStable(t *testing.T) {
	dir := t.TempDir()
	path := dir + "/quotes.txt"
	if err := os.WriteFile(path, []byte("a\n来自@1\n\nb\n来自@2"), 0o644); err != nil {
		t.Fatal(err)
	}
	day, err := time.Parse("2006-01-02", "2026-08-22")
	if err != nil {
		t.Fatal(err)
	}
	a, err := PickDailyQuoteEntry(path, day)
	if err != nil {
		t.Fatal(err)
	}
	b, err := PickDailyQuoteEntry(path, day)
	if err != nil {
		t.Fatal(err)
	}
	if a != b {
		t.Fatalf("not stable: %+v vs %+v", a, b)
	}
}

func TestPickDailyQuoteSequentialNoRepeat(t *testing.T) {
	dir := t.TempDir()
	path := dir + "/quotes.txt"
	content := "第一条\n来自@1\n\n第二条\n来自@2\n\n第三条\n来自@3"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	day, err := time.ParseInLocation("2006-01-02", "2026-08-20", time.Local)
	if err != nil {
		t.Fatal(err)
	}
	seen := make(map[string]bool)
	for i := 0; i < 3; i++ {
		e, err := PickDailyQuoteEntry(path, day.AddDate(0, 0, i))
		if err != nil {
			t.Fatal(err)
		}
		if seen[e.Body] {
			t.Fatalf("repeated within one cycle: %q", e.Body)
		}
		seen[e.Body] = true
	}
}

func TestReformatDeployQuotesExample(t *testing.T) {
	if os.Getenv("REFORMAT_QUOTES") != "1" {
		t.Skip("set REFORMAT_QUOTES=1 to rewrite deploy/quotes/quotes.example.txt")
	}
	root := findRepoRoot()
	path := filepath.Join(root, "deploy", "quotes", "quotes.example.txt")
	n, err := ReformatQuotesFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if n < 10 {
		t.Fatalf("too few entries: %d", n)
	}
}

func findRepoRoot() string {
	dir, _ := os.Getwd()
	for i := 0; i < 8; i++ {
		if _, err := os.Stat(filepath.Join(dir, "deploy", "quotes")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return ""
}
