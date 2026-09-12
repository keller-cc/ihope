package httpserver

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/keller-cc/ihope/appserver/internal/admin"
	"github.com/keller-cc/ihope/appserver/internal/auth"
	"github.com/keller-cc/ihope/appserver/internal/call"
	"github.com/keller-cc/ihope/appserver/internal/chat"
	"github.com/keller-cc/ihope/appserver/internal/games"
	"github.com/keller-cc/ihope/appserver/internal/hub"
	"github.com/keller-cc/ihope/appserver/internal/qqbot"
	"github.com/keller-cc/ihope/appserver/internal/quotes"
	"github.com/keller-cc/ihope/appserver/internal/upload"
)

type Server struct {
	auth       *auth.Service
	chat       *chat.Service
	admin      *admin.Service
	gameSvc    *games.Service
	hub        *hub.Hub
	calls      *call.Service
	qq         *qqbot.Service
	cors       string
	qqPath     string
	adminToken string
	uploadDir  string
	quotesPath string
	webDist    string
	upg        websocket.Upgrader
}

func New(
	authSvc *auth.Service,
	chatSvc *chat.Service,
	adminSvc *admin.Service,
	gamesSvc *games.Service,
	h *hub.Hub,
	callSvc *call.Service,
	qq *qqbot.Service,
	corsOrigin, qqWebhookPath, adminToken, uploadDir, quotesPath, webDist string,
) *Server {
	return &Server{
		auth:       authSvc,
		chat:       chatSvc,
		admin:      adminSvc,
		gameSvc:    gamesSvc,
		hub:        h,
		calls:      callSvc,
		qq:         qq,
		cors:       corsOrigin,
		qqPath:     qqWebhookPath,
		adminToken: strings.TrimSpace(adminToken),
		uploadDir:  uploadDir,
		quotesPath: strings.TrimSpace(quotesPath),
		webDist:    strings.TrimSpace(webDist),
		upg: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool {
				origin := r.Header.Get("Origin")
				return origin == "" || origin == corsOrigin
			},
		},
	}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.handleHealth)
	mux.HandleFunc("GET /api/health", s.handleHealth) // 兼容旧 App / 探活 URL
	mux.HandleFunc("POST /api/auth/register", s.handleRegister)
	mux.HandleFunc("POST /api/auth/login", s.handleLogin)
	mux.HandleFunc("POST /api/auth/resend-verification", s.handleResendVerification)
	mux.HandleFunc("POST /api/auth/change-unverified-email", s.handleChangeUnverifiedEmail)
	mux.HandleFunc("GET /api/auth/verify-email", s.handleVerifyEmailGET)
	mux.HandleFunc("POST /api/auth/verify-email", s.handleVerifyEmailPOST)
	mux.HandleFunc("GET /api/me", s.withAuth(s.handleMe))
	mux.HandleFunc("PATCH /api/me", s.withAuth(s.handlePatchMe))
	mux.HandleFunc("POST /api/me/hope-id/refresh", s.withAuth(s.handleRefreshHopeID))
	mux.HandleFunc("POST /api/me/avatar", s.withAuth(s.handleUploadAvatar))
	mux.HandleFunc("PATCH /api/me/chat-bg", s.withAuth(s.handlePatchChatTheme))
	mux.HandleFunc("PATCH /api/me/chat-theme", s.withAuth(s.handlePatchChatTheme))
	mux.HandleFunc("POST /api/me/chat-bg", s.withAuth(s.handleUploadChatBg))
	mux.HandleFunc("GET /api/me/chat-bg/images", s.withAuth(s.handleListChatBgImages))
	mux.HandleFunc("DELETE /api/me/chat-bg/images/{id}", s.withAuth(s.handleDeleteChatBgImage))
	mux.HandleFunc("GET /api/quotes/today", s.withAuth(s.handleTodayQuote))
	mux.HandleFunc("GET /api/search/users", s.withAuth(s.handleSearchUsers))
	mux.HandleFunc("GET /api/search/groups", s.withAuth(s.handleSearchGroups))
	mux.HandleFunc("GET /api/conversations", s.withAuth(s.handleListConversations))
	mux.HandleFunc("POST /api/conversations/dm", s.withAuth(s.handleCreateDM))
	mux.HandleFunc("POST /api/conversations/group", s.withAuth(s.handleCreateGroup))
	mux.HandleFunc("POST /api/conversations/group/join", s.withAuth(s.handleJoinGroup))
	mux.HandleFunc("GET /api/conversations/{id}/members", s.withAuth(s.handleListMembers))
	mux.HandleFunc("GET /api/conversations/{id}/join-requests", s.withAuth(s.handleListGroupJoinRequests))
	mux.HandleFunc("POST /api/conversations/{id}/join-requests/{rid}/accept", s.withAuth(s.handleAcceptGroupJoinRequest))
	mux.HandleFunc("POST /api/conversations/{id}/join-requests/{rid}/reject", s.withAuth(s.handleRejectGroupJoinRequest))
	mux.HandleFunc("POST /api/me/group-join-requests/{id}/cancel", s.withAuth(s.handleCancelGroupJoinRequest))
	mux.HandleFunc("PATCH /api/conversations/{id}", s.withAuth(s.handlePatchConversation))
	mux.HandleFunc("POST /api/conversations/{id}/avatar", s.withAuth(s.handleUploadGroupAvatar))
	mux.HandleFunc("PATCH /api/conversations/{id}/member", s.withAuth(s.handlePatchMember))
	mux.HandleFunc("POST /api/conversations/{id}/read", s.withAuth(s.handleMarkRead))
	mux.HandleFunc("POST /api/conversations/{id}/leave", s.withAuth(s.handleLeaveGroup))
	mux.HandleFunc("POST /api/conversations/{id}/invite", s.withAuth(s.handleInviteMembers))
	mux.HandleFunc("POST /api/conversations/{id}/kick", s.withAuth(s.handleKickMember))
	mux.HandleFunc("POST /api/conversations/{id}/dissolve", s.withAuth(s.handleDissolveGroup))
	mux.HandleFunc("PATCH /api/conversations/{id}/members/role", s.withAuth(s.handleSetMemberRole))
	mux.HandleFunc("PATCH /api/conversations/{id}/members/title", s.withAuth(s.handleSetMemberTitle))
	mux.HandleFunc("GET /api/conversations/{id}/announcements", s.withAuth(s.handleListAnnouncements))
	mux.HandleFunc("POST /api/conversations/{id}/announcements", s.withAuth(s.handleCreateAnnouncement))
	mux.HandleFunc("GET /api/conversations/{id}/announcements/{aid}", s.withAuth(s.handleGetAnnouncement))
	mux.HandleFunc("PATCH /api/conversations/{id}/announcements/{aid}", s.withAuth(s.handleUpdateAnnouncement))
	mux.HandleFunc("DELETE /api/conversations/{id}/announcements/{aid}", s.withAuth(s.handleDeleteAnnouncement))
	mux.HandleFunc("POST /api/conversations/{id}/announcements/{aid}/ack", s.withAuth(s.handleAckAnnouncement))
	mux.HandleFunc("GET /api/conversations/{id}/messages", s.withAuth(s.handleListMessages))
	mux.HandleFunc("GET /api/conversations/{id}/messages/search", s.withAuth(s.handleSearchMessages))
	mux.HandleFunc("GET /api/conversations/{id}/messages/days", s.withAuth(s.handleListMessageDays))
	mux.HandleFunc("GET /api/conversations/{id}/messages/{mid}/context", s.withAuth(s.handleMessageContext))
	mux.HandleFunc("POST /api/conversations/{id}/messages", s.withAuth(s.handleSendMessage))
	mux.HandleFunc("POST /api/conversations/{id}/messages/image", s.withAuth(s.handleSendImage))
	mux.HandleFunc("POST /api/conversations/{id}/messages/file", s.withAuth(s.handleSendFile))
	mux.HandleFunc("POST /api/conversations/{id}/messages/voice", s.withAuth(s.handleSendVoice))
	mux.HandleFunc("POST /api/conversations/{id}/messages/forward", s.withAuth(s.handleForwardMessages))
	mux.HandleFunc("POST /api/conversations/{id}/messages/{mid}/recall", s.withAuth(s.handleRecallMessage))
	mux.HandleFunc("POST /api/conversations/{id}/calls", s.withAuth(s.handleStartCall))
	mux.HandleFunc("GET /api/conversations/{id}/calls/active", s.withAuth(s.handleActiveCall))
	mux.HandleFunc("GET /api/calls/incoming", s.withAuth(s.handleIncomingCalls))
	mux.HandleFunc("GET /api/calls/ice", s.withAuth(s.handleCallICE))
	mux.HandleFunc("GET /api/calls/{id}", s.withAuth(s.handleGetCall))
	mux.HandleFunc("POST /api/calls/{id}/accept", s.withAuth(s.handleAcceptCall))
	mux.HandleFunc("POST /api/calls/{id}/reject", s.withAuth(s.handleRejectCall))
	mux.HandleFunc("POST /api/calls/{id}/hangup", s.withAuth(s.handleHangupCall))
	mux.HandleFunc("GET /api/contacts/friends", s.withAuth(s.handleListFriends))
	mux.HandleFunc("POST /api/contacts/friends", s.withAuth(s.handleAddFriend))
	mux.HandleFunc("PATCH /api/contacts/friends/{id}", s.withAuth(s.handleSetFriendRemark))
	mux.HandleFunc("GET /api/contacts/friend-requests", s.withAuth(s.handleListFriendRequests))
	mux.HandleFunc("POST /api/contacts/friend-requests/{id}/accept", s.withAuth(s.handleAcceptFriendRequest))
	mux.HandleFunc("POST /api/contacts/friend-requests/{id}/reject", s.withAuth(s.handleRejectFriendRequest))
	mux.HandleFunc("POST /api/contacts/friend-requests/{id}/cancel", s.withAuth(s.handleCancelFriendRequest))
	mux.HandleFunc("GET /api/contacts/group-join-requests", s.withAuth(s.handleListManagedGroupJoinRequests))
	mux.HandleFunc("DELETE /api/contacts/friends/{id}", s.withAuth(s.handleRemoveFriend))
	mux.HandleFunc("GET /api/contacts/groups", s.withAuth(s.handleListGroups))
	mux.Handle("/uploads/", s.withUploadCache(http.StripPrefix("/uploads/", http.FileServer(http.Dir(s.uploadDir)))))
	mux.HandleFunc("GET /api/me/qq-bot", s.withAuth(s.handleQQStatus))
	mux.HandleFunc("POST /api/me/qq-bot/bind-code", s.withAuth(s.handleQQBindCode))
	mux.HandleFunc("PATCH /api/me/qq-bot", s.withAuth(s.handleQQPatch))
	mux.HandleFunc("DELETE /api/me/qq-bot", s.withAuth(s.handleQQUnbind))
	mux.HandleFunc("GET /api/games/dino/leaderboard", s.handleDinoLeaderboard)
	mux.HandleFunc("POST /api/games/dino/score", s.withAuth(s.handleDinoSubmitScore))
	mux.HandleFunc("GET /api/games/dino/me", s.withAuth(s.handleDinoMyBest))
	mux.HandleFunc("GET /api/admin/users", s.withAdmin(s.handleAdminListUsers))
	mux.HandleFunc("DELETE /api/admin/users/{id}", s.withAdmin(s.handleAdminDeleteUser))
	mux.HandleFunc("PATCH /api/admin/users/{id}", s.withAdmin(s.handleAdminPatchUser))
	mux.HandleFunc("POST /api/admin/users/{id}/qq-bind-code", s.withAdmin(s.handleAdminQQBindCode))
	mux.HandleFunc("DELETE /api/admin/users/{id}/qq-bot", s.withAdmin(s.handleAdminQQUnbind))
	mux.HandleFunc("GET /api/admin/qq-bindings", s.withAdmin(s.handleAdminListQQBindings))
	mux.HandleFunc("GET /api/admin/conversations", s.withAdmin(s.handleAdminListConversations))
	mux.HandleFunc("GET /api/admin/conversations/{id}", s.withAdmin(s.handleAdminGetGroup))
	mux.HandleFunc("PATCH /api/admin/conversations/{id}", s.withAdmin(s.handleAdminPatchGroup))
	mux.HandleFunc("POST /api/admin/conversations/{id}/kick", s.withAdmin(s.handleAdminKickMember))
	mux.HandleFunc("POST /api/admin/conversations/{id}/members/role", s.withAdmin(s.handleAdminSetMemberRole))
	mux.HandleFunc("POST /api/admin/conversations/{id}/transfer-owner", s.withAdmin(s.handleAdminTransferOwner))
	mux.HandleFunc("DELETE /api/admin/conversations/{id}", s.withAdmin(s.handleAdminDeleteConversation))
	mux.HandleFunc("GET /api/admin/group-join-requests", s.withAdmin(s.handleAdminListGroupJoins))
	mux.HandleFunc("POST /api/admin/conversations/{id}/join-requests/{rid}/accept", s.withAdmin(s.handleAdminAcceptGroupJoin))
	mux.HandleFunc("POST /api/admin/conversations/{id}/join-requests/{rid}/reject", s.withAdmin(s.handleAdminRejectGroupJoin))
	mux.HandleFunc("GET /api/admin/stats", s.withAdmin(s.handleAdminStats))
	mux.HandleFunc("GET /api/admin/domains", s.withAdmin(s.handleAdminListDomains))
	mux.HandleFunc("POST /api/admin/domains", s.withAdmin(s.handleAdminCreateDomain))
	mux.HandleFunc("PATCH /api/admin/domains/{id}", s.withAdmin(s.handleAdminPatchDomain))
	mux.HandleFunc("DELETE /api/admin/domains/{id}", s.withAdmin(s.handleAdminDeleteDomain))
	mux.HandleFunc("GET /api/admin/fellowships", s.withAdmin(s.handleAdminListFellowships))
	mux.HandleFunc("POST /api/admin/fellowships", s.withAdmin(s.handleAdminCreateFellowship))
	mux.HandleFunc("PATCH /api/admin/fellowships/{id}", s.withAdmin(s.handleAdminPatchFellowship))
	mux.HandleFunc("DELETE /api/admin/fellowships/{id}", s.withAdmin(s.handleAdminDeleteFellowship))
	if s.qqPath != "" {
		mux.HandleFunc("POST "+s.qqPath, s.handleQQWebhook)
	}
	mux.HandleFunc("GET /api/public/qq-media/{name}", s.handleQQPublicMedia)
	mux.HandleFunc("GET /ws", s.handleWS)
	mux.HandleFunc("GET /ws/user", s.handleUserWS)
	if s.webDist != "" {
		if st, err := os.Stat(s.webDist); err == nil && st.IsDir() {
			mux.Handle("/", s.spaFileServer())
		}
	}
	return s.corsMiddleware(mux)
}

