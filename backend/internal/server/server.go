// Package server 注册 HTTP 路由。
package server

import (
	"net/http"

	"github.com/ihope/ihope/internal/admin"
	"github.com/ihope/ihope/internal/apprelease"
	"github.com/ihope/ihope/internal/auth"
	"github.com/ihope/ihope/internal/config"
	"github.com/ihope/ihope/internal/conversation"
	"github.com/ihope/ihope/internal/devicelink"
	"github.com/ihope/ihope/internal/filestore"
	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/jwt"
	"github.com/ihope/ihope/internal/lifecycle"
	"github.com/ihope/ihope/internal/message"
	"github.com/ihope/ihope/internal/middleware"
	"github.com/ihope/ihope/internal/signal"
	"github.com/ihope/ihope/internal/user"
	"github.com/ihope/ihope/internal/ws"
)

type Server struct {
	cfg           config.Config
	auth          *auth.Handler
	users         *user.Handler
	conversations *conversation.Handler
	messages      *message.Handler
	ws            *ws.Handler
	signal        *signal.Handler
	admin         *admin.Handler
	deviceLink    *devicelink.Handler
	files         *filestore.Handler
	userRepo      *user.Repository
	jwt           *jwt.Manager
	loginLimit    *middleware.RateLimiter
}

func New(
	cfg config.Config,
	authHandler *auth.Handler,
	userHandler *user.Handler,
	userRepo *user.Repository,
	jwtMgr *jwt.Manager,
	convHandler *conversation.Handler,
	msgHandler *message.Handler,
	wsHandler *ws.Handler,
	signalHandler *signal.Handler,
	adminHandler *admin.Handler,
	deviceLinkHandler *devicelink.Handler,
	fileHandler *filestore.Handler,
) *Server {
	return &Server{
		cfg:           cfg,
		auth:          authHandler,
		users:         userHandler,
		conversations: convHandler,
		messages:      msgHandler,
		ws:            wsHandler,
		signal:        signalHandler,
		admin:         adminHandler,
		deviceLink:    deviceLinkHandler,
		files:         fileHandler,
		userRepo:      userRepo,
		jwt:           jwtMgr,
		loginLimit:    middleware.NewRateLimiter(cfg.LoginRateLimit, cfg.LoginRateWindow),
	}
}

