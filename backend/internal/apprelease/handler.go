package apprelease

import (
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"

	"github.com/ihope/ihope/internal/httpx"
)

type Handler struct {
	uploadDir string
}

func NewHandler(uploadDir string) *Handler {
	return &Handler{uploadDir: uploadDir}
}

// Download GET /api/app/download — 分发 uploads/releases/latest.apk（无需登录）
func (h *Handler) Download(w http.ResponseWriter, r *http.Request) {
	path := filepath.Join(h.uploadDir, "releases", "latest.apk")
	f, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			httpx.WriteError(w, http.StatusNotFound, "not_found", "release apk not found; place file at uploads/releases/latest.apk")
			return
		}
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not open release")
		return
	}
	defer f.Close()

	stat, err := f.Stat()
	if err != nil || stat.IsDir() {
		httpx.WriteError(w, http.StatusNotFound, "not_found", "release apk not found")
		return
	}

	w.Header().Set("Content-Type", "application/vnd.android.package-archive")
	w.Header().Set("Content-Disposition", `attachment; filename="ihope-latest.apk"`)
	w.Header().Set("Content-Length", strconv.FormatInt(stat.Size(), 10))
	w.WriteHeader(http.StatusOK)
	_, _ = io.Copy(w, f)
}
