package config

import (
	"encoding/base64"
	"log"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

type Config struct {
	HTTPAddr              string
	DatabaseURL           string
	JWTSecret             string
	JWTAccessTTL          time.Duration
	CORSOrigin            string
	MessageEncryptionKey  []byte
	UploadDir             string
	AppPublicURL          string
	MailDriver            string
	MailFrom              string
	SMTPHost              string
	SMTPPort              string
	SMTPUser              string
	SMTPPass              string
	EmailVerifyTTL        time.Duration
	PasswordResetTTL      time.Duration
	UnverifiedUserTTL     time.Duration
	QQBotEnabled          bool
	QQBotAppID            string
	QQBotAppSecret        string
	QQWebhookPath         string
	QQBotAddHint          string
	QQDoorbellCooldownSec int
	QQQuotesFilePath      string
	QQPoetryAPIURL        string
	QQPoetryFontPath      string
	QQNews60sAPIURL       string
	QQDailyPoetryHHMM     string
	QQDailyQuotesHHMM     string
	QQDailyNewsHHMM       string
	FellowshipCode        string
	AdminToken            string
	CallTurnURLs          string
	CallTurnUsername      string
	CallTurnCredential    string
	WebDist               string
}

func Load() Config {
	loadDotEnv()

	keyB64 := env("MESSAGE_ENCRYPTION_KEY", "")
	var key []byte
	if keyB64 != "" {
		decoded, err := base64.StdEncoding.DecodeString(keyB64)
		if err != nil || len(decoded) != 32 {
			log.Fatal("MESSAGE_ENCRYPTION_KEY must be base64 of 32 bytes")
		}
		key = decoded
	} else {
		key = make([]byte, 32)
		copy(key, []byte("ihope-web-dev-only-key-32bytes!!"))
		log.Println("config: using insecure dev MESSAGE_ENCRYPTION_KEY")
	}

	return Config{
		HTTPAddr:              env("HTTP_ADDR", ":8090"),
		DatabaseURL:           env("DATABASE_URL", "postgres://ihope_web:webdevpassword@127.0.0.1:5434/ihope_web?sslmode=disable"),
		JWTSecret:             env("JWT_SECRET", "dev-change-me-jwt-secret-min-32-chars!!"),
		JWTAccessTTL:          time.Duration(envInt("JWT_ACCESS_TTL_MIN", 60)) * time.Minute,
		CORSOrigin:            env("CORS_ORIGIN", "http://localhost:5173"),
		MessageEncryptionKey:  key,
		UploadDir:             env("UPLOAD_DIR", "data/uploads"),
		AppPublicURL:          env("APP_PUBLIC_URL", "http://localhost:5173"),
		MailDriver:            env("MAIL_DRIVER", "log"),
		MailFrom:              env("MAIL_FROM", "noreply@localhost"),
		SMTPHost:              env("SMTP_HOST", ""),
		SMTPPort:              env("SMTP_PORT", "587"),
		SMTPUser:              env("SMTP_USER", ""),
		SMTPPass:              env("SMTP_PASS", ""),
		EmailVerifyTTL:        time.Duration(envInt("EMAIL_VERIFY_TTL_MIN", 1440)) * time.Minute,
		PasswordResetTTL:      time.Duration(envInt("PASSWORD_RESET_TTL_MIN", 60)) * time.Minute,
		UnverifiedUserTTL:     time.Duration(envInt("UNVERIFIED_USER_TTL_HOURS", 24)) * time.Hour,
		QQBotEnabled:          envBool("QQ_BOT_ENABLED", false),
		QQBotAppID:            strings.TrimSpace(env("QQ_BOT_APP_ID", "")),
		QQBotAppSecret:        strings.TrimSpace(env("QQ_BOT_APP_SECRET", "")),
		QQWebhookPath:         env("QQ_WEBHOOK_PATH", "/api/webhooks/qq"),
		QQBotAddHint:          env("QQ_BOT_ADD_HINT", "请在 QQ 中添加 IHope 机器人，并将绑定码发送给它"),
		QQDoorbellCooldownSec: envInt("QQ_DOORBELL_COOLDOWN_SEC", 600),
		QQQuotesFilePath:      env("QQ_QUOTES_FILE_PATH", ""),
		QQPoetryAPIURL:        env("QQ_POETRY_API_URL", "https://v1.hitokoto.cn/?c=i"),
		QQPoetryFontPath:      env("QQ_POETRY_FONT_PATH", ""),
		QQNews60sAPIURL:       env("QQ_NEWS_60S_API_URL", "https://60s.viki.moe/v2/60s?encoding=image-proxy"),
		QQDailyPoetryHHMM:     env("QQ_DAILY_POETRY_HHMM", "08:00"),
		QQDailyQuotesHHMM:     env("QQ_DAILY_QUOTES_HHMM", "08:02"),
		QQDailyNewsHHMM:       env("QQ_DAILY_NEWS_HHMM", "08:05"),
		FellowshipCode:        env("FELLOWSHIP_CODE", "盼望之地"),
		AdminToken:            env("ADMIN_TOKEN", "dev-admin-token-change-me"),
		CallTurnURLs:          env("CALL_TURN_URLS", ""),
		CallTurnUsername:      env("CALL_TURN_USERNAME", ""),
		CallTurnCredential:    env("CALL_TURN_CREDENTIAL", ""),
		WebDist:               strings.TrimSpace(env("WEB_DIST", "")),
	}
}

// 仅加载本目录 .env（或 ENV_FILE 显式指定的文件）。
func loadDotEnv() {
	if path := strings.TrimSpace(os.Getenv("ENV_FILE")); path != "" {
		if err := godotenv.Overload(path); err == nil {
			log.Printf("config: loaded %s", path)
		} else {
			log.Printf("config: ENV_FILE=%s not loaded: %v", path, err)
		}
		return
	}
	for _, path := range []string{".env", "../appserver/.env"} {
		if err := godotenv.Overload(path); err == nil {
			log.Printf("config: loaded %s", path)
			return
		}
	}
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envInt(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return n
}

func envBool(key string, fallback bool) bool {
	v := strings.ToLower(strings.TrimSpace(os.Getenv(key)))
	if v == "" {
		return fallback
	}
	return v == "1" || v == "true" || v == "yes" || v == "on"
}
