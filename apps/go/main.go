package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"

	ytapi "github.com/pgboyahpgr-commits/ytapis/go"
)

func main() {
	fs := http.FileServer(http.Dir("static"))
	http.Handle("/", fs)

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
			http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(results)
	})

	addr := ":8080"
	log.Printf("ytapis Go app running at http://localhost%s", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}
