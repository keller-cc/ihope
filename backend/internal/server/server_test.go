package server

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ihope/ihope/internal/auth"
	"github.com/ihope/ihope/internal/config"
	"github.com/ihope/ihope/internal/jwt"
	"github.com/ihope/ihope/internal/user"
)

func TestHealthEndpoint(t *testing.T) {
	cfg := config.Config{
		CORSAllowOrigin: "*",
		LoginRateLimit:  5,
		LoginRateWindow: time.Minute,
	}
	jwtMgr := jwt.NewManager("test-secret-at-least-32-characters-long", 15*time.Minute)
	srv := New(cfg, auth.NewHandler(nil), user.NewHandler(nil), nil, jwtMgr)

	rec := httptest.NewRecorder()
	srv.Router().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/health", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	var body map[string]any
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if body["ok"] != true {
		t.Fatalf("unexpected body: %+v", body)
	}
}
