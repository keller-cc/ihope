// Package mail 发送邮件；MAIL_DRIVER=log 时只打印到控制台。
package mail

import (
	"fmt"
	"log"
	"net/smtp"
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
	case "smtp":
		return s.sendSMTP(to, resetURL)
	default:
		return fmt.Errorf("unsupported mail driver %q", s.cfg.MailDriver)
	}
}

func (s *Service) sendSMTP(to, resetURL string) error {
	host := strings.TrimSpace(s.cfg.SMTPHost)
	user := strings.TrimSpace(s.cfg.SMTPUser)
	pass := s.cfg.SMTPPass
	if host == "" || user == "" || pass == "" {
		return fmt.Errorf("smtp: set SMTP_HOST, SMTP_USER, SMTP_PASS in .env")
	}
	port := strings.TrimSpace(s.cfg.SMTPPort)
	if port == "" {
		port = "587"
	}
	from := strings.TrimSpace(s.cfg.MailFrom)
	if from == "" {
		from = user
	}

	subject := "IHope password reset"
	body := fmt.Sprintf(
		"Use the link below to reset your password (valid for %d minutes):\n\n%s\n\n"+
			"In the IHope app: Forgot password -> Enter reset token.\n"+
			"The token is the value after token= in the link above.\n",
		int(s.cfg.ResetTokenTTL.Minutes()),
		resetURL,
	)

	msg := buildPlainTextMessage(from, to, subject, body)
	addr := netJoinHostPort(host, port)
	auth := smtp.PlainAuth("", user, pass, host)
	return smtp.SendMail(addr, auth, mailAddress(from), []string{to}, []byte(msg))
}

func buildPlainTextMessage(from, to, subject, body string) string {
	return fmt.Sprintf(
		"From: %s\r\nTo: %s\r\nSubject: %s\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n%s",
		from, to, subject, body,
	)
}

func mailAddress(from string) string {
	if i := strings.LastIndex(from, "<"); i >= 0 {
		if j := strings.Index(from[i:], ">"); j > 0 {
			return strings.TrimSpace(from[i+1 : i+j])
		}
	}
	return strings.TrimSpace(from)
}

func netJoinHostPort(host, port string) string {
	if strings.Contains(host, ":") && !strings.HasPrefix(host, "[") {
		return host + ":" + port
	}
	return host + ":" + port
}
