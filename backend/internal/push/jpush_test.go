package push

import (
	"context"
	"testing"
)

func TestMultiSenderFallbackLogsUnknownPlatform(t *testing.T) {
	m := &multiSender{fallback: logSender{}}
	if err := m.Send(context.Background(), "tok", "unknown", Payload{Title: "t", Body: "b"}); err != nil {
		t.Fatal(err)
	}
}
