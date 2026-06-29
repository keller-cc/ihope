package testutil

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/ihope/ihope/internal/auth"
	"github.com/ihope/ihope/internal/config"
	"github.com/ihope/ihope/internal/db"
	"github.com/ihope/ihope/internal/jwt"
	"github.com/ihope/ihope/internal/mail"
	"github.com/ihope/ihope/internal/server"
	"github.com/ihope/ihope/internal/user"
	"github.com/jackc/pgx/v5/pgxpool"
)

func DatabaseURL() string {
	if v := os.Getenv("TEST_DATABASE_URL"); v != "" {
		return v
	}
	return os.Getenv("DATABASE_URL")
}

func OpenPool(t *testing.T) *pgxpool.Pool {
	t.Helper()

	url := DatabaseURL()
	if url == "" {
		cfg := config.Load()
		url = cfg.DatabaseURL
	}

	ctx := context.Background()
	pool, err := db.Connect(ctx, url)
	if err != nil {
		t.Skipf("database not available: %v", err)
	}
	if err := db.Migrate(ctx, pool); err != nil {
		pool.Close()
		t.Fatalf("migrate: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func TestConfig() config.Config {
	return config.Config{
		Port:            "8080",
		JWTSecret:       "test-secret-at-least-32-characters-long",
		JWTAccessTTL:    15 * time.Minute,
		AppPublicURL:    "http://localhost:8080",
		CORSAllowOrigin: "*",
		MailDriver:      "log",
		LoginRateLimit:  5,
		LoginRateWindow: time.Minute,
		ResetTokenTTL:   30 * time.Minute,
	}
}

func NewTestServer(t *testing.T) *server.Server {
	t.Helper()

	pool := OpenPool(t)
	cfg := TestConfig()

	userRepo := user.NewRepository(pool)
	jwtMgr := jwt.NewManager(cfg.JWTSecret, cfg.JWTAccessTTL)
	authSvc := auth.NewService(cfg, userRepo, jwtMgr, mail.New(cfg))

	return server.New(cfg, auth.NewHandler(authSvc), user.NewHandler(userRepo), userRepo, jwtMgr)
}
