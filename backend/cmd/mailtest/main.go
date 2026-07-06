// mailtest 用 deploy/.env 的 SMTP 配置发一封测试邮件后退出。
// 用法：cd backend && set ENV_FILE=../deploy/.env && go run ./cmd/mailtest [收件人]
package main

import (
	"fmt"
	"log"
	"os"

	"github.com/ihope/ihope/internal/config"
	"github.com/ihope/ihope/internal/mail"
)

func main() {
	to := "noreply@clprince.top"
	if len(os.Args) > 1 {
		to = os.Args[1]
	}
	cfg := config.Load()
	svc := mail.New(cfg)
	err := svc.SendPasswordReset(to, "https://im.clprince.top/reset?token=mailtest")
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("test email sent: from=%s to=%s via %s:%s\n", cfg.MailFrom, to, cfg.SMTPHost, cfg.SMTPPort)
}
