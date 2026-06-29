package jwt

import (
	"testing"
	"time"
)

func TestIssueAndParseAccessToken(t *testing.T) {
	mgr := NewManager("test-secret-at-least-32-characters-long", 15*time.Minute)
	token, expiresIn, err := mgr.IssueAccessToken("user-1", "device-1", 0)
	if err != nil {
		t.Fatal(err)
	}
	if expiresIn != int64((15 * 60)) {
		t.Fatalf("expiresIn = %d", expiresIn)
	}

	claims, err := mgr.ParseAccessToken(token)
	if err != nil {
		t.Fatal(err)
	}
	if claims.UserID != "user-1" || claims.DeviceID != "device-1" || claims.TokenVersion != 0 {
		t.Fatalf("unexpected claims: %+v", claims)
	}
}
