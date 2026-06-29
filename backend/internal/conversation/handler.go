package conversation

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

type createRequest struct {
	Type       string   `json:"type"`
	PeerUserID string   `json:"peer_user_id"`
	Name       string   `json:"name"`
	MemberIDs  []string `json:"member_ids"`
}

// List GET /api/conversations
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	items, err := h.svc.List(r.Context(), userID)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not list conversations")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"conversations": items})
}

// Create POST /api/conversations
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var req createRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}

	userID := middleware.UserIDFromContext(r.Context())
	item, err := h.svc.Create(r.Context(), userID, CreateInput{
		Type:       req.Type,
		PeerUserID: req.PeerUserID,
		Name:       req.Name,
		MemberIDs:  req.MemberIDs,
	})
	if errors.Is(err, ErrInvalidInput) || errors.Is(err, ErrInvalidPeer) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	if errors.Is(err, ErrPeerNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "user_not_found", "user not found")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not create conversation")
		return
	}

	httpx.WriteJSON(w, http.StatusCreated, map[string]any{"conversation": item})
}
