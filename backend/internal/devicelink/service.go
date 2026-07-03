package devicelink

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"strings"
	"time"

	"github.com/ihope/ihope/internal/auth"
)

const linkTokenBytes = 32

type Service struct {
	repo *Repository
	ttl  time.Duration
}

func NewService(repo *Repository, ttl time.Duration) *Service {
	if ttl <= 0 {
		ttl = 5 * time.Minute
	}
	return &Service{repo: repo, ttl: ttl}
}

type InitResult struct {
	LinkID    string    `json:"link_id"`
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
}

func (s *Service) Init(ctx context.Context, userID, initiatorDeviceID string) (*InitResult, error) {
	userID = strings.TrimSpace(userID)
	initiatorDeviceID = strings.TrimSpace(initiatorDeviceID)
	if userID == "" || initiatorDeviceID == "" {
		return nil, ErrForbidden
	}

	token, err := randomToken(linkTokenBytes)
	if err != nil {
		return nil, err
	}
	expiresAt := time.Now().UTC().Add(s.ttl)
	id, err := s.repo.Create(ctx, userID, initiatorDeviceID, auth.HashToken(token), expiresAt)
	if err != nil {
		return nil, err
	}
	return &InitResult{LinkID: id, Token: token, ExpiresAt: expiresAt}, nil
}

func (s *Service) UploadPayload(ctx context.Context, linkID, userID, deviceID, ciphertext string) error {
	linkID = strings.TrimSpace(linkID)
	ciphertext = strings.TrimSpace(ciphertext)
	if linkID == "" || ciphertext == "" {
		return ErrForbidden
	}
	return s.repo.SetPayload(ctx, linkID, userID, deviceID, ciphertext)
}

func (s *Service) Complete(ctx context.Context, userID, deviceID, token string) (string, error) {
	token = strings.TrimSpace(token)
	if token == "" {
		return "", ErrForbidden
	}
	return s.repo.Complete(ctx, auth.HashToken(token), userID, deviceID)
}

func randomToken(n int) (string, error) {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}
