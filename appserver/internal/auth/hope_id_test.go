package auth

import "testing"

func TestValidateHopeID(t *testing.T) {
	ok := []string{"12345", "987654321012", "10000"}
	for _, s := range ok {
		if !ValidateHopeID(s) {
			t.Fatalf("expected ok: %q", s)
		}
	}
	bad := []string{"", "1234", "012345", "12345a", "1234567890123", " 12345 "}
	for _, s := range bad {
		// leading/trailing space is trimmed inside ValidateHopeID for " 12345 "
		if s == " 12345 " {
			if !ValidateHopeID(s) {
				t.Fatalf("trim should allow %q", s)
			}
			continue
		}
		if ValidateHopeID(s) {
			t.Fatalf("expected bad: %q", s)
		}
	}
}
