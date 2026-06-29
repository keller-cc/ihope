// Package server 注册 HTTP 路由。
package server

import (
	"net/http"

	"github.com/ihope/ihope/internal/auth"
	"github.com/ihope/ihope/internal/config"
	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/jwt"
	"github.com/ihope/ihope/internal/middleware"
	"github.com/ihope/ihope/internal/user"
)

type Server struct {
	cfg        config.Config
	auth       *auth.Handler
	users      *user.Handler
	userRepo   *user.Repository
	jwt        *jwt.Manager
	loginLimit *middleware.RateLimiter
}

func New(cfg config.Config, authHandler *auth.Handler, userHandler *user.Handler, userRepo *user.Repository, jwtMgr *jwt.Manager) *Server {
	return &Server{
		cfg:        cfg,
		auth:       authHandler,
		users:      userHandler,
		userRepo:   userRepo,
		jwt:        jwtMgr,
		loginLimit: middleware.NewRateLimiter(cfg.LoginRateLimit, cfg.LoginRateWindow),
	}
}

func (s *Server) Router() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /api/health", s.handleHealth)
	mux.HandleFunc("GET /health", s.handleHealth)

	mux.Handle("POST /api/auth/register", s.loginLimit.Middleware(http.HandlerFunc(s.auth.Register)))
	mux.Handle("POST /api/auth/login", s.loginLimit.Middleware(http.HandlerFunc(s.auth.Login)))
	mux.HandleFunc("POST /api/auth/refresh", s.auth.Refresh)
	mux.HandleFunc("POST /api/auth/forgot-password", s.auth.ForgotPassword)
	mux.HandleFunc("POST /api/auth/reset-password", s.auth.ResetPassword)

	authRequired := middleware.Auth(s.jwt, s.userRepo)
	mux.Handle("POST /api/auth/change-password", authRequired(http.HandlerFunc(s.auth.ChangePassword)))
	mux.Handle("GET /api/users/me", authRequired(http.HandlerFunc(s.users.Me)))

	return cors(s.cfg.CORSAllowOrigin, mux)
}

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"ok": true, "service": "ihope"})
}

func cors(allowOrigin string, next http.Handler) http.Handler {
	if allowOrigin == "" {
		allowOrigin = "*"
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", allowOrigin)
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
