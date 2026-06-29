package config

import (
	"os"
)

type Config struct {
	Port          string
	DatabaseURL   string
	JWTSecret     string
	AppPublicURL  string
	MailDriver    string
	MailFrom      string
	SMTPHost      string
	SMTPPort      string
	SMTPUser      string
	SMTPPass      string
}

func Load() Config {
	port := env("SERVER_PORT", "8080")
	dbPassword := env("DB_PASSWORD", "devpassword")
	dbUser := env("POSTGRES_USER", "ihope")
	dbName := env("POSTGRES_DB", "ihope")
	dbHost := env("DB_HOST", "localhost")

	return Config{
		Port:         port,
		DatabaseURL:  "postgres://" + dbUser + ":" + dbPassword + "@" + dbHost + ":5432/" + dbName + "?sslmode=disable",
		JWTSecret:    env("JWT_SECRET", "dev-only-change-in-production-min-32-chars"),
		AppPublicURL: env("APP_PUBLIC_URL", "http://localhost:"+port),
		MailDriver:   env("MAIL_DRIVER", "log"),
		MailFrom:     env("MAIL_FROM", "noreply@localhost"),
		SMTPHost:     env("SMTP_HOST", ""),
		SMTPPort:     env("SMTP_PORT", "587"),
		SMTPUser:     env("SMTP_USER", ""),
		SMTPPass:     env("SMTP_PASS", ""),
	}
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
