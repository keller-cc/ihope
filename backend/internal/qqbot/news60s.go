package qqbot

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Fetch60sImage 拉取「每天60秒读懂世界」图片字节。
func Fetch60sImage(ctx context.Context, apiURL string) ([]byte, error) {
	apiURL = strings.TrimSpace(apiURL)
	if apiURL == "" {
		return nil, fmt.Errorf("60s api url empty")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, apiURL, nil)
	if err != nil {
		return nil, err
	}
	client := &http.Client{
		Timeout: 45 * time.Second,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 8 {
				return fmt.Errorf("too many redirects")
			}
			return nil
		},
	}
	res, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return nil, fmt.Errorf("60s image: http %d", res.StatusCode)
	}
	raw, err := io.ReadAll(io.LimitReader(res.Body, 12<<20))
	if err != nil {
		return nil, err
	}
	if len(raw) < 32 {
		return nil, fmt.Errorf("60s image: too small")
	}
	return raw, nil
}
