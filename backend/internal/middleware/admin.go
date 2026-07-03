package middleware

import (
	"crypto/subtle"
	"net/http"
	"strings"

	"github.com/ihope/ihope/internal/httpx"
)

// DevAdmin 校验开发者管理密钥（Authorization: Bearer <ADMIN_SECRET>）。
// secret 为空时管理 API 不可用。
func DevAdmin(secret string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if strings.TrimSpace(secret) == "" {
				httpx.WriteError(w, http.StatusServiceUnavailable, "admin_disabled", "admin secret not configured")
				return
			}
			token := bearerToken(r)
			if token == "" || subtle.ConstantTimeCompare([]byte(token), []byte(secret)) != 1 {
				httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "invalid admin secret")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func bearerToken(r *http.Request) string {
	header := r.Header.Get("Authorization")
	if !strings.HasPrefix(header, "Bearer ") {
		return ""
	}
	return strings.TrimSpace(strings.TrimPrefix(header, "Bearer "))
}