/** 生产：托管 Vite dist；未知路径回退 index.html（SPA）。 */
func (s *Server) spaFileServer() http.Handler {
	root := filepath.Clean(s.webDist)
	fileServer := http.FileServer(http.Dir(root))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		rel := strings.TrimPrefix(filepath.Clean("/"+r.URL.Path), "/")
		full := filepath.Join(root, rel)
		if !strings.HasPrefix(full, root+string(os.PathSeparator)) && full != root {
			http.NotFound(w, r)
			return
		}
		if info, err := os.Stat(full); err == nil && !info.IsDir() {
			base := filepath.Base(full)
			// Service Worker / manifest 必须可及时更新，避免长期缓存旧壳
			if base == "sw.js" || base == "registerSW.js" ||
				strings.HasSuffix(base, ".webmanifest") || strings.HasPrefix(base, "workbox-") {
				w.Header().Set("Cache-Control", "no-cache")
			}
			fileServer.ServeHTTP(w, r)
			return
		}
		http.ServeFile(w, r, filepath.Join(root, "index.html"))
	})
}

func (s *Server) corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", s.cors)
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handleDinoLeaderboard(w http.ResponseWriter, r *http.Request) {
	list, err := s.gameSvc.ListDinoLeaderboard(r.Context(), 20)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	if list == nil {
		list = []games.ScoreRow{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"scores": list})
}

