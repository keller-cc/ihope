package user

import (
	"errors"
	"net/http"

	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/middleware"
)

// Handler 用户相关 HTTP 接口（当前仅 /api/users/me）。
type Handler struct {
	repo *Repository
}

func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

// Me GET /api/users/me — 返回 JWT 对应用户的公开资料。
func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	if userID == "" {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "missing user")
		return
	}

	u, err := h.repo.GetByID(r.Context(), userID)
	if errors.Is(err, ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not_found", "user not found")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not load user")
		return
	}

	httpx.WriteJSON(w, http.StatusOK, u)
}
