package server

import (
	"net/http"
	"os"
	"path/filepath"
)

// adminWebDir 定位仓库 admin/ 静态管理页。
func adminWebDir() string {
	if d := os.Getenv("ADMIN_WEB_DIR"); d != "" {
		return d
	}
	for _, rel := range []string{"admin", "../admin", "../../admin"} {
		if st, err := os.Stat(filepath.Join(rel, "index.html")); err == nil && !st.IsDir() {
			abs, _ := filepath.Abs(rel)
			return abs
		}
	}
	return ""
}

func mountAdminWeb(mux *http.ServeMux) {
	dir := adminWebDir()
	if dir == "" {
		return
	}
	fs := http.FileServer(http.Dir(dir))
	mux.Handle("GET /admin/", http.StripPrefix("/admin/", fs))
	mux.HandleFunc("GET /admin", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/admin/", http.StatusFound)
	})
}