func (s *Server) handleDinoSubmitScore(w http.ResponseWriter, r *http.Request, userID string) {
	var body struct {
		Score int `json:"score"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	best, improved, err := s.gameSvc.SubmitDinoScore(r.Context(), userID, body.Score)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"best":     best,
		"improved": improved,
		"score":    body.Score,
	})
}

func (s *Server) handleDinoMyBest(w http.ResponseWriter, r *http.Request, userID string) {
	best, err := s.gameSvc.MyDinoBest(r.Context(), userID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "query failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"best": best})
}

func (s *Server) handleRegister(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Email          string `json:"email"`
		Username       string `json:"username"`
		Password       string `json:"password"`
		FellowshipCode string `json:"fellowshipCode"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	res, err := s.auth.Register(r.Context(), body.Email, body.Username, body.Password, body.FellowshipCode)
	if err != nil {
		switch {
		case errors.Is(err, auth.ErrEmailTaken):
			writeErr(w, http.StatusConflict, "email taken")
		case errors.Is(err, auth.ErrUsernameTaken):
			writeErr(w, http.StatusConflict, "username taken")
		case errors.Is(err, auth.ErrInvalidFellowshipCode):
			writeErr(w, http.StatusForbidden, "invalid fellowship code")
		default:
			writeErr(w, http.StatusBadRequest, err.Error())
		}
		return
	}
	writeJSON(w, http.StatusCreated, res)
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Login    string `json:"login"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	u, token, err := s.auth.Login(r.Context(), body.Login, body.Password)
	if err != nil {
		if errors.Is(err, auth.ErrInvalidCredentials) {
			writeErr(w, http.StatusUnauthorized, "invalid credentials")
			return
		}
		if errors.Is(err, auth.ErrEmailNotVerified) {
			payload := map[string]any{"error": "email_not_verified"}
			if u != nil {
				if u.Email != "" {
					payload["email"] = u.Email
				}
				if u.Username != "" {
					payload["username"] = u.Username
				}
			}
			writeJSON(w, http.StatusForbidden, payload)
			return
		}
		writeErr(w, http.StatusInternalServerError, "login failed")
		return
	}
	if ensured, err := s.auth.EnsureHopeID(r.Context(), u.ID); err == nil {
		u = ensured
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": u, "token": token})
}

func (s *Server) handleResendVerification(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Email string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	status, dev, err := s.auth.ResendVerification(r.Context(), body.Email)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "resend failed")
		return
	}
	out := map[string]any{"status": status}
	if dev != "" {
		out["devVerifyToken"] = dev
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) handleChangeUnverifiedEmail(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Login    string `json:"login"`
		Password string `json:"password"`
		NewEmail string `json:"newEmail"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	dev, err := s.auth.ChangeUnverifiedEmail(r.Context(), body.Login, body.Password, body.NewEmail)
	if err != nil {
		switch {
		case errors.Is(err, auth.ErrInvalidCredentials):
			writeErr(w, http.StatusUnauthorized, "invalid credentials")
		case errors.Is(err, auth.ErrEmailTaken):
			writeErr(w, http.StatusConflict, "email taken")
		case err.Error() == "email already verified":
			writeErr(w, http.StatusConflict, "email already verified")
		case err.Error() == "invalid email":
			writeErr(w, http.StatusBadRequest, "invalid email")
		default:
			writeErr(w, http.StatusInternalServerError, "change email failed")
		}
		return
	}
	out := map[string]any{
		"status": "sent",
		"email":  auth.NormalizeEmail(body.NewEmail),
	}
	if dev != "" {
		out["devVerifyToken"] = dev
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) handleVerifyEmailGET(w http.ResponseWriter, r *http.Request) {
	token := html.EscapeString(r.URL.Query().Get("token"))
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = fmt.Fprintf(w, `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>确认邮箱</title>
<style>body{font-family:"Segoe UI","PingFang SC",sans-serif;max-width:28rem;margin:4rem auto;padding:0 1.25rem;color:#132033;background:#f3f6fa}
h1{font-size:1.5rem;margin-bottom:.5rem}p{line-height:1.6;color:#4a5b6e}
button{margin-top:1.25rem;padding:.75rem 1.25rem;border:0;border-radius:.75rem;background:#0b6bcb;color:#fff;font-size:1rem;cursor:pointer}</style></head>
<body><h1>确认验证邮箱</h1><p>点击下方按钮完成邮箱验证，然后返回 IHope 登录。</p>
<form method="POST" action="/api/auth/verify-email"><input type="hidden" name="token" value="%s"><button type="submit">完成验证</button></form></body></html>`, token)
}

func (s *Server) handleVerifyEmailPOST(w http.ResponseWriter, r *http.Request) {
	_ = r.ParseForm()
	token := strings.TrimSpace(r.FormValue("token"))
	wantJSON := strings.Contains(r.Header.Get("Content-Type"), "application/json") ||
		strings.Contains(r.Header.Get("Accept"), "application/json")
	if token == "" && wantJSON {
		var body struct {
			Token string `json:"token"`
		}
		_ = json.NewDecoder(r.Body).Decode(&body)
		token = strings.TrimSpace(body.Token)
	}
	if err := s.auth.VerifyEmail(r.Context(), token); err != nil {
		if wantJSON {
			writeErr(w, http.StatusBadRequest, "invalid verify token")
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write([]byte(`<!DOCTYPE html><html lang="zh-CN"><body><h1>验证失败</h1><p>链接无效或已过期。</p></body></html>`))
		return
	}
	if wantJSON {
		writeJSON(w, http.StatusOK, map[string]string{"message": "email verified"})
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write([]byte(`<!DOCTYPE html><html lang="zh-CN"><body><h1>验证成功</h1><p>邮箱已验证，请返回 IHope 登录。</p></body></html>`))
}

func (s *Server) handleMe(w http.ResponseWriter, r *http.Request, userID string) {
	u, err := s.auth.EnsureHopeID(r.Context(), userID)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func (s *Server) handlePatchMe(w http.ResponseWriter, r *http.Request, userID string) {
	var body struct {
		Username *string `json:"username"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	if body.Username == nil {
		writeErr(w, http.StatusBadRequest, "nothing to update")
		return
	}
	u, err := s.auth.SetUsername(r.Context(), userID, *body.Username)
	if err != nil {
		switch {
		case errors.Is(err, auth.ErrUsernameTaken):
			writeErr(w, http.StatusConflict, "username taken")
		case strings.Contains(err.Error(), "username must"):
			writeErr(w, http.StatusBadRequest, err.Error())
		default:
			writeErr(w, http.StatusInternalServerError, "update failed")
		}
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func (s *Server) handleRefreshHopeID(w http.ResponseWriter, r *http.Request, userID string) {
	u, err := s.auth.RefreshHopeID(r.Context(), userID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "refresh hope id failed")
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func (s *Server) handleTodayQuote(w http.ResponseWriter, r *http.Request, _ string) {
	if s.quotesPath == "" {
		writeErr(w, http.StatusNotFound, "quotes disabled")
		return
	}
	entry, err := quotes.PickDailyQuoteEntry(s.quotesPath, time.Now())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "quotes error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"body":   entry.Body,
		"author": entry.Author,
		"date":   time.Now().Format("2006-01-02"),
	})
}

func (s *Server) handleUploadAvatar(w http.ResponseWriter, r *http.Request, userID string) {
	if err := r.ParseMultipartForm(upload.MaxAvatarBytes + (1 << 20)); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid form")
		return
	}
	file, _, err := r.FormFile("file")
	if err != nil {
		writeErr(w, http.StatusBadRequest, "file required")
		return
	}
	defer file.Close()
	url, err := upload.SaveSquareJPEGFrom(
		filepath.Join(s.uploadDir, "avatars"),
		userID,
		"/uploads/avatars",
		file,
	)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	u, err := s.auth.SetAvatarURL(r.Context(), userID, url)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "save failed")
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func (s *Server) handleUploadGroupAvatar(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	if err := r.ParseMultipartForm(upload.MaxAvatarBytes + (1 << 20)); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid form")
		return
	}
	file, _, err := r.FormFile("file")
	if err != nil {
		writeErr(w, http.StatusBadRequest, "file required")
		return
	}
	defer file.Close()
	url, err := upload.SaveSquareJPEGFrom(
		filepath.Join(s.uploadDir, "groups"),
		id,
		"/uploads/groups",
		file,
	)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	c, err := s.chat.SetGroupAvatarURL(r.Context(), id, userID, url)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, c)
}

func (s *Server) handleSearchUsers(w http.ResponseWriter, r *http.Request, userID string) {
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if q == "" {
		writeErr(w, http.StatusBadRequest, "query required")
		return
	}
	u, err := s.chat.SearchUser(r.Context(), userID, q)
	if err != nil {
		writeErr(w, http.StatusNotFound, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func (s *Server) handleSearchGroups(w http.ResponseWriter, r *http.Request, userID string) {
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if q == "" {
		writeErr(w, http.StatusBadRequest, "query required")
		return
	}
	g, err := s.chat.SearchGroup(r.Context(), userID, q)
	if err != nil {
		writeErr(w, http.StatusNotFound, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, g)
}

func (s *Server) handleSetFriendRemark(w http.ResponseWriter, r *http.Request, userID string) {
	friendID := r.PathValue("id")
	var body struct {
		Remark string `json:"remark"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	c, err := s.chat.SetFriendRemark(r.Context(), userID, friendID, body.Remark)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, c)
}

func (s *Server) handleListConversations(w http.ResponseWriter, r *http.Request, userID string) {
	list, err := s.chat.ListConversations(r.Context(), userID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"conversations": list})
}

func (s *Server) handleCreateDM(w http.ResponseWriter, r *http.Request, userID string) {
	var body struct {
		Username string `json:"username"`
		HopeID   string `json:"hopeId"`
		Query    string `json:"query"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	login := firstNonEmpty(body.Query, body.HopeID, body.Username)
	c, err := s.chat.CreateDM(r.Context(), userID, login)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, c)
}

func (s *Server) handleCreateGroup(w http.ResponseWriter, r *http.Request, userID string) {
	var body struct {
		Title   string   `json:"title"`
		Members []string `json:"members"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	c, err := s.chat.CreateGroup(r.Context(), userID, body.Title, body.Members)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, c)
}

func (s *Server) handleJoinGroup(w http.ResponseWriter, r *http.Request, userID string) {
	var body struct {
		GroupNo string `json:"groupNo"`
		Message string `json:"message"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	res, err := s.chat.JoinGroupByNo(r.Context(), userID, body.GroupNo, body.Message)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if res.Status == "pending" && res.Request != nil {
		managers, _ := s.chat.GroupManagerIDs(r.Context(), res.Request.ConversationID)
		s.hub.PublishToUsers(managers, map[string]any{
			"type":           "group.join_request",
			"conversationId": res.Request.ConversationID,
			"request":        res.Request,
		})
		writeJSON(w, http.StatusCreated, res)
		return
	}
	if res.Status == "joined" && res.NewlyJoined && res.Conversation != nil {
		name := s.chat.UsernameByID(r.Context(), userID)
		tip := name + " 加入了群聊"
		if name == "" {
			tip = "有人加入了群聊"
		}
		if m, err := s.chat.PostSystemMessage(r.Context(), res.Conversation.ID, userID, tip); err == nil && m != nil {
			s.afterMessage(res.Conversation.ID, userID, m)
		}
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) handleListGroupJoinRequests(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	list, err := s.chat.ListGroupJoinRequests(r.Context(), id, userID)
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"requests": list})
}

func (s *Server) handleAcceptGroupJoinRequest(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	rid := r.PathValue("rid")
	c, err := s.chat.AcceptGroupJoinRequest(r.Context(), id, userID, rid)
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	name := c.Username
	tip := name + " 加入了群聊"
	if name == "" {
		tip = "有人加入了群聊"
	}
	if m, err := s.chat.PostSystemMessage(r.Context(), id, userID, tip); err == nil && m != nil {
		s.afterMessage(id, userID, m)
	}
	writeJSON(w, http.StatusOK, c)
}

func (s *Server) handleRejectGroupJoinRequest(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	rid := r.PathValue("rid")
	if err := s.chat.RejectGroupJoinRequest(r.Context(), id, userID, rid); err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "rejected"})
}

func (s *Server) handleCancelGroupJoinRequest(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	if err := s.chat.CancelGroupJoinRequest(r.Context(), userID, id); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "cancelled"})
}

func (s *Server) handleListMembers(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	list, err := s.chat.ListGroupMembers(r.Context(), id, userID)
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"members": list})
}

func (s *Server) handlePatchConversation(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	var body struct {
		Title                  *string `json:"title"`
		JoinMode               *string `json:"joinMode"`
		InviteRequiresApproval *bool   `json:"inviteRequiresApproval"`
		Announcement           *string `json:"announcement"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	joinMode := body.JoinMode
	if joinMode == nil && body.InviteRequiresApproval != nil {
		mode := "anyone"
		if *body.InviteRequiresApproval {
			mode = "verify"
		}
		joinMode = &mode
	}
	c, tipMsg, err := s.chat.PatchGroup(r.Context(), id, userID, body.Title, joinMode, body.Announcement)
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if tipMsg != nil {
		s.afterMessage(id, userID, tipMsg)
	}
	writeJSON(w, http.StatusOK, c)
}

func (s *Server) handleListAnnouncements(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	q := r.URL.Query()
	limit := 20
	if v := strings.TrimSpace(q.Get("limit")); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			limit = n
		}
	}
	list, hasMore, total, err := s.chat.ListAnnouncements(r.Context(), id, userID, limit, q.Get("before"))
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	pending, _ := s.chat.PendingAnnouncement(r.Context(), id, userID)
	writeJSON(w, http.StatusOK, map[string]any{
		"announcements": list,
		"hasMore":       hasMore,
		"total":         total,
		"pending":       pending,
	})
}

func (s *Server) handleGetAnnouncement(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	aid := r.PathValue("aid")
	a, err := s.chat.GetAnnouncement(r.Context(), id, aid, userID)
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, a)
}

func (s *Server) handleCreateAnnouncement(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	var body struct {
		Body           string `json:"body"`
		RequireConfirm *bool  `json:"requireConfirm"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	requireConfirm := false
	if body.RequireConfirm != nil {
		requireConfirm = *body.RequireConfirm
	}
	a, err := s.chat.CreateAnnouncement(r.Context(), id, userID, body.Body, requireConfirm)
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	tip := "发布了新公告"
	if name := s.chat.UsernameByID(r.Context(), userID); name != "" {
		tip = name + " 发布了新公告"
	}
	if m, err := s.chat.PostSystemMessage(r.Context(), id, userID, tip); err == nil && m != nil {
		s.afterMessage(id, userID, m)
	}
	if members, err := s.chat.MemberUserIDs(r.Context(), id); err == nil {
		s.hub.PublishToUsers(members, map[string]any{
			"type":           "group.announcement",
			"conversationId": id,
			"announcement":   a,
		})
	}
	writeJSON(w, http.StatusCreated, a)
}

func (s *Server) handleUpdateAnnouncement(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	aid := r.PathValue("aid")
	var body struct {
		Body string `json:"body"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	a, err := s.chat.UpdateAnnouncement(r.Context(), id, aid, userID, body.Body)
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, a)
}

func (s *Server) handleDeleteAnnouncement(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	aid := r.PathValue("aid")
	if err := s.chat.DeleteAnnouncement(r.Context(), id, aid, userID); err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "deleted"})
}

