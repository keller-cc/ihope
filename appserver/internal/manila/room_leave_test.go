package manila

import (
	"testing"
	"time"
)

func TestWaitingRoomDissolvesWhenLastMemberLeaves(t *testing.T) {
	mgr := NewManager(nil)
	r := &Room{
		ID: "r1", Code: "abc", HostUserID: "u1", Status: "open",
		MaxPlayers: 4, Members: []PlayerView{{UserID: "u1", Username: "a", Seat: 0, IsHost: true}},
		subs: map[string][]*subscriber{}, manager: mgr, createdAt: time.Now(),
	}
	mgr.mu.Lock()
	mgr.rooms[r.ID] = r
	mgr.codes[r.Code] = r
	mgr.mu.Unlock()

	if err := r.ApplyAction("u1", map[string]any{"type": "leave"}); err != nil {
		t.Fatal(err)
	}
	time.Sleep(30 * time.Millisecond)
	if got := mgr.GetByID("r1"); got != nil {
		t.Fatalf("expected room removed, still present status=%s members=%d", got.Status, len(got.Members))
	}
}

func TestPlayingRoomKeepsSeatOnLeave(t *testing.T) {
	mgr := NewManager(nil)
	r := &Room{
		ID: "r2", Code: "def", HostUserID: "u1", Status: "playing",
		MaxPlayers: 4,
		Members: []PlayerView{
			{UserID: "u1", Username: "a", Seat: 0, Connected: true},
			{UserID: "u2", Username: "b", Seat: 1, Connected: true},
			{UserID: "u3", Username: "c", Seat: 2, Connected: true},
		},
		// Non-nil Match so leave path can update Connected without dissolving.
		Match: &Match{Phase: PhaseAuction},
		subs:  map[string][]*subscriber{}, manager: mgr, createdAt: time.Now(),
	}
	mgr.mu.Lock()
	mgr.rooms[r.ID] = r
	mgr.codes[r.Code] = r
	mgr.mu.Unlock()

	if err := r.ApplyAction("u2", map[string]any{"type": "leave"}); err != nil {
		t.Fatal(err)
	}
	time.Sleep(30 * time.Millisecond)
	got := mgr.GetByID("r2")
	if got == nil {
		t.Fatal("playing room must not dissolve")
	}
	if len(got.Members) != 3 {
		t.Fatalf("members want 3 got %d", len(got.Members))
	}
	for _, m := range got.Members {
		if m.UserID == "u2" && m.Connected {
			t.Fatal("leaver should be marked disconnected")
		}
	}
}
