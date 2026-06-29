package ws

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
	"github.com/ihope/ihope/internal/message"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type Hub struct {
	mu    sync.RWMutex
	conns map[string]map[*Conn]struct{}
}

type Conn struct {
	hub      *Hub
	userID   string
	deviceID string
	ws       *websocket.Conn
	send     chan []byte
}

func NewHub() *Hub {
	return &Hub{conns: make(map[string]map[*Conn]struct{})}
}

func (h *Hub) Register(userID, deviceID string, ws *websocket.Conn) *Conn {
	c := &Conn{
		hub:      h,
		userID:   userID,
		deviceID: deviceID,
		ws:       ws,
		send:     make(chan []byte, 16),
	}
	h.mu.Lock()
	if h.conns[userID] == nil {
		h.conns[userID] = make(map[*Conn]struct{})
	}
	h.conns[userID][c] = struct{}{}
	h.mu.Unlock()
	go c.writePump()
	return c
}

func (c *Conn) Close() {
	c.hub.mu.Lock()
	if set, ok := c.hub.conns[c.userID]; ok {
		delete(set, c)
		if len(set) == 0 {
			delete(c.hub.conns, c.userID)
		}
	}
	c.hub.mu.Unlock()
	_ = c.ws.Close()
}

func (c *Conn) writePump() {
	for payload := range c.send {
		if err := c.ws.WriteMessage(websocket.TextMessage, payload); err != nil {
			return
		}
	}
}

func (h *Hub) NotifyMessage(memberUserIDs []string, msg *message.Message) {
	payload, err := json.Marshal(map[string]any{
		"event":   "message",
		"message": msg,
	})
	if err != nil {
		return
	}

	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, uid := range memberUserIDs {
		for c := range h.conns[uid] {
			select {
			case c.send <- payload:
			default:
				log.Printf("ws: drop message to user=%s device=%s (slow consumer)", c.userID, c.deviceID)
			}
		}
	}
}

func (h *Hub) SendJSON(c *Conn, v any) {
	payload, err := json.Marshal(v)
	if err != nil {
		return
	}
	select {
	case c.send <- payload:
	default:
	}
}