func (s *Server) handleAckAnnouncement(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	aid := r.PathValue("aid")
	a, err := s.chat.AckAnnouncement(r.Context(), id, aid, userID)
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	next, _ := s.chat.PendingAnnouncement(r.Context(), id, userID)
	writeJSON(w, http.StatusOK, map[string]any{
		"announcement": a,
		"nextPending":  next,
	})
}

func (s *Server) handleLeaveGroup(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	name := s.chat.UsernameByID(r.Context(), userID)
	tip := name + " 退出了群聊"
	if name == "" {
		tip = "有人退出了群聊"
	}
	if m, err := s.chat.PostSystemMessage(r.Context(), id, userID, tip); err == nil && m != nil {
		s.afterMessage(id, userID, m)
	}
	if err := s.chat.LeaveGroup(r.Context(), id, userID); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "left"})
}

func (s *Server) handleInviteMembers(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	var body struct {
		MemberIDs []string `json:"memberIds"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	res, err := s.chat.InviteToGroup(r.Context(), id, userID, body.MemberIDs)
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if res.Added > 0 && len(res.AddedNames) > 0 {
		inviter := s.chat.UsernameByID(r.Context(), userID)
		joined := strings.Join(res.AddedNames, "、")
		tip := joined + " 加入了群聊"
		if inviter != "" {
			tip = inviter + " 邀请 " + joined + " 加入了群聊"
		}
		if m, err := s.chat.PostSystemMessage(r.Context(), id, userID, tip); err == nil && m != nil {
			s.afterMessage(id, userID, m)
		}
	}
	if res.Pending > 0 {
		managers, _ := s.chat.GroupManagerIDs(r.Context(), id)
		s.hub.PublishToUsers(managers, map[string]any{
			"type":           "group.join_request",
			"conversationId": id,
		})
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) handleKickMember(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	var body struct {
		MemberID string `json:"memberId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	actorName := s.chat.UsernameByID(r.Context(), userID)
	targetName := s.chat.UsernameByID(r.Context(), body.MemberID)
	tip := "有人被移出了群聊"
	if actorName != "" && targetName != "" {
		tip = actorName + " 将 " + targetName + " 移出了群聊"
	} else if targetName != "" {
		tip = targetName + " 被移出了群聊"
	}
	var sysMsg *chat.Message
	if m, err := s.chat.PostSystemMessage(r.Context(), id, userID, tip); err == nil {
		sysMsg = m
		s.afterMessage(id, userID, m)
	}
	if err := s.chat.KickFromGroup(r.Context(), id, userID, body.MemberID); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	payload := map[string]any{
		"type":           "group.kicked",
		"conversationId": id,
		"body":           "你已被移出群聊",
	}
	if sysMsg != nil {
		payload["message"] = sysMsg
	}
	s.hub.PublishToUser(body.MemberID, payload)
	writeJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}

func (s *Server) handleDissolveGroup(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	if err := s.chat.DissolveGroup(r.Context(), id, userID); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}

func (s *Server) handleSetMemberRole(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	var body struct {
		MemberID string `json:"memberId"`
		Role     string `json:"role"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := s.chat.SetMemberRole(r.Context(), id, userID, body.MemberID, body.Role); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}

func (s *Server) handleSetMemberTitle(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	var body struct {
		MemberID string `json:"memberId"`
		Title    string `json:"title"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := s.chat.SetMemberTitle(r.Context(), id, userID, body.MemberID, body.Title); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}

func (s *Server) handleListFriends(w http.ResponseWriter, r *http.Request, userID string) {
	list, err := s.chat.ListFriends(r.Context(), userID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"friends": list})
}

func (s *Server) handleAddFriend(w http.ResponseWriter, r *http.Request, userID string) {
	var body struct {
		Username string `json:"username"`
		HopeID   string `json:"hopeId"`
		Query    string `json:"query"`
		Message  string `json:"message"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	login := firstNonEmpty(body.Query, body.HopeID, body.Username)
	fr, err := s.chat.RequestFriend(r.Context(), userID, login, body.Message)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if fr != nil {
		s.hub.PublishToUser(fr.ToUserID, map[string]any{
			"type":    "friend.request",
			"request": fr,
		})
	}
	writeJSON(w, http.StatusCreated, fr)
}

func (s *Server) handleListFriendRequests(w http.ResponseWriter, r *http.Request, userID string) {
	incoming, outgoing, err := s.chat.ListFriendRequests(r.Context(), userID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"incoming": incoming,
		"outgoing": outgoing,
	})
}

func (s *Server) handleAcceptFriendRequest(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	c, err := s.chat.AcceptFriendRequest(r.Context(), userID, id)
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, c)
}

func (s *Server) handleRejectFriendRequest(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	if err := s.chat.RejectFriendRequest(r.Context(), userID, id); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "rejected"})
}

func (s *Server) handleCancelFriendRequest(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	if err := s.chat.CancelFriendRequest(r.Context(), userID, id); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "cancelled"})
}

func (s *Server) handleListManagedGroupJoinRequests(w http.ResponseWriter, r *http.Request, userID string) {
	list, err := s.chat.ListManagedGroupJoinRequests(r.Context(), userID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"requests": list})
}

func (s *Server) handleRemoveFriend(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	if err := s.chat.RemoveFriend(r.Context(), userID, id); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	s.hub.PublishToUser(id, map[string]any{
		"type":     "friend.removed",
		"friendId": userID,
	})
	writeJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}

func (s *Server) handlePatchMember(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	var body struct {
		Pinned *bool `json:"pinned"`
		Muted  *bool `json:"muted"`
		Hidden *bool `json:"hidden"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := s.chat.SetMemberPrefs(r.Context(), id, userID, body.Pinned, body.Muted, body.Hidden); err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}

func (s *Server) handlePatchChatTheme(w http.ResponseWriter, r *http.Request, userID string) {
	var raw map[string]json.RawMessage
	if err := json.NewDecoder(r.Body).Decode(&raw); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	b, _ := json.Marshal(raw)
	// Legacy wallpaper-only: {"kind":"gradient","id":"..."}
	if _, hasKind := raw["kind"]; hasKind {
		if _, hasBg := raw["background"]; !hasBg {
			var bg auth.ChatBg
			if err := json.Unmarshal(b, &bg); err != nil {
				writeErr(w, http.StatusBadRequest, "invalid json")
				return
			}
			u, err := s.auth.SetChatTheme(r.Context(), userID, &auth.ChatTheme{Background: &bg})
			if err != nil {
				writeErr(w, http.StatusBadRequest, err.Error())
				return
			}
			writeJSON(w, http.StatusOK, u)
			return
		}
	}
	var body auth.ChatTheme
	if err := json.Unmarshal(b, &body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	u, err := s.auth.SetChatTheme(r.Context(), userID, &body)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func (s *Server) handleUploadChatBg(w http.ResponseWriter, r *http.Request, userID string) {
	if err := r.ParseMultipartForm(upload.MaxWallpaperBytes + (1 << 20)); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid form")
		return
	}
	file, _, err := r.FormFile("file")
	if err != nil {
		writeErr(w, http.StatusBadRequest, "file required")
		return
	}
	defer file.Close()
	name := uuid.NewString()
	url, err := upload.SaveWallpaperJPEG(
		filepath.Join(s.uploadDir, "chat-bg"),
		name,
		"/uploads/chat-bg",
		file,
	)
	if err != nil {
		if err.Error() == "file too large" {
			writeErr(w, http.StatusRequestEntityTooLarge, "file too large")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if _, err := s.auth.AddChatBackground(r.Context(), userID, url, s.uploadDir); err != nil {
		writeErr(w, http.StatusInternalServerError, "save library failed")
		return
	}
	u, err := s.auth.SetChatBg(r.Context(), userID, &auth.ChatBg{Kind: "image", URL: url})
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "save failed")
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func (s *Server) handleListChatBgImages(w http.ResponseWriter, r *http.Request, userID string) {
	list, err := s.auth.ListChatBackgrounds(r.Context(), userID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"images": list})
}

func (s *Server) handleDeleteChatBgImage(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	u, err := s.auth.DeleteChatBackground(r.Context(), userID, id, s.uploadDir)
	if err != nil {
		if err.Error() == "not found" {
			writeErr(w, http.StatusNotFound, "not found")
			return
		}
		writeErr(w, http.StatusInternalServerError, "delete failed")
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func (s *Server) handleMarkRead(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	if err := s.chat.MarkRead(r.Context(), id, userID); err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}

func (s *Server) handleListGroups(w http.ResponseWriter, r *http.Request, userID string) {
	list, err := s.chat.ListGroups(r.Context(), userID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"groups": list})
}

func (s *Server) handleListMessages(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	q := r.URL.Query()
	before := q.Get("before")
	opts := chat.ListMessagesOpts{
		Limit:     50,
		Before:    before,
		Type:      q.Get("type"),
		SenderID:  q.Get("senderId"),
		SenderIDs: splitCSV(q.Get("senderIds")),
		Day:       q.Get("day"),
	}
	list, hasMore, err := s.chat.ListMessagesFiltered(r.Context(), id, userID, opts)
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		if err.Error() == "invalid type" || err.Error() == "invalid day" {
			writeErr(w, http.StatusBadRequest, err.Error())
			return
		}
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	if before == "" && opts.Type == "" && opts.SenderID == "" && len(opts.SenderIDs) == 0 && opts.Day == "" {
		_ = s.chat.MarkRead(r.Context(), id, userID)
	}
	writeJSON(w, http.StatusOK, map[string]any{"messages": list, "hasMore": hasMore})
}

func (s *Server) handleSearchMessages(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	q := r.URL.Query()
	opts := chat.ListMessagesOpts{
		Limit:     30,
		Before:    q.Get("before"),
		Day:       q.Get("day"),
		SenderID:  q.Get("senderId"),
		SenderIDs: splitCSV(q.Get("senderIds")),
	}
	list, hasMore, err := s.chat.SearchMessages(r.Context(), id, userID, opts, q.Get("q"))
	if err != nil {
		switch err.Error() {
		case "forbidden":
			writeErr(w, http.StatusForbidden, "forbidden")
		case "query required", "query too long", "invalid day":
			writeErr(w, http.StatusBadRequest, err.Error())
		default:
			writeErr(w, http.StatusInternalServerError, "search failed")
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"messages": list, "hasMore": hasMore})
}

func splitCSV(raw string) []string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func (s *Server) handleListMessageDays(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	days, err := s.chat.ListMessageDays(r.Context(), id, userID)
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"days": days})
}

func (s *Server) handleMessageContext(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	mid := r.PathValue("mid")
	list, err := s.chat.MessageContext(r.Context(), id, userID, mid, 25, 25)
	if err != nil {
		switch err.Error() {
		case "forbidden":
			writeErr(w, http.StatusForbidden, "forbidden")
		case "message not found":
			writeErr(w, http.StatusNotFound, "message not found")
		default:
			writeErr(w, http.StatusInternalServerError, "load failed")
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"messages": list})
}

func (s *Server) handleForwardMessages(w http.ResponseWriter, r *http.Request, userID string) {
	targetID := r.PathValue("id")
	var body struct {
		SourceConversationID string `json:"sourceConversationId"`
		MessageIDs           []string `json:"messageIds"`
		Mode                 string `json:"mode"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	mode := chat.ForwardMode(body.Mode)
	if mode == "" {
		mode = chat.ForwardOneByOne
	}
	list, err := s.chat.ForwardMessages(r.Context(), targetID, userID, body.SourceConversationID, body.MessageIDs, mode)
	if err != nil {
		switch err.Error() {
		case "forbidden":
			writeErr(w, http.StatusForbidden, "forbidden")
		case "invalid mode", "messageIds required", "too many messages",
			"cannot forward recalled", "unsupported message type", "message not found",
			"decrypt failed", "invalid image body", "invalid file body":
			writeErr(w, http.StatusBadRequest, err.Error())
		default:
			writeErr(w, http.StatusInternalServerError, "forward failed")
		}
		return
	}
	for i := range list {
		s.afterMessage(targetID, userID, &list[i])
	}
	writeJSON(w, http.StatusCreated, map[string]any{"messages": list})
}

func (s *Server) handleSendMessage(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	var body struct {
		Body string `json:"body"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	m, err := s.chat.SendText(r.Context(), id, userID, body.Body)
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	s.afterMessage(id, userID, m)
	writeJSON(w, http.StatusCreated, m)
}

func (s *Server) handleSendImage(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	if err := r.ParseMultipartForm(upload.MaxChatImageBytes + (1 << 20)); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid form")
		return
	}
	file, _, err := r.FormFile("file")
	if err != nil {
		writeErr(w, http.StatusBadRequest, "file required")
		return
	}
	defer file.Close()
	fileID := uuid.NewString()
	saved, err := upload.SaveChatImage(filepath.Join(s.uploadDir, "chat"), fileID, file)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	m, err := s.chat.SendImage(r.Context(), id, userID, chat.ImageBody{
		ThumbURL: saved.ThumbURL,
		URL:      saved.URL,
		Width:    saved.Width,
		Height:   saved.Height,
	})
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	s.afterMessage(id, userID, m)
	writeJSON(w, http.StatusCreated, m)
}

func (s *Server) handleSendFile(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	if err := r.ParseMultipartForm(upload.MaxChatFileBytes + (1 << 20)); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid form")
		return
	}
	file, hdr, err := r.FormFile("file")
	if err != nil {
		writeErr(w, http.StatusBadRequest, "file required")
		return
	}
	defer file.Close()
	name := ""
	mime := ""
	if hdr != nil {
		name = hdr.Filename
		mime = hdr.Header.Get("Content-Type")
	}
	fileID := uuid.NewString()
	saved, err := upload.SaveChatFile(filepath.Join(s.uploadDir, "chat"), fileID, name, mime, file)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	m, err := s.chat.SendFile(r.Context(), id, userID, chat.FileBody{
		URL:  saved.URL,
		Name: saved.Name,
		Size: saved.Size,
		Mime: saved.Mime,
	})
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	s.afterMessage(id, userID, m)
	writeJSON(w, http.StatusCreated, m)
}

func (s *Server) handleSendVoice(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	if err := r.ParseMultipartForm(upload.MaxChatVoiceBytes + (1 << 20)); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid form")
		return
	}
	file, hdr, err := r.FormFile("file")
	if err != nil {
		writeErr(w, http.StatusBadRequest, "file required")
		return
	}
	defer file.Close()
	dur, err := strconv.ParseFloat(strings.TrimSpace(r.FormValue("duration")), 64)
	if err != nil || dur < 0.3 {
		writeErr(w, http.StatusBadRequest, "invalid duration")
		return
	}
	if dur > float64(upload.MaxChatVoiceSec)+0.5 {
		writeErr(w, http.StatusBadRequest, "voice too long")
		return
	}
	mime := ""
	if hdr != nil {
		mime = hdr.Header.Get("Content-Type")
	}
	if mime == "" {
		mime = r.FormValue("mime")
	}
	fileID := uuid.NewString()
	saved, err := upload.SaveChatVoice(filepath.Join(s.uploadDir, "chat"), fileID, mime, file)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	m, err := s.chat.SendVoice(r.Context(), id, userID, chat.VoiceBody{
		URL:      saved.URL,
		Duration: dur,
		Size:     saved.Size,
		Mime:     saved.Mime,
	})
	if err != nil {
		if err.Error() == "forbidden" {
			writeErr(w, http.StatusForbidden, "forbidden")
			return
		}
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	s.afterMessage(id, userID, m)
	writeJSON(w, http.StatusCreated, m)
}

func (s *Server) handleRecallMessage(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	mid := r.PathValue("mid")
	m, err := s.chat.RecallMessage(r.Context(), id, userID, mid)
	if err != nil {
		switch err.Error() {
		case "forbidden":
			writeErr(w, http.StatusForbidden, "forbidden")
		case "recall expired":
			writeErr(w, http.StatusBadRequest, "recall expired")
		case "message not found":
			writeErr(w, http.StatusNotFound, "message not found")
		default:
			writeErr(w, http.StatusBadRequest, err.Error())
		}
		return
	}
	s.hub.Publish(id, map[string]any{"type": "message_recalled", "message": m})
	writeJSON(w, http.StatusOK, m)
}

func (s *Server) afterMessage(conversationID, userID string, m *chat.Message) {
	s.hub.Publish(conversationID, map[string]any{"type": "message", "message": m})
	if m != nil && m.Type == "system" {
		return
	}
	if s.qq == nil || !s.qq.Enabled() {
		return
	}
	members, _ := s.chat.MemberUserIDs(context.Background(), conversationID)
	senderName := s.chat.UsernameByID(context.Background(), userID)
	for _, mid := range members {
		if mid == userID {
			continue
		}
		uid := mid
		hint := senderName
		go s.qq.NotifyDoorbell(context.Background(), uid, hint)
	}
}

func (s *Server) withUploadCache(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		next.ServeHTTP(w, r)
	})
}

