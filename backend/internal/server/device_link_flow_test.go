package server_test

import (
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/ihope/ihope/internal/testutil"
)

func TestDeviceLinkFlowIntegration(t *testing.T) {
	srv := testutil.NewTestServer(t)
	handler := srv.Router()

	email := fmt.Sprintf("link_%d@example.com", time.Now().UnixNano())
	username := fmt.Sprintf("link_%d", time.Now().UnixNano()%1_000_000_000)
	oldDevice := "old-device-link"
	newDevice := "new-device-link"

	regRec := doJSON(t, handler, http.MethodPost, "/api/auth/register", map[string]string{
		"email":               email,
		"username":            username,
		"password":            "password123",
		"identity_public_key": testutil.TestIdentityPublicKey,
	}, "")
	verifyRegisteredEmail(t, handler, regRec)

	oldLogin := doJSON(t, handler, http.MethodPost, "/api/auth/login", map[string]string{
		"email": email, "password": "password123", "device_id": oldDevice, "device_name": "old",
	}, "")
	var oldTokens struct {
		AccessToken string `json:"access_token"`
	}
	decodeBody(t, oldLogin.Body, &oldTokens)

	initRec := doJSON(t, handler, http.MethodPost, "/api/device-link/init", nil, oldTokens.AccessToken)
	if initRec.Code != http.StatusCreated {
		t.Fatalf("init status = %d body = %s", initRec.Code, initRec.Body.String())
	}
	var initResp struct {
		LinkID string `json:"link_id"`
		Token  string `json:"token"`
	}
	decodeBody(t, initRec.Body, &initResp)
	if initResp.LinkID == "" || initResp.Token == "" {
		t.Fatalf("init response missing fields: %+v", initResp)
	}

	payloadRec := doJSON(t, handler, http.MethodPut, "/api/device-link/"+initResp.LinkID+"/payload", map[string]string{
		"ciphertext": "e2ee-test-bundle",
	}, oldTokens.AccessToken)
	if payloadRec.Code != http.StatusNoContent {
		t.Fatalf("payload status = %d body = %s", payloadRec.Code, payloadRec.Body.String())
	}

	newLogin := doJSON(t, handler, http.MethodPost, "/api/auth/login", map[string]string{
		"email": email, "password": "password123", "device_id": newDevice, "device_name": "new",
	}, "")
	var newTokens struct {
		AccessToken string `json:"access_token"`
	}
	decodeBody(t, newLogin.Body, &newTokens)

	completeRec := doJSON(t, handler, http.MethodPost, "/api/device-link/complete", map[string]string{
		"token": initResp.Token,
	}, newTokens.AccessToken)
	if completeRec.Code != http.StatusOK {
		t.Fatalf("complete status = %d body = %s", completeRec.Code, completeRec.Body.String())
	}
	var completeResp struct {
		Ciphertext string `json:"ciphertext"`
	}
	decodeBody(t, completeRec.Body, &completeResp)
	if completeResp.Ciphertext != "e2ee-test-bundle" {
		t.Fatalf("ciphertext = %q", completeResp.Ciphertext)
	}

	repeat := doJSON(t, handler, http.MethodPost, "/api/device-link/complete", map[string]string{
		"token": initResp.Token,
	}, newTokens.AccessToken)
	if repeat.Code != http.StatusConflict {
		t.Fatalf("repeat complete status = %d, want 409", repeat.Code)
	}
}
