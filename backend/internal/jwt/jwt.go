// Package jwt 签发与解析 access_token。
package jwt

import (
	"errors"
	"fmt"
	"time"

	jwtlib "github.com/golang-jwt/jwt/v5"
)

// Claims JWT 载荷：用户 ID + 设备 ID。
type Claims struct {
	UserID       string `json:"uid"`
	DeviceID     string `json:"did"`
	TokenVersion int    `json:"tv"`
	jwtlib.RegisteredClaims
}

// Manager 使用 HMAC-SHA256 签发/校验 access_token。
type Manager struct {
	secret    []byte
	accessTTL time.Duration
}

func NewManager(secret string, accessTTL time.Duration) *Manager {
	if accessTTL <= 0 {
		accessTTL = 15 * time.Minute
	}
	return &Manager{secret: []byte(secret), accessTTL: accessTTL}
}

func (m *Manager) IssueAccessToken(userID, deviceID string, tokenVersion int) (string, int64, error) {
	now := time.Now()
	expires := now.Add(m.accessTTL)
	claims := Claims{
		UserID:       userID,
		DeviceID:     deviceID,
		TokenVersion: tokenVersion,
		RegisteredClaims: jwtlib.RegisteredClaims{
			Subject:   userID,
			IssuedAt:  jwtlib.NewNumericDate(now),
			ExpiresAt: jwtlib.NewNumericDate(expires),
		},
	}
	token := jwtlib.NewWithClaims(jwtlib.SigningMethodHS256, claims)
	signed, err := token.SignedString(m.secret)
	if err != nil {
		return "", 0, err
	}
	return signed, int64(m.accessTTL.Seconds()), nil
}

func (m *Manager) ParseAccessToken(tokenStr string) (*Claims, error) {
	token, err := jwtlib.ParseWithClaims(tokenStr, &Claims{}, func(t *jwtlib.Token) (any, error) {
		if t.Method != jwtlib.SigningMethodHS256 {
			return nil, fmt.Errorf("unexpected signing method")
		}
		return m.secret, nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token")
	}
	return claims, nil
}
