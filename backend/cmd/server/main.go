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
	"github.com/ihope/ihope/internal/db"
	"github.com/ihope/ihope/internal/jwt"
	"github.com/ihope/ihope/internal/mail"
	"github.com/ihope/ihope/internal/server"
	"github.com/ihope/ihope/internal/user"
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
	jwtMgr := jwt.NewManager(cfg.JWTSecret, cfg.JWTAccessTTL)
	authSvc := auth.NewService(cfg, userRepo, jwtMgr, mail.New(cfg))
	srv := server.New(cfg, auth.NewHandler(authSvc), user.NewHandler(userRepo), userRepo, jwtMgr)

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
