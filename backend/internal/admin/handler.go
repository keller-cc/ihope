// Package admin 运维 Web 管理 API（用户列表、禁用账号）。
package admin

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/user"
)

const adminServiceVersion = "0.1.0"

// OnlineChecker 判断设备 WebSocket 是否在线。
type OnlineChecker interface {
	IsDeviceOnline(userID, deviceID string) bool
}

type Handler struct {
	users        *user.Repository
	online       OnlineChecker
	refreshTTL   time.Duration
	started      time.Time
}

func NewHandler(users *user.Repository, online OnlineChecker, refreshTTL time.Duration) *Handler {
	return &Handler{users: users, online: online, refreshTTL: refreshTTL, started: time.Now().UTC()}
}

func (h *Handler) Stats(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	total, disabled, err := h.users.AdminCounts(ctx)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not load stats")
		return
	}
	pushTotal, pushByPlatform, err := h.users.AdminPushStats(ctx)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not load push stats")
		return
	}
	dbOK := h.users.Ping(ctx) == nil
	ttlDays := 0
	if h.refreshTTL > 0 {
		ttlDays = int(h.refreshTTL / (24 * time.Hour))
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"users_total":            total,
		"users_disabled":         disabled,
		"push_tokens":            pushTotal,
		"push_by_platform":       pushByPlatform,
		"refresh_token_ttl_days": ttlDays,
		"service": map[string]any{
			"ok":       dbOK,
			"version":  adminServiceVersion,
			"uptime_s": int(time.Since(h.started).Seconds()),
			"database": map[string]any{"ok": dbOK},
		},
	})
}

func (h *Handler) ListUsers(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query().Get("q")
	sortBy := r.URL.Query().Get("sort")
	sortOrder := r.URL.Query().Get("order")
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	total, err := h.users.CountForAdmin(r.Context(), q)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not count users")
		return
	}
	items, err := h.users.ListForAdmin(r.Context(), q, limit, offset, sortBy, sortOrder)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not list users")
		return
	}
	if items == nil {
		items = []user.AdminUser{}
	}
	respSort := strings.TrimSpace(sortBy)
	respOrder := strings.ToLower(strings.TrimSpace(sortOrder))
	if respSort == "" {
		respOrder = ""
	} else if respOrder != "desc" {
		respOrder = "asc"
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"users":  items,
		"total":  total,
		"limit":  clampLimit(limit),
		"offset": max(0, offset),
		"q":      q,
		"sort":   respSort,
		"order":  respOrder,
	})
}

func (h *Handler) GetUser(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_request", "missing user id")
		return
	}
	u, err := h.users.GetForAdmin(r.Context(), id)
	if err == user.ErrNotFound {
		httpx.WriteError(w, http.StatusNotFound, "not_found", "user not found")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not load user")
		return
	}
	h.applyOnlineStatus(id, u.Devices)
	h.applySessionState(u.Devices)
	httpx.WriteJSON(w, http.StatusOK, u)
}

func (h *Handler) applySessionState(devices []user.AdminDevice) {
	for i := range devices {
		devices[i].SessionState = deviceSessionState(devices[i], h.refreshTTL)
	}
}

func deviceSessionState(d user.AdminDevice, ttl time.Duration) string {
	if d.Online {
		return "online"
	}
	if !d.HasSession {
		return "none"
	}
	if ttl > 0 && time.Since(d.LastActiveAt) > ttl {
		return "idle"
	}
	return "logged_in"
}

func (h *Handler) applyOnlineStatus(userID string, devices []user.AdminDevice) {
	if h.online == nil {
		return
	}
	for i := range devices {
		devices[i].Online = h.online.IsDeviceOnline(userID, devices[i].DeviceID)
	}
}

func (h *Handler) DisableUser(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_request", "missing user id")
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

func (h *Handler) KickDevice(w http.ResponseWriter, r *http.Request) {
	userID := r.PathValue("id")
	deviceID := r.PathValue("deviceId")
	if userID == "" || deviceID == "" {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_request", "missing user or device id")
		return
	}
	if err := h.users.KickDevice(r.Context(), userID, deviceID); err != nil {
		if err == user.ErrNotFound {
			httpx.WriteError(w, http.StatusNotFound, "not_found", "device not found")
			return
		}
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not kick device")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func clampLimit(limit int) int {
	if limit <= 0 || limit > 200 {
		return 50
	}
	return limit
}
