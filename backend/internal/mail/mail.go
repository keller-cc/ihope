// Package mail 发送邮件；MAIL_DRIVER=log 时只打印到控制台。
package mail

import (
	"crypto/tls"
	"fmt"
	"log"
	"net"
	"net/smtp"
	"strings"

	"github.com/ihope/ihope/internal/config"
)

type Sender interface {
	SendPasswordReset(to, resetURL string) error
	SendEmailVerification(to, verifyURL string) error
}

type Service struct {
	cfg config.Config
}

func New(cfg config.Config) *Service {
	return &Service{cfg: cfg}
}

func (s *Service) SendPasswordReset(to, resetURL string) error {
	subject := "IHope password reset"
	body := fmt.Sprintf(
		"Use the link below to reset your password (valid for %d minutes):\n\n%s\n\n"+
			"In the IHope app: Forgot password -> Enter reset token.\n"+
			"The token is the value after token= in the link above.\n",
		int(s.cfg.ResetTokenTTL.Minutes()),
		resetURL,
	)
	return s.deliver(to, subject, body)
}

func (s *Service) SendEmailVerification(to, verifyURL string) error {
	subject := "Verify your IHope account"
	body := fmt.Sprintf(
		"Welcome to IHope. Click the link below to verify your email (valid for %d minutes):\n\n%s\n\n"+
			"After verification you can sign in to the app.\n",
		int(s.cfg.EmailVerifyTTL.Minutes()),
		verifyURL,
	)
	return s.deliver(to, subject, body)
}

func (s *Service) deliver(to, subject, body string) error {
	switch strings.ToLower(strings.TrimSpace(s.cfg.MailDriver)) {
	case "log", "":
		log.Printf("[mail] to=%s subject=%q body=%s", to, subject, body)
		return nil
	case "smtp":
		return s.sendSMTP(to, subject, body)
	default:
		return fmt.Errorf("unsupported mail driver %q", s.cfg.MailDriver)
	}
}

func (s *Service) sendSMTP(to, subject, body string) error {
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

	msg := buildPlainTextMessage(from, to, subject, body)
	addr := netJoinHostPort(host, port)
	auth := smtp.PlainAuth("", user, pass, host)
	return sendSMTPMail(addr, host, smtpConnModeForPort(port), auth, mailAddress(from), []string{to}, []byte(msg))
}

// smtpConnMode selects implicit TLS, STARTTLS, or STARTTLS-with-plain fallback by port.
type smtpConnMode int

const (
	smtpTLSImplicit smtpConnMode = iota
	smtpTLSStartTLS
	smtpTLSTryStartTLS
)

func smtpConnModeForPort(port string) smtpConnMode {
	switch port {
	case "465":
		return smtpTLSImplicit
	case "587":
		return smtpTLSStartTLS
	default:
		return smtpTLSTryStartTLS
	}
}

func smtpTLSConfig(host string) *tls.Config {
	return &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12}
}

func sendSMTPMail(addr, host string, mode smtpConnMode, auth smtp.Auth, from string, to []string, msg []byte) error {
	if mode == smtpTLSImplicit {
		return sendSMTPImplicitTLS(addr, host, auth, from, to, msg)
	}
	return sendSMTPWithSTARTTLS(addr, host, mode, auth, from, to, msg)
}

func sendSMTPImplicitTLS(addr, host string, auth smtp.Auth, from string, to []string, msg []byte) error {
	conn, err := tls.Dial("tcp", addr, smtpTLSConfig(host))
	if err != nil {
		return err
	}
	defer conn.Close()

	client, err := smtp.NewClient(conn, host)
	if err != nil {
		return err
	}
	defer client.Close()

	return smtpSendWithClient(client, auth, from, to, msg)
}

func sendSMTPWithSTARTTLS(addr, host string, mode smtpConnMode, auth smtp.Auth, from string, to []string, msg []byte) error {
	conn, err := net.Dial("tcp", addr)
	if err != nil {
		return err
	}
	defer conn.Close()

	client, err := smtp.NewClient(conn, host)
	if err != nil {
		return err
	}
	defer client.Close()

	if mode == smtpTLSStartTLS {
		if ok, _ := client.Extension("STARTTLS"); !ok {
			return fmt.Errorf("smtp: server %s does not support STARTTLS", addr)
		}
		if err := client.StartTLS(smtpTLSConfig(host)); err != nil {
			return err
		}
	} else if ok, _ := client.Extension("STARTTLS"); ok {
		_ = client.StartTLS(smtpTLSConfig(host)) // port 25: upgrade when offered, else plain
	}

	return smtpSendWithClient(client, auth, from, to, msg)
}

func smtpSendWithClient(client *smtp.Client, auth smtp.Auth, from string, to []string, msg []byte) error {
	if auth != nil {
		if err := client.Auth(auth); err != nil {
			return err
		}
	}
	if err := client.Mail(from); err != nil {
		return err
	}
	for _, rcpt := range to {
		if err := client.Rcpt(rcpt); err != nil {
			return err
		}
	}
	w, err := client.Data()
	if err != nil {
		return err
	}
	if _, err := w.Write(msg); err != nil {
		return err
	}
	if err := w.Close(); err != nil {
		return err
	}
	return client.Quit()
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
