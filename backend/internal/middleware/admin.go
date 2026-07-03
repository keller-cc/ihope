package middleware

import (
	"context"
	"net/http"

	"github.com/ihope/ihope/internal/httpx"
)

// AdminChecker 判断用户是否为管理员。
type AdminChecker interface {
	IsAdmin(ctx context.Context, userID string) (bool, error)
}

// Admin 要求已通过 JWT 鉴权且 is_admin=true。
func Admin(checker AdminChecker) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			userID := UserIDFromContext(r.Context())
			if userID == "" {
				httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "missing user")
				return
			}
			ok, err := checker.IsAdmin(r.Context(), userID)
			if err != nil || !ok {
				httpx.WriteError(w, http.StatusForbidden, "forbidden", "admin access required")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