func (s *Server) Router() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /api/health", s.handleHealth)
	mux.HandleFunc("GET /health", s.handleHealth)
	mux.HandleFunc("GET /api/app/download", apprelease.NewHandler(s.cfg.UploadDir).Download)

	mux.Handle("POST /api/auth/register", s.loginLimit.Middleware(http.HandlerFunc(s.auth.Register)))
	mux.Handle("POST /api/auth/login", s.loginLimit.Middleware(http.HandlerFunc(s.auth.Login)))
	mux.HandleFunc("POST /api/auth/refresh", s.auth.Refresh)
	mux.HandleFunc("POST /api/auth/forgot-password", s.auth.ForgotPassword)
	mux.HandleFunc("POST /api/auth/reset-password", s.auth.ResetPassword)

	authRequired := middleware.AuthActive(s.jwt, s.userRepo)
	devAdminRequired := middleware.DevAdmin(s.cfg.AdminSecret)
	mux.Handle("POST /api/auth/change-password", authRequired(http.HandlerFunc(s.auth.ChangePassword)))
	mux.Handle("POST /api/auth/logout", authRequired(http.HandlerFunc(s.auth.Logout)))
	mux.Handle("GET /api/users/me", authRequired(http.HandlerFunc(s.users.Me)))
	mux.Handle("PATCH /api/users/me", authRequired(http.HandlerFunc(s.users.UpdateMe)))
	mux.Handle("POST /api/users/me/avatar", authRequired(http.HandlerFunc(s.users.UploadAvatar)))
	mux.Handle("PUT /api/users/me/push-token", authRequired(http.HandlerFunc(s.users.RegisterPushToken)))
	mux.Handle("GET /api/devices", authRequired(http.HandlerFunc(s.users.ListDevices)))
	mux.Handle("DELETE /api/devices/{deviceId}", authRequired(http.HandlerFunc(s.users.KickDevice)))
	mux.HandleFunc("GET /api/avatars/{filename}", s.users.ServeAvatar)
	mux.Handle("GET /api/users", authRequired(http.HandlerFunc(s.users.List)))

	if s.signal != nil {
		mux.Handle("PUT /api/users/me/signal-keys", authRequired(http.HandlerFunc(s.signal.UploadKeys)))
		mux.Handle("GET /api/users/{userId}/signal-bundle", authRequired(http.HandlerFunc(s.signal.GetUserBundle)))
		mux.Handle("GET /api/users/{userId}/signal-devices", authRequired(http.HandlerFunc(s.signal.ListDevices)))
	}

	if s.conversations != nil {
		mux.Handle("GET /api/conversations", authRequired(http.HandlerFunc(s.conversations.List)))
		mux.Handle("POST /api/conversations", authRequired(http.HandlerFunc(s.conversations.Create)))
		mux.Handle("POST /api/conversations/{id}/members", authRequired(http.HandlerFunc(s.conversations.AddMembers)))
		mux.Handle("POST /api/conversations/{id}/rotate-keys", authRequired(http.HandlerFunc(s.conversations.RotateKeys)))
		mux.Handle("DELETE /api/conversations/{id}/members/{userId}", authRequired(http.HandlerFunc(s.conversations.RemoveMember)))
		mux.Handle("DELETE /api/conversations/{id}", authRequired(http.HandlerFunc(s.conversations.Delete)))
		mux.Handle("PATCH /api/conversations/{id}", authRequired(http.HandlerFunc(s.conversations.Patch)))
		mux.Handle("POST /api/conversations/{id}/avatar", authRequired(http.HandlerFunc(s.conversations.UploadAvatar)))
		mux.Handle("GET /api/conversations/{id}/key-bundles", authRequired(http.HandlerFunc(s.conversations.ListKeyBundles)))
		mux.Handle("POST /api/conversations/{id}/key-bundles", authRequired(http.HandlerFunc(s.conversations.UploadKeyBundles)))
		mux.Handle("GET /api/conversations/{id}/member-directory", authRequired(http.HandlerFunc(s.conversations.MemberDirectory)))
	}
	if s.messages != nil {
		mux.Handle("GET /api/conversations/{id}/messages", authRequired(http.HandlerFunc(s.messages.List)))
		mux.Handle("POST /api/conversations/{id}/messages", authRequired(http.HandlerFunc(s.messages.Send)))
	}
	if s.ws != nil {
		mux.Handle("GET /ws", s.ws)
	}

	if s.deviceLink != nil {
		mux.Handle("POST /api/device-link/init", authRequired(http.HandlerFunc(s.deviceLink.Init)))
		mux.Handle("PUT /api/device-link/{id}/payload", authRequired(http.HandlerFunc(s.deviceLink.UploadPayload)))
		mux.Handle("POST /api/device-link/complete", authRequired(http.HandlerFunc(s.deviceLink.Complete)))
	}

	if s.files != nil {
		mux.Handle("POST /api/upload", authRequired(http.HandlerFunc(s.files.Upload)))
		mux.Handle("GET /api/files/{id}", authRequired(http.HandlerFunc(s.files.Download)))
	}

	if s.admin != nil {
		mux.Handle("GET /api/admin/stats", devAdminRequired(http.HandlerFunc(s.admin.Stats)))
		mux.Handle("GET /api/admin/users", devAdminRequired(http.HandlerFunc(s.admin.ListUsers)))
		mux.Handle("GET /api/admin/users/{id}", devAdminRequired(http.HandlerFunc(s.admin.GetUser)))
		mux.Handle("POST /api/admin/users/{id}/disable", devAdminRequired(http.HandlerFunc(s.admin.DisableUser)))
		mux.Handle("POST /api/admin/users/{id}/enable", devAdminRequired(http.HandlerFunc(s.admin.EnableUser)))
		mux.Handle("POST /api/admin/users/{id}/devices/{deviceId}/kick", devAdminRequired(http.HandlerFunc(s.admin.KickDevice)))
		mux.Handle("GET /api/admin/config", devAdminRequired(http.HandlerFunc(s.admin.Config)))
		mux.Handle("POST /api/admin/drain", devAdminRequired(http.HandlerFunc(s.admin.Drain)))
	}

	mountAdminWeb(mux)

	return cors(s.cfg.CORSAllowOrigin, drainGuard(mux))
}

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"ok":       true,
		"service":  "ihope",
		"version":  s.cfg.ServerVersion,
		"draining": lifecycle.IsDraining(),
		"port":     s.cfg.Port,
		"client":   clientConfigJSON(s.cfg),
	})
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
