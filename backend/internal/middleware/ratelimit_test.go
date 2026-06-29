package middleware

import (
	"testing"
	"time"
)

func TestRateLimiterAllowsWithinLimit(t *testing.T) {
	rl := NewRateLimiter(3, time.Minute)
	for i := 0; i < 3; i++ {
		if !rl.Allow("127.0.0.1:/api/auth/login") {
			t.Fatalf("request %d should be allowed", i+1)
		}
	}
}

func TestRateLimiterBlocksOverLimit(t *testing.T) {
	rl := NewRateLimiter(2, time.Minute)
	if !rl.Allow("ip") || !rl.Allow("ip") {
		t.Fatal("first two requests should be allowed")
	}
	if rl.Allow("ip") {
		t.Fatal("third request should be blocked")
	}
}
