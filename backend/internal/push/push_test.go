package push

import "testing"

func TestBodyForType(t *testing.T) {
	tests := map[string]string{
		"text":         "新消息",
		"image":        "[图片]",
		"audio":        "[语音]",
		"file":         "[文件]",
		"announcement": "[群公告]",
		"system":       "[系统消息]",
	}
	for typ, want := range tests {
		if got := bodyForType(typ); got != want {
			t.Fatalf("bodyForType(%q) = %q, want %q", typ, got, want)
		}
	}
}

func TestLogSender(t *testing.T) {
	s := logSender{}
	err := s.Send(t.Context(), "token-abc", "android", Payload{
		ConversationID: "conv-1",
		MessageID:      "msg-1",
		MessageType:    "text",
		SenderID:       "user-2",
		Ciphertext:     "cipher-blob",
		Epoch:          1,
		Title:          "Alice",
		Body:           "收到一条新消息",
	})
	if err != nil {
		t.Fatal(err)
	}
}

func TestServiceNilToken(t *testing.T) {
	svc := &Service{sender: logSender{}}
	if err := svc.Send(t.Context(), "", "android", Payload{}); err != nil {
		t.Fatal(err)
	}
}
