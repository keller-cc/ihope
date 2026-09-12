package httpserver

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"github.com/gorilla/websocket"
	"github.com/keller-cc/ihope/appserver/internal/manila"
)

func (s *Server) handleManilaCreateRoom(w http.ResponseWriter, r *http.Request, userID string) {
	var body struct {
		MaxPlayers int  `json:"maxPlayers"`
		Private    bool `json:"private"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	name, err := s.manilaStore.Username(r.Context(), userID)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "user not found")
		return
	}
	room, err := s.manilaMgr.Create(r.Context(), userID, name, body.MaxPlayers, body.Private)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, room.Public())
}

func (s *Server) handleManilaListRooms(w http.ResponseWriter, r *http.Request, userID string) {
	_ = userID
	writeJSON(w, http.StatusOK, map[string]any{"rooms": s.manilaMgr.ListOpen()})
}

func (s *Server) handleManilaJoinRoom(w http.ResponseWriter, r *http.Request, userID string) {
	code := strings.ToLower(strings.TrimSpace(r.PathValue("code")))
	room := s.manilaMgr.GetByCode(code)
	if room == nil {
		writeErr(w, http.StatusNotFound, "room not found")
		return
	}
	name, err := s.manilaStore.Username(r.Context(), userID)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "user not found")
		return
	}
	if err := room.Join(userID, name); err != nil {
		writeErr(w, http.StatusConflict, err.Error())
		return
	}
	room.Broadcast()
	writeJSON(w, http.StatusOK, room.PublicFor(userID))
}

func (s *Server) handleManilaGetRoom(w http.ResponseWriter, r *http.Request, userID string) {
	code := strings.ToLower(strings.TrimSpace(r.PathValue("code")))
	room := s.manilaMgr.GetByCode(code)
	if room == nil {
		writeErr(w, http.StatusNotFound, "room not found")
		return
	}
	writeJSON(w, http.StatusOK, room.PublicFor(userID))
}

func (s *Server) handleManilaMyHistory(w http.ResponseWriter, r *http.Request, userID string) {
	limit := 30
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			limit = n
		}
	}
	list, err := s.manilaStore.ListResultsForUser(r.Context(), userID, limit)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"results": list})
}

func (s *Server) handleManilaWS(w http.ResponseWriter, r *http.Request) {
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
	roomID := r.PathValue("roomId")
	room := s.manilaMgr.GetByID(roomID)
	if room == nil {
		// also try code
		room = s.manilaMgr.GetByCode(strings.ToLower(roomID))
	}
	if room == nil {
		writeErr(w, http.StatusNotFound, "room not found")
		return
	}
	name, err := s.manilaStore.Username(r.Context(), userID)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "user not found")
		return
	}
	_ = room.Join(userID, name)

	conn, err := s.upg.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	ch, unsub := room.Subscribe(userID)
	defer unsub()
	room.Broadcast()

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
			if typ == "ping" {
				_ = conn.WriteMessage(websocket.TextMessage, []byte(`{"type":"pong"}`))
				continue
			}
			if err := room.ApplyAction(userID, msg); err != nil {
				_ = conn.WriteMessage(websocket.TextMessage, manila.EncodeError(err.Error()))
			}
		}
	}()

	for {
		select {
		case <-done:
			return
		case payload, ok := <-ch:
			if !ok {
				return
			}
			if err := conn.WriteMessage(websocket.TextMessage, payload); err != nil {
				return
			}
		}
	}
}
