package emailnotify

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestScopeAllows(t *testing.T) {
	listed := map[string]bool{"c1": true}
	cases := []struct {
		scope, typ, id string
		want           bool
	}{
		{ScopeAll, "dm", "x", true},
		{ScopeDMOnly, "dm", "x", true},
		{ScopeDMOnly, "group", "x", false},
		{ScopeGroupOnly, "group", "x", true},
		{ScopeInclude, "dm", "c1", true},
		{ScopeInclude, "dm", "c2", false},
		{ScopeExclude, "dm", "c1", false},
		{ScopeExclude, "dm", "c2", true},
	}
	for _, tc := range cases {
		if got := ScopeAllows(tc.scope, tc.typ, tc.id, listed); got != tc.want {
			t.Fatalf("%s typ=%s id=%s got %v want %v", tc.scope, tc.typ, tc.id, got, tc.want)
		}
	}
}

func TestChannelOpen(t *testing.T) {
	if ChannelOpen(true, false, true, ModeFirstDaily) {
		t.Fatal("online should block")
	}
	if ChannelOpen(false, true, true, ModeFirstDaily) {
		t.Fatal("qq suppress should block")
	}
	if ChannelOpen(false, false, false, ModeFirstDaily) {
		t.Fatal("disabled should block")
	}
	if ChannelOpen(false, false, true, ModeOff) {
		t.Fatal("mode off should block")
	}
	if !ChannelOpen(false, false, true, ModeEvery) {
		t.Fatal("expected open")
	}
}

func TestEffectiveStatus(t *testing.T) {
	if EffectiveStatus(false, true, true, ModeFirstDaily) != EffectivePausedByQQ {
		t.Fatal("want paused_by_qq")
	}
	if EffectiveStatus(false, false, false, ModeFirstDaily) != EffectiveDisabled {
		t.Fatal("want disabled")
	}
	if EffectiveStatus(false, false, true, ModeFirstDaily) != EffectiveActive {
		t.Fatal("want active")
	}
}

type fakeMailer struct {
	chat   []string
	batch  []int
	social []string
	err    error
}

func (m *fakeMailer) SendMessageReminder(to, senderHint, appURL string) error {
	m.chat = append(m.chat, senderHint)
	return m.err
}
func (m *fakeMailer) SendBatchMessageReminder(to string, count int, hints []string, appURL string) error {
	m.batch = append(m.batch, count)
	return m.err
}
func (m *fakeMailer) SendSocialReminder(to, text, appURL string) error {
	m.social = append(m.social, text)
	return m.err
}

type fakeOnline map[string]bool

func (o fakeOnline) IsUserOnline(userID string) bool { return o[userID] }

type fakeQQ map[string]bool

func (q fakeQQ) SuppressEmail(_ context.Context, userID string) (bool, error) {
	return q[userID], nil
}

type fakeChat struct {
	muted map[string]bool
	typ   map[string]string
}

func (c fakeChat) IsMemberMuted(_ context.Context, conversationID, userID string) bool {
	return c.muted[conversationID+":"+userID]
}
func (c fakeChat) ConversationType(_ context.Context, conversationID string) (string, error) {
	if t, ok := c.typ[conversationID]; ok {
		return t, nil
	}
	return "dm", nil
}

type memPrefStore struct {
	prefs    Prefs
	verified bool
	email    string
	lastOn   *time.Time
	lastAt   *time.Time
	pending  int
	hints    []string
	releaseN int
}

