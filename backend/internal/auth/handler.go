// Package auth 注册、登录、刷新 Token、找回/重置密码。
package auth

import (
	"errors"
	"net/http"

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

// Register POST /api/auth/register — 注册新用户，返回 user（不含密码）。
func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}

	u, err := h.svc.Register(r.Context(), RegisterInput{
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

	httpx.WriteJSON(w, http.StatusCreated, map[string]any{"user": u})
}

// Login POST /api/auth/login — 验证邮箱密码，签发 access_token + refresh_token。
func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}

	resp, err := h.svc.Login(r.Context(), LoginInput{
		Email:      req.Email,
		Password:   req.Password,
		DeviceID:   req.DeviceID,
		DeviceName: req.DeviceName,
	})
	if errors.Is(err, ErrInvalidCredentials) {
		httpx.WriteError(w, http.StatusUnauthorized, "invalid_credentials", "invalid email or password")
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
