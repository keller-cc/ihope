// Package admin 运维 Web 管理 API（用户列表、禁用账号）。
package admin

import (
	"net/http"
	"strconv"

	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/middleware"
	"github.com/ihope/ihope/internal/user"
)

type Handler struct {
	users *user.Repository
}

func NewHandler(users *user.Repository) *Handler {
	return &Handler{users: users}
}

func (h *Handler) Stats(w http.ResponseWriter, r *http.Request) {
	total, disabled, err := h.users.AdminCounts(r.Context())
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not load stats")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"users_total":    total,
		"users_disabled": disabled,
	})
}

func (h *Handler) ListUsers(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	items, err := h.users.ListForAdmin(r.Context(), limit, offset)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not list users")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"users": items})
}

func (h *Handler) DisableUser(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_request", "missing user id")
		return
	}
	selfID := middleware.UserIDFromContext(r.Context())
	if id == selfID {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_request", "cannot disable yourself")
		return
	}
	if err := h.users.DisableUser(r.Context(), id); err != nil {
		if err == user.ErrNotFound {
			httpx.WriteError(w, http.StatusNotFound, "not_found", "user not found")
			return
		}
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not disable user")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) EnableUser(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_request", "missing user id")
		return
	}
	if err := h.users.EnableUser(r.Context(), id); err != nil {
		if err == user.ErrNotFound {
			httpx.WriteError(w, http.StatusNotFound, "not_found", "user not found")
			return
		}
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not enable user")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
