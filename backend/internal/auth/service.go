package auth

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/ihope/ihope/internal/config"
	"github.com/ihope/ihope/internal/jwt"
	"github.com/ihope/ihope/internal/mail"
	"github.com/ihope/ihope/internal/user"
)

var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrInvalidRefresh     = errors.New("invalid refresh token")
	ErrInvalidResetToken  = errors.New("invalid or expired reset token")
	ErrAccountDisabled    = errors.New("account disabled")
)

// Service 账号业务逻辑，依赖 user.Repository 持久化、JWTManager 签发令牌、mail.Sender 发信。
type Service struct {
	cfg    config.Config
	users  *user.Repository
	jwt    *jwt.Manager
	mailer mail.Sender
}

func NewService(cfg config.Config, users *user.Repository, jwtMgr *jwt.Manager, mailer mail.Sender) *Service {
	return &Service{cfg: cfg, users: users, jwt: jwtMgr, mailer: mailer}
}

type RegisterInput struct {
	Email             string
	Username          string
	Password          string
	IdentityPublicKey string
}

type LoginInput struct {
	Email      string
	Password   string
	DeviceID   string
	DeviceName string
}

type TokenResponse struct {
	AccessToken  string     `json:"access_token"`
	RefreshToken string     `json:"refresh_token"`
	ExpiresIn    int64      `json:"expires_in"`
	User         *user.User `json:"user"`
}

// ForgotPassword 生成重置 token；邮箱存在时返回明文 token（供开发/Postman，生产应走邮件）。
func (s *Service) ForgotPassword(ctx context.Context, email string) (string, error) {
	email = NormalizeEmail(email)
	if !ValidateEmail(email) {
		return "", nil
	}

	u, _, err := s.users.GetByEmail(ctx, email)
	if errors.Is(err, user.ErrNotFound) {
		return "", nil
	}
	if err != nil {
		return "", err
	}

	plain, tokenHash, err := NewResetToken()
	if err != nil {
		return "", err
	}

	expires := time.Now().Add(s.cfg.ResetTokenTTL)
	if err := s.users.CreatePasswordResetToken(ctx, u.ID, tokenHash, expires); err != nil {
		return "", err
	}

	resetURL := fmt.Sprintf("%s/reset-password?token=%s", trimSlash(s.cfg.AppPublicURL), plain)
	if err := s.mailer.SendPasswordReset(u.Email, resetURL); err != nil {
		return "", err
	}

	return plain, nil
}

func (s *Service) Register(ctx context.Context, in RegisterInput) (*user.User, error) {
	email := NormalizeEmail(in.Email)
	username := strings.TrimSpace(in.Username)
	identityKey := strings.TrimSpace(in.IdentityPublicKey)

	if !ValidateEmail(email) {
		return nil, fmt.Errorf("invalid email")
	}
	if !ValidateUsername(username) {
		return nil, fmt.Errorf("username must be 3-32 chars: letters, numbers, underscore")
	}
	if !ValidatePassword(in.Password) {
		return nil, fmt.Errorf("password must be at least 8 characters")
	}
	if identityKey == "" {
		return nil, fmt.Errorf("identity_public_key is required")
	}
	if err := user.ValidateIdentityPublicKey(identityKey); err != nil {
		return nil, fmt.Errorf("identity_public_key must be a base64-encoded 33-byte Signal identity key (0x05 prefix)")
	}

	hash, err := HashPassword(in.Password)
	if err != nil {
		return nil, err
	}

	return s.users.Create(ctx, email, username, hash, identityKey)
}

func (s *Service) Login(ctx context.Context, in LoginInput) (*TokenResponse, error) {
	email := NormalizeEmail(in.Email)
	deviceID := strings.TrimSpace(in.DeviceID)
	if !ValidateEmail(email) || !ValidatePassword(in.Password) || deviceID == "" {
		return nil, ErrInvalidCredentials
	}

	u, passwordHash, err := s.users.GetByEmail(ctx, email)
	if err != nil {
		if errors.Is(err, user.ErrNotFound) {
			return nil, ErrInvalidCredentials
		}
		return nil, err
	}
	if !CheckPassword(passwordHash, in.Password) {
		return nil, ErrInvalidCredentials
	}

	disabled, err := s.users.IsUserDisabled(ctx, u.ID)
	if err != nil {
		return nil, err
	}
	if disabled {
		return nil, ErrAccountDisabled
	}

	return s.issueTokens(ctx, u, deviceID, strings.TrimSpace(in.DeviceName))
}

