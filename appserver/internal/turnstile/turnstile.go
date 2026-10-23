package turnstile

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const siteVerifyURL = "https://challenges.cloudflare.com/turnstile/v0/siteverify"

var (
	ErrMissingToken = errors.New("turnstile token required")
	ErrInvalidToken = errors.New("turnstile failed")
)

// Verify checks a Turnstile response token with Cloudflare.
// When secret is empty, verification is skipped (dev / disabled).
func Verify(secret, response, remoteIP string) error {
	secret = strings.TrimSpace(secret)
	if secret == "" {
		return nil
	}
	response = strings.TrimSpace(response)
	if response == "" {
		return ErrMissingToken
	}

	form := url.Values{}
	form.Set("secret", secret)
	form.Set("response", response)
	if ip := strings.TrimSpace(remoteIP); ip != "" {
		form.Set("remoteip", ip)
	}

	client := &http.Client{Timeout: 8 * time.Second}
	resp, err := client.PostForm(siteVerifyURL, form)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrInvalidToken, err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return fmt.Errorf("%w: read body", ErrInvalidToken)
	}

	var out struct {
		Success    bool     `json:"success"`
		ErrorCodes []string `json:"error-codes"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return fmt.Errorf("%w: bad json", ErrInvalidToken)
	}
	if !out.Success {
		if len(out.ErrorCodes) > 0 {
			return fmt.Errorf("%w: %s", ErrInvalidToken, strings.Join(out.ErrorCodes, ","))
		}
		return ErrInvalidToken
	}
	return nil
}
