// devproxy：本地开发固定入口，转发到「当前活跃」后端端口，便于双实例无感升级。
//
// 用法（在 deploy 目录）：
//   go run ../backend/cmd/devproxy
//
// App / 管理页连 PUBLIC_PORT（默认 8080）；后端实例在 8081/8082 间切换。
package main

import (
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
)

func main() {
	publicPort := env("PUBLIC_PORT", "8080")
	activeFile := env("ACTIVE_BACKEND_FILE", ".active-backend-port")
	backendHost := env("BACKEND_HOST", "127.0.0.1")
	defaultBackend := env("DEFAULT_BACKEND_PORT", "8081")

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		port := readActivePort(activeFile, defaultBackend)
		target, err := url.Parse("http://" + backendHost + ":" + port)
		if err != nil {
			http.Error(w, "bad backend url", http.StatusBadGateway)
			return
		}
		proxy := httputil.NewSingleHostReverseProxy(target)
		proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
			http.Error(w, "backend unreachable on port "+port, http.StatusBadGateway)
		}
		proxy.ServeHTTP(w, r)
	})

	addr := ":" + publicPort
	log.Printf("devproxy http://localhost:%s -> %s:<active from %s>", publicPort, backendHost, activeFile)
	log.Fatal(http.ListenAndServe(addr, nil))
}

func readActivePort(file, fallback string) string {
	data, err := os.ReadFile(file)
	if err != nil {
		return fallback
	}
	port := strings.TrimSpace(string(data))
	if port == "" {
		return fallback
	}
	return port
}

func env(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}
