package chat

import "testing"

func TestFormatNotifyHint(t *testing.T) {
	t.Parallel()
	cases := []struct {
		typ, title, name, want string
	}{
		{"dm", "", "老王", "老王"},
		{"dm", "", "", "有人"},
		{"group", "周末爬山", "老王", "群 · 老王"},
		{"group", "", "老王", "群 · 老王"},
		{"group", "  ", "  ", "群 · 有人"},
	}
	for _, c := range cases {
		got := FormatNotifyHint(c.typ, c.title, c.name)
		if got != c.want {
			t.Fatalf("FormatNotifyHint(%q,%q,%q)=%q want %q", c.typ, c.title, c.name, got, c.want)
		}
	}
}
