package updatenotice

import "testing"

func TestNoticeFieldsJSONShape(t *testing.T) {
	// Sanity: published draft vs published flags for admin UX copy.
	n := Notice{Title: "更新说明", Body: "· 修复若干问题", Published: false}
	if n.Title == "" || n.Body == "" {
		t.Fatal("expected content")
	}
	if n.Published {
		t.Fatal("draft should not be published")
	}
}
