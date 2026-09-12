package mail

import (
	"crypto/tls"
	"fmt"
	"log"
	"net"
	"net/smtp"
	"strings"
	"time"
)

const smtpTimeout = 20 * time.Second

type Config struct {
	Driver    string
	From      string
	SMTPHost  string
	SMTPPort  string
	SMTPUser  string
	SMTPPass  string
	VerifyTTL time.Duration
}

type Sender struct {
	cfg Config
}

func New(cfg Config) *Sender {
	return &Sender{cfg: cfg}
}

func (s *Sender) SendEmailVerification(to, verifyURL string) error {
	subject := "验证你的 IHope 账号"
	mins := int(s.cfg.VerifyTTL.Minutes())
	if mins <= 0 {
		mins = 1440
	}
	body := fmt.Sprintf(
		"欢迎使用 IHope。请点击以下链接完成邮箱验证（%d 分钟内有效）：\n\n%s\n\n验证后即可登录。\n",
		mins, verifyURL,
	)
	return s.deliver(to, subject, body)
}

func (s *Sender) deliver(to, subject, body string) error {
	switch strings.ToLower(strings.TrimSpace(s.cfg.Driver)) {
	case "log", "":
		log.Printf("[mail] to=%s subject=%q body=%s", to, subject, body)
		return nil
	case "smtp":
		return s.sendSMTP(to, subject, body)
	default:
		return fmt.Errorf("unsupported mail driver %q", s.cfg.Driver)
	}
}

func (s *Sender) sendSMTP(to, subject, body string) error {
	host := strings.TrimSpace(s.cfg.SMTPHost)
	user := strings.TrimSpace(s.cfg.SMTPUser)
	pass := s.cfg.SMTPPass
	if host == "" || user == "" || pass == "" {
		return fmt.Errorf("smtp: set SMTP_HOST, SMTP_USER, SMTP_PASS")
	}
	port := strings.TrimSpace(s.cfg.SMTPPort)
	if port == "" {
		port = "465"
	}
	from := strings.TrimSpace(s.cfg.From)
	if from == "" {
		from = user
	}
	msg := []byte(fmt.Sprintf(
		"From: %s\r\nTo: %s\r\nSubject: %s\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n%s",
		from, to, subject, body,
	))
	addr := net.JoinHostPort(host, port)
	auth := smtp.PlainAuth("", user, pass, host)
	if port == "465" {
		return sendSMTPTLS(addr, host, auth, from, to, msg)
	}
	return sendSMTPStartTLS(addr, host, auth, from, to, msg)
}

func sendSMTPTLS(addr, host string, auth smtp.Auth, from, to string, msg []byte) error {
	raw, err := net.DialTimeout("tcp", addr, smtpTimeout)
	if err != nil {
		return fmt.Errorf("smtp dial: %w", err)
	}
	conn := tls.Client(raw, &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12})
	if err := conn.Handshake(); err != nil {
		_ = raw.Close()
		return fmt.Errorf("smtp tls: %w", err)
	}
	_ = conn.SetDeadline(time.Now().Add(smtpTimeout))
	defer conn.Close()
	return smtpSend(conn, host, auth, from, to, msg)
}

func sendSMTPStartTLS(addr, host string, auth smtp.Auth, from, to string, msg []byte) error {
	conn, err := net.DialTimeout("tcp", addr, smtpTimeout)
	if err != nil {
		return fmt.Errorf("smtp dial: %w", err)
	}
	_ = conn.SetDeadline(time.Now().Add(smtpTimeout))
	defer conn.Close()

	client, err := smtp.NewClient(conn, host)
	if err != nil {
		return err
	}
	defer client.Close()
	if ok, _ := client.Extension("STARTTLS"); ok {
		if err := client.StartTLS(&tls.Config{ServerName: host, MinVersion: tls.VersionTLS12}); err != nil {
			return err
		}
	}
	return smtpSendWithClient(client, auth, from, to, msg)
}

func smtpSend(conn net.Conn, host string, auth smtp.Auth, from, to string, msg []byte) error {
	client, err := smtp.NewClient(conn, host)
	if err != nil {
		return err
	}
	defer client.Close()
	return smtpSendWithClient(client, auth, from, to, msg)
}

func smtpSendWithClient(client *smtp.Client, auth smtp.Auth, from, to string, msg []byte) error {
	if err := client.Auth(auth); err != nil {
		return err
	}
	if err := client.Mail(from); err != nil {
		return err
	}
	if err := client.Rcpt(to); err != nil {
		return err
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
