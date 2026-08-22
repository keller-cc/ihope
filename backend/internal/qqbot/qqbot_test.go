package qqbot

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestIsBindCode(t *testing.T) {
	if !isBindCode("123456") {
		t.Fatal("expected true")
	}
	if isBindCode("12ab56") || isBindCode("12345") || isBindCode("123456789") {
		t.Fatal("expected false")
	}
}

func TestWrapRunes(t *testing.T) {
	lines := wrapRunes("床前明月光疑是地上霜", 5)
	if len(lines) != 2 {
		t.Fatalf("lines=%v", lines)
	}
	if lines[0] != "床前明月光" || lines[1] != "疑是地上霜" {
		t.Fatalf("unexpected %v", lines)
	}
}

func TestNormalizeCmd(t *testing.T) {
	if normalizeCmd(" /Help ") != "help" {
		t.Fatal(normalizeCmd(" /Help "))
	}
	if normalizeCmd("金句") != "金句" && normalizeCmd("金句") != strings.ToLower("金句") {
		t.Fatal(normalizeCmd("金句"))
	}
}

func TestSignValidationOfficialExample(t *testing.T) {
	// https://bot.q.qq.com/wiki/develop/api-v2/dev-prepare/event-emit/webhook.html
	const secret = "DG5g3B4j9X2KOErG"
	const plain = "Arq0D5A61EgUu4OxUvOp"
	const ts = "1725442341"
	const want = "87befc99c42c651b3aac0278e71ada338433ae26fcb24307bdc5ad38c1adc2d01bcfcadc0842edac85e85205028a1132afe09280305f13aa6909ffc2d652c706"
	got, err := signValidation(secret, ts, plain)
	if err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("signature mismatch\ngot  %s\nwant %s", got, want)
	}
}

func TestValidationBodyEventTsNumber(t *testing.T) {
	var v validationBody
	if err := json.Unmarshal([]byte(`{"plain_token":"abc","event_ts":1725442341}`), &v); err != nil {
		t.Fatal(err)
	}
	if v.EventTs != "1725442341" || v.PlainToken != "abc" {
		t.Fatalf("%+v", v)
	}
}

func TestParseExpiresIn(t *testing.T) {
	if got := parseExpiresIn(json.RawMessage(`7200`)); got != 7200 {
		t.Fatalf("int: %d", got)
	}
	if got := parseExpiresIn(json.RawMessage(`"7200"`)); got != 7200 {
		t.Fatalf("string: %d", got)
	}
	if got := parseExpiresIn(json.RawMessage(`null`)); got != 0 {
		t.Fatalf("null: %d", got)
	}
}
