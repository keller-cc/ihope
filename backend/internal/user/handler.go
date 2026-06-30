package user

import (
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/ihope/ihope/internal/config"
	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/middleware"
)

var usernamePattern = regexp.MustCompile(`^[a-zA-Z0-9_]{3,32}$`)

var (
	ErrInvalidUsername = errors.New("invalid username")
	ErrInvalidAvatar   = errors.New("invalid avatar file")
)

// Handler 用户资料 HTTP 接口。
type Handler struct {
	repo          *Repository
	publicURL     string
	uploadDir     string
	maxAvatarSize int64
}

func NewHandler(repo *Repository, cfg config.Config) *Handler {
	return &Handler{
		repo:          repo,
		publicURL:     strings.TrimRight(cfg.AppPublicURL, "/"),
		uploadDir:     cfg.UploadDir,
		maxAvatarSize: cfg.MaxAvatarBytes,
	}
}

type updateMeRequest struct {
	Username string `json:"username"`
}

// Me GET /api/users/me
func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	if userID == "" {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "missing user")
		return
	}

	u, err := h.repo.GetByID(r.Context(), userID)
	if errors.Is(err, ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not_found", "user not found")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not load user")
		return
	}

	httpx.WriteJSON(w, http.StatusOK, u)
}

// UpdateMe PATCH /api/users/me — 修改用户名。
func (h *Handler) UpdateMe(w http.ResponseWriter, r *http.Request) {
	var req updateMeRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}

	username := strings.TrimSpace(req.Username)
	if !usernamePattern.MatchString(username) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "invalid username")
		return
	}

	userID := middleware.UserIDFromContext(r.Context())
	u, err := h.repo.UpdateUsername(r.Context(), userID, username)
	if errors.Is(err, ErrUsernameTaken) {
		httpx.WriteError(w, http.StatusConflict, "username_taken", "username already taken")
		return
	}
	if errors.Is(err, ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not_found", "user not found")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not update profile")
		return
	}

	httpx.WriteJSON(w, http.StatusOK, u)
}

// UploadAvatar POST /api/users/me/avatar — multipart 字段 avatar。
func (h *Handler) UploadAvatar(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	if userID == "" {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "missing user")
		return
	}

	if err := r.ParseMultipartForm(h.maxAvatarSize + 1024); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_form", "invalid multipart form")
		return
	}

	file, header, err := r.FormFile("avatar")
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_form", "avatar file required")
		return
	}
	defer file.Close()

	ext, err := validateAvatarFile(file, header, h.maxAvatarSize)
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}

	avatarDir := filepath.Join(h.uploadDir, "avatars")
	if err := os.MkdirAll(avatarDir, 0o755); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not store avatar")
		return
	}

	filename := fmt.Sprintf("%s%s", userID, ext)
	destPath := filepath.Join(avatarDir, filename)
	if err := saveAvatarFile(destPath, file); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not store avatar")
		return
	}

  avatarURL := "/api/avatars/" + filename
	u, err := h.repo.UpdateAvatarURL(r.Context(), userID, avatarURL)
	if err != nil {
		_ = os.Remove(destPath)
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not update profile")
		return
	}

	httpx.WriteJSON(w, http.StatusOK, u)
}

// ServeAvatar GET /api/avatars/{filename}
func (h *Handler) ServeAvatar(w http.ResponseWriter, r *http.Request) {
	filename := filepath.Base(r.PathValue("filename"))
	if !safeAvatarFilename(filename) {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_file", "invalid filename")
		return
	}

	path := filepath.Join(h.uploadDir, "avatars", filename)
	http.ServeFile(w, r, path)
}

// List GET /api/users
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	limit := 50
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			limit = n
		}
	}
	if limit > 100 {
		limit = 100
	}

	users, err := h.repo.ListPublic(r.Context(), userID, r.URL.Query().Get("q"), limit)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not list users")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"users": users})
}

func validateAvatarFile(file multipart.File, header *multipart.FileHeader, maxBytes int64) (string, error) {
	if header.Size > maxBytes {
		return "", ErrInvalidAvatar
	}

	head := make([]byte, 512)
	n, err := file.Read(head)
	if err != nil {
		return "", ErrInvalidAvatar
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return "", ErrInvalidAvatar
	}

	contentType := http.DetectContentType(head[:n])
	switch contentType {
	case "image/jpeg":
		return ".jpg", nil
	case "image/png":
		return ".png", nil
	case "image/gif":
		return ".gif", nil
	case "image/webp":
		return ".webp", nil
	default:
		return "", ErrInvalidAvatar
	}
}

func saveAvatarFile(path string, src multipart.File) error {
	dst, err := os.Create(path)
	if err != nil {
		return err
	}
	defer dst.Close()

	if _, err := io.Copy(dst, src); err != nil {
		_ = os.Remove(path)
		return err
	}
	return nil
}

func safeAvatarFilename(name string) bool {
	if name == "" || name == "." || name == ".." {
		return false
	}
	ext := strings.ToLower(filepath.Ext(name))
	switch ext {
	case ".jpg", ".jpeg", ".png", ".gif", ".webp":
		return !strings.Contains(name, "..") && !strings.ContainsAny(name, `/\`)
	default:
		return false
	}
}
