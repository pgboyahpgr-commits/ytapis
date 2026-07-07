package main

import (
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"

	ytapi "github.com/pgboyahpgr-commits/ytapis/go"
)

//go:embed static/index.html
var staticFiles embed.FS

func getPort() int {
	addr, err := net.Listen("tcp", ":0")
	if err != nil {
		return 8080
	}
	addr.Close()
	return addr.Addr().(*net.TCPAddr).Port
}

func openBrowser(url string) {
	switch runtime.GOOS {
	case "windows":
		exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
	case "darwin":
		exec.Command("open", url).Start()
	default:
		exec.Command("xdg-open", url).Start()
	}
}

func main() {
	port := getPort()
	addr := fmt.Sprintf(":%d", port)

	subFS, _ := fs.Sub(staticFiles, "static")
	http.Handle("/", http.FileServer(http.FS(subFS)))

	http.HandleFunc("/search", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query().Get("q")
		if q == "" {
			http.Error(w, `{"error":"missing query param \"q\""}`, http.StatusBadRequest)
			return
		}
		limit := 15
		if l, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && l > 0 {
			limit = l
		}
		results, err := ytapi.Search(q, limit)
		if err != nil {
			msg := strings.ReplaceAll(err.Error(), "\"", "'")
			http.Error(w, fmt.Sprintf(`{"error":"%s"}`, msg), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(results)
	})

	url := fmt.Sprintf("http://localhost:%d", port)
	openBrowser(url)

	fmt.Printf("\n  ytapis Go app running at %s\n", url)
	fmt.Println("  Close this window or press Ctrl+C to stop.\n")

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal(err)
	}
	os.Exit(0)
}
