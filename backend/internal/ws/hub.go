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

// CloseAll 关停时主动断开全部 WebSocket，避免 http.Server.Shutdown 长时间阻塞。
func (h *Hub) CloseAll() {
	h.mu.Lock()
	var toClose []*Conn
	for _, set := range h.conns {
		for c := range set {
			toClose = append(toClose, c)
		}
	}
	h.mu.Unlock()
	for _, c := range toClose {
		_ = c.ws.Close()
	}
}

func (c *Conn) writePump() {
	for payload := range c.send {
		if err := c.ws.WriteMessage(websocket.TextMessage, payload); err != nil {
			return
		}
	}
}

func (h *Hub) IsDeviceOnline(userID, deviceID string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for c := range h.conns[userID] {
		if c.deviceID == deviceID {
			return true
		}
	}
	return false
}

func (h *Hub) NotifyMessage(memberUserIDs []string, msg *message.Message) {
	const wsCipherLimit = 24 * 1024
	wireMsg := any(msg)
	fetchRequired := false
	if len(msg.Ciphertext) > wsCipherLimit {
		light := *msg
		light.Ciphertext = ""
		wireMsg = &light
		fetchRequired = true
	}
	payload, err := json.Marshal(map[string]any{
		"event":          "message",
		"message":        wireMsg,
		"fetch_required": fetchRequired,
	})
	if err != nil {
		return
	}
	h.broadcast(memberUserIDs, payload)
}

func (h *Hub) NotifyEpochUpdated(memberUserIDs []string, conversationID string, epoch int) {
	payload, err := json.Marshal(map[string]any{
		"event":           "epoch_updated",
		"conversation_id": conversationID,
		"epoch":           epoch,
	})
	if err != nil {
		return
	}
	h.broadcast(memberUserIDs, payload)
}

func (h *Hub) NotifyGmkUpdated(memberUserIDs []string, conversationID, senderID string, epochs []int) {
	if len(epochs) == 0 {
		return
	}
	payload, err := json.Marshal(map[string]any{
		"event":           "gmk_updated",
		"conversation_id": conversationID,
		"sender_user_id":  senderID,
		"epochs":          epochs,
	})
	if err != nil {
		return
	}
	h.broadcast(memberUserIDs, payload)
}

func (h *Hub) NotifyGroupDissolved(memberUserIDs []string, conversationID, groupName, dissolvedBy string) {
	payload, err := json.Marshal(map[string]any{
		"event":           "group_dissolved",
		"conversation_id": conversationID,
		"group_name":      groupName,
		"dissolved_by":    dissolvedBy,
	})
	if err != nil {
		return
	}
	h.broadcast(memberUserIDs, payload)
}

func (h *Hub) NotifyConversationAdded(userIDs []string, conversation map[string]any) {
	payload, err := json.Marshal(map[string]any{
		"event":        "conversation_added",
		"conversation": conversation,
	})
	if err != nil {
		return
	}
	h.broadcast(userIDs, payload)
}

func (h *Hub) NotifyConversationRemoved(userIDs []string, conversationID string) {
	payload, err := json.Marshal(map[string]any{
		"event":           "conversation_removed",
		"conversation_id": conversationID,
	})
	if err != nil {
		return
	}
	h.broadcast(userIDs, payload)
}

func (h *Hub) NotifyConversationUpdated(userIDs []string, conversation map[string]any) {
	payload, err := json.Marshal(map[string]any{
		"event":        "conversation_updated",
		"conversation": conversation,
	})
	if err != nil {
		return
	}
	h.broadcast(userIDs, payload)
}

func (h *Hub) NotifyKeyRelay(targetUserID string, frame map[string]any) {
	payload, err := json.Marshal(frame)
	if err != nil {
		return
	}

	h.mu.RLock()
	defer h.mu.RUnlock()
	for c := range h.conns[targetUserID] {
		select {
		case c.send <- payload:
		default:
			log.Printf("ws: drop key_relay to user=%s device=%s (slow consumer)", c.userID, c.deviceID)
		}
	}
}

func (h *Hub) NotifyGmkRequest(memberUserIDs []string, requesterUserID string, frame map[string]any) {
	payload, err := json.Marshal(frame)
	if err != nil {
		return
	}

	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, uid := range memberUserIDs {
		if uid == requesterUserID {
			continue
		}
		for c := range h.conns[uid] {
			select {
			case c.send <- payload:
			default:
				log.Printf("ws: drop gmk_request to user=%s device=%s (slow consumer)", c.userID, c.deviceID)
			}
		}
	}
}

func (h *Hub) broadcast(memberUserIDs []string, payload []byte) {
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
