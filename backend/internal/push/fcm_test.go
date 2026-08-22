package push

import (
	"os"
	"path/filepath"
	"testing"
)

func TestReadFCMProjectIDFromJSON(t *testing.T) {
	got, err := readFCMProjectIDFromJSON([]byte(`{"project_id":"ihope-606b3"}`))
	if err != nil {
		t.Fatal(err)
	}
	if got != "ihope-606b3" {
		t.Fatalf("project_id = %q", got)
	}
}

func TestReadFCMProjectID(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sa.json")
	if err := os.WriteFile(path, []byte(`{"project_id":"ihope-606b3","type":"service_account"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	got, err := readFCMProjectID(path)
	if err != nil {
		t.Fatal(err)
	}
	if got != "ihope-606b3" {
		t.Fatalf("project_id = %q", got)
	}
}

func TestStringifyPushExtras(t *testing.T) {
	out := stringifyPushExtras(map[string]string{"epoch": "3", "conversation_id": "abc"})
	if out["epoch"] != "3" || out["conversation_id"] != "abc" {
		t.Fatalf("unexpected %v", out)
	}
}
