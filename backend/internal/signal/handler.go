package signal

import (
	"errors"
	"net/http"
	"strings"

	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/middleware"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

type uploadKeysRequest struct {
	DeviceID         string         `json:"device_id"`
	SignalDeviceID   int            `json:"signal_device_id"`
	RegistrationID   int            `json:"registration_id"`
	IdentityKey     string         `json:"identity_key"`
	SignedPreKeyID  int            `json:"signed_pre_key_id"`
	SignedPreKey    string         `json:"signed_pre_key_public"`
	SignedPreKeySig string         `json:"signed_pre_key_signature"`
	OneTimePreKeys  []PreKeyUpload `json:"one_time_pre_keys"`
}

// UploadKeys PUT /api/users/me/signal-keys
func (h *Handler) UploadKeys(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	var req uploadKeysRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}

	err := h.svc.UploadKeys(r.Context(), userID, UploadInput{
		DeviceID:        strings.TrimSpace(req.DeviceID),
		SignalDeviceID:  req.SignalDeviceID,
		RegistrationID:  req.RegistrationID,
		IdentityKey:     strings.TrimSpace(req.IdentityKey),
		SignedPreKeyID:  req.SignedPreKeyID,
		SignedPreKey:    strings.TrimSpace(req.SignedPreKey),
		SignedPreKeySig: strings.TrimSpace(req.SignedPreKeySig),
		OneTimePreKeys:  req.OneTimePreKeys,
	})
	if errors.Is(err, ErrInvalidPayload) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "invalid signal keys")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not store signal keys")
		return
	}

	needs, _ := h.svc.NeedsPreKeyReplenish(r.Context(), userID, req.DeviceID)
	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"ok":                   true,
		"needs_pre_key_upload": needs,
	})
}

// GetUserBundle GET /api/users/{userId}/signal-bundle
func (h *Handler) GetUserBundle(w http.ResponseWriter, r *http.Request) {
	targetID := strings.TrimSpace(r.PathValue("userId"))
	if targetID == "" {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "missing user id")
		return
	}

	deviceID := strings.TrimSpace(r.URL.Query().Get("device_id"))
	var (
		bundle *PreKeyBundleResponse
		err    error
	)
	if deviceID != "" {
		bundle, err = h.svc.FetchBundle(r.Context(), targetID, deviceID)
	} else {
		bundle, err = h.svc.PickBundle(r.Context(), targetID)
	}
	if errors.Is(err, ErrNoDevice) {
		httpx.WriteError(w, http.StatusNotFound, "no_signal_device", "user has no signal keys")
		return
	}
	if errors.Is(err, ErrInvalidPayload) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "invalid bundle")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not fetch bundle")
		return
	}

	httpx.WriteJSON(w, http.StatusOK, bundle)
}

// ListDevices GET /api/users/{userId}/signal-devices
func (h *Handler) ListDevices(w http.ResponseWriter, r *http.Request) {
	targetID := strings.TrimSpace(r.PathValue("userId"))
	if targetID == "" {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "missing user id")
		return
	}

	ids, err := h.svc.ListDeviceIDs(r.Context(), targetID)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not list devices")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"device_ids": ids})
}