func (m *memPrefStore) GetPrefs(_ context.Context, _ string) (Prefs, error) {
	return NormalizePrefs(m.prefs), nil
}
func (m *memPrefStore) SavePrefs(_ context.Context, _ string, p Prefs) (Prefs, error) {
	m.prefs = NormalizePrefs(p)
	return m.prefs, nil
}
func (m *memPrefStore) EmailVerified(_ context.Context, _ string) (bool, error) {
	return m.verified, nil
}
func (m *memPrefStore) AcquireChatSend(_ context.Context, _ string, prefs Prefs, now time.Time, hint string) (chatAcquire, error) {
	prefs = NormalizePrefs(prefs)
	if !m.verified || m.email == "" {
		return chatAcquire{}, nil
	}
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	switch prefs.Mode {
	case ModeFirstDaily:
		if m.lastOn != nil {
			lo := time.Date(m.lastOn.Year(), m.lastOn.Month(), m.lastOn.Day(), 0, 0, 0, 0, today.Location())
			if !lo.Before(today) {
				return chatAcquire{}, nil
			}
		}
		m.lastOn = &today
		m.lastAt = &now
		return chatAcquire{Send: true, Email: m.email, Kind: "single", Hint: hint}, nil
	case ModeEvery:
		min := time.Duration(prefs.MinIntervalSec) * time.Second
		if m.lastAt != nil && now.Sub(*m.lastAt) < min {
			return chatAcquire{}, nil
		}
		m.lastAt = &now
		m.lastOn = &today
		return chatAcquire{Send: true, Email: m.email, Kind: "single", Hint: hint}, nil
	case ModeBatch:
		m.pending++
		m.hints = appendHint(m.hints, hint, 8)
		if m.pending < prefs.BatchSize {
			return chatAcquire{}, nil
		}
		out := chatAcquire{Send: true, Email: m.email, Kind: "batch", Count: m.pending, Hints: append([]string{}, m.hints...)}
		m.pending = 0
		m.hints = nil
		m.lastAt = &now
		m.lastOn = &today
		return out, nil
	default:
		return chatAcquire{}, nil
	}
}
func (m *memPrefStore) AcquireSocialSend(_ context.Context, _ string, prefs Prefs, now time.Time) (socialAcquire, error) {
	prefs = NormalizePrefs(prefs)
	if !m.verified || m.email == "" {
		return socialAcquire{}, nil
	}
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	switch prefs.Mode {
	case ModeFirstDaily:
		if m.lastOn != nil {
			lo := time.Date(m.lastOn.Year(), m.lastOn.Month(), m.lastOn.Day(), 0, 0, 0, 0, today.Location())
			if !lo.Before(today) {
				return socialAcquire{}, nil
			}
		}
	case ModeEvery, ModeBatch:
		min := time.Duration(prefs.MinIntervalSec) * time.Second
		if m.lastAt != nil && now.Sub(*m.lastAt) < min {
			return socialAcquire{}, nil
		}
	default:
		return socialAcquire{}, nil
	}
	m.lastAt = &now
	m.lastOn = &today
	return socialAcquire{Send: true, Email: m.email}, nil
}
func (m *memPrefStore) ReleaseLastSend(_ context.Context, _ string, _ time.Time) error {
	m.releaseN++
	m.lastOn = nil
	m.lastAt = nil
	return nil
}

func newTestSvc(mail *fakeMailer, store *memPrefStore, online fakeOnline, qq fakeQQ, chat fakeChat) *Service {
	if store.prefs.Mode == "" {
		store.prefs = DefaultPrefs()
	}
	svc := New(mail, store, online, qq, chat, "https://im.example.com")
	svc.now = func() time.Time { return time.Date(2026, 9, 24, 10, 0, 0, 0, Shanghai()) }
	return svc
}

func TestNotifyChat_FirstDailyOnce(t *testing.T) {
	mail := &fakeMailer{}
	store := &memPrefStore{verified: true, email: "u@example.com", prefs: DefaultPrefs()}
	svc := newTestSvc(mail, store, nil, nil, fakeChat{typ: map[string]string{"c1": "dm"}})
	svc.NotifyChat(context.Background(), "u1", "c1", "Alice")
	svc.NotifyChat(context.Background(), "u1", "c1", "Bob")
	if len(mail.chat) != 1 || mail.chat[0] != "Alice" {
		t.Fatalf("chat=%v", mail.chat)
	}
}

func TestNotifyChat_SuppressedByQQDoorbell(t *testing.T) {
	mail := &fakeMailer{}
	store := &memPrefStore{verified: true, email: "u@example.com", prefs: DefaultPrefs()}
	svc := newTestSvc(mail, store, nil, fakeQQ{"u1": true}, fakeChat{})
	svc.NotifyChat(context.Background(), "u1", "c1", "Alice")
	if len(mail.chat) != 0 {
		t.Fatal("expected suppress")
	}
}

func TestNotifyChat_AllowsWhenQQBoundButDoorbellOff(t *testing.T) {
	mail := &fakeMailer{}
	store := &memPrefStore{verified: true, email: "u@example.com", prefs: DefaultPrefs()}
	svc := newTestSvc(mail, store, nil, fakeQQ{"u1": false}, fakeChat{typ: map[string]string{"c1": "dm"}})
	svc.NotifyChat(context.Background(), "u1", "c1", "Alice")
	if len(mail.chat) != 1 {
		t.Fatal("doorbell off should allow email")
	}
}

func TestNotifyChat_MutedSkipped(t *testing.T) {
	mail := &fakeMailer{}
	store := &memPrefStore{verified: true, email: "u@example.com", prefs: DefaultPrefs()}
	svc := newTestSvc(mail, store, nil, nil, fakeChat{muted: map[string]bool{"c1:u1": true}})
	svc.NotifyChat(context.Background(), "u1", "c1", "Alice")
	if len(mail.chat) != 0 {
		t.Fatal("muted should skip")
	}
}

