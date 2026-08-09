package ytapi

import (
	"strings"
	"testing"
)

func TestFallbackResult(t *testing.T) {
	r := fallbackResult("dQw4w9WgXcQ")
	if r.ID != "dQw4w9WgXcQ" {
		t.Errorf("expected id dQw4w9WgXcQ, got %s", r.ID)
	}
	if r.Title != "Video dQw4w9WgXcQ" {
		t.Errorf("expected title, got %s", r.Title)
	}
	if len(r.Thumbnails) == 0 {
		t.Error("expected thumbnails")
	}
	if r.Thumbnails[0].URL != "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg" {
		t.Error("expected thumbnail URL")
	}
}

func TestGetVideo(t *testing.T) {
	r := GetVideo("dQw4w9WgXcQ")
	if r.ID != "dQw4w9WgXcQ" {
		t.Errorf("expected id, got %s", r.ID)
	}
	if r.Title == "" {
		t.Error("expected non-empty title")
	}
	if !strings.HasPrefix(r.FullURL, "https://www.youtube.com/watch?v=") {
		t.Errorf("expected youtube URL, got %s", r.FullURL)
	}
}

func TestSearch(t *testing.T) {
	results, err := Search("never gonna give you up", "", "", 3)
	if err != nil {
		t.Fatalf("search failed: %v", err)
	}
	if len(results) == 0 {
		t.Error("expected at least 1 result")
	}
	if len(results) > 3 {
		t.Errorf("expected at most 3 results, got %d", len(results))
	}
	for _, r := range results {
		if r.ID == "" {
			t.Error("expected non-empty video ID")
		}
		if r.Title == "" {
			t.Errorf("expected non-empty title for video %s", r.ID)
		}
		if r.DurationSeconds == 0 && r.Duration != "" {
			t.Logf("video %s: could not parse duration '%s'", r.ID, r.Duration)
		}
		t.Logf("  %s | %s | %s | %s views", r.Title, r.Author, r.Duration, r.ViewCount)
	}
}

func TestSearchJSON(t *testing.T) {
	json, err := SearchJSON("cats", 2)
	if err != nil {
		t.Fatalf("searchJSON failed: %v", err)
	}
	if json == "" {
		t.Error("expected non-empty JSON string")
	}
}

func TestParseDuration(t *testing.T) {
	_, secs := parseDuration("3:45")
	if secs != 225 {
		t.Errorf("expected 225, got %d", secs)
	}
	_, secs = parseDuration("1:02:34")
	if secs != 3754 {
		t.Errorf("expected 3754, got %d", secs)
	}
}

func TestParseViewCount(t *testing.T) {
	_, raw := parseViewCount("1.2M views")
	if raw != 1200000 {
		t.Errorf("expected 1200000, got %d", raw)
	}
	_, raw = parseViewCount("53K views")
	if raw != 53000 {
		t.Errorf("expected 53000, got %d", raw)
	}
}
