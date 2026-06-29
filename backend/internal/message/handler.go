package message

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/ihope/ihope/internal/conversation"
	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/middleware"
)

// Notifier 新消息推送给在线用户（WebSocket）。
type Notifier interface {
	NotifyMessage(memberUserIDs []string, msg *Message)
}

type Handler struct {
	svc      *Service
	convSvc  *conversation.Service
	notifier Notifier
}

func NewHandler(svc *Service, convSvc *conversation.Service, notifier Notifier) *Handler {
	return &Handler{svc: svc, convSvc: convSvc, notifier: notifier}
}

type sendRequest struct {
	Type       string `json:"type"`
	Ciphertext string `json:"ciphertext"`
}

// List GET /api/conversations/{id}/messages
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	conversationID := r.PathValue("id")
	userID := middleware.UserIDFromContext(r.Context())

	limit := DefaultLimit
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			limit = n
		}
	}

	msgs, hasMore, err := h.svc.List(r.Context(), conversationID, userID, r.URL.Query().Get("before"), limit)
	if errors.Is(err, ErrNotMember) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "not a conversation member")
		return
	}
	if errors.Is(err, ErrNotFound) {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_before", "invalid before message id")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not list messages")
		return
	}

	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"messages":  msgs,
		"has_more":  hasMore,
	})
}

// Send POST /api/conversations/{id}/messages
func (h *Handler) Send(w http.ResponseWriter, r *http.Request) {
	conversationID := r.PathValue("id")
	userID := middleware.UserIDFromContext(r.Context())

	var req sendRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}

	msg, err := h.svc.Send(r.Context(), SendInput{
		ConversationID: conversationID,
		SenderID:       userID,
		Type:           req.Type,
		Ciphertext:     req.Ciphertext,
	})
	if errors.Is(err, ErrNotMember) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "not a conversation member")
		return
	}
	if errors.Is(err, ErrInvalidInput) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "invalid message")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not send message")
		return
	}

	if h.notifier != nil {
		if ids, err := h.convSvc.MemberUserIDs(r.Context(), conversationID); err == nil {
			h.notifier.NotifyMessage(ids, msg)
		}
	}

	httpx.WriteJSON(w, http.StatusCreated, map[string]any{"message": msg})
}