func (s *Server) handleQQStatus(w http.ResponseWriter, r *http.Request, userID string) {
	enabled := s.qq != nil && s.qq.Enabled()
	out := map[string]any{"botEnabled": enabled, "bound": false}
	if !enabled {
		writeJSON(w, http.StatusOK, out)
		return
	}
	b, err := s.qq.Store().GetByUserID(r.Context(), userID)
	if errors.Is(err, qqbot.ErrNotBound) {
		writeJSON(w, http.StatusOK, out)
		return
	}
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "load failed")
		return
	}
	out["bound"] = true
	out["doorbellEnabled"] = b.DoorbellEnabled
	out["boundAt"] = b.BoundAt.UTC().Format(time.RFC3339)
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) handleQQBindCode(w http.ResponseWriter, r *http.Request, userID string) {
	if s.qq == nil || !s.qq.Enabled() {
		writeErr(w, http.StatusServiceUnavailable, "qq_bot_disabled")
		return
	}
	code, expires, err := s.qq.Store().CreateBindCode(r.Context(), userID, 10*time.Minute)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "create failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"code":       code,
		"expiresAt":  expires.UTC().Format(time.RFC3339),
		"botAddHint": s.qq.AddHint(),
	})
}

func (s *Server) handleQQPatch(w http.ResponseWriter, r *http.Request, userID string) {
	if s.qq == nil || !s.qq.Enabled() {
		writeErr(w, http.StatusServiceUnavailable, "qq_bot_disabled")
		return
	}
	var body struct {
		DoorbellEnabled *bool `json:"doorbellEnabled"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := s.qq.Store().UpdateFlags(r.Context(), userID, body.DoorbellEnabled, nil, nil, nil); err != nil {
		if errors.Is(err, qqbot.ErrNotBound) {
			writeErr(w, http.StatusBadRequest, "not bound")
			return
		}
		writeErr(w, http.StatusInternalServerError, "update failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}

func (s *Server) handleQQUnbind(w http.ResponseWriter, r *http.Request, userID string) {
	if s.qq == nil || !s.qq.Enabled() {
		writeErr(w, http.StatusServiceUnavailable, "qq_bot_disabled")
		return
	}
	if err := s.qq.Store().Unbind(r.Context(), userID); err != nil {
		if errors.Is(err, qqbot.ErrNotBound) {
			writeErr(w, http.StatusBadRequest, "not bound")
			return
		}
		writeErr(w, http.StatusInternalServerError, "unbind failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}

func (s *Server) handleQQWebhook(w http.ResponseWriter, r *http.Request) {
	if s.qq == nil {
		http.Error(w, "disabled", http.StatusServiceUnavailable)
		return
	}
	s.qq.HandleWebhook(w, r)
}

func (s *Server) handleQQPublicMedia(w http.ResponseWriter, r *http.Request) {
	if s.qq == nil || s.qq.Media() == nil {
		http.NotFound(w, r)
		return
	}
	name := r.PathValue("name")
	raw, err := s.qq.Media().Read(name)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "image/png")
	w.Header().Set("Cache-Control", "public, max-age=300")
	_, _ = w.Write(raw)
}

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	convID := r.URL.Query().Get("conversationId")
	if token == "" || convID == "" {
		writeErr(w, http.StatusBadRequest, "token and conversationId required")
		return
	}
	userID, err := s.auth.ParseToken(token)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	ok, err := s.chat.IsMember(r.Context(), convID, userID)
	if err != nil || !ok {
		writeErr(w, http.StatusForbidden, "forbidden")
		return
	}
	conn, err := s.upg.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	s.hub.UserOnline(userID)
	defer s.hub.UserOffline(userID)

	ch := s.hub.Subscribe(convID)
	defer s.hub.Unsubscribe(convID, ch)

	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			if _, _, err := conn.ReadMessage(); err != nil {
				return
			}
		}
	}()

	for {
		select {
		case <-done:
			return
		case msg, ok := <-ch:
			if !ok {
				return
			}
			if err := conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		}
	}
}

type authedHandler func(http.ResponseWriter, *http.Request, string)

func (s *Server) withAuth(h authedHandler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		authz := r.Header.Get("Authorization")
		if !strings.HasPrefix(authz, "Bearer ") {
			writeErr(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		userID, err := s.auth.ParseToken(strings.TrimPrefix(authz, "Bearer "))
		if err != nil {
			writeErr(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		h(w, r, userID)
	}
}

type adminHandler func(http.ResponseWriter, *http.Request)

func (s *Server) withAdmin(h adminHandler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if s.adminToken == "" {
			writeErr(w, http.StatusServiceUnavailable, "admin disabled")
			return
		}
		authz := r.Header.Get("Authorization")
		token := strings.TrimPrefix(authz, "Bearer ")
		if !strings.HasPrefix(authz, "Bearer ") || token != s.adminToken {
			writeErr(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		h(w, r)
	}
}

func (s *Server) handleAdminListUsers(w http.ResponseWriter, r *http.Request) {
	list, err := s.admin.ListUsers(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"users": list})
}

func (s *Server) handleAdminDeleteUser(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := s.admin.DeleteUser(r.Context(), id); err != nil {
		if err.Error() == "user not found" {
			writeErr(w, http.StatusNotFound, "user not found")
			return
		}
		writeErr(w, http.StatusInternalServerError, "delete failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "deleted"})
}

func (s *Server) handleAdminPatchUser(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		FellowshipID   *string `json:"fellowshipId"`
		EmailVerified  *bool   `json:"emailVerified"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	if body.FellowshipID != nil {
		if err := s.admin.SetUserFellowship(r.Context(), id, *body.FellowshipID); err != nil {
			switch err.Error() {
			case "user not found":
				writeErr(w, http.StatusNotFound, "user not found")
			case "fellowship not found", "fellowship required":
				writeErr(w, http.StatusBadRequest, err.Error())
			default:
				writeErr(w, http.StatusInternalServerError, "update failed")
			}
			return
		}
	}
	if body.EmailVerified != nil {
		if err := s.admin.SetEmailVerified(r.Context(), id, *body.EmailVerified); err != nil {
			if err.Error() == "user not found" {
				writeErr(w, http.StatusNotFound, "user not found")
				return
			}
			writeErr(w, http.StatusInternalServerError, "update failed")
			return
		}
	}
	if body.FellowshipID == nil && body.EmailVerified == nil {
		writeErr(w, http.StatusBadRequest, "nothing to update")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "updated"})
}

