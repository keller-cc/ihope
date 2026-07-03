package ws

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/ihope/ihope/internal/conversation"
	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/jwt"
	"github.com/ihope/ihope/internal/message"
	"github.com/ihope/ihope/internal/middleware"
)

type Handler struct {
	hub        *Hub
	msgNotify  message.Notifier
	jwt        *jwt.Manager
	lookup     middleware.TokenVersionLookup
	convSvc    *conversation.Service
	msgSvc     *message.Service
}

func NewHandler(
	hub *Hub,
	msgNotify message.Notifier,
	jwtMgr *jwt.Manager,
	lookup middleware.TokenVersionLookup,
	convSvc *conversation.Service,
	msgSvc *message.Service,
) *Handler {
	return &Handler{
		hub:       hub,
		msgNotify: msgNotify,
		jwt:       jwtMgr,
		lookup:    lookup,
		convSvc:   convSvc,
		msgSvc:    msgSvc,
	}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	token := strings.TrimSpace(r.URL.Query().Get("token"))
	if token == "" {
		auth := r.Header.Get("Authorization")
		if strings.HasPrefix(auth, "Bearer ") {
			token = strings.TrimSpace(strings.TrimPrefix(auth, "Bearer "))
		}
	}
	if token == "" {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "missing token")
		return
	}

	claims, err := h.jwt.ParseAccessToken(token)
	if err != nil {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "invalid or expired token")
		return
	}
	version, err := h.lookup.GetTokenVersion(r.Context(), claims.UserID)
	if err != nil || version != claims.TokenVersion {
		httpx.WriteError(w, http.StatusUnauthorized, "session_revoked", "session expired, please sign in again")
		return
	}

	wsConn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}

	conn := h.hub.Register(claims.UserID, claims.DeviceID, wsConn)
	defer conn.Close()

	for {
		_, data, err := wsConn.ReadMessage()
		if err != nil {
			return
		}
		h.handleFrame(r, conn, claims.UserID, data)
	}
}

func (h *Handler) handleFrame(r *http.Request, c *Conn, userID string, data []byte) {
	var frame struct {
		Event          string `json:"event"`
		ConversationID string `json:"conversation_id"`
		Type           string `json:"type"`
		Ciphertext     string `json:"ciphertext"`
		TargetUserID   string `json:"target_user_id"`
		PayloadType    string `json:"payload_type"`
		Epoch          int    `json:"epoch"`
		Epochs         []int  `json:"epochs"`
	}
	if err := json.Unmarshal(data, &frame); err != nil {
		h.hub.SendJSON(c, map[string]string{"event": "error", "error": "invalid_json"})
		return
	}

	switch frame.Event {
	case "join":
		if frame.ConversationID == "" {
			h.hub.SendJSON(c, map[string]string{"event": "error", "error": "missing conversation_id"})
			return
		}
		if _, err := h.convSvc.GetIfMember(r.Context(), frame.ConversationID, userID); err != nil {
			h.hub.SendJSON(c, map[string]string{"event": "error", "error": "forbidden"})
			return
		}
		h.hub.SendJSON(c, map[string]any{"event": "joined", "conversation_id": frame.ConversationID})

	case "gmk_request":
		if frame.ConversationID == "" {
			h.hub.SendJSON(c, map[string]string{"event": "error", "error": "missing conversation_id"})
			return
		}
		conv, err := h.convSvc.GetIfMember(r.Context(), frame.ConversationID, userID)
		if err != nil {
			h.hub.SendJSON(c, map[string]string{"event": "error", "error": "forbidden"})
			return
		}
		if conv.Type != "group" {
			h.hub.SendJSON(c, map[string]string{"event": "error", "error": "not_group"})
			return
		}
		epochs := frame.Epochs
		if len(epochs) == 0 {
			epoch := frame.Epoch
			if epoch <= 0 {
				epoch = conv.Epoch
			}
			epochs = []int{epoch}
		}
		ids, err := h.convSvc.MemberUserIDs(r.Context(), frame.ConversationID)
		if err != nil || len(ids) == 0 {
			h.hub.SendJSON(c, map[string]string{"event": "error", "error": "no_members"})
			return
		}
		h.hub.NotifyGmkRequest(ids, userID, map[string]any{
			"event":             "gmk_request",
			"conversation_id":   frame.ConversationID,
			"requester_user_id": userID,
			"epochs":            epochs,
		})
		h.hub.SendJSON(c, map[string]any{"event": "gmk_requested", "epochs": epochs})

	case "key_relay":
		if frame.ConversationID == "" || frame.TargetUserID == "" || strings.TrimSpace(frame.Ciphertext) == "" {
			h.hub.SendJSON(c, map[string]string{"event": "error", "error": "invalid_key_relay"})
			return
		}
		if _, err := h.convSvc.GetIfMember(r.Context(), frame.ConversationID, userID); err != nil {
			h.hub.SendJSON(c, map[string]string{"event": "error", "error": "forbidden"})
			return
		}
		ok, err := h.convSvc.IsActiveMember(r.Context(), frame.ConversationID, frame.TargetUserID)
		if err != nil || !ok {
			h.hub.SendJSON(c, map[string]string{"event": "error", "error": "invalid_target"})
			return
		}
		payloadType := strings.TrimSpace(frame.PayloadType)
		if payloadType == "" {
			payloadType = "welcome_bundle"
		}
		h.hub.NotifyKeyRelay(frame.TargetUserID, map[string]any{
			"event":           "key_relay",
			"conversation_id": frame.ConversationID,
			"from_user_id":    userID,
			"target_user_id":  frame.TargetUserID,
			"payload_type":    payloadType,
			"ciphertext":      frame.Ciphertext,
		})
		h.hub.SendJSON(c, map[string]any{"event": "relayed", "target_user_id": frame.TargetUserID})

	case "send":
		msg, err := h.msgSvc.Send(r.Context(), message.SendInput{
			ConversationID: frame.ConversationID,
			SenderID:       userID,
			Type:           frame.Type,
			Ciphertext:     frame.Ciphertext,
		})
		if errors.Is(err, message.ErrNotMember) {
			h.hub.SendJSON(c, map[string]string{"event": "error", "error": "forbidden"})
			return
		}
		if errors.Is(err, message.ErrInvalidInput) {
			h.hub.SendJSON(c, map[string]string{"event": "error", "error": "invalid_message"})
			return
		}
		if err != nil {
			h.hub.SendJSON(c, map[string]string{"event": "error", "error": "send_failed"})
			return
		}
		if ids, err := h.convSvc.MemberUserIDs(r.Context(), frame.ConversationID); err == nil && h.msgNotify != nil {
			h.msgNotify.NotifyMessage(ids, msg)
		}
		h.hub.SendJSON(c, map[string]any{"event": "sent", "message": msg})

	default:
		h.hub.SendJSON(c, map[string]string{"event": "error", "error": "unknown_event"})
	}
}
