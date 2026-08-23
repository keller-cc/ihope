// Package auth 注册、登录、刷新 Token、找回/重置密码。
package auth

import (
	"errors"
	"fmt"
	"html"
	"net/http"
	"strings"

	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/middleware"
	"github.com/ihope/ihope/internal/user"
)

// Handler 处理 /api/auth/* 请求，委托 Service 执行业务逻辑。
type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

type registerRequest struct {
	Email             string `json:"email"`
	Username          string `json:"username"`
	Password          string `json:"password"`
	IdentityPublicKey string `json:"identity_public_key"`
}

type loginRequest struct {
	Login      string `json:"login"`
	Email      string `json:"email"`
	Password   string `json:"password"`
	DeviceID   string `json:"device_id"`
	DeviceName string `json:"device_name"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
	DeviceID     string `json:"device_id"`
}

type forgotPasswordRequest struct {
	Email string `json:"email"`
}

type resetPasswordRequest struct {
	Token    string `json:"token"`
	Password string `json:"password"`
}

type changePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}

// Register POST /api/auth/register — 注册新用户，发送验证邮件。
func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}

	result, err := h.svc.Register(r.Context(), RegisterInput{
		Email:             req.Email,
		Username:          req.Username,
		Password:          req.Password,
		IdentityPublicKey: req.IdentityPublicKey,
	})
	if err != nil {
		switch {
		case errors.Is(err, user.ErrEmailTaken):
			httpx.WriteError(w, http.StatusConflict, "email_taken", "email already registered")
		case errors.Is(err, user.ErrUsernameTaken):
			httpx.WriteError(w, http.StatusConflict, "username_taken", "username already taken")
		default:
			httpx.WriteError(w, http.StatusBadRequest, "validation_error", err.Error())
		}
		return
	}

	resp := map[string]any{
		"user":    result.User,
		"message": "verification email sent; check your inbox to activate",
	}
	if result.DevVerifyToken != "" {
		resp["dev_verify_token"] = result.DevVerifyToken
	}
	httpx.WriteJSON(w, http.StatusCreated, resp)
}

// Login POST /api/auth/login — 验证邮箱或用户名与密码，签发 access_token + refresh_token。
func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}

	resp, err := h.svc.Login(r.Context(), LoginInput{
		Login:      req.Login,
		Email:      req.Email,
		Password:   req.Password,
		DeviceID:   req.DeviceID,
		DeviceName: req.DeviceName,
	})
	if errors.Is(err, ErrInvalidCredentials) {
		httpx.WriteError(w, http.StatusUnauthorized, "invalid_credentials", "invalid account or password")
		return
	}
	if errors.Is(err, ErrAccountDisabled) {
		httpx.WriteError(w, http.StatusForbidden, "account_disabled", "account disabled")
		return
	}
	if errors.Is(err, ErrEmailNotVerified) {
		httpx.WriteError(w, http.StatusForbidden, "email_not_verified", "verify your email before signing in")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "login failed")
		return
	}

	httpx.WriteJSON(w, http.StatusOK, resp)
}

// Refresh POST /api/auth/refresh — 用 refresh_token 换取新的 token 对。
func (h *Handler) Refresh(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}

	resp, err := h.svc.Refresh(r.Context(), req.RefreshToken, req.DeviceID)
	if errors.Is(err, ErrInvalidRefresh) {
		httpx.WriteError(w, http.StatusUnauthorized, "invalid_refresh", "invalid refresh token")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "refresh failed")
		return
	}

	httpx.WriteJSON(w, http.StatusOK, resp)
}

// Logout POST /api/auth/logout — 清除当前设备的 refresh_token（需 access_token）。
func (h *Handler) Logout(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	deviceID := middleware.DeviceIDFromContext(r.Context())
	if userID == "" || deviceID == "" {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "missing user or device")
		return
	}
	if err := h.svc.Logout(r.Context(), userID, deviceID); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "logout failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type verifyEmailRequest struct {
	Token string `json:"token"`
}

type resendVerificationRequest struct {
	Email string `json:"email"`
}

// VerifyEmail GET /api/auth/verify-email?token= — 展示确认页，不立刻消耗 token（避免邮件扫描器误激活）。
func (h *Handler) VerifyEmail(w http.ResponseWriter, r *http.Request) {
	token := strings.TrimSpace(r.URL.Query().Get("token"))
	if token == "" {
		writeVerifyEmailHTML(w, http.StatusBadRequest, "缺少验证 token", false)
		return
	}
	writeVerifyEmailConfirmHTML(w, token)
}

// VerifyEmailJSON POST /api/auth/verify-email — App JSON 或邮件确认表单提交 token。
func (h *Handler) VerifyEmailJSON(w http.ResponseWriter, r *http.Request) {
	token, asHTML := readVerifyToken(r)
	if token == "" {
		if asHTML {
			writeVerifyEmailHTML(w, http.StatusBadRequest, "缺少验证 token", false)
			return
		}
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}
	if err := h.svc.VerifyEmail(r.Context(), token); errors.Is(err, ErrInvalidVerifyToken) {
		if asHTML {
			writeVerifyEmailHTML(w, http.StatusBadRequest, "链接无效或已过期", false)
			return
		}
		httpx.WriteError(w, http.StatusBadRequest, "invalid_token", "invalid or expired verification token")
		return
	} else if err != nil {
		if asHTML {
			writeVerifyEmailHTML(w, http.StatusInternalServerError, "验证失败，请稍后重试", false)
			return
		}
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "verification failed")
		return
	}
	if asHTML {
		writeVerifyEmailHTML(w, http.StatusOK, "邮箱已验证，可以返回 App 登录", true)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]string{"message": "email verified"})
}

func readVerifyToken(r *http.Request) (string, bool) {
	ct := strings.ToLower(r.Header.Get("Content-Type"))
	if strings.Contains(ct, "application/x-www-form-urlencoded") ||
		strings.Contains(ct, "multipart/form-data") {
		_ = r.ParseForm()
		return strings.TrimSpace(r.FormValue("token")), true
	}
	var req verifyEmailRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		return "", false
	}
	return strings.TrimSpace(req.Token), false
}

// ResendVerification POST /api/auth/resend-verification — 重发验证邮件。
func (h *Handler) ResendVerification(w http.ResponseWriter, r *http.Request) {
	var req resendVerificationRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}

	token, err := h.svc.ResendVerification(r.Context(), req.Email)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not process request")
		return
	}

	resp := map[string]string{"message": "if the email exists and is not verified, a verification link has been sent"}
	if token != "" {
		resp["dev_verify_token"] = token
	}
	httpx.WriteJSON(w, http.StatusOK, resp)
}

func writeVerifyEmailHTML(w http.ResponseWriter, status int, message string, ok bool) {
	title := "邮箱验证"
	if ok {
		title = "验证成功"
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(status)
	_, _ = fmt.Fprintf(w, `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>%s</title><style>body{font-family:system-ui,sans-serif;max-width:32rem;margin:4rem auto;padding:0 1rem;color:#0f172a}h1{font-size:1.5rem}p{line-height:1.6;color:#334155}</style></head><body><h1>%s</h1><p>%s</p></body></html>`, title, title, message)
}

func writeVerifyEmailConfirmHTML(w http.ResponseWriter, token string) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	safe := html.EscapeString(token)
	_, _ = fmt.Fprintf(w, `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>确认邮箱</title><style>body{font-family:system-ui,sans-serif;max-width:32rem;margin:4rem auto;padding:0 1rem;color:#0f172a}h1{font-size:1.5rem}p{line-height:1.6;color:#334155}button{margin-top:1rem;padding:.7rem 1.2rem;border:0;border-radius:.5rem;background:#2563eb;color:#fff;font-size:1rem;cursor:pointer}</style></head><body><h1>确认验证邮箱</h1><p>点击下方按钮完成邮箱验证，然后返回 App 登录。</p><form method="POST" action="/api/auth/verify-email"><input type="hidden" name="token" value="%s"><button type="submit">完成验证</button></form></body></html>`, safe)
}

