package config

import (
	"encoding/base64"
	"log"
	"os"
	"path/filepath"
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
	QQBotEnabled          bool
	QQBotAppID            string
	QQBotAppSecret        string
	QQWebhookPath         string
	QQBotAddHint          string
	QQDoorbellCooldownSec  int
	QQQuotesFilePath      string
	FellowshipCode        string
	AdminToken            string
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

	// 共享项来自 deploy/.env；Web 隔离项由 appserver/.env 覆盖
	cors := firstNonEmpty(env("CORS_ORIGIN", ""), env("CORS_ALLOW_ORIGIN", ""), "http://localhost:5173")
	admin := firstNonEmpty(env("ADMIN_TOKEN", ""), env("ADMIN_SECRET", ""), "dev-admin-token-change-me")

	return Config{
		HTTPAddr:             env("HTTP_ADDR", ":8090"),
		DatabaseURL:          env("DATABASE_URL", "postgres://ihope_web:webdevpassword@127.0.0.1:5434/ihope_web?sslmode=disable"),
		JWTSecret:            env("JWT_SECRET", "dev-change-me-jwt-secret-min-32-chars!!"),
		JWTAccessTTL:         time.Duration(envInt("JWT_ACCESS_TTL_MIN", 60)) * time.Minute,
		CORSOrigin:           cors,
		MessageEncryptionKey: key,
		UploadDir:            env("UPLOAD_DIR", "uploads"),
		AppPublicURL:         env("APP_PUBLIC_URL", "http://localhost:5173"),
		MailDriver:           env("MAIL_DRIVER", "log"),
		MailFrom:             env("MAIL_FROM", "noreply@localhost"),
		SMTPHost:             env("SMTP_HOST", ""),
		SMTPPort:             env("SMTP_PORT", "587"),
		SMTPUser:             env("SMTP_USER", ""),
		SMTPPass:             env("SMTP_PASS", ""),
		EmailVerifyTTL:       time.Duration(envInt("EMAIL_VERIFY_TTL_MIN", 1440)) * time.Minute,
		QQBotEnabled:         envBool("QQ_BOT_ENABLED", false),
		QQBotAppID:           strings.TrimSpace(env("QQ_BOT_APP_ID", "")),
		QQBotAppSecret:       strings.TrimSpace(env("QQ_BOT_APP_SECRET", "")),
		QQWebhookPath:        env("QQ_WEBHOOK_PATH", "/api/webhooks/qq"),
		QQBotAddHint:         env("QQ_BOT_ADD_HINT", "请在 QQ 中添加 IHope 机器人，并将绑定码发送给它"),
		QQDoorbellCooldownSec: envInt("QQ_DOORBELL_COOLDOWN_SEC", 600),
		QQQuotesFilePath:     env("QQ_QUOTES_FILE_PATH", "../deploy/quotes/quotes.example.txt"),
		FellowshipCode:       env("FELLOWSHIP_CODE", "盼望之地"),
		AdminToken:           admin,
	}
}

// 先读共享 deploy/.env，再用 appserver/.env 覆盖（库、端口、Web 域名等）。
func loadDotEnv() {
	if path := strings.TrimSpace(os.Getenv("ENV_FILE")); path != "" {
		if err := godotenv.Overload(path); err == nil {
			log.Printf("config: shared %s", path)
		} else {
			log.Printf("config: ENV_FILE=%s not loaded: %v", path, err)
		}
	} else {
		loadedShared := false
		for _, path := range sharedEnvCandidates() {
			if err := godotenv.Overload(path); err == nil {
				log.Printf("config: shared %s", path)
				loadedShared = true
				break
			}
		}
		if !loadedShared {
			log.Println("config: no deploy/.env found; mail/QQ use process env or defaults")
		}
	}

	for _, path := range []string{".env", "../appserver/.env"} {
		if err := godotenv.Overload(path); err == nil {
			log.Printf("config: web overlay %s", path)
			return
		}
	}
}

func sharedEnvCandidates() []string {
	out := []string{"../deploy/.env", "../../deploy/.env", "deploy/.env"}
	dir, err := os.Getwd()
	if err != nil {
		return out
	}
	for i := 0; i < 8; i++ {
		out = append(out, filepath.Join(dir, "deploy", ".env"))
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return out
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
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
