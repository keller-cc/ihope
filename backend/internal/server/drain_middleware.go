package server

import (
	"net/http"
	"strings"

	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/lifecycle"
)

func drainGuard(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if lifecycle.IsDraining() && !isHealthPath(r.URL.Path) {
			httpx.WriteError(w, http.StatusServiceUnavailable, "draining", "server upgrading, please retry")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func isHealthPath(path string) bool {
	path = strings.TrimSuffix(path, "/")
	return path == "/api/health" || path == "/health" || path == "/api/app/download"
}
