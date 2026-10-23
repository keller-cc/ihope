package turnstile

import "testing"

func TestVerifyDisabledSkips(t *testing.T) {
	if err := Verify("", "anything", "1.2.3.4"); err != nil {
		t.Fatal(err)
	}
}

func TestVerifyRequiresTokenWhenEnabled(t *testing.T) {
	err := Verify("secret", "", "")
	if err != ErrMissingToken {
		t.Fatalf("got %v", err)
	}
}
