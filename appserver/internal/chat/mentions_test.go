package chat

import "testing"

func TestNormalizeMentionIDs(t *testing.T) {
	got := normalizeMentionIDs([]string{" a ", "b", "a", "", "self", "b"}, "self")
	if len(got) != 2 || got[0] != "a" || got[1] != "b" {
		t.Fatalf("got %#v", got)
	}
}
