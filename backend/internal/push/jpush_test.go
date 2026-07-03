package push

import "testing"

func TestMultiSenderFallbackLogsUnknownPlatform(t *testing.T) {
	m := &multiSender{fallback: logSender{}}
	if err := m.Send(t.Context(), "tok", "unknown", Payload{Title: "t", Body: "b"}); err != nil {
		t.Fatal(err)
	}
}
