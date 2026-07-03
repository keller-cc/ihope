package server_test

import (
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/ihope/ihope/internal/testutil"
)

func TestUserDevicesListAndKickIntegration(t *testing.T) {
	srv := testutil.NewTestServer(t)
	handler := srv.Router()

	email := fmt.Sprintf("udev_%d@example.com", time.Now().UnixNano())
	username := fmt.Sprintf("udev_%d", time.Now().UnixNano()%1_000_000_000)
	deviceA := "device-a-list"
	deviceB := "device-b-kick"

	doJSON(t, handler, http.MethodPost, "/api/auth/register", map[string]string{
		"email":               email,
		"username":            username,
		"password":            "password123",
		"identity_public_key": testutil.TestIdentityPublicKey,
	}, "")

	loginA := doJSON(t, handler, http.MethodPost, "/api/auth/login", map[string]string{
		"email": email, "password": "password123", "device_id": deviceA, "device_name": "Phone",
	}, "")
	var tokensA struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	}
	decodeBody(t, loginA.Body, &tokensA)

	loginB := doJSON(t, handler, http.MethodPost, "/api/auth/login", map[string]string{
		"email": email, "password": "password123", "device_id": deviceB, "device_name": "Tablet",
	}, "")
	var tokensB struct {
		RefreshToken string `json:"refresh_token"`
	}
	decodeBody(t, loginB.Body, &tokensB)

	listRec := doJSON(t, handler, http.MethodGet, "/api/devices", nil, tokensA.AccessToken)
	if listRec.Code != http.StatusOK {
		t.Fatalf("list devices status = %d body = %s", listRec.Code, listRec.Body.String())
	}
	var listResp struct {
		Devices []struct {
			DeviceID  string `json:"device_id"`
			IsCurrent bool   `json:"is_current"`
		} `json:"devices"`
	}
	decodeBody(t, listRec.Body, &listResp)
	if len(listResp.Devices) < 2 {
		t.Fatalf("devices = %d, want >= 2", len(listResp.Devices))
	}

	kickSelf := doJSON(t, handler, http.MethodDelete, "/api/devices/"+deviceA, nil, tokensA.AccessToken)
	if kickSelf.Code != http.StatusNoContent {
		t.Fatalf("kick self status = %d, want 204", kickSelf.Code)
	}

	refreshSelf := doJSON(t, handler, http.MethodPost, "/api/auth/refresh", map[string]string{
		"refresh_token": tokensA.RefreshToken,
		"device_id":     deviceA,
	}, "")
	if refreshSelf.Code != http.StatusUnauthorized {
		t.Fatalf("kicked self refresh should fail, got %d", refreshSelf.Code)
	}

	kickRec := doJSON(t, handler, http.MethodDelete, "/api/devices/"+deviceB, nil, tokensA.AccessToken)
	if kickRec.Code != http.StatusNoContent {
		t.Fatalf("kick other status = %d body = %s", kickRec.Code, kickRec.Body.String())
	}

	refreshRec := doJSON(t, handler, http.MethodPost, "/api/auth/refresh", map[string]string{
		"refresh_token": tokensB.RefreshToken,
		"device_id":     deviceB,
	}, "")
	if refreshRec.Code != http.StatusUnauthorized {
		t.Fatalf("kicked device refresh should fail, got %d body=%s", refreshRec.Code, refreshRec.Body.String())
	}
}
