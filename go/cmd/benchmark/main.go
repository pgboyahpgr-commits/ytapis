// Benchmark tool for ytapis Go package.
//
// Build: go build -o benchmark.exe ./cmd/benchmark/
// Run:   ./benchmark.exe
//
// Or run without building:
//   go run ./cmd/benchmark/

package main

import (
	"fmt"
	"strings"
	"time"

	ytapi "github.com/pgboyahpgr-commits/ytapis/go"
)

type BenchmarkRow struct {
	Function string
	Limit    string
	TimeMs   string
	Results  string
}

func fmtMs(d time.Duration) string {
	return fmt.Sprintf("%.1f", float64(d.Microseconds())/1000.0)
}

func pad(s string, length int) string {
	if len(s) >= length {
		return s
	}
	return s + strings.Repeat(" ", length-len(s))
}

func renderTable(rows []BenchmarkRow) {
	cols := []string{"Function", "Limit", "Time (ms)", "Results"}
	widths := make([]int, len(cols))
	for i, c := range cols {
		widths[i] = len(c)
	}
	for _, r := range rows {
		if len(r.Function) > widths[0] {
			widths[0] = len(r.Function)
		}
		if len(r.Limit) > widths[1] {
			widths[1] = len(r.Limit)
		}
		if len(r.TimeMs) > widths[2] {
			widths[2] = len(r.TimeMs)
		}
		if len(r.Results) > widths[3] {
			widths[3] = len(r.Results)
		}
	}

	var sep strings.Builder
	sep.WriteString("+")
	for _, w := range widths {
		for j := 0; j < w+2; j++ {
			sep.WriteString("-")
		}
		sep.WriteString("+")
	}
	sepStr := sep.String()

	fmt.Println(sepStr)
	fmt.Printf("| %s | %s | %s | %s |\n", pad(cols[0], widths[0]), pad(cols[1], widths[1]), pad(cols[2], widths[2]), pad(cols[3], widths[3]))
	fmt.Println(sepStr)

	for _, r := range rows {
		fmt.Printf("| %s | %s | %s | %s |\n", pad(r.Function, widths[0]), pad(r.Limit, widths[1]), pad(r.TimeMs, widths[2]), pad(r.Results, widths[3]))
	}
	fmt.Println(sepStr)
}

func main() {
	var rows []BenchmarkRow

	for _, limit := range []int{5, 10, 20, 50} {
		start := time.Now()
		results, err := ytapi.Search("cats", "", "", limit)
		elapsed := time.Since(start)
		if err != nil {
			rows = append(rows, BenchmarkRow{"search", fmt.Sprintf("%d", limit), "ERR", err.Error()[:40]})
		} else {
			rows = append(rows, BenchmarkRow{"search", fmt.Sprintf("%d", limit), fmtMs(elapsed), fmt.Sprintf("%d", len(results))})
		}
	}

	for _, limit := range []int{10} {
		start := time.Now()
		results, err := ytapi.SearchTrending("", "", limit)
		elapsed := time.Since(start)
		if err != nil {
			rows = append(rows, BenchmarkRow{"searchTrending", fmt.Sprintf("%d", limit), "ERR", err.Error()[:40]})
		} else {
			rows = append(rows, BenchmarkRow{"searchTrending", fmt.Sprintf("%d", limit), fmtMs(elapsed), fmt.Sprintf("%d", len(results))})
		}
	}

	{
		start := time.Now()
		video := ytapi.GetVideo("dQw4w9WgXcQ")
		if video != nil {
			elapsed := time.Since(start)
			rows = append(rows, BenchmarkRow{"getVideo", "dQw4w9WgXcQ", fmtMs(elapsed), video.Title})
		}
	}

	renderTable(rows)
}
