package filestore

import (
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/middleware"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// Upload POST /api/upload — multipart: conversation_id + file（流式写入，非分片续传）
func (h *Handler) Upload(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	reader, err := r.MultipartReader()
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_form", "invalid multipart form")
		return
	}

	var conversationID string
	var fileBody io.ReadCloser
	var fileSize int64

	for {
		part, err := reader.NextPart()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			httpx.WriteError(w, http.StatusBadRequest, "invalid_form", "invalid multipart form")
			return
		}

		switch part.FormName() {
		case "conversation_id":
			b, _ := io.ReadAll(io.LimitReader(part, 128))
			conversationID = strings.TrimSpace(string(b))
			_ = part.Close()
		case "file":
			if fileBody != nil {
				_ = part.Close()
				httpx.WriteError(w, http.StatusBadRequest, "invalid_form", "duplicate file field")
				return
			}
			fileBody = part
			if cl := part.Header.Get("Content-Length"); cl != "" {
				if n, err := strconv.ParseInt(cl, 10, 64); err == nil {
					fileSize = n
				}
			}
			// 文件 part 须最后消费；不可在打开时继续 NextPart
			goto upload
		default:
			_, _ = io.Copy(io.Discard, part)
			_ = part.Close()
		}
	}

upload:

	if conversationID == "" {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "conversation_id required")
		return
	}
	if fileBody == nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_form", "file required")
		return
	}
	defer fileBody.Close()

	f, err := h.svc.Upload(r.Context(), UploadInput{
		ConversationID: conversationID,
		UploaderID:     userID,
		Body:           fileBody,
		ByteSize:       fileSize,
	})
	if errors.Is(err, ErrForbidden) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "not a conversation member")
		return
	}
	if errors.Is(err, ErrInvalidInput) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "invalid upload")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not store file")
		return
	}

	httpx.WriteJSON(w, http.StatusCreated, map[string]any{
		"file_id":   f.ID,
		"byte_size": f.ByteSize,
	})
}

// Download GET /api/files/{id}
func (h *Handler) Download(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	fileID := r.PathValue("id")

	meta, file, err := h.svc.OpenForDownload(r.Context(), fileID, userID)
	if errors.Is(err, ErrForbidden) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "not a conversation member")
		return
	}
	if errors.Is(err, ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not_found", "file not found")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not open file")
		return
	}
	defer file.Close()

	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Length", strconv.FormatInt(meta.ByteSize, 10))
	w.Header().Set("Content-Disposition", "attachment; filename=\""+fileID+".bin\"")
	w.WriteHeader(http.StatusOK)
	_, _ = io.Copy(w, file)
}
