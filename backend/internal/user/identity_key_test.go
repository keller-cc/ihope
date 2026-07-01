package user

import "testing"

func TestValidateIdentityPublicKey(t *testing.T) {
	cases := map[string]bool{
		"BQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA":                         true,
		"BTM0NTY3ODk6Ozw9Pj9AQUJDREVGR0hJSktMTU5PUFFS":                         true,
		"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=":                         false,
		"BQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=":                         false,
	}
	for key, want := range cases {
		got := ValidateIdentityPublicKey(key) == nil
		if got != want {
			t.Errorf("key %q valid=%v want=%v", key, got, want)
		}
	}
}
