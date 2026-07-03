// Package lifecycle 进程排空与优雅关停（开发/生产滚动升级）。
package lifecycle

import (
	"sync/atomic"
	"time"
)

var (
	draining    atomic.Bool
	drainWait   = 15 * time.Second
	shutdownFn  func()
)

// SetDrainWait 设置排空等待时长（SIGTERM 或 /api/admin/drain 后）。
func SetDrainWait(d time.Duration) {
	if d > 0 {
		drainWait = d
	}
}

// SetShutdownFunc 注册关停回调（通常为 http.Server.Shutdown）。
func SetShutdownFunc(fn func()) {
	shutdownFn = fn
}

func IsDraining() bool {
	return draining.Load()
}

func SetDraining(v bool) {
	draining.Store(v)
}

// RequestDrain 进入排空并在等待后触发关停。
func RequestDrain() {
	if draining.Swap(true) {
		return
	}
	if shutdownFn == nil {
		return
	}
	go func() {
		if drainWait > 0 {
			time.Sleep(drainWait)
		}
		shutdownFn()
	}()
}
