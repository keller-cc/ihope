package crypto_test

import (
	"testing"

	"github.com/keller-cc/ihope/appserver/internal/crypto"
)

func TestSealOpen(t *testing.T) {
	key := make([]byte, 32)
	copy(key, []byte("ihope-web-dev-only-key-32bytes!!"))
	sealed, err := crypto.Seal(key, []byte("hello"))
	if err != nil {
		t.Fatal(err)
	}
	plain, err := crypto.Open(key, sealed)
	if err != nil {
		t.Fatal(err)
	}
	if string(plain) != "hello" {
		t.Fatalf("got %q", plain)
	}
}
