package testutil_test

import (
	"testing"

	"github.com/ihope/ihope/internal/testutil"
	"github.com/ihope/ihope/internal/user"
)

func TestFixtureIdentityKeys(t *testing.T) {
	for _, key := range []string{
		testutil.TestIdentityPublicKey,
		testutil.TestIdentityPublicKeyBob,
		testutil.TestSignalIdentityKey,
	} {
		if err := user.ValidateIdentityPublicKey(key); err != nil {
			t.Fatalf("invalid fixture key: %v", err)
		}
	}
}
