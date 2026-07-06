package mail

import "testing"

func TestSMTPConnModeForPort(t *testing.T) {
	tests := []struct {
		port string
		want smtpConnMode
	}{
		{"465", smtpTLSImplicit},
		{"587", smtpTLSStartTLS},
		{"25", smtpTLSTryStartTLS},
		{"2525", smtpTLSTryStartTLS},
	}
	for _, tc := range tests {
		if got := smtpConnModeForPort(tc.port); got != tc.want {
			t.Errorf("smtpConnModeForPort(%q) = %v, want %v", tc.port, got, tc.want)
		}
	}
}

func TestSMTPTLSConfig(t *testing.T) {
	cfg := smtpTLSConfig("smtp.qiye.aliyun.com")
	if cfg.ServerName != "smtp.qiye.aliyun.com" {
		t.Fatalf("ServerName = %q", cfg.ServerName)
	}
	if cfg.MinVersion != 0x0303 { // tls.VersionTLS12
		t.Fatalf("MinVersion = %#x, want TLS 1.2", cfg.MinVersion)
	}
}
