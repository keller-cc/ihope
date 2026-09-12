package auth

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/keller-cc/ihope/appserver/internal/mail"
)

var (
	ErrInvalidCredentials    = errors.New("invalid credentials")
	ErrEmailTaken            = errors.New("email taken")
	ErrUsernameTaken         = errors.New("username taken")
	ErrEmailNotVerified      = errors.New("email not verified")
	ErrInvalidVerifyToken    = errors.New("invalid verify token")
	ErrInvalidFellowshipCode = errors.New("invalid fellowship code")
	ErrInvalidHopeID = errors.New("invalid hope id")
	ErrHopeIDTaken   = errors.New("hope id taken")
)

type User struct {
	ID            string  `json:"id"`
	Email         string  `json:"email"`
	Username      string  `json:"username"`
	EmailVerified bool    `json:"emailVerified"`
	HopeID        *string `json:"hopeId,omitempty"`
	AvatarURL     *string    `json:"avatarUrl,omitempty"`
	ChatTheme     *ChatTheme `json:"chatTheme,omitempty"`
	// ChatBg is derived from ChatTheme.Background for older clients.
	ChatBg *ChatBg `json:"chatBg,omitempty"`
}

type RegisterResult struct {
	User           *User  `json:"user"`
	Message        string `json:"message"`
	DevVerifyToken string `json:"devVerifyToken,omitempty"`
}

type Options struct {
	JWTSecret       string
	AccessTTL       time.Duration
	AppPublicURL    string
	EmailVerifyTTL  time.Duration
	MailDriver      string
	Mailer          *mail.Sender
	FellowshipCode  string
}

type Service struct {
	pool *pgxpool.Pool
	opt  Options
}

func NewService(pool *pgxpool.Pool, opt Options) *Service {
	return &Service{pool: pool, opt: opt}
}

func (s *Service) Register(ctx context.Context, email, username, password, fellowshipCode string) (*RegisterResult, error) {
	email = NormalizeEmail(email)
	username = strings.TrimSpace(username)
	fellowshipID, err := s.lookupFellowshipID(ctx, fellowshipCode)
	if err != nil {
		return nil, err
	}
	if !ValidateEmail(email) {
		return nil, errors.New("invalid email")
	}
	if !ValidateUsername(username) {
		return nil, errors.New("username must be 1-32 characters after trim")
	}
	if !ValidatePassword(password) {
		return nil, errors.New("password must be at least 6 characters")
	}
	hash, err := HashPassword(password)
	if err != nil {
		return nil, err
	}
	var u User
	err = s.pool.QueryRow(ctx, `
		INSERT INTO users (email, username, password_hash, email_verified, fellowship_id)
		VALUES ($1, $2, $3, FALSE, $4::uuid)
		RETURNING id::text, email, username, email_verified, hope_id, avatar_url
	`, email, username, hash, fellowshipID).Scan(&u.ID, &u.Email, &u.Username, &u.EmailVerified, &u.HopeID, &u.AvatarURL)
	if err != nil {
		msg := err.Error()
		if strings.Contains(msg, "users_email_key") {
			return nil, ErrEmailTaken
		}
		if strings.Contains(msg, "users_username_key") {
			return nil, ErrUsernameTaken
		}
		return nil, err
	}
	hopeID, err := s.assignHopeID(ctx, u.ID)
	if err != nil {
		return nil, err
	}
	u.HopeID = &hopeID
	devToken, err := s.sendEmailVerification(ctx, u.ID, u.Email)
	if err != nil {
		return nil, err
	}
	return &RegisterResult{
		User:           &u,
		Message:        "verification email sent; check your inbox to activate",
		DevVerifyToken: devToken,
	}, nil
}

func (s *Service) ResendVerification(ctx context.Context, email string) (status string, devToken string, err error) {
	email = NormalizeEmail(email)
	if !ValidateEmail(email) {
		return "not_found", "", nil
	}
	var id string
	var verified bool
	err = s.pool.QueryRow(ctx, `
		SELECT id::text, email_verified FROM users WHERE email = $1
	`, email).Scan(&id, &verified)
	if errors.Is(err, pgx.ErrNoRows) {
		return "not_found", "", nil
	}
	if err != nil {
		return "", "", err
	}
	if verified {
		return "already_verified", "", nil
	}
	devToken, err = s.sendEmailVerification(ctx, id, email)
	if err != nil {
		return "", "", err
	}
	return "sent", devToken, nil
}

