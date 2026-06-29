// 集成测试：完整账号 API 流程（需本地 PostgreSQL，否则 Skip）。
package server_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ihope/ihope/internal/auth"
	"github.com/ihope/ihope/internal/jwt"
	"github.com/ihope/ihope/internal/mail"
	"github.com/ihope/ihope/internal/server"
	"github.com/ihope/ihope/internal/testutil"
	"github.com/ihope/ihope/internal/user"
)

func TestAuthFlowIntegration(t *testing.T) {
	srv := testutil.NewTestServer(t)
	handler := srv.Router()

	email := fmt.Sprintf("test_%d@example.com", time.Now().UnixNano())
	username := fmt.Sprintf("user_%d", time.Now().UnixNano()%1_000_000_000)
	password := "password123"
	deviceID := "postman-test-device"

	// register
	regBody := map[string]string{
		"email":               email,
		"username":            username,
		"password":            password,
		"identity_public_key": "dGVzdF9pZGVudGl0eV9rZXk=",
	}
	regRec := doJSON(t, handler, http.MethodPost, "/api/auth/register", regBody, "")
	if regRec.Code != http.StatusCreated {
		t.Fatalf("register status = %d body = %s", regRec.Code, regRec.Body.String())
	}

	// login
	loginBody := map[string]string{
		"email":       email,
		"password":    password,
		"device_id":   deviceID,
		"device_name": "Integration Test",
	}
	loginRec := doJSON(t, handler, http.MethodPost, "/api/auth/login", loginBody, "")
	if loginRec.Code != http.StatusOK {
		t.Fatalf("login status = %d body = %s", loginRec.Code, loginRec.Body.String())
	}

	var loginResp struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	}
	decodeBody(t, loginRec.Body, &loginResp)
	if loginResp.AccessToken == "" || loginResp.RefreshToken == "" {
		t.Fatalf("missing tokens: %+v", loginResp)
	}

	// me
	meRec := doJSON(t, handler, http.MethodGet, "/api/users/me", nil, loginResp.AccessToken)
	if meRec.Code != http.StatusOK {
		t.Fatalf("me status = %d body = %s", meRec.Code, meRec.Body.String())
	}

	// refresh
	refreshRec := doJSON(t, handler, http.MethodPost, "/api/auth/refresh", map[string]string{
		"refresh_token": loginResp.RefreshToken,
		"device_id":     deviceID,
	}, "")
	if refreshRec.Code != http.StatusOK {
		t.Fatalf("refresh status = %d body = %s", refreshRec.Code, refreshRec.Body.String())
	}

	// forgot password
	forgotRec := doJSON(t, handler, http.MethodPost, "/api/auth/forgot-password", map[string]string{
		"email": email,
	}, "")
	if forgotRec.Code != http.StatusOK {
		t.Fatalf("forgot status = %d body = %s", forgotRec.Code, forgotRec.Body.String())
	}
}

func TestResetPasswordFlowIntegration(t *testing.T) {
	pool := testutil.OpenPool(t)
	cfg := testutil.TestConfig()
	capture := &mail.CapturingSender{}

	userRepo := user.NewRepository(pool)
	jwtMgr := jwt.NewManager(cfg.JWTSecret, cfg.JWTAccessTTL)
	authSvc := auth.NewService(cfg, userRepo, jwtMgr, capture)
	handler := server.New(cfg, auth.NewHandler(authSvc), user.NewHandler(userRepo), userRepo, jwtMgr).Router()

	email := fmt.Sprintf("reset_%d@example.com", time.Now().UnixNano())
	username := fmt.Sprintf("reset_%d", time.Now().UnixNano()%1_000_000_000)
	deviceID := "reset-device"

	doJSON(t, handler, http.MethodPost, "/api/auth/register", map[string]string{
		"email":               email,
		"username":            username,
		"password":            "password123",
		"identity_public_key": "dGVzdA==",
	}, "")

	loginRec := doJSON(t, handler, http.MethodPost, "/api/auth/login", map[string]string{
		"email": email, "password": "password123", "device_id": deviceID, "device_name": "t",
	}, "")
	var loginResp struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	}
	decodeBody(t, loginRec.Body, &loginResp)

	doJSON(t, handler, http.MethodPost, "/api/auth/forgot-password", map[string]string{"email": email}, "")
	token := mail.ExtractTokenFromResetURL(capture.LastResetURL)
	if token == "" {
		t.Fatalf("missing reset token in url %q", capture.LastResetURL)
	}

	resetRec := doJSON(t, handler, http.MethodPost, "/api/auth/reset-password", map[string]string{
		"token": token, "password": "newpassword123",
	}, "")
	if resetRec.Code != http.StatusOK {
		t.Fatalf("reset status = %d body = %s", resetRec.Code, resetRec.Body.String())
	}

	meRec := doJSON(t, handler, http.MethodGet, "/api/users/me", nil, loginResp.AccessToken)
	if meRec.Code != http.StatusUnauthorized {
		t.Fatalf("old access token should fail after reset, got %d", meRec.Code)
	}

	refreshRec := doJSON(t, handler, http.MethodPost, "/api/auth/refresh", map[string]string{
		"refresh_token": loginResp.RefreshToken,
		"device_id":     deviceID,
	}, "")
	if refreshRec.Code != http.StatusUnauthorized {
		t.Fatalf("old refresh should fail, got %d", refreshRec.Code)
	}

	newLoginRec := doJSON(t, handler, http.MethodPost, "/api/auth/login", map[string]string{
		"email": email, "password": "newpassword123", "device_id": deviceID,
	}, "")
	if newLoginRec.Code != http.StatusOK {
		t.Fatalf("login with new password failed: %s", newLoginRec.Body.String())
	}
}

