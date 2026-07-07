package ytapi

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"
)

var videoIDRegex = regexp.MustCompile(`"videoId":"([^"]{11})"`)
var httpClient = &http.Client{Timeout: 15 * time.Second}

type VideoResult struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Author    string `json:"author"`
	Thumbnail string `json:"thumbnail"`
	FullURL   string `json:"fullUrl"`
	EmbedURL  string `json:"embedUrl"`
}

func fallbackResult(id string) VideoResult {
	return VideoResult{
		ID:        id,
		Title:     fmt.Sprintf("Video %s", id),
		Author:    "YouTube",
		Thumbnail: fmt.Sprintf("https://i.ytimg.com/vi/%s/hqdefault.jpg", id),
		FullURL:   fmt.Sprintf("https://www.youtube.com/watch?v=%s", id),
		EmbedURL:  fmt.Sprintf("https://www.youtube.com/embed/%s?rel=0", id),
	}
}

type oembedResponse struct {
	Title        string `json:"title"`
	AuthorName   string `json:"author_name"`
	ThumbnailURL string `json:"thumbnail_url"`
}

func fetchOembed(id string) VideoResult {
	fallback := fallbackResult(id)
	u := fmt.Sprintf("https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=%s&format=json", id)
	resp, err := httpClient.Get(u)
	if err != nil || resp.StatusCode != 200 {
		return fallback
	}
	defer resp.Body.Close()

	var data oembedResponse
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return fallback
	}

	title := data.Title
	author := data.AuthorName
	thumb := data.ThumbnailURL
	if title == "" {
		title = fallback.Title
	}
	if author == "" {
		author = fallback.Author
	}
	if thumb == "" {
		thumb = fallback.Thumbnail
	}

	return VideoResult{
		ID:        id,
		Title:     title,
		Author:    author,
		Thumbnail: thumb,
		FullURL:   fallback.FullURL,
		EmbedURL:  fallback.EmbedURL,
	}
}

func Search(query string, limit ...int) ([]VideoResult, error) {
	maxResults := 15
	if len(limit) > 0 && limit[0] > 0 {
		maxResults = limit[0]
	}

	u := fmt.Sprintf("https://www.youtube.com/results?search_query=%s", url.QueryEscape(query))
	resp, err := httpClient.Get(u)
	if err != nil {
		return nil, fmt.Errorf("search request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response failed: %w", err)
	}

	matches := videoIDRegex.FindAllStringSubmatch(string(body), -1)
	seen := make(map[string]bool)
	var ids []string
	for _, m := range matches {
		id := m[1]
		if !seen[id] {
			seen[id] = true
			ids = append(ids, id)
		}
	}
	if maxResults < len(ids) {
		ids = ids[:maxResults]
	}

	results := make([]VideoResult, len(ids))
	for i, id := range ids {
		results[i] = fetchOembed(id)
	}
	return results, nil
}

func SearchJSON(query string, limit ...int) (string, error) {
	results, err := Search(query, limit...)
	if err != nil {
		return "", err
	}
	var sb strings.Builder
	enc := json.NewEncoder(&sb)
	enc.SetIndent("", "  ")
	if err := enc.Encode(results); err != nil {
		return "", err
	}
	return sb.String(), nil
}
