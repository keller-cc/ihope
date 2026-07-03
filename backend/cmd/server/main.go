package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/ihope/ihope/internal/admin"
	"github.com/ihope/ihope/internal/auth"
	"github.com/ihope/ihope/internal/config"
	"github.com/ihope/ihope/internal/conversation"
	"github.com/ihope/ihope/internal/db"
	"github.com/ihope/ihope/internal/devicelink"
	"github.com/ihope/ihope/internal/filestore"
	"github.com/ihope/ihope/internal/jwt"
	"github.com/ihope/ihope/internal/mail"
	"github.com/ihope/ihope/internal/message"
	"github.com/ihope/ihope/internal/server"
	signalkds "github.com/ihope/ihope/internal/signal"
	"github.com/ihope/ihope/internal/user"
	"github.com/ihope/ihope/internal/ws"
	"github.com/ihope/ihope/internal/lifecycle"
	"github.com/ihope/ihope/internal/push"
)

func main() {
	cfg := config.Load()
	ctx := context.Background()

	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database: %v", err)
	}
	defer pool.Close()

	if err := db.Migrate(ctx, pool); err != nil {
		log.Fatalf("migrate: %v", err)
	}

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

	srv := server.New(
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

	httpServer := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: srv.Router(),
	}

	done := make(chan struct{})
	lifecycle.SetDrainWait(time.Duration(cfg.DrainSeconds) * time.Second)
	lifecycle.SetShutdownFunc(func() {
		hub.CloseAll()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), time.Duration(cfg.DrainSeconds+5)*time.Second)
		defer cancel()
		if err := httpServer.Shutdown(shutdownCtx); err != nil {
			log.Printf("shutdown: %v", err)
		}
		close(done)
	})

	go func() {
		log.Printf("server listening on http://localhost:%s (version=%s)", cfg.Port, cfg.ServerVersion)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	sig := <-quit
	// Ctrl+C：本地开发快速退出；SIGTERM：生产滚动升级保留完整排空。
	wait := time.Duration(cfg.DrainSeconds) * time.Second
	if sig == syscall.SIGINT && wait > time.Second {
		wait = time.Second
	}
	lifecycle.SetDrainWait(wait)
	log.Printf("signal received (%v), draining %s...", sig, wait)
	lifecycle.RequestDrain()
	<-done
	log.Printf("server stopped")
}
