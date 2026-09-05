package httpserver

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"net/http"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/keller-cc/ihope/appserver/internal/admin"
	"github.com/keller-cc/ihope/appserver/internal/auth"
	"github.com/keller-cc/ihope/appserver/internal/chat"
	"github.com/keller-cc/ihope/appserver/internal/hub"
	"github.com/keller-cc/ihope/appserver/internal/qqbot"
	"github.com/keller-cc/ihope/appserver/internal/quotes"
	"github.com/keller-cc/ihope/appserver/internal/upload"
)

type Server struct {
	auth       *auth.Service
	chat       *chat.Service
	admin      *admin.Service
	hub        *hub.Hub
	qq         *qqbot.Service
	cors       string
	qqPath     string
	adminToken string
	uploadDir  string
	quotesPath string
	upg        websocket.Upgrader
}

func New(
	authSvc *auth.Service,
	chatSvc *chat.Service,
	adminSvc *admin.Service,
	h *hub.Hub,
	qq *qqbot.Service,
	corsOrigin, qqWebhookPath, adminToken, uploadDir, quotesPath string,
) *Server {
	return &Server{
		auth:       authSvc,
		chat:       chatSvc,
		admin:      adminSvc,
		hub:        h,
		qq:         qq,
		cors:       corsOrigin,
		qqPath:     qqWebhookPath,
		adminToken: strings.TrimSpace(adminToken),
		uploadDir:  uploadDir,
		quotesPath: strings.TrimSpace(quotesPath),
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
	mux.HandleFunc("POST /api/auth/register", s.handleRegister)
	mux.HandleFunc("POST /api/auth/login", s.handleLogin)
	mux.HandleFunc("POST /api/auth/resend-verification", s.handleResendVerification)
	mux.HandleFunc("GET /api/auth/verify-email", s.handleVerifyEmailGET)
	mux.HandleFunc("POST /api/auth/verify-email", s.handleVerifyEmailPOST)
	mux.HandleFunc("GET /api/me", s.withAuth(s.handleMe))
	mux.HandleFunc("PATCH /api/me", s.withAuth(s.handlePatchMe))
	mux.HandleFunc("POST /api/me/hope-id/refresh", s.withAuth(s.handleRefreshHopeID))
	mux.HandleFunc("POST /api/me/avatar", s.withAuth(s.handleUploadAvatar))
	mux.HandleFunc("PATCH /api/me/chat-bg", s.withAuth(s.handlePatchChatBg))
	mux.HandleFunc("POST /api/me/chat-bg", s.withAuth(s.handleUploadChatBg))
	mux.HandleFunc("GET /api/quotes/today", s.withAuth(s.handleTodayQuote))
	mux.HandleFunc("GET /api/search/users", s.withAuth(s.handleSearchUsers))
	mux.HandleFunc("GET /api/search/groups", s.withAuth(s.handleSearchGroups))
	mux.HandleFunc("GET /api/conversations", s.withAuth(s.handleListConversations))
	mux.HandleFunc("POST /api/conversations/dm", s.withAuth(s.handleCreateDM))
	mux.HandleFunc("POST /api/conversations/group", s.withAuth(s.handleCreateGroup))
	mux.HandleFunc("POST /api/conversations/group/join", s.withAuth(s.handleJoinGroup))
	mux.HandleFunc("GET /api/conversations/{id}/members", s.withAuth(s.handleListMembers))
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
	mux.HandleFunc("GET /api/conversations/{id}/messages", s.withAuth(s.handleListMessages))
	mux.HandleFunc("GET /api/conversations/{id}/messages/search", s.withAuth(s.handleSearchMessages))
	mux.HandleFunc("GET /api/conversations/{id}/messages/days", s.withAuth(s.handleListMessageDays))
	mux.HandleFunc("GET /api/conversations/{id}/messages/{mid}/context", s.withAuth(s.handleMessageContext))
	mux.HandleFunc("POST /api/conversations/{id}/messages", s.withAuth(s.handleSendMessage))
	mux.HandleFunc("POST /api/conversations/{id}/messages/image", s.withAuth(s.handleSendImage))
	mux.HandleFunc("POST /api/conversations/{id}/messages/file", s.withAuth(s.handleSendFile))
	mux.HandleFunc("POST /api/conversations/{id}/messages/forward", s.withAuth(s.handleForwardMessages))
	mux.HandleFunc("POST /api/conversations/{id}/messages/{mid}/recall", s.withAuth(s.handleRecallMessage))
	mux.HandleFunc("GET /api/contacts/friends", s.withAuth(s.handleListFriends))
	mux.HandleFunc("POST /api/contacts/friends", s.withAuth(s.handleAddFriend))
	mux.HandleFunc("PATCH /api/contacts/friends/{id}", s.withAuth(s.handleSetFriendRemark))
	mux.HandleFunc("GET /api/contacts/friend-requests", s.withAuth(s.handleListFriendRequests))
	mux.HandleFunc("POST /api/contacts/friend-requests/{id}/accept", s.withAuth(s.handleAcceptFriendRequest))
	mux.HandleFunc("POST /api/contacts/friend-requests/{id}/reject", s.withAuth(s.handleRejectFriendRequest))
	mux.HandleFunc("GET /api/contacts/groups", s.withAuth(s.handleListGroups))
	mux.Handle("/uploads/", s.withUploadCache(http.StripPrefix("/uploads/", http.FileServer(http.Dir(s.uploadDir)))))
	mux.HandleFunc("GET /api/me/qq-bot", s.withAuth(s.handleQQStatus))
	mux.HandleFunc("POST /api/me/qq-bot/bind-code", s.withAuth(s.handleQQBindCode))
	mux.HandleFunc("PATCH /api/me/qq-bot", s.withAuth(s.handleQQPatch))
	mux.HandleFunc("DELETE /api/me/qq-bot", s.withAuth(s.handleQQUnbind))
	mux.HandleFunc("GET /api/admin/users", s.withAdmin(s.handleAdminListUsers))
	mux.HandleFunc("DELETE /api/admin/users/{id}", s.withAdmin(s.handleAdminDeleteUser))
	mux.HandleFunc("POST /api/admin/users/{id}/qq-bind-code", s.withAdmin(s.handleAdminQQBindCode))
	mux.HandleFunc("DELETE /api/admin/users/{id}/qq-bot", s.withAdmin(s.handleAdminQQUnbind))
	mux.HandleFunc("GET /api/admin/qq-bindings", s.withAdmin(s.handleAdminListQQBindings))
	mux.HandleFunc("GET /api/admin/conversations", s.withAdmin(s.handleAdminListConversations))
	mux.HandleFunc("DELETE /api/admin/conversations/{id}", s.withAdmin(s.handleAdminDeleteConversation))
	if s.qqPath != "" {
		mux.HandleFunc("POST "+s.qqPath, s.handleQQWebhook)
	}
	mux.HandleFunc("GET /ws", s.handleWS)
	return s.corsMiddleware(mux)
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
			writeErr(w, http.StatusForbidden, "email_not_verified")
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
	dev, err := s.auth.ResendVerification(r.Context(), body.Email)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "resend failed")
		return
	}
	out := map[string]any{
		"message": "if the email exists and is not verified, a verification link has been sent",
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
		switch {
		case errors.Is(err, auth.ErrHopeIDCooldown):
			writeErr(w, http.StatusTooManyRequests, "hope id cooldown")
		default:
			writeErr(w, http.StatusInternalServerError, "refresh hope id failed")
		}
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
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	c, err := s.chat.JoinGroupByNo(r.Context(), userID, body.GroupNo)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, c)
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
		Title string `json:"title"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	c, err := s.chat.RenameGroup(r.Context(), id, userID, body.Title)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, c)
}

func (s *Server) handleLeaveGroup(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
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
	c, err := s.chat.InviteToGroup(r.Context(), id, userID, body.MemberIDs)
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

func (s *Server) handleKickMember(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	var body struct {
		MemberID string `json:"memberId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := s.chat.KickFromGroup(r.Context(), id, userID, body.MemberID); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
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

