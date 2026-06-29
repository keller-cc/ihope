package server_test

import (
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/ihope/ihope/internal/testutil"
)

func TestConversationFlowIntegration(t *testing.T) {
	handler := testutil.NewTestServer(t).Router()

	aEmail := fmt.Sprintf("conv_a_%d@example.com", time.Now().UnixNano())
	bEmail := fmt.Sprintf("conv_b_%d@example.com", time.Now().UnixNano())
	password := "password123"
	deviceID := "conv-device"

	_ = registerUser(t, handler, aEmail, fmt.Sprintf("user_a_%d", time.Now().UnixNano()%1_000_000_000), password)
	bUser := registerUser(t, handler, bEmail, fmt.Sprintf("user_b_%d", time.Now().UnixNano()%1_000_000_000), password)

	aToken := loginToken(t, handler, aEmail, password, deviceID)
	bToken := loginToken(t, handler, bEmail, password, deviceID)

	usersRec := doJSON(t, handler, http.MethodGet, "/api/users", nil, aToken)
	if usersRec.Code != http.StatusOK {
		t.Fatalf("list users status = %d body = %s", usersRec.Code, usersRec.Body.String())
	}

	createRec := doJSON(t, handler, http.MethodPost, "/api/conversations", map[string]string{
		"type":         "private",
		"peer_user_id": bUser.ID,
	}, aToken)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create private status = %d body = %s", createRec.Code, createRec.Body.String())
	}

	var createResp struct {
		Conversation struct {
			ID string `json:"id"`
		} `json:"conversation"`
	}
	decodeBody(t, createRec.Body, &createResp)
	convID := createResp.Conversation.ID
	if convID == "" {
		t.Fatal("missing conversation id")
	}

	dupRec := doJSON(t, handler, http.MethodPost, "/api/conversations", map[string]string{
		"type":         "private",
		"peer_user_id": bUser.ID,
	}, aToken)
	if dupRec.Code != http.StatusCreated {
		t.Fatalf("duplicate private status = %d", dupRec.Code)
	}
	var dupResp struct {
		Conversation struct {
			ID string `json:"id"`
		} `json:"conversation"`
	}
	decodeBody(t, dupRec.Body, &dupResp)
	if dupResp.Conversation.ID != convID {
		t.Fatalf("expected same private conversation, got %s vs %s", dupResp.Conversation.ID, convID)
	}

	sendRec := doJSON(t, handler, http.MethodPost, "/api/conversations/"+convID+"/messages", map[string]string{
		"type":       "text",
		"ciphertext": "hello from A",
	}, aToken)
	if sendRec.Code != http.StatusCreated {
		t.Fatalf("send message status = %d body = %s", sendRec.Code, sendRec.Body.String())
	}

	listRec := doJSON(t, handler, http.MethodGet, "/api/conversations/"+convID+"/messages", nil, bToken)
	if listRec.Code != http.StatusOK {
		t.Fatalf("list messages status = %d body = %s", listRec.Code, listRec.Body.String())
	}

	convListRec := doJSON(t, handler, http.MethodGet, "/api/conversations", nil, bToken)
	if convListRec.Code != http.StatusOK {
		t.Fatalf("list conversations status = %d body = %s", convListRec.Code, convListRec.Body.String())
	}

	groupRec := doJSON(t, handler, http.MethodPost, "/api/conversations", map[string]any{
		"type":        "group",
		"name":        "Test Group",
		"member_ids":  []string{bUser.ID},
	}, aToken)
	if groupRec.Code != http.StatusCreated {
		t.Fatalf("create group status = %d body = %s", groupRec.Code, groupRec.Body.String())
	}
}

func registerUser(t *testing.T, handler http.Handler, email, username, password string) struct{ ID string } {
	t.Helper()
	rec := doJSON(t, handler, http.MethodPost, "/api/auth/register", map[string]string{
		"email":               email,
		"username":            username,
		"password":            password,
		"identity_public_key": "dGVzdA==",
	}, "")
	if rec.Code != http.StatusCreated {
		t.Fatalf("register status = %d body = %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		User struct {
			ID string `json:"id"`
		} `json:"user"`
	}
	decodeBody(t, rec.Body, &resp)
	return struct{ ID string }{ID: resp.User.ID}
}

func loginToken(t *testing.T, handler http.Handler, email, password, deviceID string) string {
	t.Helper()
	rec := doJSON(t, handler, http.MethodPost, "/api/auth/login", map[string]string{
		"email": email, "password": password, "device_id": deviceID, "device_name": "test",
	}, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("login status = %d body = %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		AccessToken string `json:"access_token"`
	}
	decodeBody(t, rec.Body, &resp)
	if resp.AccessToken == "" {
		t.Fatal("missing access token")
	}
	return resp.AccessToken
}
