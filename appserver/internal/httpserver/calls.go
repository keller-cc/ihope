package httpserver

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/gorilla/websocket"
	"github.com/keller-cc/ihope/appserver/internal/call"
)

func (s *Server) handleStartCall(w http.ResponseWriter, r *http.Request, userID string) {
	if s.calls == nil {
		writeErr(w, http.StatusServiceUnavailable, "calls disabled")
		return
	}
	id := r.PathValue("id")
	var body struct {
		Kind string `json:"kind"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	room, err := s.calls.Start(r.Context(), id, userID, body.Kind)
	if err != nil {
		writeCallErr(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, room)
}

func (s *Server) handleActiveCall(w http.ResponseWriter, r *http.Request, userID string) {
	if s.calls == nil {
		writeErr(w, http.StatusServiceUnavailable, "calls disabled")
		return
	}
	room, err := s.calls.ActiveByConversation(r.Context(), r.PathValue("id"), userID)
	if err != nil {
		writeCallErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"call": room})
}

func (s *Server) handleIncomingCalls(w http.ResponseWriter, r *http.Request, userID string) {
	if s.calls == nil {
		writeErr(w, http.StatusServiceUnavailable, "calls disabled")
		return
	}
	_ = r
	list := s.calls.PendingInvites(userID)
	if list == nil {
		list = []*call.Room{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"calls": list})
}

func (s *Server) handleGetCall(w http.ResponseWriter, r *http.Request, userID string) {
	if s.calls == nil {
		writeErr(w, http.StatusServiceUnavailable, "calls disabled")
		return
	}
	room, err := s.calls.Get(r.PathValue("id"), userID)
	if err != nil {
		writeCallErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, room)
}

func (s *Server) handleAcceptCall(w http.ResponseWriter, r *http.Request, userID string) {
	if s.calls == nil {
		writeErr(w, http.StatusServiceUnavailable, "calls disabled")
		return
	}
	room, err := s.calls.Accept(r.Context(), r.PathValue("id"), userID)
	if err != nil {
		writeCallErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, room)
}

func (s *Server) handleRejectCall(w http.ResponseWriter, r *http.Request, userID string) {
	if s.calls == nil {
		writeErr(w, http.StatusServiceUnavailable, "calls disabled")
		return
	}
	if err := s.calls.Reject(r.Context(), r.PathValue("id"), userID); err != nil {
		writeCallErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) handleHangupCall(w http.ResponseWriter, r *http.Request, userID string) {
	if s.calls == nil {
		writeErr(w, http.StatusServiceUnavailable, "calls disabled")
		return
	}
	if err := s.calls.Hangup(r.Context(), r.PathValue("id"), userID); err != nil {
		writeCallErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) handleCallICE(w http.ResponseWriter, r *http.Request, userID string) {
	_ = userID
	if s.calls == nil {
		writeErr(w, http.StatusServiceUnavailable, "calls disabled")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"iceServers": s.calls.ICEServers()})
}

func writeCallErr(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, call.ErrNotFound):
		writeErr(w, http.StatusNotFound, err.Error())
	case errors.Is(err, call.ErrForbidden):
		writeErr(w, http.StatusForbidden, err.Error())
	case errors.Is(err, call.ErrBusy), errors.Is(err, call.ErrFull), errors.Is(err, call.ErrActiveExists),
		errors.Is(err, call.ErrEnded), errors.Is(err, call.ErrInvalidKind):
		writeErr(w, http.StatusConflict, err.Error())
	default:
		writeErr(w, http.StatusBadRequest, err.Error())
	}
}

func (s *Server) handleUserWS(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	if token == "" {
		writeErr(w, http.StatusBadRequest, "token required")
		return
	}
	userID, err := s.auth.ParseToken(token)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	conn, err := s.upg.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	s.hub.UserOnline(userID)
	defer s.hub.UserOffline(userID)
	if s.calls != nil {
		s.calls.OnUserConnect(userID)
		defer s.calls.OnUserDisconnect(userID)
	}

	ch := s.hub.SubscribeUser(userID)
	defer s.hub.UnsubscribeUser(userID, ch)

	// 订阅就绪后再补发未接来电，刚登录可看到接听/拒绝
	if s.calls != nil {
		s.calls.ResyncInvites(userID)
	}

	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			_, data, err := conn.ReadMessage()
			if err != nil {
				return
			}
			var msg map[string]any
			if err := json.Unmarshal(data, &msg); err != nil {
				continue
			}
			typ, _ := msg["type"].(string)
			switch typ {
			case "ping":
				_ = conn.WriteMessage(websocket.TextMessage, []byte(`{"type":"pong"}`))
			case "call.offer", "call.answer", "call.ice":
				if s.calls != nil {
					_ = s.calls.Relay(userID, msg)
				}
			case "call.media":
				if s.calls == nil {
					continue
				}
				callID, _ := msg["callId"].(string)
				var audioPtr, videoPtr *bool
				if v, ok := msg["audio"].(bool); ok {
					audioPtr = &v
				}
				if v, ok := msg["video"].(bool); ok {
					videoPtr = &v
				}
				_ = s.calls.SetMedia(callID, userID, audioPtr, videoPtr)
			}
		}
	}()

	for {
		select {
		case <-done:
			return
		case msg, ok := <-ch:
			if !ok {
				return
			}
			if err := conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		}
	}
}

func parseICEFromEnv(urls, user, pass string) []call.ICEServer {
	urls = strings.TrimSpace(urls)
	if urls == "" {
		return nil
	}
	parts := strings.Split(urls, ",")
	list := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			list = append(list, p)
		}
	}
	if len(list) == 0 {
		return nil
	}
	srv := call.ICEServer{URLs: list}
	if user != "" {
		srv.Username = user
		srv.Credential = pass
	}
	return []call.ICEServer{srv}
}
