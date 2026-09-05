package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/keller-cc/ihope/appserver/internal/admin"
	"github.com/keller-cc/ihope/appserver/internal/auth"
	"github.com/keller-cc/ihope/appserver/internal/call"
	"github.com/keller-cc/ihope/appserver/internal/chat"
	"github.com/keller-cc/ihope/appserver/internal/config"
	"github.com/keller-cc/ihope/appserver/internal/db"
	"github.com/keller-cc/ihope/appserver/internal/hub"
	"github.com/keller-cc/ihope/appserver/internal/httpserver"
	"github.com/keller-cc/ihope/appserver/internal/mail"
	"github.com/keller-cc/ihope/appserver/internal/qqbot"
)

func main() {
	cfg := config.Load()
	ctx := context.Background()

	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("db connect: %v", err)
	}
	defer pool.Close()

	if err := db.Migrate(ctx, pool); err != nil {
		log.Fatalf("migrate: %v", err)
	}

	mailer := mail.New(mail.Config{
		Driver:    cfg.MailDriver,
		From:      cfg.MailFrom,
		SMTPHost:  cfg.SMTPHost,
		SMTPPort:  cfg.SMTPPort,
		SMTPUser:  cfg.SMTPUser,
		SMTPPass:  cfg.SMTPPass,
		VerifyTTL: cfg.EmailVerifyTTL,
	})

	authSvc := auth.NewService(pool, auth.Options{
		JWTSecret:      cfg.JWTSecret,
		AccessTTL:      cfg.JWTAccessTTL,
		AppPublicURL:   cfg.AppPublicURL,
		EmailVerifyTTL: cfg.EmailVerifyTTL,
		MailDriver:     cfg.MailDriver,
		Mailer:         mailer,
		FellowshipCode: cfg.FellowshipCode,
	})
	if err := authSvc.EnsureFellowshipsBootstrapped(ctx); err != nil {
		log.Fatalf("fellowship bootstrap: %v", err)
	}
	chatSvc := chat.NewService(pool, cfg.MessageEncryptionKey)
	if err := chatSvc.BackfillGroupNos(ctx); err != nil {
		log.Printf("backfill group nos: %v", err)
	}
	adminSvc := admin.NewService(pool)
	h := hub.New()

	var ice []call.ICEServer
	if urls := strings.TrimSpace(cfg.CallTurnURLs); urls != "" {
		parts := strings.Split(urls, ",")
		list := make([]string, 0, len(parts))
		for _, p := range parts {
			p = strings.TrimSpace(p)
			if p != "" {
				list = append(list, p)
			}
		}
		if len(list) > 0 {
			ice = append(ice, call.ICEServer{
				URLs:       list,
				Username:   cfg.CallTurnUsername,
				Credential: cfg.CallTurnCredential,
			})
		}
	}
	ice = append(ice, call.ICEServer{
		URLs: []string{"stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"},
	})
	callSvc := call.New(h, call.ChatMembership{Chat: chatSvc, Hub: h}, ice)

	var qqSvc *qqbot.Service
	var qqSched *qqbot.Scheduler
	uploadDir := cfg.UploadDir
	if uploadDir == "" {
		uploadDir = "data/uploads"
	}
	if cfg.QQBotEnabled {
		client := qqbot.NewClient(cfg.QQBotAppID, cfg.QQBotAppSecret)
		media := qqbot.NewMediaHost(uploadDir, cfg.AppPublicURL)
		qqSvc = qqbot.NewService(cfg, qqbot.NewStore(pool), client, media, h)
		qqSched = qqbot.NewScheduler(qqSvc, cfg.QQDailyPoetryHHMM, cfg.QQDailyQuotesHHMM, cfg.QQDailyNewsHHMM)
		qqSched.Start()
		log.Println("qq bot enabled")
	}

	srv := httpserver.New(authSvc, chatSvc, adminSvc, h, callSvc, qqSvc, cfg.CORSOrigin, cfg.QQWebhookPath, cfg.AdminToken, uploadDir, cfg.QQQuotesFilePath, cfg.WebDist)
	_ = os.MkdirAll(filepath.Join(uploadDir, "avatars"), 0o755)
	_ = os.MkdirAll(filepath.Join(uploadDir, "groups"), 0o755)
	_ = os.MkdirAll(filepath.Join(uploadDir, "chat"), 0o755)
	_ = os.MkdirAll(filepath.Join(uploadDir, "chat-bg"), 0o755)

	httpSrv := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		if cfg.WebDist != "" {
			log.Printf("appserver listening on %s (web dist %s)", cfg.HTTPAddr, cfg.WebDist)
		} else {
			log.Printf("appserver listening on %s", cfg.HTTPAddr)
		}
		if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("http: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	if qqSched != nil {
		qqSched.Stop()
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = httpSrv.Shutdown(shutdownCtx)
}
