package devicelink

import (
	"errors"
	"net/http"

	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/middleware"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) Init(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	deviceID := middleware.DeviceIDFromContext(r.Context())
	if userID == "" || deviceID == "" {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "missing user or device")
		return
	}
	res, err := h.svc.Init(r.Context(), userID, deviceID)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not init device link")
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, res)
}

func (h *Handler) UploadPayload(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	deviceID := middleware.DeviceIDFromContext(r.Context())
	linkID := r.PathValue("id")
	if userID == "" || deviceID == "" || linkID == "" {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_request", "missing link id")
		return
	}
	var req struct {
		Ciphertext string `json:"ciphertext"`
	}
	if err := httpx.DecodeJSON(r, &req); err != nil || req.Ciphertext == "" {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "ciphertext required")
		return
	}
	if err := h.svc.UploadPayload(r.Context(), linkID, userID, deviceID, req.Ciphertext); err != nil {
		writeLinkError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) Complete(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	deviceID := middleware.DeviceIDFromContext(r.Context())
	if userID == "" || deviceID == "" {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "missing user or device")
		return
	}
	var req struct {
		Token string `json:"token"`
	}
	if err := httpx.DecodeJSON(r, &req); err != nil || req.Token == "" {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "token required")
		return
	}
	ciphertext, err := h.svc.Complete(r.Context(), userID, deviceID, req.Token)
	if err != nil {
		writeLinkError(w, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]string{"ciphertext": ciphertext})
}

func writeLinkError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrNotFound):
		httpx.WriteError(w, http.StatusNotFound, "not_found", "device link not found")
	case errors.Is(err, ErrExpired):
		httpx.WriteError(w, http.StatusGone, "expired", "device link expired")
	case errors.Is(err, ErrNotReady):
		httpx.WriteError(w, http.StatusConflict, "not_ready", "payload not uploaded yet")
	case errors.Is(err, ErrAlreadyUsed):
		httpx.WriteError(w, http.StatusConflict, "already_used", "device link already used")
	case errors.Is(err, ErrForbidden):
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "device link forbidden")
	default:
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "device link failed")
	}
}
