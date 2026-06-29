package auth

import "testing"

func TestValidateEmail(t *testing.T) {
	tests := []struct {
		email string
		ok    bool
	}{
		{"user@example.com", true},
		{" User@Example.COM ", true},
		{"bad", false},
		{"", false},
	}
	for _, tc := range tests {
		if got := ValidateEmail(tc.email); got != tc.ok {
			t.Fatalf("ValidateEmail(%q) = %v, want %v", tc.email, got, tc.ok)
		}
	}
}

func TestValidateUsername(t *testing.T) {
	if !ValidateUsername("alice_01") {
		t.Fatal("expected valid username")
	}
	if ValidateUsername("ab") {
		t.Fatal("expected too short username to fail")
	}
	if ValidateUsername("bad-name") {
		t.Fatal("expected hyphen username to fail")
	}
}

func TestValidatePassword(t *testing.T) {
	if !ValidatePassword("password123") {
		t.Fatal("expected valid password")
	}
	if ValidatePassword("short") {
		t.Fatal("expected short password to fail")
	}
}

func TestPasswordHashRoundTrip(t *testing.T) {
	hash, err := HashPassword("password123")
	if err != nil {
		t.Fatal(err)
	}
	if !CheckPassword(hash, "password123") {
		t.Fatal("expected password to match hash")
	}
	if CheckPassword(hash, "wrong") {
		t.Fatal("expected wrong password to fail")
	}
}

func TestHashTokenDeterministic(t *testing.T) {
	a := HashToken("abc")
	b := HashToken("abc")
	if a != b {
		t.Fatal("expected deterministic token hash")
	}
	if a == HashToken("xyz") {
		t.Fatal("expected different input to produce different hash")
	}
}

func TestNewRefreshAndResetTokens(t *testing.T) {
	rPlain, rHash, err := NewRefreshToken()
	if err != nil || rPlain == "" || rHash == "" {
		t.Fatalf("refresh token: plain=%q hash=%q err=%v", rPlain, rHash, err)
	}
	if HashToken(rPlain) != rHash {
		t.Fatal("refresh token hash mismatch")
	}

	resetPlain, resetHash, err := NewResetToken()
	if err != nil || resetPlain == "" || resetHash == "" {
		t.Fatalf("reset token: plain=%q hash=%q err=%v", resetPlain, resetHash, err)
	}
	if HashToken(resetPlain) != resetHash {
		t.Fatal("reset token hash mismatch")
	}
}
