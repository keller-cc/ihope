package qqbot

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/middleware"
)

// HTTPHandler App 侧绑定 API + 公开媒体。
type HTTPHandler struct {
	svc   *Service
	media *MediaHost
}

func NewHTTPHandler(svc *Service, media *MediaHost) *HTTPHandler {
	return &HTTPHandler{svc: svc, media: media}
}

func (h *HTTPHandler) CreateBindCode(w http.ResponseWriter, r *http.Request) {
	if h.svc == nil || !h.svc.Enabled() {
		httpx.WriteError(w, http.StatusServiceUnavailable, "qq_bot_disabled", "QQ 机器人未启用")
		return
	}
	userID := middleware.UserIDFromContext(r.Context())
	code, expires, err := h.svc.store.CreateBindCode(r.Context(), userID, 10*time.Minute)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not create bind code")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"code":         code,
		"expires_at":   expires.UTC().Format(time.RFC3339),
		"bot_add_hint": h.svc.cfg.QQBotAddHint,
	})
}

func (h *HTTPHandler) Status(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	enabled := h.svc != nil && h.svc.Enabled()
	out := map[string]any{
		"bot_enabled": enabled,
		"bound":       false,
	}
	if !enabled {
		httpx.WriteJSON(w, http.StatusOK, out)
		return
	}
	b, err := h.svc.store.GetByUserID(r.Context(), userID)
	if errors.Is(err, ErrNotBound) {
		httpx.WriteJSON(w, http.StatusOK, out)
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not load binding")
		return
	}
	out["bound"] = true
	out["doorbell_enabled"] = b.DoorbellEnabled
	out["poetry_enabled"] = b.PoetryEnabled
	out["quotes_enabled"] = b.QuotesEnabled
	out["news_enabled"] = b.NewsEnabled
	out["bound_at"] = b.BoundAt.UTC().Format(time.RFC3339)
	httpx.WriteJSON(w, http.StatusOK, out)
}

type patchBody struct {
	DoorbellEnabled *bool `json:"doorbell_enabled"`
	PoetryEnabled   *bool `json:"poetry_enabled"`
	QuotesEnabled   *bool `json:"quotes_enabled"`
	NewsEnabled     *bool `json:"news_enabled"`
}

func (h *HTTPHandler) Patch(w http.ResponseWriter, r *http.Request) {
	if h.svc == nil || !h.svc.Enabled() {
		httpx.WriteError(w, http.StatusServiceUnavailable, "qq_bot_disabled", "QQ 机器人未启用")
		return
	}
	userID := middleware.UserIDFromContext(r.Context())
	var body patchBody
	if err := httpx.DecodeJSON(r, &body); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}
	if err := h.svc.store.UpdateFlags(r.Context(), userID, body.DoorbellEnabled, body.PoetryEnabled, body.QuotesEnabled, body.NewsEnabled); err != nil {
		if errors.Is(err, ErrNotBound) {
			httpx.WriteError(w, http.StatusBadRequest, "not_bound", "尚未绑定 QQ")
			return
		}
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "update failed")
		return
	}
	h.Status(w, r)
}

func (h *HTTPHandler) TodayQuote(w http.ResponseWriter, r *http.Request) {
	path := ""
	if h.svc != nil {
		path = h.svc.cfg.QQQuotesFilePath
	}
	if strings.TrimSpace(path) == "" {
		httpx.WriteError(w, http.StatusNotFound, "quotes_disabled", "金句未配置")
		return
	}
	entry, err := PickDailyQuoteEntry(path, time.Now())
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "quotes_error", "无法读取金句")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"body":   entry.Body,
		"author": entry.Author,
		"date":   time.Now().Format("2006-01-02"),
	})
}

func (h *HTTPHandler) Unbind(w http.ResponseWriter, r *http.Request) {
	if h.svc == nil || !h.svc.Enabled() {
		httpx.WriteError(w, http.StatusServiceUnavailable, "qq_bot_disabled", "QQ 机器人未启用")
		return
	}
	userID := middleware.UserIDFromContext(r.Context())
	if err := h.svc.store.Unbind(r.Context(), userID); err != nil && !errors.Is(err, ErrNotBound) {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "unbind failed")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (h *HTTPHandler) PublicMedia(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	raw, err := h.media.Read(name)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "image/png")
	w.Header().Set("Cache-Control", "public, max-age=300")
	_, _ = w.Write(raw)
}
