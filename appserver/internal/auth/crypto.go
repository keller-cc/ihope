package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"net/mail"
	"strings"
	"unicode"
	"unicode/utf8"

	"golang.org/x/crypto/bcrypt"
)

func HashPassword(password string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

func CheckPassword(hash, password string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}

func NewVerifyToken() (plain, hash string, err error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", "", err
	}
	plain = hex.EncodeToString(buf)
	hash = HashToken(plain)
	return plain, hash, nil
}

func HashToken(plain string) string {
	sum := sha256.Sum256([]byte(plain))
	return hex.EncodeToString(sum[:])
}

func NormalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

func ValidateEmail(email string) bool {
	email = NormalizeEmail(email)
	if email == "" || utf8.RuneCountInString(email) > 254 {
		return false
	}
	_, err := mail.ParseAddress(email)
	return err == nil
}

// ValidateUsername: trim 后 1–32 字；允许中间空格；须为字母/中文/数字/下划线/间隔号或空格。
func ValidateUsername(username string) bool {
	username = strings.TrimSpace(username)
	n := utf8.RuneCountInString(username)
	if n < 1 || n > 32 {
		return false
	}
	for _, r := range username {
		if unicode.IsControl(r) {
			return false
		}
		if unicode.IsLetter(r) || unicode.IsDigit(r) || r == '_' || r == '·' || r == '・' || r == ' ' {
			continue
		}
		return false
	}
	return true
}

func ValidatePassword(password string) bool {
	return utf8.RuneCountInString(password) >= 6
}

// ValidateHopeID: 纯数字 5–12 位，首位 1–9（无前导零）。
func ValidateHopeID(id string) bool {
	id = strings.TrimSpace(id)
	n := len(id)
	if n < 5 || n > 12 {
		return false
	}
	if id[0] < '1' || id[0] > '9' {
		return false
	}
	for i := 1; i < n; i++ {
		if id[i] < '0' || id[i] > '9' {
			return false
		}
	}
	return true
}

// LooksLikeHopeID: 登录/查找时判断输入是否应按数字号解析。
func LooksLikeHopeID(s string) bool {
	return ValidateHopeID(strings.TrimSpace(s))
}
