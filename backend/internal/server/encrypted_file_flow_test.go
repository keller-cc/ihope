package server_test

import (
	"bytes"
	"fmt"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/ihope/ihope/internal/testutil"
)

func TestEncryptedFileUploadFlow(t *testing.T) {
	handler := testutil.NewTestServer(t).Router()

	aEmail := fmt.Sprintf("file_a_%d@example.com", time.Now().UnixNano())
	bEmail := fmt.Sprintf("file_b_%d@example.com", time.Now().UnixNano())
	cEmail := fmt.Sprintf("file_c_%d@example.com", time.Now().UnixNano())
	password := "password123"
	deviceID := "file-device"

	_ = registerUser(t, handler, aEmail, fmt.Sprintf("file_a_%d", time.Now().UnixNano()%1_000_000_000), password)
	bUser := registerUser(t, handler, bEmail, fmt.Sprintf("file_b_%d", time.Now().UnixNano()%1_000_000_000), password)
	_ = registerUser(t, handler, cEmail, fmt.Sprintf("file_c_%d", time.Now().UnixNano()%1_000_000_000), password)

	aToken := loginToken(t, handler, aEmail, password, deviceID)
	bToken := loginToken(t, handler, bEmail, password, deviceID)
	cToken := loginToken(t, handler, cEmail, password, deviceID)

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

	blob := []byte("encrypted-blob-bytes-for-test")
	uploadRec := doMultipartUpload(t, handler, "/api/upload", aToken, convID, blob)
	if uploadRec.Code != http.StatusCreated {
		t.Fatalf("upload status = %d body = %s", uploadRec.Code, uploadRec.Body.String())
	}

	var uploadResp struct {
		FileID string `json:"file_id"`
	}
	decodeBody(t, uploadRec.Body, &uploadResp)
	if uploadResp.FileID == "" {
		t.Fatal("missing file_id")
	}

	downloadRec := doRawGET(t, handler, "/api/files/"+uploadResp.FileID, bToken)
	if downloadRec.Code != http.StatusOK {
		t.Fatalf("member download status = %d", downloadRec.Code)
	}
	if !bytes.Equal(downloadRec.Body.Bytes(), blob) {
		t.Fatalf("download body mismatch: got %q", downloadRec.Body.Bytes())
	}

	forbiddenRec := doRawGET(t, handler, "/api/files/"+uploadResp.FileID, cToken)
	if forbiddenRec.Code != http.StatusForbidden {
		t.Fatalf("non-member download status = %d, want 403", forbiddenRec.Code)
	}

	sendRec := doJSON(t, handler, http.MethodPost, "/api/conversations/"+convID+"/messages", map[string]string{
		"type":       "file",
		"ciphertext": "metadata-only-ciphertext",
		"file_id":    uploadResp.FileID,
	}, aToken)
	if sendRec.Code != http.StatusCreated {
		t.Fatalf("send message status = %d body = %s", sendRec.Code, sendRec.Body.String())
	}

	var sendResp struct {
		Message struct {
			FileID *string `json:"file_id"`
		} `json:"message"`
	}
	decodeBody(t, sendRec.Body, &sendResp)
	if sendResp.Message.FileID == nil || *sendResp.Message.FileID != uploadResp.FileID {
		t.Fatalf("message file_id = %v, want %s", sendResp.Message.FileID, uploadResp.FileID)
	}

	badSendRec := doJSON(t, handler, http.MethodPost, "/api/conversations/"+convID+"/messages", map[string]string{
		"type":       "file",
		"ciphertext": "bad file ref",
		"file_id":    "00000000-0000-0000-0000-000000000099",
	}, aToken)
	if badSendRec.Code != http.StatusBadRequest {
		t.Fatalf("invalid file_id send status = %d, want 400", badSendRec.Code)
	}
}

func doMultipartUpload(
	t *testing.T,
	handler http.Handler,
	path, bearer, conversationID string,
	data []byte,
) *httptest.ResponseRecorder {
	t.Helper()

	var body bytes.Buffer
	w := multipart.NewWriter(&body)
	if err := w.WriteField("conversation_id", conversationID); err != nil {
		t.Fatal(err)
	}
	part, err := w.CreateFormFile("file", "blob.bin")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := part.Write(data); err != nil {
		t.Fatal(err)
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}

	req := httptest.NewRequest(http.MethodPost, path, &body)
	req.Header.Set("Content-Type", w.FormDataContentType())
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}

func doRawGET(t *testing.T, handler http.Handler, path, bearer string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}
