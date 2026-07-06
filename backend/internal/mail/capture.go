// 测试专用：捕获发信内容，或从 URL 解析 token（集成测试用）。
package mail

import "strings"

// CapturingSender 实现 Sender，将最后一封邮件内容保存在内存中。
type CapturingSender struct {
	LastTo         string
	LastResetURL   string
	LastVerifyURL  string
}

func (c *CapturingSender) SendPasswordReset(to, resetURL string) error {
	c.LastTo = to
	c.LastResetURL = resetURL
	return nil
}

func (c *CapturingSender) SendEmailVerification(to, verifyURL string) error {
	c.LastTo = to
	c.LastVerifyURL = verifyURL
	return nil
}

// ExtractTokenFromResetURL 从 ...?token=xxx 中提取重置令牌。
func ExtractTokenFromResetURL(resetURL string) string {
	return extractQueryToken(resetURL)
}

// ExtractTokenFromVerifyURL 从验证链接中提取 token。
func ExtractTokenFromVerifyURL(verifyURL string) string {
	return extractQueryToken(verifyURL)
}

func extractQueryToken(url string) string {
	const q = "token="
	if i := strings.Index(url, q); i >= 0 {
		return strings.TrimSpace(url[i+len(q):])
	}
	return ""
}