func (s *Server) handleAdminListDomains(w http.ResponseWriter, r *http.Request) {
	list, err := s.admin.ListDomains(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"domains": list})
}

func (s *Server) handleAdminCreateDomain(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	d, err := s.admin.CreateDomain(r.Context(), body.Name)
	if err != nil {
		switch err.Error() {
		case "name required", "domain name taken":
			writeErr(w, http.StatusBadRequest, err.Error())
		default:
			writeErr(w, http.StatusInternalServerError, "create failed")
		}
		return
	}
	writeJSON(w, http.StatusCreated, d)
}

func (s *Server) handleAdminPatchDomain(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	d, err := s.admin.UpdateDomain(r.Context(), id, body.Name)
	if err != nil {
		switch err.Error() {
		case "domain not found":
			writeErr(w, http.StatusNotFound, "domain not found")
		case "name required", "domain name taken":
			writeErr(w, http.StatusBadRequest, err.Error())
		default:
			writeErr(w, http.StatusInternalServerError, "update failed")
		}
		return
	}
	writeJSON(w, http.StatusOK, d)
}

func (s *Server) handleAdminDeleteDomain(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := s.admin.DeleteDomain(r.Context(), id); err != nil {
		switch err.Error() {
		case "domain not found":
			writeErr(w, http.StatusNotFound, "domain not found")
		case "domain has fellowships":
			writeErr(w, http.StatusConflict, "domain has fellowships")
		default:
			writeErr(w, http.StatusInternalServerError, "delete failed")
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "deleted"})
}

