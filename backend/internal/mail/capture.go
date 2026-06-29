// 测试专用：捕获发信内容，或从重置 URL 解析 token（集成测试用）。
package mail

import "strings"

// CapturingSender 实现 Sender，将最后一封邮件内容保存在内存中。
type CapturingSender struct {
	LastTo       string
	LastResetURL string
}

func (c *CapturingSender) SendPasswordReset(to, resetURL string) error {
	c.LastTo = to
	c.LastResetURL = resetURL
	return nil
}

// ExtractTokenFromResetURL 从 ...?token=xxx 中提取重置令牌。
func ExtractTokenFromResetURL(resetURL string) string {
	const q = "token="
	if i := strings.Index(resetURL, q); i >= 0 {
		return resetURL[i+len(q):]
	}
	return ""
}
