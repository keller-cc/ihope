// Package admin 运维 Web 管理 API（用户列表、禁用账号）。
package admin

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/lifecycle"
	"github.com/ihope/ihope/internal/user"
)

// RuntimeConfig 来自 env 的运行时配置快照（只读；改 env 后需重启实例）。
type RuntimeConfig struct {
	Port                  string
	MaxEncryptedFileBytes int64
	CloudDriveURL         string
	ServerVersion         string
	DrainSeconds          int
	AppDownloadURL        string
}

func (h *Handler) configPayload() map[string]any {
	return map[string]any{
		"server_port":              h.cfg.Port,
		"max_encrypted_file_bytes": h.cfg.MaxEncryptedFileBytes,
		"cloud_drive_url":          h.cfg.CloudDriveURL,
		"server_version":           h.cfg.ServerVersion,
		"drain_seconds":            h.cfg.DrainSeconds,
		"app_download_url":         h.cfg.AppDownloadURL,
		"draining":                 lifecycle.IsDraining(),
	}
}

func (h *Handler) Config(w http.ResponseWriter, r *http.Request) {
	httpx.WriteJSON(w, http.StatusOK, h.configPayload())
}

func (h *Handler) Drain(w http.ResponseWriter, r *http.Request) {
	lifecycle.RequestDrain()
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"draining":      true,
		"drain_seconds": h.cfg.DrainSeconds,
	})
}

// OnlineChecker 判断设备 WebSocket 是否在线。
type OnlineChecker interface {
	IsDeviceOnline(userID, deviceID string) bool
}

type Handler struct {
	users      *user.Repository
	online     OnlineChecker
	refreshTTL time.Duration
	cfg        RuntimeConfig
	started    time.Time
}

func NewHandler(users *user.Repository, online OnlineChecker, refreshTTL time.Duration, cfg RuntimeConfig) *Handler {
	return &Handler{users: users, online: online, refreshTTL: refreshTTL, cfg: cfg, started: time.Now().UTC()}
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
		"config":                 h.configPayload(),
		"service": map[string]any{
			"ok":       dbOK,
			"version":  h.cfg.ServerVersion,
			"uptime_s": int(time.Since(h.started).Seconds()),
			"database": map[string]any{"ok": dbOK},
			"draining": lifecycle.IsDraining(),
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
