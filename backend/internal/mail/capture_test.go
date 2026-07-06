package mail

import "testing"

func TestExtractTokenFromResetURL(t *testing.T) {
	url := "http://localhost:8080/reset-password?token=abc123def"
	if got := ExtractTokenFromResetURL(url); got != "abc123def" {
		t.Fatalf("got %q", got)
	}
}

func TestCapturingSender(t *testing.T) {
	c := &CapturingSender{}
	if err := c.SendPasswordReset("a@b.com", "http://x?token=t"); err != nil {
		t.Fatal(err)
	}
	if c.LastTo != "a@b.com" || c.LastResetURL != "http://x?token=t" {
		t.Fatalf("unexpected capture: %+v", c)
	}
	if err := c.SendEmailVerification("a@b.com", "http://x/verify?token=v"); err != nil {
		t.Fatal(err)
	}
	if c.LastVerifyURL != "http://x/verify?token=v" {
		t.Fatalf("unexpected verify url: %q", c.LastVerifyURL)
	}
}
