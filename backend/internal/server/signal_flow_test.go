package server_test

import (
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/ihope/ihope/internal/testutil"
)

func TestSignalFlowIntegration(t *testing.T) {
	handler := testutil.NewTestServer(t).Router()

	aEmail := fmt.Sprintf("sig_a_%d@example.com", time.Now().UnixNano())
	bEmail := fmt.Sprintf("sig_b_%d@example.com", time.Now().UnixNano())
	password := "password123"
	deviceA := "signal-device-a"
	deviceB := "signal-device-b"

	aUser := registerUser(t, handler, aEmail, fmt.Sprintf("sig_a_%d", time.Now().UnixNano()%1_000_000_000), password)
	bUser := registerUser(t, handler, bEmail, fmt.Sprintf("sig_b_%d", time.Now().UnixNano()%1_000_000_000), password)

	aToken := loginToken(t, handler, aEmail, password, deviceA)
	bToken := loginToken(t, handler, bEmail, password, deviceB)

	noBundleRec := doJSON(t, handler, http.MethodGet, "/api/users/"+aUser.ID+"/signal-bundle", nil, bToken)
	if noBundleRec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 before upload, got %d body=%s", noBundleRec.Code, noBundleRec.Body.String())
	}

	uploadRec := doJSON(t, handler, http.MethodPut, "/api/users/me/signal-keys", signalKeysBody(deviceA), aToken)
	if uploadRec.Code != http.StatusOK {
		t.Fatalf("upload keys status = %d body = %s", uploadRec.Code, uploadRec.Body.String())
	}
	var uploadResp struct {
		OK bool `json:"ok"`
	}
	decodeBody(t, uploadRec.Body, &uploadResp)
	if !uploadResp.OK {
		t.Fatal("expected ok=true after upload")
	}

	devicesRec := doJSON(t, handler, http.MethodGet, "/api/users/"+aUser.ID+"/signal-devices", nil, bToken)
	if devicesRec.Code != http.StatusOK {
		t.Fatalf("list devices status = %d body = %s", devicesRec.Code, devicesRec.Body.String())
	}
	var devicesResp struct {
		DeviceIDs []string `json:"device_ids"`
	}
	decodeBody(t, devicesRec.Body, &devicesResp)
	if len(devicesResp.DeviceIDs) != 1 || devicesResp.DeviceIDs[0] != deviceA {
		t.Fatalf("device_ids = %+v, want [%s]", devicesResp.DeviceIDs, deviceA)
	}

	bundleRec := doJSON(t, handler, http.MethodGet, "/api/users/"+aUser.ID+"/signal-bundle?device_id="+deviceA, nil, bToken)
	if bundleRec.Code != http.StatusOK {
		t.Fatalf("fetch bundle status = %d body = %s", bundleRec.Code, bundleRec.Body.String())
	}
	var bundle struct {
		DeviceID        string `json:"device_id"`
		IdentityKey     string `json:"identity_key"`
		SignedPreKey    string `json:"signed_pre_key_public"`
		SignedPreKeySig string `json:"signed_pre_key_signature"`
		PreKeyPublic    string `json:"pre_key_public"`
	}
	decodeBody(t, bundleRec.Body, &bundle)
	if bundle.DeviceID != deviceA {
		t.Fatalf("bundle device_id = %q", bundle.DeviceID)
	}
	if bundle.IdentityKey != testutil.TestSignalIdentityKey {
		t.Fatalf("identity_key mismatch")
	}
	if bundle.PreKeyPublic == "" {
		t.Fatal("expected one-time pre key in bundle")
	}

	// Bob uploads keys; Alice can fetch Bob's bundle without device_id query.
	_ = bUser
	uploadBRec := doJSON(t, handler, http.MethodPut, "/api/users/me/signal-keys", signalKeysBody(deviceB), bToken)
	if uploadBRec.Code != http.StatusOK {
		t.Fatalf("bob upload keys status = %d", uploadBRec.Code)
	}
	pickRec := doJSON(t, handler, http.MethodGet, "/api/users/"+bUser.ID+"/signal-bundle", nil, aToken)
	if pickRec.Code != http.StatusOK {
		t.Fatalf("pick bundle status = %d body = %s", pickRec.Code, pickRec.Body.String())
	}
}

func signalKeysBody(deviceID string) map[string]any {
	return map[string]any{
		"device_id":                 deviceID,
		"signal_device_id":          1,
		"registration_id":           12345,
		"identity_key":              testutil.TestSignalIdentityKey,
		"signed_pre_key_id":         1,
		"signed_pre_key_public":     testutil.TestSignalSignedPreKey,
		"signed_pre_key_signature":  testutil.TestSignalSignedPreKeySig,
		"one_time_pre_keys": []map[string]any{
			{"pre_key_id": 1, "public_key": testutil.TestSignalOneTimePreKey},
			{"pre_key_id": 2, "public_key": testutil.TestSignalOneTimePreKey},
		},
	}
}
