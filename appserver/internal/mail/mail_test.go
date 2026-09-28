package mail

import (
	"bytes"
	"log"
	"strings"
	"testing"
)

func TestSendMessageReminder_LogDriver(t *testing.T) {
	var buf bytes.Buffer
	prev := log.Writer()
	log.SetOutput(&buf)
	t.Cleanup(func() { log.SetOutput(prev) })

	s := New(Config{Driver: "log"})
	if err := s.SendMessageReminder("a@example.com", "Alice", "https://im.example.com"); err != nil {
		t.Fatal(err)
	}
	out := buf.String()
	if !strings.Contains(out, "to=a@example.com") {
		t.Fatalf("missing recipient: %s", out)
	}
	if !strings.Contains(out, "你有新的 IHope 消息") {
		t.Fatalf("missing subject: %s", out)
	}
	if !strings.Contains(out, "来自 Alice") {
		t.Fatalf("missing sender: %s", out)
	}
	if !strings.Contains(out, "https://im.example.com") {
		t.Fatalf("missing app url: %s", out)
	}
}

func TestSendSocialReminder_LogDriver(t *testing.T) {
	var buf bytes.Buffer
	prev := log.Writer()
	log.SetOutput(&buf)
	t.Cleanup(func() { log.SetOutput(prev) })

	s := New(Config{Driver: "log"})
	if err := s.SendSocialReminder("a@example.com", "Alice 请求添加你为好友，请打开 IHope 查看。", "https://im.example.com"); err != nil {
		t.Fatal(err)
	}
	out := buf.String()
	if !strings.Contains(out, "你有新的 IHope 提醒") {
		t.Fatalf("missing subject: %s", out)
	}
	if !strings.Contains(out, "请求添加你为好友") {
		t.Fatalf("missing body: %s", out)
	}
}

func TestSendBatchMessageReminder_LogDriver(t *testing.T) {
	var buf bytes.Buffer
	prev := log.Writer()
	log.SetOutput(&buf)
	t.Cleanup(func() { log.SetOutput(prev) })

	s := New(Config{Driver: "log"})
	if err := s.SendBatchMessageReminder("a@example.com", 5, []string{"Alice", "Bob"}, ""); err != nil {
		t.Fatal(err)
	}
	out := buf.String()
	if !strings.Contains(out, "5 条") || !strings.Contains(out, "Alice") {
		t.Fatalf("batch body: %s", out)
	}
}
