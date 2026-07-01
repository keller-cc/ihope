package server_test

import (
	"bytes"
	"fmt"
	"mime/multipart"
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

// 1x1 PNG
var tinyPNG = []byte{
	0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
	0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
	0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
	0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
	0x42, 0x60, 0x82,
}

func TestProfileFlowIntegration(t *testing.T) {
	pool := testutil.OpenPool(t)
	cfg := testutil.TestConfig()
	cfg.UploadDir = t.TempDir()

	userRepo := user.NewRepository(pool)
	jwtMgr := jwt.NewManager(cfg.JWTSecret, cfg.JWTAccessTTL)
	authSvc := auth.NewService(cfg, userRepo, jwtMgr, mail.New(cfg))
	handler := server.New(cfg, auth.NewHandler(authSvc), user.NewHandler(userRepo, cfg), userRepo, jwtMgr, nil, nil, nil, nil).Router()

	email := fmt.Sprintf("profile_%d@example.com", time.Now().UnixNano())
	username := fmt.Sprintf("prof_%d", time.Now().UnixNano()%1_000_000_000)
	newUsername := fmt.Sprintf("new_%d", time.Now().UnixNano()%1_000_000_000)
	password := "password123"

	doJSON(t, handler, http.MethodPost, "/api/auth/register", map[string]string{
		"email":               email,
		"username":            username,
		"password":            password,
		"identity_public_key": testutil.TestIdentityPublicKey,
	}, "")

	loginRec := doJSON(t, handler, http.MethodPost, "/api/auth/login", map[string]string{
		"email": email, "password": password, "device_id": "profile-device", "device_name": "t",
	}, "")
	var loginResp struct {
		AccessToken string `json:"access_token"`
		User        struct {
			ID string `json:"id"`
		} `json:"user"`
	}
	decodeBody(t, loginRec.Body, &loginResp)

	patchRec := doJSON(t, handler, http.MethodPatch, "/api/users/me", map[string]string{
		"username": newUsername,
	}, loginResp.AccessToken)
	if patchRec.Code != http.StatusOK {
		t.Fatalf("patch username status = %d body = %s", patchRec.Code, patchRec.Body.String())
	}

	meRec := doJSON(t, handler, http.MethodGet, "/api/users/me", nil, loginResp.AccessToken)
	var me struct {
		Username string `json:"username"`
	}
	decodeBody(t, meRec.Body, &me)
	if me.Username != newUsername {
		t.Fatalf("username = %q, want %q", me.Username, newUsername)
	}

	avatarRec := doMultipartAvatar(t, handler, loginResp.AccessToken, tinyPNG)
	if avatarRec.Code != http.StatusOK {
		t.Fatalf("upload avatar status = %d body = %s", avatarRec.Code, avatarRec.Body.String())
	}

	var avatarResp struct {
		AvatarURL *string `json:"avatar_url"`
	}
	decodeBody(t, avatarRec.Body, &avatarResp)
	if avatarResp.AvatarURL == nil || *avatarResp.AvatarURL == "" {
		t.Fatal("missing avatar_url")
	}

	getAvatar := doJSON(t, handler, http.MethodGet, "/api/avatars/"+loginResp.User.ID+".png", nil, "")
	if getAvatar.Code != http.StatusOK {
		t.Fatalf("get avatar status = %d", getAvatar.Code)
	}
}

func doMultipartAvatar(t *testing.T, handler http.Handler, bearer string, data []byte) *httptest.ResponseRecorder {
	t.Helper()

	var body bytes.Buffer
	w := multipart.NewWriter(&body)
	part, err := w.CreateFormFile("avatar", "avatar.png")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := part.Write(data); err != nil {
		t.Fatal(err)
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/users/me/avatar", &body)
	req.Header.Set("Content-Type", w.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+bearer)

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}