func (s *Server) handlePatchChatBg(w http.ResponseWriter, r *http.Request, userID string) {
	var body auth.ChatBg
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	u, err := s.auth.SetChatBg(r.Context(), userID, &body)
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
	u, err := s.auth.SetChatBg(r.Context(), userID, &auth.ChatBg{Kind: "image", URL: url})
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "save failed")
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
		Limit:    50,
		Before:   before,
		Type:     q.Get("type"),
		SenderID: q.Get("senderId"),
		Day:      q.Get("day"),
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
	if before == "" && opts.Type == "" && opts.SenderID == "" && opts.Day == "" {
		_ = s.chat.MarkRead(r.Context(), id, userID)
	}
	writeJSON(w, http.StatusOK, map[string]any{"messages": list, "hasMore": hasMore})
}

func (s *Server) handleSearchMessages(w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	q := r.URL.Query()
	list, hasMore, err := s.chat.SearchMessages(r.Context(), id, userID, q.Get("q"), 30, q.Get("before"))
	if err != nil {
		switch err.Error() {
		case "forbidden":
			writeErr(w, http.StatusForbidden, "forbidden")
		case "query required", "query too long":
			writeErr(w, http.StatusBadRequest, err.Error())
		default:
			writeErr(w, http.StatusInternalServerError, "search failed")
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"messages": list, "hasMore": hasMore})
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