func (s *Server) handleAdminListFellowships(w http.ResponseWriter, r *http.Request) {
	list, err := s.admin.ListFellowships(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"fellowships": list})
}

func (s *Server) handleAdminCreateFellowship(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Code     string `json:"code"`
		Name     string `json:"name"`
		DomainID string `json:"domainId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	f, err := s.admin.CreateFellowship(r.Context(), body.Code, body.Name, body.DomainID)
	if err != nil {
		switch err.Error() {
		case "code required", "domain required", "domain not found", "fellowship code taken":
			writeErr(w, http.StatusBadRequest, err.Error())
		default:
			writeErr(w, http.StatusInternalServerError, "create failed")
		}
		return
	}
	writeJSON(w, http.StatusCreated, f)
}

func (s *Server) handleAdminPatchFellowship(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		Code     string `json:"code"`
		Name     string `json:"name"`
		DomainID string `json:"domainId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	f, err := s.admin.UpdateFellowship(r.Context(), id, body.Code, body.Name, body.DomainID)
	if err != nil {
		switch err.Error() {
		case "fellowship not found":
			writeErr(w, http.StatusNotFound, "fellowship not found")
		case "code required", "domain required", "domain not found", "fellowship code taken":
			writeErr(w, http.StatusBadRequest, err.Error())
		default:
			writeErr(w, http.StatusInternalServerError, "update failed")
		}
		return
	}
	writeJSON(w, http.StatusOK, f)
}