func (s *Service) VerifyEmail(ctx context.Context, token string) error {
	token = strings.TrimSpace(token)
	if token == "" {
		return ErrInvalidVerifyToken
	}
	tokenHash := HashToken(token)
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var userID string
	var expires time.Time
	var usedAt *time.Time
	err = tx.QueryRow(ctx, `
		SELECT user_id::text, expires_at, used_at
		FROM email_verification_tokens WHERE token_hash = $1 FOR UPDATE
	`, tokenHash).Scan(&userID, &expires, &usedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrInvalidVerifyToken
	}
	if err != nil {
		return err
	}
	if usedAt != nil || time.Now().After(expires) {
		return ErrInvalidVerifyToken
	}
	if _, err := tx.Exec(ctx, `UPDATE email_verification_tokens SET used_at = now() WHERE token_hash = $1`, tokenHash); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `UPDATE users SET email_verified = TRUE WHERE id = $1`, userID); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *Service) sendEmailVerification(ctx context.Context, userID, email string) (string, error) {
	plain, tokenHash, err := NewVerifyToken()
	if err != nil {
		return "", err
	}
	ttl := s.opt.EmailVerifyTTL
	if ttl <= 0 {
		ttl = 24 * time.Hour
	}
	expires := time.Now().Add(ttl)
	_, _ = s.pool.Exec(ctx, `
		UPDATE email_verification_tokens SET used_at = now()
		WHERE user_id = $1 AND used_at IS NULL
	`, userID)
	_, err = s.pool.Exec(ctx, `
		INSERT INTO email_verification_tokens (token_hash, user_id, expires_at)
		VALUES ($1, $2, $3)
	`, tokenHash, userID, expires)
	if err != nil {
		return "", err
	}
	base := strings.TrimRight(s.opt.AppPublicURL, "/")
	verifyURL := fmt.Sprintf("%s/verify?token=%s", base, plain)
	if s.opt.Mailer != nil {
		if err := s.opt.Mailer.SendEmailVerification(email, verifyURL); err != nil {
			_, _ = s.pool.Exec(ctx, `
				UPDATE email_verification_tokens SET used_at = now() WHERE token_hash = $1
			`, tokenHash)
			return "", err
		}
	}
	driver := strings.ToLower(strings.TrimSpace(s.opt.MailDriver))
	if driver == "" || driver == "log" {
		return plain, nil
	}
	return "", nil
}

func (s *Service) Login(ctx context.Context, login, password string) (*User, string, error) {
	login = strings.TrimSpace(login)
	var u User
	var hash string
	var err error
	if LooksLikeHopeID(login) {
		err = s.pool.QueryRow(ctx, `
			SELECT id::text, email, username, email_verified, hope_id, avatar_url, password_hash
			FROM users WHERE hope_id = $1
			LIMIT 1
		`, login).Scan(&u.ID, &u.Email, &u.Username, &u.EmailVerified, &u.HopeID, &u.AvatarURL, &hash)
	} else {
		err = s.pool.QueryRow(ctx, `
			SELECT id::text, email, username, email_verified, hope_id, avatar_url, password_hash
			FROM users
			WHERE email = lower($1) OR username = $1
			LIMIT 1
		`, login).Scan(&u.ID, &u.Email, &u.Username, &u.EmailVerified, &u.HopeID, &u.AvatarURL, &hash)
	}
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, "", ErrInvalidCredentials
		}
		return nil, "", err
	}
	if !CheckPassword(hash, password) {
		return nil, "", ErrInvalidCredentials
	}
	if !u.EmailVerified {
		return &u, "", ErrEmailNotVerified
	}
	token, err := s.issueToken(u.ID)
	if err != nil {
		return nil, "", err
	}
	full, err := s.UserByID(ctx, u.ID)
	if err != nil {
		return nil, "", err
	}
	return full, token, nil
}

func (s *Service) UserByID(ctx context.Context, id string) (*User, error) {
	var u User
	var chatBgRaw string
	err := s.pool.QueryRow(ctx, `
		SELECT id::text, email, username, email_verified, hope_id, avatar_url, COALESCE(chat_bg, '')
		FROM users WHERE id = $1
	`, id).Scan(&u.ID, &u.Email, &u.Username, &u.EmailVerified, &u.HopeID, &u.AvatarURL, &chatBgRaw)
	if err != nil {
		return nil, err
	}
	u.ChatTheme = ParseChatTheme(chatBgRaw)
	if u.ChatTheme != nil {
		u.ChatBg = u.ChatTheme.Background
	}
	return &u, nil
}

func (s *Service) SetUsername(ctx context.Context, userID, username string) (*User, error) {
	username = strings.TrimSpace(username)
	if !ValidateUsername(username) {
		return nil, errors.New("username must be 1-32 characters after trim")
	}
	_, err := s.pool.Exec(ctx, `UPDATE users SET username = $1 WHERE id = $2`, username, userID)
	if err != nil {
		msg := err.Error()
		if strings.Contains(msg, "users_username_key") || strings.Contains(msg, "duplicate key") {
			return nil, ErrUsernameTaken
		}
		return nil, err
	}
	return s.UserByID(ctx, userID)
}

