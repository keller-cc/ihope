package emailnotify

import (
	"context"
	"log"
	"strings"
	"sync"
	"time"
)

type Mailer interface {
	SendMessageReminder(to, senderHint, appURL string) error
	SendBatchMessageReminder(to string, count int, hints []string, appURL string) error
	SendSocialReminder(to, text, appURL string) error
}

type OnlineCheck interface {
	IsUserOnline(userID string) bool
}

// QQSuppressor reports when QQ doorbell is actively handling offline alerts.
type QQSuppressor interface {
	SuppressEmail(ctx context.Context, userID string) (bool, error)
}

type ChatMeta interface {
	IsMemberMuted(ctx context.Context, conversationID, userID string) bool
	ConversationType(ctx context.Context, conversationID string) (string, error)
}

type PrefStore interface {
	GetPrefs(ctx context.Context, userID string) (Prefs, error)
	SavePrefs(ctx context.Context, userID string, p Prefs) (Prefs, error)
	EmailVerified(ctx context.Context, userID string) (bool, error)
	AcquireChatSend(ctx context.Context, userID string, prefs Prefs, now time.Time, hint string) (chatAcquire, error)
	AcquireSocialSend(ctx context.Context, userID string, prefs Prefs, now time.Time) (socialAcquire, error)
	ReleaseLastSend(ctx context.Context, userID string, today time.Time) error
}

type Service struct {
	mail   Mailer
	store  PrefStore
	online OnlineCheck
	qq     QQSuppressor
	chat   ChatMeta
	appURL string
	now    func() time.Time

	socialMu   sync.Mutex
	socialLast map[string]time.Time
}

func New(mail Mailer, store PrefStore, online OnlineCheck, qq QQSuppressor, chat ChatMeta, appURL string) *Service {
	return &Service{
		mail:       mail,
		store:      store,
		online:     online,
		qq:         qq,
		chat:       chat,
		appURL:     strings.TrimSpace(appURL),
		now:        time.Now,
		socialLast: make(map[string]time.Time),
	}
}

func (s *Service) Status(ctx context.Context, userID string) (Status, error) {
	out := Status{Prefs: DefaultPrefs()}
	if s == nil || s.store == nil || userID == "" {
		return out, nil
	}
	p, err := s.store.GetPrefs(ctx, userID)
	if err != nil {
		return out, err
	}
	out.Prefs = p
	verified, _ := s.store.EmailVerified(ctx, userID)
	out.EmailVerified = verified
	qqSup := s.qqSuppress(ctx, userID)
	out.Effective = EffectiveStatus(false, qqSup, p.Enabled, p.Mode)
	if !verified && out.Effective == EffectiveActive {
		out.Effective = EffectiveDisabled
	}
	return out, nil
}

func (s *Service) UpdatePrefs(ctx context.Context, userID string, p Prefs) (Status, error) {
	if s == nil || s.store == nil {
		return Status{}, nil
	}
	saved, err := s.store.SavePrefs(ctx, userID, p)
	if err != nil {
		return Status{}, err
	}
	st := Status{Prefs: saved}
	verified, _ := s.store.EmailVerified(ctx, userID)
	st.EmailVerified = verified
	qqSup := s.qqSuppress(ctx, userID)
	st.Effective = EffectiveStatus(false, qqSup, saved.Enabled, saved.Mode)
	if !verified && st.Effective == EffectiveActive {
		st.Effective = EffectiveDisabled
	}
	return st, nil
}

func (s *Service) qqSuppress(ctx context.Context, userID string) bool {
	if s.qq == nil {
		return false
	}
	ok, err := s.qq.SuppressEmail(ctx, userID)
	if err != nil {
		log.Printf("emailnotify qq suppress user=%s: %v", userID, err)
		return true // fail closed toward not double-notifying if uncertain
	}
	return ok
}

