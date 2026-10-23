package ratelimit

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestLimiterAllowsWithinLimit(t *testing.T) {
	rl := New(3, time.Minute)
	for i := 0; i < 3; i++ {
		if !rl.Allow("127.0.0.1:auth") {
			t.Fatalf("request %d should be allowed", i+1)
		}
	}
}

func TestLimiterBlocksOverLimit(t *testing.T) {
	rl := New(2, time.Minute)
	if !rl.Allow("ip") || !rl.Allow("ip") {
		t.Fatal("first two requests should be allowed")
	}
	if rl.Allow("ip") {
		t.Fatal("third request should be blocked")
	}
}

func TestClientIPPrefersCF(t *testing.T) {
	r := httptest.NewRequest(http.MethodPost, "/api/auth/login", nil)
	r.Header.Set("CF-Connecting-IP", "1.2.3.4")
	r.Header.Set("X-Forwarded-For", "9.9.9.9")
	r.RemoteAddr = "10.0.0.1:1234"
	if got := ClientIP(r); got != "1.2.3.4" {
		t.Fatalf("got %q", got)
	}
}
