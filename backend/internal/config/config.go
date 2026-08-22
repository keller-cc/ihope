// Package config 从 deploy/.env 与环境变量加载配置。
package config

import (
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

// Config 应用运行时配置（与 deploy/.env 一一对应）。
type Config struct {
	Port            string
	DatabaseURL     string
	JWTSecret       string
	JWTAccessTTL    time.Duration
	RefreshTokenTTL time.Duration
	AppPublicURL    string
	CORSAllowOrigin string
	MailDriver      string
	MailFrom        string
	SMTPHost        string
	SMTPPort        string
	SMTPUser        string
	SMTPPass        string
	LoginRateLimit  int
	LoginRateWindow time.Duration
	ResetTokenTTL   time.Duration
	EmailVerifyTTL  time.Duration
	UploadDir       string
	MaxAvatarBytes  int64
	MaxEncryptedFileBytes int64
	CloudDriveURL         string
	ServerVersion         string
	DrainSeconds          int
	AppDownloadURL        string
	PushDriver            string
	FCMServerKey          string
	FCMCredentialsFile    string
	FCMCredentialsJSON    string
	FCMProjectID          string
	JPushAppKey        string
	JPushMasterSecret  string
	AdminSecret string

	QQBotEnabled         bool
	QQBotAppID           string
	QQBotAppSecret       string
	QQWebhookPath        string
	QQPoetryAPIURL       string
	QQNews60sAPIURL      string
	QQPoetryFontPath     string
	QQDailyPoetryHHMM    string
	QQDailyNewsHHMM      string
	QQDoorbellCooldownSec int
	QQBotAddHint         string
}

// Load 读取 .env 与环境变量。
func Load() Config {
	loadDotEnv()

	port := env("SERVER_PORT", "8080")
	dbPassword := env("DB_PASSWORD", "devpassword")
	dbUser := env("POSTGRES_USER", "ihope")
	dbName := env("POSTGRES_DB", "ihope")
	dbHost := env("DB_HOST", "127.0.0.1")
	dbPort := env("DB_PORT", "5432")

	return Config{
		Port:            port,
		DatabaseURL:     "postgres://" + dbUser + ":" + dbPassword + "@" + dbHost + ":" + dbPort + "/" + dbName + "?sslmode=disable",
		JWTSecret:       env("JWT_SECRET", "dev-only-change-in-production-min-32-chars"),
		JWTAccessTTL:    envDurationMinutes("JWT_ACCESS_TTL_MIN", 15),
		RefreshTokenTTL: envDurationDays("REFRESH_TOKEN_TTL_DAYS", 30),
		AppPublicURL:    env("APP_PUBLIC_URL", "http://localhost:"+port),
		CORSAllowOrigin: env("CORS_ALLOW_ORIGIN", "*"),
		MailDriver:      env("MAIL_DRIVER", "log"),
		MailFrom:        env("MAIL_FROM", "noreply@localhost"),
		SMTPHost:        env("SMTP_HOST", ""),
		SMTPPort:        env("SMTP_PORT", "587"),
		SMTPUser:        env("SMTP_USER", ""),
		SMTPPass:        env("SMTP_PASS", ""),
		LoginRateLimit:  envInt("LOGIN_RATE_LIMIT", 5),
		LoginRateWindow: envDurationSeconds("LOGIN_RATE_WINDOW_SEC", 60),
		ResetTokenTTL:   envDurationMinutes("RESET_TOKEN_TTL_MIN", 30),
		EmailVerifyTTL:  envDurationMinutes("EMAIL_VERIFY_TTL_MIN", 24*60),
		UploadDir:       env("UPLOAD_DIR", "uploads"),
		MaxAvatarBytes:  int64(envInt("MAX_AVATAR_BYTES", 2*1024*1024)),
		// 0 = 不限制；默认 300MB
		MaxEncryptedFileBytes: int64(envIntAllowZero("MAX_ENCRYPTED_FILE_BYTES", 300*1024*1024)),
		CloudDriveURL:         env("CLOUD_DRIVE_URL", "https://1t1.org"),
		ServerVersion:         env("SERVER_VERSION", "2026-07-03 0.1.0 version"),
		DrainSeconds:          envInt("DRAIN_SECONDS", 15),
		AppDownloadURL:        env("APP_DOWNLOAD_URL", ""),
		PushDriver:        env("PUSH_DRIVER", "log"),
		FCMServerKey:       env("FCM_SERVER_KEY", ""),
		FCMCredentialsFile: env("FCM_CREDENTIALS_FILE", ""),
		FCMCredentialsJSON: env("FCM_CREDENTIALS_JSON", ""),
		FCMProjectID:       env("FCM_PROJECT_ID", ""),
		JPushAppKey:       env("JPUSH_APP_KEY", ""),
		JPushMasterSecret: env("JPUSH_MASTER_SECRET", ""),
		AdminSecret: env("ADMIN_SECRET", ""),

		QQBotEnabled:         envBool("QQ_BOT_ENABLED", false),
		QQBotAppID:           strings.TrimSpace(env("QQ_BOT_APP_ID", "")),
		QQBotAppSecret:       strings.TrimSpace(env("QQ_BOT_APP_SECRET", "")),
		QQWebhookPath:        env("QQ_WEBHOOK_PATH", "/api/webhooks/qq"),
		QQPoetryAPIURL:       env("QQ_POETRY_API_URL", "https://v1.hitokoto.cn/?c=i"),
		QQNews60sAPIURL:      env("QQ_NEWS_60S_API_URL", "https://60s.viki.moe/v2/60s?encoding=image-proxy"),
		QQPoetryFontPath:     env("QQ_POETRY_FONT_PATH", ""),
		QQDailyPoetryHHMM:    env("QQ_DAILY_POETRY_HHMM", "08:00"),
		QQDailyNewsHHMM:      env("QQ_DAILY_NEWS_HHMM", "08:05"),
		QQDoorbellCooldownSec: envInt("QQ_DOORBELL_COOLDOWN_SEC", 600),
		QQBotAddHint:         env("QQ_BOT_ADD_HINT", "请在 QQ 中添加 IHope 机器人，并将绑定码发送给它"),
	}
}

func loadDotEnv() {
	if path := strings.TrimSpace(os.Getenv("ENV_FILE")); path != "" {
		if err := godotenv.Overload(path); err == nil {
			log.Printf("config: loaded %s", path)
		}
		return
	}

	for _, path := range []string{"../deploy/.env", ".env", "../.env"} {
		if err := godotenv.Overload(path); err == nil {
			log.Printf("config: loaded %s", path)
			return
		}
	}

	// go test 在 internal/*/ 子目录运行，../deploy/.env 会找不到；向上查找 deploy/.env
	dir, err := os.Getwd()
	for i := 0; i < 8 && err == nil; i++ {
		candidate := filepath.Join(dir, "deploy", ".env")
		if err := godotenv.Overload(candidate); err == nil {
			log.Printf("config: loaded %s", candidate)
			return
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
}

func env(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

func envBool(key string, fallback bool) bool {
	v := strings.TrimSpace(strings.ToLower(os.Getenv(key)))
	if v == "" {
		return fallback
	}
	switch v {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	default:
		log.Printf("config: invalid %s=%q, use default %v", key, v, fallback)
		return fallback
	}
}

func envInt(key string, fallback int) int {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil || n <= 0 {
		log.Printf("config: invalid %s=%q, use default %d", key, v, fallback)
		return fallback
	}
	return n
}

func envIntAllowZero(key string, fallback int) int {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil || n < 0 {
		log.Printf("config: invalid %s=%q, use default %d", key, v, fallback)
		return fallback
	}
	return n
}

func envDurationSeconds(key string, fallbackSec int) time.Duration {
	return time.Duration(envInt(key, fallbackSec)) * time.Second
}

func envDurationMinutes(key string, fallbackMin int) time.Duration {
	return time.Duration(envInt(key, fallbackMin)) * time.Minute
}

func envDurationDays(key string, fallbackDays int) time.Duration {
	d := envInt(key, fallbackDays)
	if d <= 0 {
		return 0
	}
	return time.Duration(d) * 24 * time.Hour
}

// ClientAppDownloadURL App 更新包地址；未设 APP_DOWNLOAD_URL 时用 APP_PUBLIC_URL/api/app/download。
func (c Config) ClientAppDownloadURL() string {
	if u := strings.TrimSpace(c.AppDownloadURL); u != "" {
		return u
	}
	base := strings.TrimRight(c.AppPublicURL, "/")
	if base == "" {
		return ""
	}
	return base + "/api/app/download"
}
