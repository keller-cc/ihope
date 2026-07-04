package filestore

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/google/uuid"
	"github.com/ihope/ihope/internal/conversation"
)

var (
	ErrInvalidInput = errors.New("invalid upload")
	ErrForbidden    = conversation.ErrNotMember
)

type Service struct {
	files    *Repository
	conv     *conversation.Repository
	uploadDir string
	maxBytes  int64
}

func NewService(files *Repository, conv *conversation.Repository, uploadDir string, maxBytes int64) *Service {
	return &Service{
		files:     files,
		conv:      conv,
		uploadDir: uploadDir,
		maxBytes:  maxBytes,
	}
}

type UploadInput struct {
	ConversationID string
	UploaderID     string
	Body           io.Reader
	ByteSize       int64
}

func (s *Service) Upload(ctx context.Context, in UploadInput) (*File, error) {
	if in.ConversationID == "" || in.UploaderID == "" || in.Body == nil {
		return nil, ErrInvalidInput
	}
	byteSize := in.ByteSize
	if byteSize < 0 {
		byteSize = 0
	}
	// 客户端 multipart 的 file part 常不带 Content-Length；仅在有声明大小时预检。
	if s.maxBytes > 0 && byteSize > s.maxBytes {
		return nil, ErrInvalidInput
	}

	ok, err := s.conv.IsActiveMember(ctx, in.ConversationID, in.UploaderID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrForbidden
	}

	dir := filepath.Join(s.uploadDir, "encrypted")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}

	filename := uuid.New().String() + ".bin"
	storagePath := filepath.Join("encrypted", filename)
	destPath := filepath.Join(s.uploadDir, storagePath)

	dst, err := os.Create(destPath)
	if err != nil {
		return nil, err
	}
	body := io.Reader(in.Body)
	if s.maxBytes > 0 {
		body = io.LimitReader(in.Body, s.maxBytes+1)
	}
	written, err := io.Copy(dst, body)
	closeErr := dst.Close()
	if err != nil {
		_ = os.Remove(destPath)
		return nil, err
	}
	if closeErr != nil {
		_ = os.Remove(destPath)
		return nil, closeErr
	}
	if s.maxBytes > 0 && written > s.maxBytes {
		_ = os.Remove(destPath)
		return nil, ErrInvalidInput
	}
	if byteSize > 0 && written != byteSize {
		_ = os.Remove(destPath)
		return nil, ErrInvalidInput
	}
	if written <= 0 {
		_ = os.Remove(destPath)
		return nil, ErrInvalidInput
	}

	return s.files.Create(ctx, in.ConversationID, in.UploaderID, storagePath, written)
}

func (s *Service) OpenForDownload(ctx context.Context, fileID, userID string) (*File, *os.File, error) {
	f, err := s.files.GetByID(ctx, fileID)
	if err != nil {
		return nil, nil, err
	}

	ok, err := s.conv.IsActiveMember(ctx, f.ConversationID, userID)
	if err != nil {
		return nil, nil, err
	}
	if !ok {
		return nil, nil, ErrForbidden
	}

	path := filepath.Join(s.uploadDir, f.StoragePath)
	file, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil, ErrNotFound
		}
		return nil, nil, err
	}
	return f, file, nil
}

func (s *Service) ValidateForMessage(ctx context.Context, fileID, conversationID string) error {
	f, err := s.files.GetByID(ctx, fileID)
	if err != nil {
		return err
	}
	if f.ConversationID != conversationID {
		return fmt.Errorf("%w: conversation mismatch", ErrInvalidInput)
	}
	return nil
}