func (s *Service) SetChatTheme(ctx context.Context, userID string, patch *ChatTheme) (*User, error) {
	u, err := s.UserByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	merged := MergeChatTheme(u.ChatTheme, patch)
	raw, err := EncodeChatTheme(merged)
	if err != nil {
		return nil, err
	}
	_, err = s.pool.Exec(ctx, `UPDATE users SET chat_bg = $1 WHERE id = $2`, raw, userID)
	if err != nil {
		return nil, err
	}
	return s.UserByID(ctx, userID)
}

// SetChatBg updates only the wallpaper layer (legacy / upload helper).
func (s *Service) SetChatBg(ctx context.Context, userID string, bg *ChatBg) (*User, error) {
	return s.SetChatTheme(ctx, userID, &ChatTheme{Background: bg})
}

func (s *Service) SetAvatarURL(ctx context.Context, userID, url string) (*User, error) {
	_, err := s.pool.Exec(ctx, `UPDATE users SET avatar_url = $1 WHERE id = $2`, url, userID)
	if err != nil {
		return nil, err
	}
	return s.UserByID(ctx, userID)
}

// assignHopeID generates a unique system IHope number (8–10 digits).
func (s *Service) assignHopeID(ctx context.Context, userID string) (string, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)

	var lockedID string
	if err := tx.QueryRow(ctx, `SELECT id::text FROM users WHERE id = $1 FOR UPDATE`, userID).Scan(&lockedID); err != nil {
		return "", err
	}

	var hopeID string
	for i := 0; i < 40; i++ {
		candidate, err := randomHopeID()
		if err != nil {
			return "", err
		}
		var taken bool
		if err := tx.QueryRow(ctx, `
			SELECT EXISTS(SELECT 1 FROM users WHERE hope_id = $1 AND id <> $2)
		`, candidate, userID).Scan(&taken); err != nil {
			return "", err
		}
		if !taken {
			hopeID = candidate
			break
		}
	}
	if hopeID == "" {
		return "", errors.New("failed to allocate hope id")
	}
	_, err = tx.Exec(ctx, `
		UPDATE users SET hope_id = $1 WHERE id = $2
	`, hopeID, userID)
	if err != nil {
		return "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return "", err
	}
	return hopeID, nil
}

func randomHopeID() (string, error) {
	// 8–10 位，类似 QQ 号体量；首位 1–9
	lenN, err := rand.Int(rand.Reader, big.NewInt(3))
	if err != nil {
		return "", err
	}
	digits := int(lenN.Int64()) + 8 // 8, 9, or 10
	max := new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(digits-1)), nil)
	max.Mul(max, big.NewInt(9)) // 9 * 10^(n-1) values starting from 10^(n-1)
	n, err := rand.Int(rand.Reader, max)
	if err != nil {
		return "", err
	}
	base := new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(digits-1)), nil)
	n.Add(n, base)
	return n.String(), nil
}

// RefreshHopeID regenerates a system IHope number.
func (s *Service) RefreshHopeID(ctx context.Context, userID string) (*User, error) {
	if _, err := s.assignHopeID(ctx, userID); err != nil {
		return nil, err
	}
	return s.UserByID(ctx, userID)
}

// EnsureHopeID assigns one if missing (legacy users).
func (s *Service) EnsureHopeID(ctx context.Context, userID string) (*User, error) {
	u, err := s.UserByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	if u.HopeID != nil && *u.HopeID != "" {
		return u, nil
	}
	if _, err := s.assignHopeID(ctx, userID); err != nil {
		return nil, err
	}
	return s.UserByID(ctx, userID)
}

// Deprecated: use RefreshHopeID. Kept so old clients fail closed if still calling with body.
func (s *Service) SetHopeID(ctx context.Context, userID, _ string) (*User, error) {
	return s.RefreshHopeID(ctx, userID)
}

type claims struct {
	UserID string `json:"uid"`
	jwt.RegisteredClaims
}

func (s *Service) issueToken(userID string) (string, error) {
	now := time.Now()
	c := claims{
		UserID: userID,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(s.opt.AccessTTL)),
			ID:        uuid.NewString(),
		},
	}
	t := jwt.NewWithClaims(jwt.SigningMethodHS256, c)
	return t.SignedString([]byte(s.opt.JWTSecret))
}

func (s *Service) ParseToken(tokenStr string) (string, error) {
	t, err := jwt.ParseWithClaims(tokenStr, &claims{}, func(t *jwt.Token) (any, error) {
		if t.Method != jwt.SigningMethodHS256 {
			return nil, errors.New("unexpected signing method")
		}
		return []byte(s.opt.JWTSecret), nil
	})
	if err != nil {
		return "", err
	}
	c, ok := t.Claims.(*claims)
	if !ok || !t.Valid {
		return "", errors.New("invalid token")
	}
	return c.UserID, nil
}
