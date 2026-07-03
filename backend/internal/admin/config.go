package admin

import "github.com/ihope/ihope/internal/config"

func RuntimeConfigFrom(cfg config.Config) RuntimeConfig {
	return RuntimeConfig{
		Port:                  cfg.Port,
		MaxEncryptedFileBytes: cfg.MaxEncryptedFileBytes,
		CloudDriveURL:         cfg.CloudDriveURL,
		ServerVersion:         cfg.ServerVersion,
		DrainSeconds:          cfg.DrainSeconds,
		AppDownloadURL:        cfg.ClientAppDownloadURL(),
	}
}