func (s *Service) gate(ctx context.Context, userID string) (Prefs, bool) {
	if s == nil || s.mail == nil || s.store == nil || userID == "" {
		return Prefs{}, false
	}
	online := s.online != nil && s.online.IsUserOnline(userID)
	qqSup := s.qqSuppress(ctx, userID)
	prefs, err := s.store.GetPrefs(ctx, userID)
	if err != nil {
		log.Printf("emailnotify prefs user=%s: %v", userID, err)
		return Prefs{}, false
	}
	if !ChannelOpen(online, qqSup, prefs.Enabled, prefs.Mode) {
		return prefs, false
	}
	return prefs, true
}

// NotifyChat sends an offline chat email according to user prefs and scope.
func (s *Service) NotifyChat(ctx context.Context, userID, conversationID, senderHint string) {
	prefs, ok := s.gate(ctx, userID)
	if !ok {
		return
	}
	if s.chat != nil {
		if s.chat.IsMemberMuted(ctx, conversationID, userID) {
			return
		}
		convType, err := s.chat.ConversationType(ctx, conversationID)
		if err != nil {
			log.Printf("emailnotify conv type user=%s: %v", userID, err)
			return
		}
		listed := map[string]bool{}
		for _, id := range prefs.ConversationIDs {
			listed[id] = true
		}
		if !ScopeAllows(prefs.Scope, convType, conversationID, listed) {
			return
		}
	}

	now := s.now().In(Shanghai())
	acq, err := s.store.AcquireChatSend(ctx, userID, prefs, now, senderHint)
	if err != nil {
		log.Printf("emailnotify acquire chat user=%s: %v", userID, err)
		return
	}
	if !acq.Send || acq.Email == "" {
		return
	}

	var sendErr error
	switch acq.Kind {
	case "batch":
		sendErr = s.mail.SendBatchMessageReminder(acq.Email, acq.Count, acq.Hints, s.appURL)
	default:
		sendErr = s.mail.SendMessageReminder(acq.Email, acq.Hint, s.appURL)
	}
	if sendErr != nil {
		log.Printf("emailnotify send chat user=%s: %v", userID, sendErr)
		today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, Shanghai())
		_ = s.store.ReleaseLastSend(ctx, userID, today)
	}
}

// NotifySocial emails offline social tips (friend request, group join, etc.).
func (s *Service) NotifySocial(ctx context.Context, userID, text, dedupeKey string) {
	text = strings.TrimSpace(text)
	if text == "" {
		return
	}
	prefs, ok := s.gate(ctx, userID)
	if !ok {
		return
	}
	key := strings.TrimSpace(dedupeKey)
	if key == "" {
		key = text
	}
	key = userID + ":" + key
	if !s.allowSocial(key, 60*time.Second) {
		return
	}

	now := s.now().In(Shanghai())
	acq, err := s.store.AcquireSocialSend(ctx, userID, prefs, now)
	if err != nil {
		log.Printf("emailnotify acquire social user=%s: %v", userID, err)
		return
	}
	if !acq.Send || acq.Email == "" {
		return
	}
	if err := s.mail.SendSocialReminder(acq.Email, text, s.appURL); err != nil {
		log.Printf("emailnotify send social user=%s: %v", userID, err)
		today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, Shanghai())
		_ = s.store.ReleaseLastSend(ctx, userID, today)
	}
}

func (s *Service) allowSocial(key string, minInterval time.Duration) bool {
	now := s.now()
	s.socialMu.Lock()
	defer s.socialMu.Unlock()
	if t, ok := s.socialLast[key]; ok && now.Sub(t) < minInterval {
		return false
	}
	s.socialLast[key] = now
	if len(s.socialLast) > 4096 {
		cutoff := now.Add(-30 * time.Minute)
		for k, t := range s.socialLast {
			if t.Before(cutoff) {
				delete(s.socialLast, k)
			}
		}
	}
	return true
}

// NotifyFirstOfDay kept as alias for older call sites / tests.
func (s *Service) NotifyFirstOfDay(ctx context.Context, userID, senderHint string) {
	s.NotifyChat(ctx, userID, "", senderHint)
}