func (s *Service) Refresh(ctx context.Context, refreshToken, deviceID string) (*TokenResponse, error) {
	refreshToken = strings.TrimSpace(refreshToken)
	deviceID = strings.TrimSpace(deviceID)
	if refreshToken == "" || deviceID == "" {
		return nil, ErrInvalidRefresh
	}

	tokenHash := HashToken(refreshToken)

	// Find user by matching refresh hash on device — scan devices via user lookup is inefficient;
	// we store hash per device and need user_id. Query device by hash.
	userID, err := s.findUserByRefreshHash(ctx, tokenHash, deviceID)
	if err != nil {
		return nil, ErrInvalidRefresh
	}

	u, err := s.users.GetByID(ctx, userID)
	if err != nil {
		return nil, ErrInvalidRefresh
	}

	disabled, err := s.users.IsUserDisabled(ctx, u.ID)
	if err != nil {
		return nil, ErrInvalidRefresh
	}
	if disabled {
		return nil, ErrAccountDisabled
	}

	storedHash, err := s.users.GetDeviceSession(ctx, userID, deviceID)
	if err != nil || storedHash.RefreshHash != tokenHash {
		return nil, ErrInvalidRefresh
	}
	if s.cfg.RefreshTokenTTL > 0 && time.Since(storedHash.LastActiveAt) > s.cfg.RefreshTokenTTL {
		_ = s.users.KickDevice(ctx, userID, deviceID)
		return nil, ErrInvalidRefresh
	}

	return s.issueTokens(ctx, u, deviceID, "")
}

func (s *Service) Logout(ctx context.Context, userID, deviceID string) error {
	userID = strings.TrimSpace(userID)
	deviceID = strings.TrimSpace(deviceID)
	if userID == "" || deviceID == "" {
		return ErrInvalidRefresh
	}
	err := s.users.KickDevice(ctx, userID, deviceID)
	if err == user.ErrNotFound {
		return nil
	}
	return err
}

func (s *Service) ChangePassword(ctx context.Context, userID, currentPassword, newPassword string) error {
	userID = strings.TrimSpace(userID)
	if userID == "" || !ValidatePassword(currentPassword) || !ValidatePassword(newPassword) {
		return ErrInvalidCredentials
	}

	hash, err := s.users.GetPasswordHashByID(ctx, userID)
	if err != nil {
		if errors.Is(err, user.ErrNotFound) {
			return ErrInvalidCredentials
		}
		return err
	}
	if !CheckPassword(hash, currentPassword) {
		return ErrInvalidCredentials
	}

	newHash, err := HashPassword(newPassword)
	if err != nil {
		return err
	}
	return s.users.ChangePasswordAndRevokeSessions(ctx, userID, newHash)
}

func (s *Service) ResetPassword(ctx context.Context, token, newPassword string) error {
	token = strings.TrimSpace(token)
	if token == "" || !ValidatePassword(newPassword) {
		return ErrInvalidResetToken
	}

	userID, err := s.users.ConsumePasswordResetToken(ctx, HashToken(token))
	if err != nil {
		return ErrInvalidResetToken
	}

	hash, err := HashPassword(newPassword)
	if err != nil {
		return err
	}
	if err := s.users.ChangePasswordAndRevokeSessions(ctx, userID, hash); err != nil {
		return err
	}
	return nil
}

// issueTokens 签发 access/refresh token，并将 refresh 哈希写入 user_devices。
func (s *Service) issueTokens(ctx context.Context, u *user.User, deviceID, deviceName string) (*TokenResponse, error) {
	tokenVersion, err := s.users.GetTokenVersion(ctx, u.ID)
	if err != nil {
		return nil, err
	}

	access, expiresIn, err := s.jwt.IssueAccessToken(u.ID, deviceID, tokenVersion)
	if err != nil {
		return nil, err
	}

	refreshPlain, refreshHash, err := NewRefreshToken()
	if err != nil {
		return nil, err
	}

	if err := s.users.UpsertDevice(ctx, u.ID, deviceID, deviceName, refreshHash); err != nil {
		return nil, err
	}

	return &TokenResponse{
		AccessToken:  access,
		RefreshToken: refreshPlain,
		ExpiresIn:    expiresIn,
		User:         u,
	}, nil
}

func (s *Service) findUserByRefreshHash(ctx context.Context, tokenHash, deviceID string) (string, error) {
	// lightweight query on pool via users repo — add method
	return s.users.FindUserIDByDeviceRefresh(ctx, deviceID, tokenHash)
}

func trimSlash(s string) string {
	for len(s) > 0 && s[len(s)-1] == '/' {
		s = s[:len(s)-1]
	}
	return s
}
