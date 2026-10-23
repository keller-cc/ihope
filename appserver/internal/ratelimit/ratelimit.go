package ratelimit

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Limiter is a simple in-memory sliding-window rate limiter.
type Limiter struct {
	mu      sync.Mutex
	entries map[string][]time.Time
	limit   int
	window  time.Duration
}

func New(limit int, window time.Duration) *Limiter {
	if limit < 1 {
		limit = 5
	}
	if window <= 0 {
		window = time.Minute
	}
	return &Limiter{
		entries: make(map[string][]time.Time),
		limit:   limit,
		window:  window,
	}
}

// Allow records a hit for key and returns false when the window is exhausted.
func (rl *Limiter) Allow(key string) bool {
	now := time.Now()
	cutoff := now.Add(-rl.window)

	rl.mu.Lock()
	defer rl.mu.Unlock()

	var kept []time.Time
	for _, t := range rl.entries[key] {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	if len(kept) >= rl.limit {
		rl.entries[key] = kept
		return false
	}
	rl.entries[key] = append(kept, now)
	if len(rl.entries) > 10_000 {
		rl.pruneLocked(cutoff)
	}
	return true
}

func (rl *Limiter) pruneLocked(cutoff time.Time) {
	for k, times := range rl.entries {
		var kept []time.Time
		for _, t := range times {
			if t.After(cutoff) {
				kept = append(kept, t)
			}
		}
		if len(kept) == 0 {
			delete(rl.entries, k)
		} else {
			rl.entries[k] = kept
		}
	}
}

// ClientIP prefers Cloudflare / proxy headers, then RemoteAddr.
func ClientIP(r *http.Request) string {
	if cf := r.Header.Get("CF-Connecting-IP"); cf != "" {
		return strings.TrimSpace(cf)
	}
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		return strings.TrimSpace(strings.Split(xff, ",")[0])
	}
	if xri := r.Header.Get("X-Real-IP"); xri != "" {
		return strings.TrimSpace(xri)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}
