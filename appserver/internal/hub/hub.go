package hub

import (
	"encoding/json"
	"sync"
)

type Hub struct {
	mu       sync.RWMutex
	subs     map[string]map[chan []byte]struct{} // conversationID -> chans
	userSubs map[string]map[chan []byte]struct{} // userID -> chans
	online   map[string]int
}

func New() *Hub {
	return &Hub{
		subs:     make(map[string]map[chan []byte]struct{}),
		userSubs: make(map[string]map[chan []byte]struct{}),
		online:   make(map[string]int),
	}
}

func (h *Hub) UserOnline(userID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.online[userID]++
}

func (h *Hub) UserOffline(userID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.online[userID] <= 1 {
		delete(h.online, userID)
		return
	}
	h.online[userID]--
}

func (h *Hub) IsUserOnline(userID string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return h.online[userID] > 0
}

func (h *Hub) Subscribe(conversationID string) chan []byte {
	ch := make(chan []byte, 64)
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.subs[conversationID] == nil {
		h.subs[conversationID] = make(map[chan []byte]struct{})
	}
	h.subs[conversationID][ch] = struct{}{}
	return ch
}

func (h *Hub) Unsubscribe(conversationID string, ch chan []byte) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if m := h.subs[conversationID]; m != nil {
		delete(m, ch)
		if len(m) == 0 {
			delete(h.subs, conversationID)
		}
	}
	close(ch)
}

func (h *Hub) Publish(conversationID string, v any) {
	b, err := json.Marshal(v)
	if err != nil {
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for ch := range h.subs[conversationID] {
		select {
		case ch <- b:
		default:
		}
	}
}

func (h *Hub) SubscribeUser(userID string) chan []byte {
	ch := make(chan []byte, 32)
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.userSubs[userID] == nil {
		h.userSubs[userID] = make(map[chan []byte]struct{})
	}
	h.userSubs[userID][ch] = struct{}{}
	return ch
}

func (h *Hub) UnsubscribeUser(userID string, ch chan []byte) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if m := h.userSubs[userID]; m != nil {
		delete(m, ch)
		if len(m) == 0 {
			delete(h.userSubs, userID)
		}
	}
	close(ch)
}

func (h *Hub) PublishToUser(userID string, v any) {
	b, err := json.Marshal(v)
	if err != nil {
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for ch := range h.userSubs[userID] {
		select {
		case ch <- b:
		default:
		}
	}
}

func (h *Hub) PublishToUsers(userIDs []string, v any) {
	b, err := json.Marshal(v)
	if err != nil {
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	seen := make(map[string]struct{}, len(userIDs))
	for _, uid := range userIDs {
		if uid == "" {
			continue
		}
		if _, ok := seen[uid]; ok {
			continue
		}
		seen[uid] = struct{}{}
		for ch := range h.userSubs[uid] {
			select {
			case ch <- b:
			default:
			}
		}
	}
}
