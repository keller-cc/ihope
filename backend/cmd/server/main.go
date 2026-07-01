package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/ihope/ihope/internal/auth"
	"github.com/ihope/ihope/internal/config"
	"github.com/ihope/ihope/internal/conversation"
	"github.com/ihope/ihope/internal/db"
	"github.com/ihope/ihope/internal/jwt"
	"github.com/ihope/ihope/internal/mail"
	"github.com/ihope/ihope/internal/message"
	"github.com/ihope/ihope/internal/server"
	signalkds "github.com/ihope/ihope/internal/signal"
	"github.com/ihope/ihope/internal/user"
	"github.com/ihope/ihope/internal/ws"
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
	msgSvc := message.NewService(msgRepo, convRepo)
	wsHandler := ws.NewHandler(hub, jwtMgr, userRepo, convSvc, msgSvc)
	convNotify := server.NewConvRealtime(hub)
	convSys := server.NewConvSystemMessenger(msgSvc)
	signalRepo := signalkds.NewRepository(pool)
	signalSvc := signalkds.NewService(signalRepo)

	srv := server.New(
		cfg,
		auth.NewHandler(authSvc),
		user.NewHandler(userRepo, cfg),
		userRepo,
		jwtMgr,
		conversation.NewHandler(convSvc, convNotify, convSys, cfg),
		message.NewHandler(msgSvc, convSvc, hub),
		wsHandler,
		signalkds.NewHandler(signalSvc),
	)

	httpServer := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: srv.Router(),
	}

	go func() {
		log.Printf("server listening on http://localhost:%s", cfg.Port)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = httpServer.Shutdown(shutdownCtx)
}