func (s *Server) handleAdminDeleteFellowship(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := s.admin.DeleteFellowship(r.Context(), id); err != nil {
		switch err.Error() {
		case "fellowship not found":
			writeErr(w, http.StatusNotFound, "fellowship not found")
		case "fellowship has users":
			writeErr(w, http.StatusConflict, "fellowship has users")
		default:
			writeErr(w, http.StatusInternalServerError, "delete failed")
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "deleted"})
}

func (s *Server) handleAdminListQQBindings(w http.ResponseWriter, r *http.Request) {
	if s.qq == nil || !s.qq.Enabled() {
		writeJSON(w, http.StatusOK, map[string]any{
			"botEnabled": false,
			"bindings":   []any{},
		})
		return
	}
	list, err := s.qq.Store().ListBindings(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"botEnabled": true,
		"bindings":   list,
		"botAddHint": s.qq.AddHint(),
	})
}

func (s *Server) handleAdminQQBindCode(w http.ResponseWriter, r *http.Request) {
	if s.qq == nil || !s.qq.Enabled() {
		writeErr(w, http.StatusServiceUnavailable, "qq_bot_disabled")
		return
	}
	id := r.PathValue("id")
	ok, err := s.admin.UserExists(r.Context(), id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "lookup failed")
		return
	}
	if !ok {
		writeErr(w, http.StatusNotFound, "user not found")
		return
	}
	code, expires, err := s.qq.Store().CreateBindCode(r.Context(), id, 10*time.Minute)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "create bind code failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"code":       code,
		"expiresAt":  expires.UTC().Format(time.RFC3339),
		"botAddHint": s.qq.AddHint(),
	})
}

func (s *Server) handleAdminQQUnbind(w http.ResponseWriter, r *http.Request) {
	if s.qq == nil || !s.qq.Enabled() {
		writeErr(w, http.StatusServiceUnavailable, "qq_bot_disabled")
		return
	}
	id := r.PathValue("id")
	if err := s.qq.Store().Unbind(r.Context(), id); err != nil {
		if errors.Is(err, qqbot.ErrNotBound) {
			writeErr(w, http.StatusNotFound, "qq not bound")
			return
		}
		writeErr(w, http.StatusInternalServerError, "unbind failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "unbound"})
}

func (s *Server) handleAdminListConversations(w http.ResponseWriter, r *http.Request) {
	list, err := s.admin.ListConversations(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"conversations": list})
}

func (s *Server) handleAdminStats(w http.ResponseWriter, r *http.Request) {
	st, err := s.admin.Stats(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "stats failed")
		return
	}
	writeJSON(w, http.StatusOK, st)
}

func (s *Server) handleAdminGetGroup(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	detail, err := s.admin.GetGroupDetail(r.Context(), id)
	if err != nil {
		writeErr(w, http.StatusNotFound, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, detail)
}

func (s *Server) handleAdminPatchGroup(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		Title                  *string `json:"title"`
		JoinMode               *string `json:"joinMode"`
		InviteRequiresApproval *bool   `json:"inviteRequiresApproval"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	joinMode := body.JoinMode
	if joinMode == nil && body.InviteRequiresApproval != nil {
		mode := "anyone"
		if *body.InviteRequiresApproval {
			mode = "verify"
		}
		joinMode = &mode
	}
	c, err := s.admin.PatchGroup(r.Context(), id, joinMode, body.Title)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, c)
}

func (s *Server) handleAdminKickMember(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		MemberID string `json:"memberId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	targetName := s.chat.UsernameByID(r.Context(), body.MemberID)
	tip := "有人被管理员移出了群聊"
	if targetName != "" {
		tip = targetName + " 被管理员移出了群聊"
	}
	sender := ""
	if managers, _ := s.chat.GroupManagerIDs(r.Context(), id); len(managers) > 0 {
		sender = managers[0]
	} else if members, _ := s.chat.MemberUserIDs(r.Context(), id); len(members) > 0 {
		for _, mid := range members {
			if mid != body.MemberID {
				sender = mid
				break
			}
		}
	}
	if sender != "" {
		if m, err := s.chat.PostSystemMessage(r.Context(), id, sender, tip); err == nil && m != nil {
			s.afterMessage(id, sender, m)
		}
	}
	if err := s.admin.KickGroupMember(r.Context(), id, body.MemberID); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	s.hub.PublishToUser(body.MemberID, map[string]any{
		"type":           "group.kicked",
		"conversationId": id,
		"body":           "你已被管理员移出群聊",
	})
	writeJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}

func (s *Server) handleAdminSetMemberRole(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		MemberID string `json:"memberId"`
		Role     string `json:"role"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := s.admin.SetGroupMemberRole(r.Context(), id, body.MemberID, body.Role); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}

func (s *Server) handleAdminTransferOwner(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body struct {
		MemberID string `json:"memberId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	newName := s.chat.UsernameByID(r.Context(), body.MemberID)
	tip := "群主已变更"
	if newName != "" {
		tip = "群主已转让给 " + newName
	}
	sender := body.MemberID
	if managers, _ := s.chat.GroupManagerIDs(r.Context(), id); len(managers) > 0 {
		sender = managers[0]
	}
	if err := s.admin.TransferGroupOwner(r.Context(), id, body.MemberID); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if m, err := s.chat.PostSystemMessage(r.Context(), id, sender, tip); err == nil && m != nil {
		s.afterMessage(id, sender, m)
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}

func (s *Server) handleAdminListGroupJoins(w http.ResponseWriter, r *http.Request) {
	list, err := s.admin.ListPendingGroupJoins(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"requests": list})
}

func (s *Server) handleAdminAcceptGroupJoin(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	rid := r.PathValue("rid")
	var fromName string
	if detail, err := s.admin.GetGroupDetail(r.Context(), id); err == nil {
		for _, j := range detail.JoinRequests {
			if j.ID == rid {
				fromName = j.FromUsername
				break
			}
		}
	}
	if err := s.admin.AcceptGroupJoin(r.Context(), id, rid); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	tip := "有人加入了群聊"
	if fromName != "" {
		tip = fromName + " 加入了群聊"
	}
	sender := ""
	if managers, _ := s.chat.GroupManagerIDs(r.Context(), id); len(managers) > 0 {
		sender = managers[0]
	}
	if sender != "" {
		if m, err := s.chat.PostSystemMessage(r.Context(), id, sender, tip); err == nil && m != nil {
			s.afterMessage(id, sender, m)
		}
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "ok"})
}

func (s *Server) handleAdminRejectGroupJoin(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	rid := r.PathValue("rid")
	if err := s.admin.RejectGroupJoin(r.Context(), id, rid); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "rejected"})
}

func (s *Server) handleAdminDeleteConversation(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := s.admin.DeleteConversation(r.Context(), id); err != nil {
		if err.Error() == "conversation not found" {
			writeErr(w, http.StatusNotFound, "conversation not found")
			return
		}
		writeErr(w, http.StatusInternalServerError, "delete failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "deleted"})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if s := strings.TrimSpace(v); s != "" {
			return s
		}
	}
	return ""
}