func TestNotifyChat_ScopeInclude(t *testing.T) {
	mail := &fakeMailer{}
	p := DefaultPrefs()
	p.Scope = ScopeInclude
	p.ConversationIDs = []string{"c1"}
	store := &memPrefStore{verified: true, email: "u@example.com", prefs: p}
	svc := newTestSvc(mail, store, nil, nil, fakeChat{typ: map[string]string{"c2": "dm"}})
	svc.NotifyChat(context.Background(), "u1", "c2", "Alice")
	if len(mail.chat) != 0 {
		t.Fatal("include miss should skip")
	}
	svc.chat = fakeChat{typ: map[string]string{"c1": "dm"}}
	svc.NotifyChat(context.Background(), "u1", "c1", "Alice")
	if len(mail.chat) != 1 {
		t.Fatal("include hit should send")
	}
}

func TestNotifyChat_Batch(t *testing.T) {
	mail := &fakeMailer{}
	p := DefaultPrefs()
	p.Mode = ModeBatch
	p.BatchSize = 3
	store := &memPrefStore{verified: true, email: "u@example.com", prefs: p}
	svc := newTestSvc(mail, store, nil, nil, fakeChat{typ: map[string]string{"c1": "dm"}})
	svc.NotifyChat(context.Background(), "u1", "c1", "A")
	svc.NotifyChat(context.Background(), "u1", "c1", "B")
	if len(mail.batch) != 0 {
		t.Fatal("should not send before batch size")
	}
	svc.NotifyChat(context.Background(), "u1", "c1", "C")
	if len(mail.batch) != 1 || mail.batch[0] != 3 {
		t.Fatalf("batch=%v", mail.batch)
	}
}

func TestNotifyChat_EveryInterval(t *testing.T) {
	mail := &fakeMailer{}
	p := DefaultPrefs()
	p.Mode = ModeEvery
	p.MinIntervalSec = 600
	store := &memPrefStore{verified: true, email: "u@example.com", prefs: p}
	svc := newTestSvc(mail, store, nil, nil, fakeChat{typ: map[string]string{"c1": "dm"}})
	svc.NotifyChat(context.Background(), "u1", "c1", "A")
	svc.NotifyChat(context.Background(), "u1", "c1", "B")
	if len(mail.chat) != 1 {
		t.Fatalf("want 1 within interval, got %d", len(mail.chat))
	}
	svc.now = func() time.Time { return time.Date(2026, 9, 24, 10, 15, 0, 0, Shanghai()) }
	svc.NotifyChat(context.Background(), "u1", "c1", "C")
	if len(mail.chat) != 2 {
		t.Fatalf("want 2 after interval, got %d", len(mail.chat))
	}
}

func TestNotifySocial_FriendRequest(t *testing.T) {
	mail := &fakeMailer{}
	store := &memPrefStore{verified: true, email: "u@example.com", prefs: DefaultPrefs()}
	svc := newTestSvc(mail, store, nil, nil, fakeChat{})
	svc.NotifySocial(context.Background(), "u1", "Alice 请求添加你为好友，请打开 IHope 查看。", "friend.request:x")
	if len(mail.social) != 1 {
		t.Fatalf("social=%v", mail.social)
	}
	svc.NotifySocial(context.Background(), "u1", "Bob 请求添加你为好友", "friend.request:y")
	if len(mail.social) != 1 {
		t.Fatal("first_daily should share slot with prior social")
	}
}

func TestNotifySocial_SuppressedByQQ(t *testing.T) {
	mail := &fakeMailer{}
	store := &memPrefStore{verified: true, email: "u@example.com", prefs: DefaultPrefs()}
	svc := newTestSvc(mail, store, nil, fakeQQ{"u1": true}, fakeChat{})
	svc.NotifySocial(context.Background(), "u1", "friend tip", "friend.request:x")
	if len(mail.social) != 0 {
		t.Fatal("qq should suppress social email")
	}
}

func TestNotifyChat_ReleaseOnFailure(t *testing.T) {
	mail := &fakeMailer{err: errors.New("smtp down")}
	store := &memPrefStore{verified: true, email: "u@example.com", prefs: DefaultPrefs()}
	svc := newTestSvc(mail, store, nil, nil, fakeChat{typ: map[string]string{"c1": "dm"}})
	svc.NotifyChat(context.Background(), "u1", "c1", "Alice")
	if store.releaseN != 1 {
		t.Fatalf("release=%d", store.releaseN)
	}
}

func TestNormalizePrefs(t *testing.T) {
	p := NormalizePrefs(Prefs{Mode: "EVERY", BatchSize: 1, MinIntervalSec: 10, Scope: "weird"})
	if p.Mode != ModeEvery || p.BatchSize != 5 || p.MinIntervalSec != 300 || p.Scope != ScopeAll {
		t.Fatalf("%+v", p)
	}
}
