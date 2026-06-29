// Package config 从 deploy/.env 与环境变量加载配置。
package config

import (
	"log"
	"os"
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
	}
}

func loadDotEnv() {
	for _, path := range []string{os.Getenv("ENV_FILE"), "../deploy/.env", ".env", "../.env"} {
		if path == "" {
			continue
		}
		if err := godotenv.Overload(path); err == nil {
			log.Printf("config: loaded %s", path)
			return
		}
	}
}

func env(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
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

func envDurationSeconds(key string, fallbackSec int) time.Duration {
	return time.Duration(envInt(key, fallbackSec)) * time.Second
}

func envDurationMinutes(key string, fallbackMin int) time.Duration {
	return time.Duration(envInt(key, fallbackMin)) * time.Minute
}
