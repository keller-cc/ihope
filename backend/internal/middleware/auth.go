// Package middleware HTTP 中间件：JWT 鉴权、登录限流。
package middleware

import (
	"context"
	"net/http"
	"strings"

	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/jwt"
)

type contextKey string

const userIDKey contextKey = "userID"
const deviceIDKey contextKey = "deviceID"

// TokenVersionLookup 查询用户 token_version，用于校验 access_token 是否已作废。
type TokenVersionLookup interface {
	GetTokenVersion(ctx context.Context, userID string) (int, error)
}

// Auth 校验 Authorization: Bearer <access_token>，并核对 token_version 是否仍有效。
func Auth(jwtMgr *jwt.Manager, lookup TokenVersionLookup) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			if !strings.HasPrefix(header, "Bearer ") {
				httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "missing bearer token")
				return
			}
			token := strings.TrimSpace(strings.TrimPrefix(header, "Bearer "))
			claims, err := jwtMgr.ParseAccessToken(token)
			if err != nil {
				httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "invalid or expired token")
				return
			}

			version, err := lookup.GetTokenVersion(r.Context(), claims.UserID)
			if err != nil {
				httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "invalid or expired token")
				return
			}
			if version != claims.TokenVersion {
				httpx.WriteError(w, http.StatusUnauthorized, "session_revoked", "session expired, please sign in again")
				return
			}

			ctx := context.WithValue(r.Context(), userIDKey, claims.UserID)
			ctx = context.WithValue(ctx, deviceIDKey, claims.DeviceID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// UserIDFromContext 从鉴权中间件注入的 Context 读取当前用户 ID。
func UserIDFromContext(ctx context.Context) string {
	v, _ := ctx.Value(userIDKey).(string)
	return v
}

// DeviceIDFromContext 从 Context 读取当前设备 ID。
func DeviceIDFromContext(ctx context.Context) string {
	v, _ := ctx.Value(deviceIDKey).(string)
	return v
}
