// Package mail 发送邮件；MAIL_DRIVER=log 时只打印到控制台。
package mail

import (
	"fmt"
	"log"
	"strings"

	"github.com/ihope/ihope/internal/config"
)

type Sender interface {
	SendPasswordReset(to, resetURL string) error
}

type Service struct {
	cfg config.Config
}

func New(cfg config.Config) *Service {
	return &Service{cfg: cfg}
}

func (s *Service) SendPasswordReset(to, resetURL string) error {
	switch strings.ToLower(strings.TrimSpace(s.cfg.MailDriver)) {
	case "log", "":
		log.Printf("[mail] password reset to=%s url=%s", to, resetURL)
		return nil
	default:
		return fmt.Errorf("unsupported mail driver %q", s.cfg.MailDriver)
	}
}
