package avatarutil

import (
	"errors"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
)

var ErrInvalid = errors.New("invalid avatar file")

func ValidateUpload(file multipart.File, header *multipart.FileHeader, maxBytes int64) (ext string, err error) {
	if header.Size > maxBytes {
		return "", ErrInvalid
	}
	head := make([]byte, 512)
	n, err := file.Read(head)
	if err != nil {
		return "", ErrInvalid
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return "", ErrInvalid
	}
	switch http.DetectContentType(head[:n]) {
	case "image/jpeg":
		return ".jpg", nil
	case "image/png":
		return ".png", nil
	case "image/gif":
		return ".gif", nil
	case "image/webp":
		return ".webp", nil
	default:
		return "", ErrInvalid
	}
}

func SaveFile(path string, src multipart.File) error {
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

func SafeFilename(name string) bool {
	if name == "" || name == "." || name == ".." {
		return false
	}
	if strings.Contains(name, "..") || strings.ContainsAny(name, `/\`) {
		return false
	}
	ext := strings.ToLower(filepath.Ext(name))
	switch ext {
	case ".jpg", ".jpeg", ".png", ".gif", ".webp":
	default:
		return false
	}
	base := strings.TrimSuffix(name, ext)
	if strings.HasPrefix(base, "g_") {
		_, err := uuid.Parse(strings.TrimPrefix(base, "g_"))
		return err == nil
	}
	_, err := uuid.Parse(base)
	return err == nil
}
