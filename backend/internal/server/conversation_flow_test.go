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

	var groupResp struct {
		Conversation struct {
			ID      string `json:"id"`
			Epoch   int    `json:"epoch"`
			Members []struct {
				UserID string `json:"user_id"`
			} `json:"members"`
		} `json:"conversation"`
	}
	decodeBody(t, groupRec.Body, &groupResp)
	groupID := groupResp.Conversation.ID
	if groupID == "" {
		t.Fatal("missing group id")
	}
	if groupResp.Conversation.Epoch != 0 {
		t.Fatalf("expected initial epoch 0, got %d", groupResp.Conversation.Epoch)
	}
	if len(groupResp.Conversation.Members) != 2 {
		t.Fatalf("expected owner+b in group, got %d members", len(groupResp.Conversation.Members))
	}

	sendGroupRec := doJSON(t, handler, http.MethodPost, "/api/conversations/"+groupID+"/messages", map[string]string{
		"type":       "text",
		"ciphertext": "before invite",
	}, aToken)
	if sendGroupRec.Code != http.StatusCreated {
		t.Fatalf("send group message status = %d", sendGroupRec.Code)
	}

	cEmail := fmt.Sprintf("conv_c_%d@example.com", time.Now().UnixNano())
	cUser := registerUser(t, handler, cEmail, fmt.Sprintf("user_c_%d", time.Now().UnixNano()%1_000_000_000), password)
	cToken := loginToken(t, handler, cEmail, password, deviceID+"-c")

	addRec := doJSON(t, handler, http.MethodPost, "/api/conversations/"+groupID+"/members", map[string]any{
		"member_ids": []string{cUser.ID},
	}, aToken)
	if addRec.Code != http.StatusOK {
		t.Fatalf("add member status = %d body = %s", addRec.Code, addRec.Body.String())
	}

	sendAfterRec := doJSON(t, handler, http.MethodPost, "/api/conversations/"+groupID+"/messages", map[string]string{
		"type":       "text",
		"ciphertext": "after invite",
	}, aToken)
	if sendAfterRec.Code != http.StatusCreated {
		t.Fatalf("send after invite status = %d", sendAfterRec.Code)
	}

	cListRec := doJSON(t, handler, http.MethodGet, "/api/conversations/"+groupID+"/messages", nil, cToken)
	if cListRec.Code != http.StatusOK {
		t.Fatalf("new member list status = %d body = %s", cListRec.Code, cListRec.Body.String())
	}
	var cList struct {
		Messages []struct {
			Ciphertext string `json:"ciphertext"`
		} `json:"messages"`
	}
	decodeBody(t, cListRec.Body, &cList)
	if len(cList.Messages) != 1 || cList.Messages[0].Ciphertext != "after invite" {
		t.Fatalf("new member should only see post-join messages, got %+v", cList.Messages)
	}
}

func registerUser(t *testing.T, handler http.Handler, email, username, password string) struct{ ID string } {
	t.Helper()
	rec := doJSON(t, handler, http.MethodPost, "/api/auth/register", map[string]string{
		"email":               email,
		"username":            username,
		"password":            password,
		"identity_public_key": testutil.TestIdentityPublicKey,
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
