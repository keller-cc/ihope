package server

import "github.com/ihope/ihope/internal/config"

func clientConfigJSON(cfg config.Config) map[string]any {
	return map[string]any{
		"max_encrypted_file_bytes": cfg.MaxEncryptedFileBytes,
		"cloud_drive_url":          cfg.CloudDriveURL,
		"app_download_url":         cfg.ClientAppDownloadURL(),
	}
}
