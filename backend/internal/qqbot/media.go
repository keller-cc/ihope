package qqbot

import (
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// MediaHost 将 PNG 落到可被 QQ 下载的公开路径。
type MediaHost struct {
	dir       string
	publicBase string // e.g. https://im.clprince.top/api/public/qq-media
	mu        sync.Mutex
}

func NewMediaHost(uploadDir, appPublicURL string) *MediaHost {
	dir := filepath.Join(uploadDir, "qq-media")
	_ = os.MkdirAll(dir, 0o755)
	base := strings.TrimRight(appPublicURL, "/") + "/api/public/qq-media"
	return &MediaHost{dir: dir, publicBase: base}
}

func (m *MediaHost) Dir() string { return m.dir }

// Put 写入文件并返回公开 URL；ttl 后尽力删除。
func (m *MediaHost) Put(png []byte, ttl time.Duration) (string, error) {
	id, err := randomHex(16)
	if err != nil {
		return "", err
	}
	name := id + ".png"
	path := filepath.Join(m.dir, name)
	if err := os.WriteFile(path, png, 0o644); err != nil {
		return "", err
	}
	if ttl > 0 {
		go func() {
			time.Sleep(ttl)
			_ = os.Remove(path)
		}()
	}
	return m.publicBase + "/" + name, nil
}

func (m *MediaHost) Read(name string) ([]byte, error) {
	name = filepath.Base(name)
	if !strings.HasSuffix(strings.ToLower(name), ".png") {
		return nil, os.ErrNotExist
	}
	return os.ReadFile(filepath.Join(m.dir, name))
}