func TestChangePasswordFlowIntegration(t *testing.T) {
	srv := testutil.NewTestServer(t)
	handler := srv.Router()

	email := fmt.Sprintf("change_%d@example.com", time.Now().UnixNano())
	username := fmt.Sprintf("change_%d", time.Now().UnixNano()%1_000_000_000)
	deviceID := "change-device"
	password := "password123"

	doJSON(t, handler, http.MethodPost, "/api/auth/register", map[string]string{
		"email":               email,
		"username":            username,
		"password":            password,
		"identity_public_key": "dGVzdA==",
	}, "")

	loginRec := doJSON(t, handler, http.MethodPost, "/api/auth/login", map[string]string{
		"email": email, "password": password, "device_id": deviceID, "device_name": "t",
	}, "")
	var loginResp struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	}
	decodeBody(t, loginRec.Body, &loginResp)

	changeRec := doJSON(t, handler, http.MethodPost, "/api/auth/change-password", map[string]string{
		"current_password": password,
		"new_password":     "newpassword123",
	}, loginResp.AccessToken)
	if changeRec.Code != http.StatusOK {
		t.Fatalf("change password status = %d body = %s", changeRec.Code, changeRec.Body.String())
	}

	meRec := doJSON(t, handler, http.MethodGet, "/api/users/me", nil, loginResp.AccessToken)
	if meRec.Code != http.StatusUnauthorized {
		t.Fatalf("old access token should fail after change, got %d", meRec.Code)
	}

	refreshRec := doJSON(t, handler, http.MethodPost, "/api/auth/refresh", map[string]string{
		"refresh_token": loginResp.RefreshToken,
		"device_id":     deviceID,
	}, "")
	if refreshRec.Code != http.StatusUnauthorized {
		t.Fatalf("old refresh should fail after change, got %d", refreshRec.Code)
	}

	newLoginRec := doJSON(t, handler, http.MethodPost, "/api/auth/login", map[string]string{
		"email": email, "password": "newpassword123", "device_id": deviceID,
	}, "")
	if newLoginRec.Code != http.StatusOK {
		t.Fatalf("login with new password failed: %s", newLoginRec.Body.String())
	}
}

func TestLoginInvalidCredentials(t *testing.T) {
	srv := testutil.NewTestServer(t)
	handler := srv.Router()

	rec := doJSON(t, handler, http.MethodPost, "/api/auth/login", map[string]string{
		"email":     "nobody@example.com",
		"password":  "password123",
		"device_id": "x",
	}, "")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

func TestUsersMeUnauthorized(t *testing.T) {
	srv := testutil.NewTestServer(t)
	handler := srv.Router()

	rec := doJSON(t, handler, http.MethodGet, "/api/users/me", nil, "")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

func doJSON(t *testing.T, handler http.Handler, method, path string, body any, bearer string) *httptest.ResponseRecorder {
	t.Helper()

	var reader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		reader = bytes.NewReader(b)
	}

	req := httptest.NewRequest(method, path, reader)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}

func decodeBody(t *testing.T, r io.Reader, dst any) {
	t.Helper()
	if err := json.NewDecoder(r).Decode(dst); err != nil {
		t.Fatal(err)
	}
}
