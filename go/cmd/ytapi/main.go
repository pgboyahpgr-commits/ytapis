package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/ytapis/ytapis/go"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "Usage: ytapi search <query> [--limit N]")
		os.Exit(1)
	}

	if os.Args[1] != "search" {
		fmt.Fprintln(os.Stderr, "Usage: ytapi search <query> [--limit N]")
		os.Exit(1)
	}

	args := os.Args[2:]
	queryParts := []string{}
	limit := 15

	for i := 0; i < len(args); i++ {
		if args[i] == "--limit" && i+1 < len(args) {
			n, err := strconv.Atoi(args[i+1])
			if err == nil {
				limit = n
			}
			i++
		} else if !strings.HasPrefix(args[i], "--") {
			queryParts = append(queryParts, args[i])
		}
	}

	if len(queryParts) == 0 {
		fmt.Fprintln(os.Stderr, "Error: search query required")
		os.Exit(1)
	}

	query := strings.Join(queryParts, " ")
	result, err := ytapi.SearchJSON(query, limit)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Search failed: %v\n", err)
		os.Exit(1)
	}
	fmt.Println(result)
}
