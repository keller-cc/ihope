package push

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

const fcmMessagingScope = "https://www.googleapis.com/auth/firebase.messaging"

// fcmV1Sender 使用 FCM HTTP v1（服务账号 JSON，Firebase 当前推荐方式）。
type fcmV1Sender struct {
	projectID   string
	tokenSource oauth2.TokenSource
	client      *http.Client
}

type fcmServiceAccountMeta struct {
	ProjectID string `json:"project_id"`
}

func newFCMV1Sender(credentialsFile, projectIDOverride string) (*fcmV1Sender, error) {
	path := resolveFCMCredentialsPath(strings.TrimSpace(credentialsFile))
	if path == "" {
		return nil, fmt.Errorf("fcm v1: empty credentials file")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("fcm v1: read credentials: %w", err)
	}
	return newFCMV1SenderFromJSON(raw, projectIDOverride)
}

func newFCMV1SenderFromJSON(raw []byte, projectIDOverride string) (*fcmV1Sender, error) {
	if len(bytes.TrimSpace(raw)) == 0 {
		return nil, fmt.Errorf("fcm v1: empty credentials json")
	}

	projectID := strings.TrimSpace(projectIDOverride)
	if projectID == "" {
		id, err := readFCMProjectIDFromJSON(raw)
		if err != nil {
			return nil, err
		}
		projectID = id
	}

	ctx := context.Background()
	creds, err := google.CredentialsFromJSON(ctx, raw, fcmMessagingScope)
	if err != nil {
		return nil, fmt.Errorf("fcm v1: load credentials: %w", err)
	}

	return &fcmV1Sender{
		projectID:   projectID,
		tokenSource: creds.TokenSource,
		client:      &http.Client{Timeout: 10 * time.Second},
	}, nil
}

func resolveFCMCredentialsPath(path string) string {
	path = strings.TrimSpace(path)
	if path == "" {
		return ""
	}
	if _, err := os.Stat(path); err == nil {
		return path
	}
	if filepath.IsAbs(path) {
		return path
	}
	if envFile := strings.TrimSpace(os.Getenv("ENV_FILE")); envFile != "" {
		candidate := filepath.Join(filepath.Dir(envFile), path)
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	for _, base := range []string{"../deploy", "deploy"} {
		candidate := filepath.Join(base, path)
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	return path
}

func readFCMProjectID(path string) (string, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("fcm v1: read credentials: %w", err)
	}
	return readFCMProjectIDFromJSON(raw)
}

func readFCMProjectIDFromJSON(raw []byte) (string, error) {
	var meta fcmServiceAccountMeta
	if err := json.Unmarshal(raw, &meta); err != nil {
		return "", fmt.Errorf("fcm v1: parse credentials: %w", err)
	}
	if strings.TrimSpace(meta.ProjectID) == "" {
		return "", fmt.Errorf("fcm v1: project_id missing in credentials")
	}
	return meta.ProjectID, nil
}

func (f *fcmV1Sender) Send(ctx context.Context, token, platform string, p Payload) error {
	accessToken, err := f.tokenSource.Token()
	if err != nil {
		return fmt.Errorf("fcm v1: oauth token: %w", err)
	}
	if accessToken.AccessToken == "" {
		return fmt.Errorf("fcm v1: empty access token")
	}

	data := stringifyPushExtras(pushExtras(p))
	body := map[string]any{
		"message": map[string]any{
			"token": token,
			"data":  data,
		},
	}
	if platform == "android" || platform == "fcm" {
		body["message"].(map[string]any)["android"] = map[string]any{
			"priority": "HIGH",
		}
	}

	raw, err := json.Marshal(body)
	if err != nil {
		return err
	}

	url := fmt.Sprintf(
		"https://fcm.googleapis.com/v1/projects/%s/messages:send",
		f.projectID,
	)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(raw))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken.AccessToken)
	req.Header.Set("Content-Type", "application/json; charset=UTF-8")

	res, err := f.client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()

	if res.StatusCode < 200 || res.StatusCode >= 300 {
		slug, _ := io.ReadAll(io.LimitReader(res.Body, 4096))
		return fmt.Errorf("fcm v1: http %d: %s", res.StatusCode, strings.TrimSpace(string(slug)))
	}
	return nil
}

func stringifyPushExtras(src map[string]string) map[string]string {
	out := make(map[string]string, len(src))
	for k, v := range src {
		out[k] = v
	}
	return out
}

// fcmLegacySender 使用已弃用的 Legacy HTTP API（仅当仍能拿到 Server key 时）。
type fcmLegacySender struct {
	serverKey string
	client    *http.Client
}

func (f *fcmLegacySender) Send(ctx context.Context, token, platform string, p Payload) error {
	if f.client == nil {
		f.client = &http.Client{Timeout: 10 * time.Second}
	}

	data := pushExtras(p)
	body := map[string]any{
		"to":       token,
		"priority": "high",
		"data":     data,
	}
	if platform == "android" || platform == "fcm" {
		body["android"] = map[string]any{"priority": "high"}
	}

	raw, err := json.Marshal(body)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		"https://fcm.googleapis.com/fcm/send",
		bytes.NewReader(raw),
	)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "key="+f.serverKey)
	req.Header.Set("Content-Type", "application/json")

	res, err := f.client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()

	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return fmt.Errorf("fcm legacy: http %d", res.StatusCode)
	}
	return nil
}

var fcmInitOnce sync.Once

func newFCMSender(credentialsJSON, credentialsFile, projectID, serverKey string) Sender {
	credentialsJSON = strings.TrimSpace(credentialsJSON)
	credentialsFile = strings.TrimSpace(credentialsFile)
	projectID = strings.TrimSpace(projectID)
	serverKey = strings.TrimSpace(serverKey)

	if credentialsJSON != "" {
		s, err := newFCMV1SenderFromJSON([]byte(credentialsJSON), projectID)
		if err != nil {
			fcmInitOnce.Do(func() {
				log.Printf("push: fcm v1 disabled: %v", err)
			})
		} else {
			return s
		}
	}

	if credentialsFile != "" {
		s, err := newFCMV1Sender(credentialsFile, projectID)
		if err != nil {
			fcmInitOnce.Do(func() {
				log.Printf("push: fcm v1 disabled: %v", err)
			})
		} else {
			return s
		}
	}

	if serverKey != "" {
		return &fcmLegacySender{serverKey: serverKey}
	}

	return nil
}
