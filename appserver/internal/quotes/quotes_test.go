package quotes

import (
	"os"
	"testing"
	"time"
)

func TestReadQuoteEntriesLegacy(t *testing.T) {
	dir := t.TempDir()
	path := dir + "/quotes.txt"
	content := "第一段\n\n第二段\n\n来自@燕子\n\n另一条金句\n来自@测试"
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
	if entries[0].Body != "第一段\n\n第二段" || entries[0].Author != "燕子" {
		t.Fatalf("first=%+v", entries[0])
	}
	if entries[1].Body != "另一条金句" || entries[1].Author != "测试" {
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
