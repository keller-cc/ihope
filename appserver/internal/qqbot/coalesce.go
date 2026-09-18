package qqbot

import (
	"sync"
	"time"
)

// coalesceGate suppresses duplicate offline pushes (server-side collapse / debounce).
// Industry pattern: per-(user, category, entity) TTL keys — same idea as APNs collapse-id / FCM collapse_key.
type coalesceGate struct {
	mu   sync.Mutex
	last map[string]time.Time
}

func newCoalesceGate() *coalesceGate {
	return &coalesceGate{last: make(map[string]time.Time)}
}

func (g *coalesceGate) allow(key string, minInterval time.Duration) bool {
	if key == "" || minInterval <= 0 {
		return true
	}
	now := time.Now()
	g.mu.Lock()
	defer g.mu.Unlock()
	if t, ok := g.last[key]; ok && now.Sub(t) < minInterval {
		return false
	}
	g.last[key] = now
	if len(g.last) > 4096 {
		g.pruneLocked(now, 30*time.Minute)
	}
	return true
}

func (g *coalesceGate) pruneLocked(now time.Time, maxAge time.Duration) {
	for k, t := range g.last {
		if now.Sub(t) > maxAge {
			delete(g.last, k)
		}
	}
}