// ForgotPassword POST /api/auth/forgot-password — 发重置邮件；邮箱不存在也返回 200。
func (h *Handler) ForgotPassword(w http.ResponseWriter, r *http.Request) {
	var req forgotPasswordRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}

	token, err := h.svc.ForgotPassword(r.Context(), req.Email)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not process request")
		return
	}

	resp := map[string]string{"message": "if the email exists, a reset link has been sent"}
	if token != "" {
		resp["dev_reset_token"] = token
	}
	httpx.WriteJSON(w, http.StatusOK, resp)
}

// ResetPassword POST /api/auth/reset-password — 用邮件 token 设置新密码，作废全部 refresh_token。
func (h *Handler) ResetPassword(w http.ResponseWriter, r *http.Request) {
	var req resetPasswordRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}

	if err := h.svc.ResetPassword(r.Context(), req.Token, req.Password); errors.Is(err, ErrInvalidResetToken) {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_token", "invalid or expired reset token")
		return
	} else if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "reset failed")
		return
	}

	httpx.WriteJSON(w, http.StatusOK, map[string]string{"message": "password updated"})
}

// ChangePassword POST /api/auth/change-password — 已登录用户修改密码，作废全部会话。
func (h *Handler) ChangePassword(w http.ResponseWriter, r *http.Request) {
	var req changePasswordRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}

	userID := middleware.UserIDFromContext(r.Context())
	if err := h.svc.ChangePassword(r.Context(), userID, req.CurrentPassword, req.NewPassword); errors.Is(err, ErrInvalidCredentials) {
		httpx.WriteError(w, http.StatusUnauthorized, "invalid_credentials", "invalid current password")
		return
	} else if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "password change failed")
		return
	}

	httpx.WriteJSON(w, http.StatusOK, map[string]string{"message": "password updated, please sign in again"})
}
