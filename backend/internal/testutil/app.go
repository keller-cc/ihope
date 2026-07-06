package testutil

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/ihope/ihope/internal/admin"
	"github.com/ihope/ihope/internal/auth"
	"github.com/ihope/ihope/internal/config"
	"github.com/ihope/ihope/internal/conversation"
	"github.com/ihope/ihope/internal/devicelink"
	"github.com/ihope/ihope/internal/filestore"
	"github.com/ihope/ihope/internal/db"
	"github.com/ihope/ihope/internal/jwt"
	"github.com/ihope/ihope/internal/mail"
	"github.com/ihope/ihope/internal/message"
	"github.com/ihope/ihope/internal/push"
	"github.com/ihope/ihope/internal/server"
	signalkds "github.com/ihope/ihope/internal/signal"
	"github.com/ihope/ihope/internal/user"
	"github.com/ihope/ihope/internal/ws"
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
		EmailVerifyTTL:  24 * time.Hour,
		UploadDir:       "uploads",
		MaxAvatarBytes:  2 * 1024 * 1024,
		MaxEncryptedFileBytes: 300 * 1024 * 1024,
		CloudDriveURL:         "https://1t1.org",
		ServerVersion:         "2026-07-03 0.1.0 version",
		DrainSeconds:          5,
		RefreshTokenTTL: 30 * 24 * time.Hour,
	}
}

func NewTestServer(t *testing.T) *server.Server {
	t.Helper()

	pool := OpenPool(t)
	cfg := TestConfig()
	cfg.UploadDir = t.TempDir()

	userRepo := user.NewRepository(pool)
	convRepo := conversation.NewRepository(pool)
	msgRepo := message.NewRepository(pool)

	jwtMgr := jwt.NewManager(cfg.JWTSecret, cfg.JWTAccessTTL)
	authSvc := auth.NewService(cfg, userRepo, jwtMgr, mail.New(cfg))
	convSvc := conversation.NewService(convRepo, userRepo)

	hub := ws.NewHub()
	fileRepo := filestore.NewRepository(pool)
	fileSvc := filestore.NewService(fileRepo, convRepo, cfg.UploadDir, cfg.MaxEncryptedFileBytes)
	msgSvc := message.NewService(msgRepo, convRepo, fileSvc)
	pushSvc := push.New(cfg)
	pushDispatch := push.NewDispatcher(pushSvc, userRepo, convRepo, hub)
	msgNotify := server.NewMessageNotifier(hub, pushDispatch)
	wsHandler := ws.NewHandler(hub, msgNotify, jwtMgr, userRepo, convSvc, msgSvc)
	convNotify := server.NewConvRealtime(hub)
	convSys := server.NewConvSystemMessenger(msgSvc)

	signalRepo := signalkds.NewRepository(pool)
	signalSvc := signalkds.NewService(signalRepo)
	deviceLinkRepo := devicelink.NewRepository(pool)
	deviceLinkSvc := devicelink.NewService(deviceLinkRepo, 5*time.Minute)

	return server.New(
		cfg,
		auth.NewHandler(authSvc),
		user.NewHandler(userRepo, cfg),
		userRepo,
		jwtMgr,
		conversation.NewHandler(convSvc, convNotify, convSys, cfg),
		message.NewHandler(msgSvc, convSvc, msgNotify),
		wsHandler,
		signalkds.NewHandler(signalSvc),
		admin.NewHandler(userRepo, hub, cfg.RefreshTokenTTL, admin.RuntimeConfigFrom(cfg)),
		devicelink.NewHandler(deviceLinkSvc),
		filestore.NewHandler(fileSvc),
	)
}
