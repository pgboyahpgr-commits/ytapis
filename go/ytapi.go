package ytapi

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"math/rand"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

var httpClient = &http.Client{Timeout: 15 * time.Second}

type Thumbnail struct {
	URL    string `json:"url"`
	Width  int    `json:"width"`
	Height int    `json:"height"`
}

type VideoResult struct {
	ID              string      `json:"id"`
	Title           string      `json:"title"`
	Author          string      `json:"author"`
	ChannelURL      string      `json:"channelUrl"`
	Thumbnail       string      `json:"thumbnail"`
	Thumbnails      []Thumbnail `json:"thumbnails"`
	FullURL         string      `json:"fullUrl"`
	EmbedURL        string      `json:"embedUrl"`
	Duration        string      `json:"duration"`
	DurationSeconds int         `json:"durationSeconds"`
	ViewCount       string      `json:"viewCount"`
	ViewCountRaw    int64       `json:"viewCountRaw"`
	PublishedTime   string      `json:"publishedTime"`
	Description     string      `json:"description"`
	ChannelAvatar   string      `json:"channelAvatar"`
	IsLive          bool        `json:"isLive"`
	IsUpcoming      bool        `json:"isUpcoming"`
	IsVerified      bool        `json:"isVerified"`
}

type oembedResponse struct {
	Title        string `json:"title"`
	AuthorName   string `json:"author_name"`
	ThumbnailURL string `json:"thumbnail_url"`
}

func fallbackResult(id string) VideoResult {
	return VideoResult{
		ID:        id,
		Title:     fmt.Sprintf("Video %s", id),
		Author:    "YouTube",
		Thumbnail: fmt.Sprintf("https://i.ytimg.com/vi/%s/hqdefault.jpg", id),
		Thumbnails: []Thumbnail{
			{URL: fmt.Sprintf("https://i.ytimg.com/vi/%s/hqdefault.jpg", id), Width: 480, Height: 360},
		},
		FullURL:  fmt.Sprintf("https://www.youtube.com/watch?v=%s", id),
		EmbedURL: fmt.Sprintf("https://www.youtube.com/embed/%s?rel=0", id),
	}
}

func parseDuration(text string) (string, int) {
	if text == "" {
		return "", 0
	}
	parts := strings.Split(text, ":")
	nums := make([]int, len(parts))
	for i, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil {
			return text, 0
		}
		nums[i] = n
	}
	switch len(nums) {
	case 3:
		return text, nums[0]*3600 + nums[1]*60 + nums[2]
	case 2:
		return text, nums[0]*60 + nums[1]
	default:
		return text, nums[0]
	}
}

func parseViewCount(text string) (string, int64) {
	if text == "" {
		return "", 0
	}
	cleaned := regexp.MustCompile(`[^0-9.KMBkmb]`).ReplaceAllString(text, "")
	numStr := regexp.MustCompile(`[KMBkmb]`).ReplaceAllString(cleaned, "")
	num, err := strconv.ParseFloat(numStr, 64)
	if err != nil {
		return text, 0
	}
	upper := strings.ToUpper(cleaned)
	mult := 1.0
	if strings.Contains(upper, "B") {
		mult = 1_000_000_000
	} else if strings.Contains(upper, "M") {
		mult = 1_000_000
	} else if strings.Contains(upper, "K") {
		mult = 1_000
	}
	return text, int64(num * mult)
}

func extractJSON(html, prefix string) map[string]interface{} {
	idx := strings.Index(html, prefix)
	if idx == -1 {
		return nil
	}
	start := strings.Index(html[idx:], "{")
	if start == -1 {
		return nil
	}
	start += idx

	depth := 0
	inString := false
	escaped := false
	for i := start; i < len(html); i++ {
		ch := html[i]
		if escaped {
			escaped = false
			continue
		}
		if ch == '\\' {
			escaped = true
			continue
		}
		if ch == '"' {
			inString = !inString
			continue
		}
		if inString {
			continue
		}
		if ch == '{' {
			depth++
		} else if ch == '}' {
			depth--
			if depth == 0 {
				var result map[string]interface{}
				if err := json.Unmarshal([]byte(html[start:i+1]), &result); err != nil {
					return nil
				}
				return result
			}
		}
	}
	return nil
}

func extractRuns(runs []interface{}) string {
	var sb strings.Builder
	for _, r := range runs {
		if m, ok := r.(map[string]interface{}); ok {
			if t, ok := m["text"].(string); ok {
				sb.WriteString(t)
			}
		}
	}
	return sb.String()
}

func thumbnailQualityScore(url string) int {
	if url == "" {
		return 0
	}
	if strings.Contains(url, "maxresdefault") {
		return 1280
	}
	if strings.Contains(url, "sddefault") {
		return 640
	}
	if strings.Contains(url, "hqdefault") {
		return 480
	}
	if strings.Contains(url, "mqdefault") {
		return 320
	}
	if strings.Contains(url, "default") {
		return 120
	}
	return 0
}

func bestThumbnail(thumbs []interface{}) string {
	if len(thumbs) == 0 {
		return ""
	}
	best := Thumbnail{}
	bestScore := 0
	first := true
	for _, t := range thumbs {
		m, ok := t.(map[string]interface{})
		if !ok {
			continue
		}
		url, _ := m["url"].(string)
		w, _ := m["width"].(float64)
		score := int(w)
		if score == 0 {
			score = thumbnailQualityScore(url)
		}
		if first || score > bestScore {
			best = Thumbnail{URL: url, Width: int(w)}
			bestScore = score
			first = false
		}
	}
	return best.URL
}

func parseThumbnails(thumbs []interface{}) []Thumbnail {
	var result []Thumbnail
	for _, t := range thumbs {
		m, ok := t.(map[string]interface{})
		if !ok {
			continue
		}
		u, _ := m["url"].(string)
		w, _ := m["width"].(float64)
		h, _ := m["height"].(float64)
		result = append(result, Thumbnail{URL: u, Width: int(w), Height: int(h)})
	}
	return result
}

func parseVideoRenderer(vr map[string]interface{}) *VideoResult {
	vid, _ := vr["videoId"].(string)
	if vid == "" {
		return nil
	}

	title := ""
	if t, ok := vr["title"].(map[string]interface{}); ok {
		if runs, ok := t["runs"].([]interface{}); ok {
			title = extractRuns(runs)
		}
	}

	author := ""
	channelURL := ""
	if ot, ok := vr["ownerText"].(map[string]interface{}); ok {
		if runs, ok := ot["runs"].([]interface{}); ok {
			author = extractRuns(runs)
			if len(runs) > 0 {
				if r, ok := runs[0].(map[string]interface{}); ok {
					if ep, ok := r["navigationEndpoint"].(map[string]interface{}); ok {
						if be, ok := ep["browseEndpoint"].(map[string]interface{}); ok {
							channelURL, _ = be["canonicalBaseUrl"].(string)
						}
					}
				}
			}
		}
	}

	var rawThumbs []Thumbnail
	thumbnail := ""
	if tn, ok := vr["thumbnail"].(map[string]interface{}); ok {
		if tl, ok := tn["thumbnails"].([]interface{}); ok {
			rawThumbs = parseThumbnails(tl)
			thumbnail = bestThumbnail(tl)
		}
	}

	durText := ""
	if lt, ok := vr["lengthText"].(map[string]interface{}); ok {
		if s, ok := lt["simpleText"].(string); ok {
			durText = s
		} else if runs, ok := lt["runs"].([]interface{}); ok {
			durText = extractRuns(runs)
		}
	}
	durStr, durSec := parseDuration(durText)

	vcText := ""
	if vc, ok := vr["viewCountText"].(map[string]interface{}); ok {
		if s, ok := vc["simpleText"].(string); ok {
			vcText = s
		} else if runs, ok := vc["runs"].([]interface{}); ok {
			vcText = extractRuns(runs)
		}
	}
	vcStr, vcRaw := parseViewCount(vcText)

	pubTime := ""
	if pt, ok := vr["publishedTimeText"].(map[string]interface{}); ok {
		pubTime, _ = pt["simpleText"].(string)
	}

	desc := ""
	if dms, ok := vr["detailedMetadataSnippets"].([]interface{}); ok && len(dms) > 0 {
		if dm, ok := dms[0].(map[string]interface{}); ok {
			if st, ok := dm["snippetText"].(map[string]interface{}); ok {
				if runs, ok := st["runs"].([]interface{}); ok {
					desc = extractRuns(runs)
				}
			}
		}
	}
	if desc == "" {
		if ds, ok := vr["descriptionSnippet"].(map[string]interface{}); ok {
			if runs, ok := ds["runs"].([]interface{}); ok {
				desc = extractRuns(runs)
			}
		}
	}

	channelAvatar := ""
	if ctsr, ok := vr["channelThumbnailSupportedRenderers"].(map[string]interface{}); ok {
		if ctw, ok := ctsr["channelThumbnailWithLinkRenderer"].(map[string]interface{}); ok {
			if tn, ok := ctw["thumbnail"].(map[string]interface{}); ok {
				if tl, ok := tn["thumbnails"].([]interface{}); ok {
					channelAvatar = bestThumbnail(tl)
				}
			}
		}
	}

	isLive := false
	isUpcoming := false
	isVerified := false
	if badges, ok := vr["badges"].([]interface{}); ok {
		for _, b := range badges {
			if mb, ok := b.(map[string]interface{}); ok {
				if mbr, ok := mb["metadataBadgeRenderer"].(map[string]interface{}); ok {
					style, _ := mbr["style"].(string)
					if strings.Contains(strings.ToUpper(style), "LIVE") {
						isLive = true
					}
				}
			}
		}
	}

	fb := fallbackResult(vid)
	if title == "" {
		title = fb.Title
	}
	if author == "" {
		author = fb.Author
	}
	if thumbnail == "" {
		thumbnail = fb.Thumbnail
	}
	if len(rawThumbs) == 0 {
		rawThumbs = fb.Thumbnails
	}

	return &VideoResult{
		ID:              vid,
		Title:           title,
		Author:          author,
		ChannelURL:      channelURL,
		Thumbnail:       thumbnail,
		Thumbnails:      rawThumbs,
		FullURL:         fb.FullURL,
		EmbedURL:        fb.EmbedURL,
		Duration:        durStr,
		DurationSeconds: durSec,
		ViewCount:       vcStr,
		ViewCountRaw:    vcRaw,
		PublishedTime:   pubTime,
		Description:     desc,
		ChannelAvatar:   channelAvatar,
		IsLive:          isLive,
		IsUpcoming:      isUpcoming,
		IsVerified:      isVerified,
	}
}

func fetchOembed(id string) map[string]string {
	result := map[string]string{}
	u := fmt.Sprintf("https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=%s&format=json", id)
	resp, err := httpClient.Get(u)
	if err != nil || resp.StatusCode != 200 {
		if resp != nil {
			resp.Body.Close()
		}
		return result
	}
	defer resp.Body.Close()
	var data oembedResponse
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return result
	}
	result["title"] = data.Title
	result["author"] = data.AuthorName
	result["thumbnail"] = data.ThumbnailURL
	return result
}

func GetVideo(id string) *VideoResult {
	fallback := fallbackResult(id)
	html, err := fetchHTML(fmt.Sprintf("https://www.youtube.com/watch?v=%s", id))
	if err != nil {
		enrich := fetchOembed(id)
		if enrich["title"] != "" {
			fallback.Title = enrich["title"]
		}
		if enrich["author"] != "" {
			fallback.Author = enrich["author"]
		}
		if enrich["thumbnail"] != "" {
			fallback.Thumbnail = enrich["thumbnail"]
		}
		return &fallback
	}

	data := extractJSON(html, "var ytInitialPlayerResponse")
	if data == nil {
		data = extractJSON(html, "var ytInitialData")
	}

	if data != nil {
		if vd, ok := data["videoDetails"].(map[string]interface{}); ok {
			dur, _ := vd["lengthSeconds"].(string)
			durSec, _ := strconv.Atoi(dur)
			hrs := durSec / 3600
			mins := (durSec % 3600) / 60
			secs := durSec % 60
			durStr := ""
			if hrs > 0 {
				durStr = fmt.Sprintf("%d:%02d:%02d", hrs, mins, secs)
			} else {
				durStr = fmt.Sprintf("%d:%02d", mins, secs)
			}

			vcStr := ""
			if vc, ok := vd["viewCount"].(string); ok {
				vcRaw, _ := strconv.ParseInt(vc, 10, 64)
				vcStr = fmt.Sprintf("%d views", vcRaw)
				fallback.ViewCountRaw = vcRaw
			}

			title, _ := vd["title"].(string)
			author, _ := vd["author"].(string)
			chId, _ := vd["channelId"].(string)
			desc, _ := vd["shortDescription"].(string)

			var athumb string
			if at, ok := vd["authorThumbnails"].([]interface{}); ok && len(at) > 0 {
				if atm, ok := at[0].(map[string]interface{}); ok {
					athumb, _ = atm["url"].(string)
				}
			}

			return &VideoResult{
				ID:              id,
				Title:           title,
				Author:          author,
				ChannelURL:      fmt.Sprintf("https://www.youtube.com/%s", chId),
				Thumbnail:       fallback.Thumbnail,
				Thumbnails:      fallback.Thumbnails,
				FullURL:         fallback.FullURL,
				EmbedURL:        fallback.EmbedURL,
				Duration:        durStr,
				DurationSeconds: durSec,
				ViewCount:       vcStr,
				Description:     desc,
				ChannelAvatar:   athumb,
			}
		}
	}

	enrich := fetchOembed(id)
	if enrich["title"] != "" {
		fallback.Title = enrich["title"]
	}
	if enrich["author"] != "" {
		fallback.Author = enrich["author"]
	}
	if enrich["thumbnail"] != "" {
		fallback.Thumbnail = enrich["thumbnail"]
	}
	return &fallback
}

func fetchHTML(u string) (string, error) {
	resp, err := httpClient.Get(u)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return string(body), nil
}

func searchHTML(query string) (string, error) {
	u := fmt.Sprintf("https://www.youtube.com/results?search_query=%s", url.QueryEscape(query))
	return fetchHTML(u)
}

func Search(query string, gl string, hl string, limit ...int) ([]VideoResult, error) {
	return SearchWithContext(context.Background(), query, gl, hl, limit...)
}

func SearchWithContext(ctx context.Context, query string, gl string, hl string, limit ...int) ([]VideoResult, error) {
	maxResults := 15
	if len(limit) > 0 && limit[0] > 0 {
		maxResults = limit[0]
	}
	if maxResults > 50 {
		maxResults = 50
	}

	su := fmt.Sprintf("https://www.youtube.com/results?search_query=%s", url.QueryEscape(query))
	if gl != "" {
		su += "&gl=" + url.QueryEscape(gl)
	}
	if hl != "" {
		su += "&hl=" + url.QueryEscape(hl)
	}
	req, err := http.NewRequestWithContext(ctx, "GET", su, nil)
	if err != nil {
		return nil, fmt.Errorf("create request failed: %w", err)
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("search request failed: %w", err)
	}
	defer resp.Body.Close()
	html, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response failed: %w", err)
	}
	htmlStr := string(html)

	data := extractJSON(htmlStr, "var ytInitialData")
	if data == nil {
		return nil, fmt.Errorf("could not extract ytInitialData")
	}

	var results []VideoResult
	contents, _ := data["contents"].(map[string]interface{})
	tcsr, _ := contents["twoColumnSearchResultsRenderer"].(map[string]interface{})
	pc, _ := tcsr["primaryContents"].(map[string]interface{})
	slr, _ := pc["sectionListRenderer"].(map[string]interface{})
	sections, _ := slr["contents"].([]interface{})

	for _, section := range sections {
		if len(results) >= maxResults {
			break
		}
		sm, ok := section.(map[string]interface{})
		if !ok {
			continue
		}
		if isr, ok := sm["itemSectionRenderer"].(map[string]interface{}); ok {
			items, _ := isr["contents"].([]interface{})
			for _, item := range items {
				if len(results) >= maxResults {
					break
				}
				im, ok := item.(map[string]interface{})
				if !ok {
					continue
				}
				if vr, ok := im["videoRenderer"].(map[string]interface{}); ok {
					v := parseVideoRenderer(vr)
					if v != nil {
						results = append(results, *v)
					}
				}
			}
		}
	}

	needsEnrichment := false
	for _, r := range results {
		if r.Title == fmt.Sprintf("Video %s", r.ID) || r.Author == "YouTube" {
			needsEnrichment = true
			break
		}
	}

	if needsEnrichment {
		var wg sync.WaitGroup
		type enriched struct {
			idx    int
			title  string
			author string
			thumb  string
		}
		enrichments := make([]enriched, len(results))
		for i, r := range results {
			if r.Title == fmt.Sprintf("Video %s", r.ID) || r.Author == "YouTube" {
				wg.Add(1)
				go func(idx int, vid string) {
					defer wg.Done()
					o := fetchOembed(vid)
					enrichments[idx] = enriched{idx: idx, title: o["title"], author: o["author"], thumb: o["thumbnail"]}
				}(i, r.ID)
			}
		}
		wg.Wait()
		for _, e := range enrichments {
			if e.title != "" {
				results[e.idx].Title = e.title
			}
			if e.author != "" {
				results[e.idx].Author = e.author
			}
			if e.thumb != "" {
				results[e.idx].Thumbnail = e.thumb
			}
		}
	}

	return results, nil
}

func SearchJSON(query string, limit ...int) (string, error) {
	results, err := Search(query, "", "", limit...)
	if err != nil {
		return "", err
	}
	b, err := json.MarshalIndent(results, "", "  ")
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// ─── parseTrendingResults ─────────────────────────────────────────────────

func parseTrendingResults(data map[string]interface{}, limit int) ([]VideoResult, string) {
	var results []VideoResult
	var continuation string

	contents, _ := data["contents"].(map[string]interface{})
	tcbr, _ := contents["twoColumnBrowseResultsRenderer"].(map[string]interface{})
	tabs, _ := tcbr["tabs"].([]interface{})

	for _, tab := range tabs {
		tabMap, ok := tab.(map[string]interface{})
		if !ok {
			continue
		}
		tr, _ := tabMap["tabRenderer"].(map[string]interface{})
		ct, _ := tr["content"].(map[string]interface{})
		slr, _ := ct["sectionListRenderer"].(map[string]interface{})
		sections, _ := slr["contents"].([]interface{})
		if sections == nil {
			continue
		}

		for _, section := range sections {
			if len(results) >= limit {
				break
			}
			sm, ok := section.(map[string]interface{})
			if !ok {
				continue
			}

			if isr, ok := sm["itemSectionRenderer"].(map[string]interface{}); ok {
				items, _ := isr["contents"].([]interface{})
				for _, item := range items {
					if len(results) >= limit {
						break
					}
					im, ok := item.(map[string]interface{})
					if !ok {
						continue
					}
					if vr, ok := im["videoRenderer"].(map[string]interface{}); ok {
						v := parseVideoRenderer(vr)
						if v != nil {
							results = append(results, *v)
						}
					}
				}
			}

			if sh, ok := sm["shelfRenderer"].(map[string]interface{}); ok {
				shContent, _ := sh["content"].(map[string]interface{})
				var shelfItems []interface{}
				if es, ok := shContent["expandedShelfContentsRenderer"].(map[string]interface{}); ok {
					shelfItems, _ = es["items"].([]interface{})
				}
				if shelfItems == nil {
					if hl, ok := shContent["horizontalListRenderer"].(map[string]interface{}); ok {
						shelfItems, _ = hl["items"].([]interface{})
					}
				}
				for _, item := range shelfItems {
					if len(results) >= limit {
						break
					}
					im, ok := item.(map[string]interface{})
					if !ok {
						continue
					}
					if vr, ok := im["videoRenderer"].(map[string]interface{}); ok {
						v := parseVideoRenderer(vr)
						if v != nil {
							results = append(results, *v)
						}
					}
				}
			}

			if cir, ok := sm["continuationItemRenderer"].(map[string]interface{}); ok {
				if ep, ok := cir["continuationEndpoint"].(map[string]interface{}); ok {
					if cc, ok := ep["continuationCommand"].(map[string]interface{}); ok {
						if tok, ok := cc["token"].(string); ok {
							continuation = tok
						}
					}
				}
			}
		}
		if len(results) > 0 {
			break
		}
	}

	return results, continuation
}

// ─── parseChannelResults ───────────────────────────────────────────────────

func parseChannelResults(data map[string]interface{}, limit int) ([]VideoResult, string) {
	var results []VideoResult
	var continuation string

	contents, _ := data["contents"].(map[string]interface{})
	tcbr, _ := contents["twoColumnBrowseResultsRenderer"].(map[string]interface{})
	tabs, _ := tcbr["tabs"].([]interface{})

	for _, tab := range tabs {
		tabMap, ok := tab.(map[string]interface{})
		if !ok {
			continue
		}
		tr, _ := tabMap["tabRenderer"].(map[string]interface{})
		ct, _ := tr["content"].(map[string]interface{})

		var items []interface{}
		if rg, ok := ct["richGridRenderer"].(map[string]interface{}); ok {
			items, _ = rg["contents"].([]interface{})
		}
		if items == nil {
			if slr, ok := ct["sectionListRenderer"].(map[string]interface{}); ok {
				items, _ = slr["contents"].([]interface{})
			}
		}
		if items == nil {
			continue
		}

		for _, item := range items {
			if len(results) >= limit {
				break
			}
			im, ok := item.(map[string]interface{})
			if !ok {
				continue
			}

			if cir, ok := im["continuationItemRenderer"].(map[string]interface{}); ok {
				if ep, ok := cir["continuationEndpoint"].(map[string]interface{}); ok {
					if cc, ok := ep["continuationCommand"].(map[string]interface{}); ok {
						if tok, ok := cc["token"].(string); ok {
							continuation = tok
						}
					}
				}
			}

			if ri, ok := im["richItemRenderer"].(map[string]interface{}); ok {
				if riContent, ok := ri["content"].(map[string]interface{}); ok {
					if vr, ok := riContent["videoRenderer"].(map[string]interface{}); ok {
						v := parseVideoRenderer(vr)
						if v != nil {
							results = append(results, *v)
						}
					}
				}
			}

			if vr, ok := im["videoRenderer"].(map[string]interface{}); ok {
				v := parseVideoRenderer(vr)
				if v != nil {
					results = append(results, *v)
				}
			}
		}

		if len(results) > 0 {
			break
		}
	}

	return results, continuation
}

// ─── parsePlaylistResults ──────────────────────────────────────────────────

func parsePlaylistResults(data map[string]interface{}, limit int) ([]VideoResult, string) {
	var results []VideoResult
	var continuation string

	contents, _ := data["contents"].(map[string]interface{})

	var pvrContents []interface{}
	if tcbr, ok := contents["twoColumnBrowseResultsRenderer"].(map[string]interface{}); ok {
		if tabs, ok := tcbr["tabs"].([]interface{}); ok && len(tabs) > 0 {
			if tab, ok := tabs[0].(map[string]interface{}); ok {
				pvrContents = getPlaylistVideoListContents(tab)
			}
		}
	}

	if pvrContents == nil {
		if tcwn, ok := contents["twoColumnWatchNextResults"].(map[string]interface{}); ok {
			if pl, ok := tcwn["playlist"].(map[string]interface{}); ok {
				if pl2, ok := pl["playlist"].(map[string]interface{}); ok {
					pvrContents, _ = pl2["contents"].([]interface{})
				}
			}
		}
	}

	if pvrContents == nil {
		return results, continuation
	}

	for _, item := range pvrContents {
		if len(results) >= limit {
			break
		}
		im, ok := item.(map[string]interface{})
		if !ok {
			continue
		}

		if cir, ok := im["continuationItemRenderer"].(map[string]interface{}); ok {
			if ep, ok := cir["continuationEndpoint"].(map[string]interface{}); ok {
				if cc, ok := ep["continuationCommand"].(map[string]interface{}); ok {
					if tok, ok := cc["token"].(string); ok {
						continuation = tok
					}
				}
			}
		}

		if pvr, ok := im["playlistVideoRenderer"].(map[string]interface{}); ok {
			vid, _ := pvr["videoId"].(string)
			if vid == "" {
				continue
			}
			title := ""
			if t, ok := pvr["title"].(map[string]interface{}); ok {
				if runs, ok := t["runs"].([]interface{}); ok {
					title = extractRuns(runs)
				}
			}
			author := ""
			if sbt, ok := pvr["shortBylineText"].(map[string]interface{}); ok {
				if runs, ok := sbt["runs"].([]interface{}); ok {
					author = extractRuns(runs)
				}
			}
			durText := ""
			if lt, ok := pvr["lengthText"].(map[string]interface{}); ok {
				if s, ok := lt["simpleText"].(string); ok {
					durText = s
				} else if runs, ok := lt["runs"].([]interface{}); ok {
					durText = extractRuns(runs)
				}
			}
			durStr, durSec := parseDuration(durText)

			fb := fallbackResult(vid)
			if title == "" {
				title = fb.Title
			}
			if author == "" {
				author = fb.Author
			}

			results = append(results, VideoResult{
				ID:              vid,
				Title:           title,
				Author:          author,
				Thumbnail:       fb.Thumbnail,
				Thumbnails:      fb.Thumbnails,
				FullURL:         fb.FullURL,
				EmbedURL:        fb.EmbedURL,
				Duration:        durStr,
				DurationSeconds: durSec,
			})
		}
	}

	return results, continuation
}

func getPlaylistVideoListContents(tab map[string]interface{}) []interface{} {
	tr, _ := tab["tabRenderer"].(map[string]interface{})
	ct, _ := tr["content"].(map[string]interface{})
	slr, _ := ct["sectionListRenderer"].(map[string]interface{})
	slrContents, _ := slr["contents"].([]interface{})
	if len(slrContents) == 0 {
		return nil
	}
	first, _ := slrContents[0].(map[string]interface{})
	isr, _ := first["itemSectionRenderer"].(map[string]interface{})
	isrContents, _ := isr["contents"].([]interface{})
	if len(isrContents) == 0 {
		return nil
	}
	firstItem, _ := isrContents[0].(map[string]interface{})
	pvlr, _ := firstItem["playlistVideoListRenderer"].(map[string]interface{})
	contents, _ := pvlr["contents"].([]interface{})
	return contents
}

// ─── parseContinuationResults (with path) ──────────────────────────────────

func parseContinuationResults(data map[string]interface{}, limit int, path string) ([]VideoResult, string) {
	var results []VideoResult
	var continuation string

	var items []interface{}
	if path == "channel" {
		if orr, ok := data["onResponseReceivedActions"].([]interface{}); ok && len(orr) > 0 {
			if a, ok := orr[0].(map[string]interface{}); ok {
				if ac, ok := a["appendContinuationItemsAction"].(map[string]interface{}); ok {
					items, _ = ac["continuationItems"].([]interface{})
				}
			}
		}
		if items == nil {
			if orr, ok := data["onResponseReceivedEndpoints"].([]interface{}); ok && len(orr) > 0 {
				if a, ok := orr[0].(map[string]interface{}); ok {
					if ac, ok := a["appendContinuationItemsAction"].(map[string]interface{}); ok {
						items, _ = ac["continuationItems"].([]interface{})
					}
				}
			}
		}
	} else if path == "playlist" {
		if orr, ok := data["onResponseReceivedActions"].([]interface{}); ok && len(orr) > 0 {
			if a, ok := orr[0].(map[string]interface{}); ok {
				if ac, ok := a["appendContinuationItemsAction"].(map[string]interface{}); ok {
					items, _ = ac["continuationItems"].([]interface{})
				}
			}
		}
	} else {
		if orr, ok := data["onResponseReceivedEndpoints"].([]interface{}); ok && len(orr) > 0 {
			if a, ok := orr[0].(map[string]interface{}); ok {
				if ac, ok := a["appendContinuationItemsAction"].(map[string]interface{}); ok {
					items, _ = ac["continuationItems"].([]interface{})
				}
			}
		}
	}
	if items == nil {
		return results, continuation
	}

	for _, item := range items {
		if len(results) >= limit {
			break
		}
		im, ok := item.(map[string]interface{})
		if !ok {
			continue
		}

		if cir, ok := im["continuationItemRenderer"].(map[string]interface{}); ok {
			if ep, ok := cir["continuationEndpoint"].(map[string]interface{}); ok {
				if cc, ok := ep["continuationCommand"].(map[string]interface{}); ok {
					if tok, ok := cc["token"].(string); ok {
						continuation = tok
					}
				}
			}
		}

		if path == "playlist" {
			if pvr, ok := im["playlistVideoRenderer"].(map[string]interface{}); ok {
				vid, _ := pvr["videoId"].(string)
				if vid != "" {
					title := ""
					if t, ok := pvr["title"].(map[string]interface{}); ok {
						if runs, ok := t["runs"].([]interface{}); ok {
							title = extractRuns(runs)
						}
					}
					author := ""
					if sbt, ok := pvr["shortBylineText"].(map[string]interface{}); ok {
						if runs, ok := sbt["runs"].([]interface{}); ok {
							author = extractRuns(runs)
						}
					}
					durText := ""
					if lt, ok := pvr["lengthText"].(map[string]interface{}); ok {
						if s, ok := lt["simpleText"].(string); ok {
							durText = s
						} else if runs, ok := lt["runs"].([]interface{}); ok {
							durText = extractRuns(runs)
						}
					}
					durStr, durSec := parseDuration(durText)
					fb := fallbackResult(vid)
					if title == "" {
						title = fb.Title
					}
					if author == "" {
						author = fb.Author
					}
					results = append(results, VideoResult{
						ID: vid, Title: title, Author: author,
						Thumbnail: fb.Thumbnail, Thumbnails: fb.Thumbnails,
						FullURL: fb.FullURL, EmbedURL: fb.EmbedURL,
						Duration: durStr, DurationSeconds: durSec,
					})
				}
				continue
			}
		}

		var vr map[string]interface{}
		if v, ok := im["videoRenderer"].(map[string]interface{}); ok {
			vr = v
		} else if ri, ok := im["richItemRenderer"].(map[string]interface{}); ok {
			if c, ok := ri["content"].(map[string]interface{}); ok {
				vr, _ = c["videoRenderer"].(map[string]interface{})
			}
		}
		if vr != nil {
			v := parseVideoRenderer(vr)
			if v != nil {
				results = append(results, *v)
			}
		}
	}

	return results, continuation
}

// ─── extractApiKeys ────────────────────────────────────────────────────────

func extractApiKeys(html string) (string, map[string]interface{}) {
	re := regexp.MustCompile(`"INNERTUBE_API_KEY":"(AIza[^"]+)"`)
	matches := re.FindStringSubmatch(html)
	apiKey := ""
	if len(matches) > 1 {
		apiKey = matches[1]
	}
	context := extractJSON(html, `"INNERTUBE_CONTEXT"`)
	return apiKey, context
}

// ─── Public API: searchTrending ────────────────────────────────────────────

func SearchTrending(gl string, hl string, limit ...int) ([]VideoResult, error) {
	return SearchTrendingWithContext(context.Background(), gl, hl, limit...)
}

func SearchTrendingWithContext(ctx context.Context, gl string, hl string, limit ...int) ([]VideoResult, error) {
	maxResults := 15
	if len(limit) > 0 && limit[0] > 0 {
		maxResults = limit[0]
	}
	if maxResults > 50 {
		maxResults = 50
	}

	trendingURL := "https://www.youtube.com/feed/trending"
	params := []string{}
	if gl != "" {
		params = append(params, "gl="+url.QueryEscape(gl))
	}
	if hl != "" {
		params = append(params, "hl="+url.QueryEscape(hl))
	}
	if len(params) > 0 {
		trendingURL += "?" + strings.Join(params, "&")
	}
	req, err := http.NewRequestWithContext(ctx, "GET", trendingURL, nil)
	if err != nil {
		return nil, fmt.Errorf("create request failed: %w", err)
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("trending request failed: %w", err)
	}
	defer resp.Body.Close()
	html, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response failed: %w", err)
	}
	htmlStr := string(html)

	data := extractJSON(htmlStr, "var ytInitialData")
	if data == nil {
		return nil, fmt.Errorf("could not extract ytInitialData")
	}

	results, _ := parseTrendingResults(data, maxResults)
	return results, nil
}

type SearchResponse struct {
	Results      []VideoResult            `json:"results"`
	Continuation string                   `json:"continuation,omitempty"`
	APIKey       string                   `json:"apiKey,omitempty"`
	Context      map[string]interface{}   `json:"context,omitempty"`
}

func SearchTrendingFull(gl string, hl string, limit ...int) (*SearchResponse, error) {
	maxResults := 15
	if len(limit) > 0 && limit[0] > 0 {
		maxResults = limit[0]
	}
	if maxResults > 50 {
		maxResults = 50
	}

	trendingURL := "https://www.youtube.com/feed/trending"
	params := []string{}
	if gl != "" {
		params = append(params, "gl="+url.QueryEscape(gl))
	}
	if hl != "" {
		params = append(params, "hl="+url.QueryEscape(hl))
	}
	if len(params) > 0 {
		trendingURL += "?" + strings.Join(params, "&")
	}
	html, err := fetchHTML(trendingURL)
	if err != nil {
		return &SearchResponse{}, err
	}

	data := extractJSON(html, "var ytInitialData")
	if data == nil {
		return &SearchResponse{}, fmt.Errorf("could not extract ytInitialData")
	}

	apiKey, ctx := extractApiKeys(html)
	results, continuation := parseTrendingResults(data, maxResults)

	return &SearchResponse{
		Results:      results,
		Continuation: continuation,
		APIKey:       apiKey,
		Context:      ctx,
	}, nil
}

// ─── Public API: searchChannel ─────────────────────────────────────────────

func SearchChannel(channelID string, gl string, hl string, limit ...int) ([]VideoResult, error) {
	return SearchChannelWithContext(context.Background(), channelID, gl, hl, limit...)
}

func SearchChannelWithContext(ctx context.Context, channelID string, gl string, hl string, limit ...int) ([]VideoResult, error) {
	maxResults := 15
	if len(limit) > 0 && limit[0] > 0 {
		maxResults = limit[0]
	}
	if maxResults > 50 {
		maxResults = 50
	}

	u := fmt.Sprintf("https://www.youtube.com/channel/%s/videos", channelID)
	params := []string{}
	if gl != "" {
		params = append(params, "gl="+url.QueryEscape(gl))
	}
	if hl != "" {
		params = append(params, "hl="+url.QueryEscape(hl))
	}
	if len(params) > 0 {
		u += "?" + strings.Join(params, "&")
	}
	req, err := http.NewRequestWithContext(ctx, "GET", u, nil)
	if err != nil {
		return nil, fmt.Errorf("create request failed: %w", err)
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("channel request failed: %w", err)
	}
	defer resp.Body.Close()
	html, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response failed: %w", err)
	}
	htmlStr := string(html)

	data := extractJSON(htmlStr, "var ytInitialData")
	if data == nil {
		return nil, fmt.Errorf("could not extract ytInitialData")
	}

	results, _ := parseChannelResults(data, maxResults)

	return results, nil
}

// ─── Public API: searchPlaylist ────────────────────────────────────────────

func SearchPlaylist(playlistID string, gl string, hl string, limit ...int) ([]VideoResult, error) {
	return SearchPlaylistWithContext(context.Background(), playlistID, gl, hl, limit...)
}

func SearchPlaylistWithContext(ctx context.Context, playlistID string, gl string, hl string, limit ...int) ([]VideoResult, error) {
	maxResults := 15
	if len(limit) > 0 && limit[0] > 0 {
		maxResults = limit[0]
	}
	if maxResults > 50 {
		maxResults = 50
	}

	u := fmt.Sprintf("https://www.youtube.com/playlist?list=%s", playlistID)
	if gl != "" {
		u += "&gl=" + url.QueryEscape(gl)
	}
	if hl != "" {
		u += "&hl=" + url.QueryEscape(hl)
	}
	req, err := http.NewRequestWithContext(ctx, "GET", u, nil)
	if err != nil {
		return nil, fmt.Errorf("create request failed: %w", err)
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("playlist request failed: %w", err)
	}
	defer resp.Body.Close()
	html, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response failed: %w", err)
	}
	htmlStr := string(html)

	data := extractJSON(htmlStr, "var ytInitialData")
	if data == nil {
		return nil, fmt.Errorf("could not extract ytInitialData")
	}

	results, _ := parsePlaylistResults(data, maxResults)

	return results, nil
}

// ─── Public API: searchContinue (with path) ────────────────────────────────

func SearchContinue(continuation string, limit int, apiKey string, contextJSON string, path string) (*SearchResponse, error) {
	if limit < 1 {
		limit = 1
	}
	if limit > 50 {
		limit = 50
	}

	key := apiKey
	if key == "" {
		key = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
	}

	var ctxMap map[string]interface{}
	if contextJSON != "" {
		if err := json.Unmarshal([]byte(contextJSON), &ctxMap); err != nil {
			ctxMap = map[string]interface{}{
				"client": map[string]interface{}{
					"hl":            "en",
					"gl":            "US",
					"clientName":    "WEB",
					"clientVersion": "2.20240801.00.00",
				},
			}
		}
	} else {
		ctxMap = map[string]interface{}{
			"client": map[string]interface{}{
				"hl":            "en",
				"gl":            "US",
				"clientName":    "WEB",
				"clientVersion": "2.20240801.00.00",
			},
		}
	}

	body := map[string]interface{}{
		"context":      ctxMap,
		"continuation": continuation,
	}
	bodyJSON, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("marshal body: %w", err)
	}

	u := fmt.Sprintf("https://www.youtube.com/youtubei/v1/search?key=%s", key)
	req, err := http.NewRequest("POST", u, strings.NewReader(string(bodyJSON)))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("innertube request: %w", err)
	}
	defer resp.Body.Close()
	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	var data map[string]interface{}
	if err := json.Unmarshal(respBody, &data); err != nil {
		return nil, fmt.Errorf("parse response: %w", err)
	}

	results, nextContinuation := parseContinuationResults(data, limit, path)

	return &SearchResponse{
		Results:      results,
		Continuation: nextContinuation,
		APIKey:       key,
	}, nil
}

// ─── Comment Types ──────────────────────────────────────

type CommentAuthor struct {
	Name       string `json:"name"`
	ChannelID  string `json:"channelId"`
	Avatar     string `json:"avatar"`
	IsVerified bool   `json:"isVerified"`
	IsOwner    bool   `json:"isOwner"`
}

type CommentReply struct {
	ID               string        `json:"id"`
	Author           CommentAuthor `json:"author"`
	Text             string        `json:"text"`
	LikeCount        int           `json:"likeCount"`
	LikeCountRaw     int           `json:"likeCountRaw"`
	PublishedTime    string        `json:"publishedTime"`
	IsLikedByCreator bool          `json:"isLikedByCreator"`
}

type VideoComment struct {
	ID               string        `json:"id"`
	Author           CommentAuthor `json:"author"`
	Text             string        `json:"text"`
	LikeCount        int           `json:"likeCount"`
	LikeCountRaw     int           `json:"likeCountRaw"`
	PublishedTime    string        `json:"publishedTime"`
	ReplyCount       int           `json:"replyCount"`
	IsLikedByCreator bool          `json:"isLikedByCreator"`
	IsPinned         bool          `json:"isPinned"`
	Replies          []CommentReply `json:"replies"`
	ReplyContinuation string       `json:"replyContinuation,omitempty"`
}

type RelatedVideo struct {
	ID              string `json:"id"`
	Title           string `json:"title"`
	Author          string `json:"author"`
	ChannelURL      string `json:"channelUrl"`
	Duration        string `json:"duration"`
	DurationSeconds int    `json:"durationSeconds"`
	ViewCount       string `json:"viewCount"`
	ViewCountRaw    int    `json:"viewCountRaw"`
	PublishedTime   string `json:"publishedTime"`
	Thumbnail       string `json:"thumbnail"`
	IsLive          bool   `json:"isLive"`
}

type LiveStreamInfo struct {
	IsLive             bool   `json:"isLive"`
	IsUpcoming         bool   `json:"isUpcoming"`
	ViewerCount        int    `json:"viewerCount"`
	ViewerCountStr     string `json:"viewerCountStr"`
	StartTime          string `json:"startTime"`
	ScheduledStartTime string `json:"scheduledStartTime"`
	LikesCount         int    `json:"likesCount"`
	DislikesCount      int    `json:"dislikesCount"`
}

type VideoStats struct {
	Views       int64 `json:"views"`
	Likes       int64 `json:"likes"`
	Comments    int64 `json:"comments"`
	IsLive      bool  `json:"isLive"`
	ViewerCount int   `json:"viewerCount"`
}

// ─── LRU Cache ─────────────────────────────────────────

type cacheEntry struct {
	value   string
	expires int64
}

type LRUCache struct {
	maxSize int
	ttlMs   int64
	mu      sync.Mutex
	keys    []string
	entries map[string]cacheEntry
}

func NewLRUCache(maxSize int, ttlMs int64) *LRUCache {
	return &LRUCache{
		maxSize: maxSize,
		ttlMs:   ttlMs,
		keys:    make([]string, 0, maxSize),
		entries: make(map[string]cacheEntry, maxSize),
	}
}

func (c *LRUCache) Get(key string) (string, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	entry, ok := c.entries[key]
	if !ok {
		return "", false
	}
	if time.Now().UnixMilli() > entry.expires {
		delete(c.entries, key)
		c.removeKey(key)
		return "", false
	}
	c.removeKey(key)
	c.keys = append(c.keys, key)
	return entry.value, true
}

func (c *LRUCache) Set(key, value string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if _, ok := c.entries[key]; ok {
		c.removeKey(key)
	} else if len(c.keys) >= c.maxSize {
		oldest := c.keys[0]
		c.keys = c.keys[1:]
		delete(c.entries, oldest)
	}
	c.keys = append(c.keys, key)
	c.entries[key] = cacheEntry{value: value, expires: time.Now().UnixMilli() + c.ttlMs}
}

func (c *LRUCache) removeKey(key string) {
	for i, k := range c.keys {
		if k == key {
			c.keys = append(c.keys[:i], c.keys[i+1:]...)
			return
		}
	}
}

func (c *LRUCache) Count() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.keys)
}

// ─── Comments ───────────────────────────────────────────

func parseCommentRenderer(cr map[string]interface{}) VideoComment {
	id, _ := cr["commentId"].(string)
	name := extractRuns(getRuns(cr, "authorText")) + getSimpleText(cr, "authorText")
	channel := ""
	if ep, ok := cr["authorEndpoint"].(map[string]interface{}); ok {
		if be, ok := ep["browseEndpoint"].(map[string]interface{}); ok {
			channel, _ = be["browseId"].(string)
		}
	}
	avatar := ""
	if at, ok := cr["authorThumbnail"].(map[string]interface{}); ok {
		if tl, ok := at["thumbnails"].([]interface{}); ok && len(tl) > 0 {
			if m, ok := tl[len(tl)-1].(map[string]interface{}); ok {
				avatar, _ = m["url"].(string)
			}
		}
	}
	isVerified := false
	if badge, ok := cr["authorCommentBadge"].(map[string]interface{}); ok {
		if abr, ok := badge["authorCommentBadgeRenderer"].(map[string]interface{}); ok {
			if icon, ok := abr["icon"].(map[string]interface{}); ok {
				t, _ := icon["iconType"].(string)
				isVerified = t == "CHECK"
			}
		}
	}
	isOwner, _ := cr["authorIsChannelOwner"].(bool)
	text := extractRuns(getRuns(cr, "contentText")) + getSimpleText(cr, "contentText")
	likes := 0
	if vc, ok := cr["voteCount"].(map[string]interface{}); ok {
		s, _ := vc["simpleText"].(string)
		likes, _ = strconv.Atoi(s)
	}
	published := ""
	if pt, ok := cr["publishedTimeText"].(map[string]interface{}); ok {
		if runs, ok := pt["runs"].([]interface{}); ok && len(runs) > 0 {
			if r, ok := runs[0].(map[string]interface{}); ok {
				published, _ = r["text"].(string)
			}
		}
	}
	replyCount := 0
	if rc, ok := cr["replyCount"].(float64); ok {
		replyCount = int(rc)
	}
	isLiked, _ := cr["isLiked"].(bool)
	isPinned := false
	if _, ok := cr["pinnedCommentBadge"]; ok {
		isPinned = true
	}

	replies := []CommentReply{}
	var replyCont string
	if rp, ok := cr["replies"].(map[string]interface{}); ok {
		if crr, ok := rp["commentRepliesRenderer"].(map[string]interface{}); ok {
			if contents, ok := crr["contents"].([]interface{}); ok {
				for _, item := range contents {
					im, ok := item.(map[string]interface{})
					if !ok {
						continue
					}
					if cir, ok := im["continuationItemRenderer"].(map[string]interface{}); ok {
						if ep, ok := cir["continuationEndpoint"].(map[string]interface{}); ok {
							if cc, ok := ep["continuationCommand"].(map[string]interface{}); ok {
								replyCont, _ = cc["token"].(string)
							}
						}
						continue
					}
					if rr, ok := im["commentRenderer"].(map[string]interface{}); ok {
						ra := CommentAuthor{IsOwner: getBool(rr, "authorIsChannelOwner")}
						ra.Name = extractRuns(getRuns(rr, "authorText")) + getSimpleText(rr, "authorText")
						if ep, ok := rr["authorEndpoint"].(map[string]interface{}); ok {
							if be, ok := ep["browseEndpoint"].(map[string]interface{}); ok {
								ra.ChannelID, _ = be["browseId"].(string)
							}
						}
						if at, ok := rr["authorThumbnail"].(map[string]interface{}); ok {
							if tl, ok := at["thumbnails"].([]interface{}); ok && len(tl) > 0 {
								if m, ok := tl[len(tl)-1].(map[string]interface{}); ok {
									ra.Avatar, _ = m["url"].(string)
								}
							}
						}
						rl := 0
						if vc, ok := rr["voteCount"].(map[string]interface{}); ok {
							s, _ := vc["simpleText"].(string)
							rl, _ = strconv.Atoi(s)
						}
						rpTime := ""
						if pt, ok := rr["publishedTimeText"].(map[string]interface{}); ok {
							if runs, ok := pt["runs"].([]interface{}); ok && len(runs) > 0 {
								if r, ok := runs[0].(map[string]interface{}); ok {
									rpTime, _ = r["text"].(string)
								}
							}
						}
						rHeart := false
						if ab, ok := rr["actionButtons"].(map[string]interface{}); ok {
							if car, ok := ab["commentActionButtonsRenderer"].(map[string]interface{}); ok {
								if ch, ok := car["creatorHeart"].(map[string]interface{}); ok {
									if chr, ok := ch["creatorHeartRenderer"].(map[string]interface{}); ok {
										rHeart, _ = chr["isHearted"].(bool)
									}
								}
							}
						}
						replies = append(replies, CommentReply{
							ID:               getString(rr, "commentId"),
							Author:           ra,
							Text:             extractRuns(getRuns(rr, "contentText")) + getSimpleText(rr, "contentText"),
							LikeCount:        rl,
							LikeCountRaw:     rl,
							PublishedTime:    rpTime,
							IsLikedByCreator: rHeart,
						})
					}
				}
			}
		}
	}

	return VideoComment{
		ID:               id,
		Author:           CommentAuthor{Name: name, ChannelID: channel, Avatar: avatar, IsVerified: isVerified, IsOwner: isOwner},
		Text:             text,
		LikeCount:        likes,
		LikeCountRaw:     likes,
		PublishedTime:    published,
		ReplyCount:       replyCount,
		IsLikedByCreator: isLiked,
		IsPinned:         isPinned,
		Replies:          replies,
		ReplyContinuation: replyCont,
	}
}

func getRuns(m map[string]interface{}, key string) []interface{} {
	if v, ok := m[key].(map[string]interface{}); ok {
		if r, ok := v["runs"].([]interface{}); ok {
			return r
		}
	}
	return nil
}

func getSimpleText(m map[string]interface{}, key string) string {
	if v, ok := m[key].(map[string]interface{}); ok {
		if s, ok := v["simpleText"].(string); ok {
			return s
		}
	}
	return ""
}

func getBool(m map[string]interface{}, key string) bool {
	if v, ok := m[key].(bool); ok {
		return v
	}
	return false
}

func getString(m map[string]interface{}, key string) string {
	if v, ok := m[key].(string); ok {
		return v
	}
	return ""
}

func GetComments(videoID string, limit int, continuation ...string) ([]VideoComment, string, error) {
	maxResults := 20
	if limit > 0 {
		maxResults = limit
	}
	if maxResults > 100 {
		maxResults = 100
	}

	if len(continuation) > 0 && continuation[0] != "" {
		html, err := fetchHTML(fmt.Sprintf("https://www.youtube.com/watch?v=%s", videoID))
		if err != nil {
			return nil, "", err
		}
		apiKey := "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
		if m := regexp.MustCompile(`"INNERTUBE_API_KEY":"(AIza[^"]+)"`).FindStringSubmatch(html); m != nil {
			apiKey = m[1]
		}
		ctx := extractJSON(html, `"INNERTUBE_CONTEXT"`)
		body, _ := json.Marshal(map[string]interface{}{
			"context":      ctxOrDefault(ctx),
			"continuation": continuation[0],
		})
		data, err := fetchInnerTube(fmt.Sprintf("https://www.youtube.com/youtubei/v1/next?key=%s", apiKey), body)
		if err != nil {
			return nil, "", err
		}
		return parseCommentsResponse(data, maxResults)
	}

	html, err := fetchHTML(fmt.Sprintf("https://www.youtube.com/watch?v=%s", videoID))
	if err != nil {
		return nil, "", err
	}
	apiKey := "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
	if m := regexp.MustCompile(`"INNERTUBE_API_KEY":"(AIza[^"]+)"`).FindStringSubmatch(html); m != nil {
		apiKey = m[1]
	}
	ctx := extractJSON(html, `"INNERTUBE_CONTEXT"`)

	token := ""
	data := extractJSON(html, "var ytInitialData")
	if data != nil {
		if con, ok := data["contents"].(map[string]interface{}); ok {
			if tcr, ok := con["twoColumnWatchNextResults"].(map[string]interface{}); ok {
				if res, ok := tcr["results"].(map[string]interface{}); ok {
					if rc, ok := res["results"].(map[string]interface{}); ok {
						if conts, ok := rc["contents"].([]interface{}); ok {
							for _, c := range conts {
								cm, ok := c.(map[string]interface{})
								if !ok {
									continue
								}
								if isr, ok := cm["itemSectionRenderer"].(map[string]interface{}); ok {
									if items, ok := isr["contents"].([]interface{}); ok {
										for _, item := range items {
											im, ok := item.(map[string]interface{})
											if !ok {
												continue
											}
											if cir, ok := im["continuationItemRenderer"].(map[string]interface{}); ok {
												if ep, ok := cir["continuationEndpoint"].(map[string]interface{}); ok {
													if cc, ok := ep["continuationCommand"].(map[string]interface{}); ok {
														token, _ = cc["token"].(string)
													}
												}
											}
											if token != "" {
												break
											}
											if cep, ok := im["commentsEntryPointHeaderRenderer"].(map[string]interface{}); ok {
												if cnts, ok := cep["contents"].([]interface{}); ok && len(cnts) > 0 {
													if cim, ok := cnts[0].(map[string]interface{}); ok {
														if cir, ok := cim["continuationItemRenderer"].(map[string]interface{}); ok {
															if ep, ok := cir["continuationEndpoint"].(map[string]interface{}); ok {
																if cc, ok := ep["continuationCommand"].(map[string]interface{}); ok {
																	token, _ = cc["token"].(string)
																}
															}
														}
													}
												}
											}
											if token != "" {
												break
											}
										}
									}
								}
								if token != "" {
									break
								}
							}
						}
					}
				}
			}
		}
	}

	if token == "" {
		return nil, "", nil
	}

	body, _ := json.Marshal(map[string]interface{}{
		"context":      ctxOrDefault(ctx),
		"continuation": token,
	})
	nd, err := fetchInnerTube(fmt.Sprintf("https://www.youtube.com/youtubei/v1/next?key=%s", apiKey), body)
	if err != nil {
		return nil, "", err
	}
	return parseCommentsResponse(nd, maxResults)
}

func ctxOrDefault(ctx map[string]interface{}) map[string]interface{} {
	if ctx != nil {
		return ctx
	}
	return map[string]interface{}{"client": map[string]interface{}{"hl": "en", "gl": "US", "clientName": "WEB", "clientVersion": "2.20240801.00.00"}}
}

func fetchInnerTube(u string, body []byte) (map[string]interface{}, error) {
	req, _ := http.NewRequest("POST", u, strings.NewReader(string(body)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	var data map[string]interface{}
	if err := json.Unmarshal(b, &data); err != nil {
		return nil, err
	}
	return data, nil
}

func parseCommentsResponse(data map[string]interface{}, limit int) ([]VideoComment, string, error) {
	eps, _ := data["onResponseReceivedEndpoints"].([]interface{})
	var items []interface{}
	if len(eps) > 0 {
		if ep, ok := eps[0].(map[string]interface{}); ok {
			if rcc, ok := ep["reloadContinuationItemsCommand"].(map[string]interface{}); ok {
				items, _ = rcc["continuationItems"].([]interface{})
			} else if aci, ok := ep["appendContinuationItemsAction"].(map[string]interface{}); ok {
				items, _ = aci["continuationItems"].([]interface{})
			}
		}
	}
	if items == nil && len(eps) > 1 {
		if ep, ok := eps[1].(map[string]interface{}); ok {
			if rcc, ok := ep["reloadContinuationItemsCommand"].(map[string]interface{}); ok {
				items, _ = rcc["continuationItems"].([]interface{})
			}
		}
	}
	if items == nil {
		return nil, "", nil
	}

	comments := []VideoComment{}
	var nc string
	for _, item := range items {
		if len(comments) >= limit {
			break
		}
		im, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		if cir, ok := im["continuationItemRenderer"].(map[string]interface{}); ok {
			if ep, ok := cir["continuationEndpoint"].(map[string]interface{}); ok {
				if cc, ok := ep["continuationCommand"].(map[string]interface{}); ok {
					nc, _ = cc["token"].(string)
				}
			}
		}
		if ctr, ok := im["commentThreadRenderer"].(map[string]interface{}); ok {
			if cm, ok := ctr["comment"].(map[string]interface{}); ok {
				if cr, ok := cm["commentRenderer"].(map[string]interface{}); ok {
					if replies, ok := ctr["replies"].(map[string]interface{}); ok {
						cr["replies"] = replies
					}
					comments = append(comments, parseCommentRenderer(cr))
				}
			}
		}
	}
	return comments, nc, nil
}

// ─── Related Videos ─────────────────────────────────────

func GetRelatedVideos(videoID string, limit int) ([]RelatedVideo, error) {
	if limit <= 0 {
		limit = 15
	}
	if limit > 50 {
		limit = 50
	}

	html, err := fetchHTML(fmt.Sprintf("https://www.youtube.com/watch?v=%s", videoID))
	if err != nil {
		return nil, err
	}
	data := extractJSON(html, "var ytInitialData")
	if data == nil {
		return nil, nil
	}

	results := []RelatedVideo{}
	contents, _ := data["contents"].(map[string]interface{})
	tcr, _ := contents["twoColumnWatchNextResults"].(map[string]interface{})
	sr, _ := tcr["secondaryResults"].(map[string]interface{})
	sr2, _ := sr["secondaryResults"].(map[string]interface{})
	items, _ := sr2["results"].([]interface{})

	for _, item := range items {
		if len(results) >= limit {
			break
		}
		im, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		vr, ok := im["compactVideoRenderer"].(map[string]interface{})
		if !ok {
			vr, ok = im["compactRadioRenderer"].(map[string]interface{})
		}
		if !ok {
			continue
		}
		id, _ := vr["videoId"].(string)
		if id == "" {
			continue
		}
		title := extractRuns(getRuns(vr, "title")) + getSimpleText(vr, "title")
		author := extractRuns(getRuns(vr, "shortBylineText")) + getSimpleText(vr, "shortBylineText")
		durText := getSimpleText(vr, "lengthText") + extractRuns(getRuns(vr, "lengthText"))
		dur, durSec := parseDuration(durText)
		vcText := getSimpleText(vr, "viewCountText") + extractRuns(getRuns(vr, "viewCountText"))
		vc, vcRaw := parseViewCount(vcText)
		pub, _ := vr["publishedTimeText"].(map[string]interface{})
		pubTime := ""
		if pub != nil {
			pubTime, _ = pub["simpleText"].(string)
		}
		thumb := ""
		if tn, ok := vr["thumbnail"].(map[string]interface{}); ok {
			if tl, ok := tn["thumbnails"].([]interface{}); ok {
				thumb = bestThumbnail(tl)
			}
		}
		if thumb == "" {
			thumb = fmt.Sprintf("https://i.ytimg.com/vi/%s/hqdefault.jpg", id)
		}
		badge := ""
		if badges, ok := vr["badges"].([]interface{}); ok && len(badges) > 0 {
			if bm, ok := badges[0].(map[string]interface{}); ok {
				if mbr, ok := bm["metadataBadgeRenderer"].(map[string]interface{}); ok {
					badge, _ = mbr["style"].(string)
				}
			}
		}
		chURL := ""
		if sbt, ok := vr["shortBylineText"].(map[string]interface{}); ok {
			if runs, ok := sbt["runs"].([]interface{}); ok && len(runs) > 0 {
				if rm, ok := runs[0].(map[string]interface{}); ok {
					if ep, ok := rm["navigationEndpoint"].(map[string]interface{}); ok {
						if be, ok := ep["browseEndpoint"].(map[string]interface{}); ok {
							chURL, _ = be["canonicalBaseUrl"].(string)
						}
					}
				}
			}
		}
		results = append(results, RelatedVideo{
			ID: id, Title: title, Author: author, ChannelURL: chURL,
			Duration: dur, DurationSeconds: durSec,
			ViewCount: vc, ViewCountRaw: int(vcRaw), PublishedTime: pubTime,
			Thumbnail: thumb, IsLive: strings.Contains(strings.ToUpper(badge), "LIVE"),
		})
	}
	return results, nil
}

// ─── Live Stream + Stats ────────────────────────────────

func GetVideoStats(videoID string) (VideoStats, error) {
	html, err := fetchHTML(fmt.Sprintf("https://www.youtube.com/watch?v=%s", videoID))
	if err != nil {
		return VideoStats{}, err
	}
	data := extractJSON(html, "var ytInitialData")
	if data == nil {
		return VideoStats{}, nil
	}

	var stats VideoStats
	con, _ := data["contents"].(map[string]interface{})
	tcr, _ := con["twoColumnWatchNextResults"].(map[string]interface{})
	res, _ := tcr["results"].(map[string]interface{})
	rc, _ := res["results"].(map[string]interface{})
	conts, _ := rc["contents"].([]interface{})
	for _, c := range conts {
		cm, ok := c.(map[string]interface{})
		if !ok {
			continue
		}
		primary, ok := cm["videoPrimaryInfoRenderer"].(map[string]interface{})
		if !ok {
			continue
		}
		vcr, _ := primary["viewCount"].(map[string]interface{})
		vvcr, _ := vcr["videoViewCountRenderer"].(map[string]interface{})
		vc, _ := vvcr["shortViewCount"].(map[string]interface{})
		if vc == nil {
			vc, _ = vvcr["viewCount"].(map[string]interface{})
		}
		viewsText := ""
		if vc != nil {
			viewsText, _ = vc["simpleText"].(string)
		}
		_, stats.Views = parseViewCount(viewsText)

		likeText := ""
		if va, ok := primary["videoActions"].(map[string]interface{}); ok {
			if mr, ok := va["menuRenderer"].(map[string]interface{}); ok {
				if tlb, ok := mr["topLevelButtons"].([]interface{}); ok && len(tlb) > 0 {
					if bm, ok := tlb[0].(map[string]interface{}); ok {
						if sld, ok := bm["segmentedLikeDislikeButtonViewModel"].(map[string]interface{}); ok {
							if lb, ok := sld["likeButtonViewModel"].(map[string]interface{}); ok {
								if lb2, ok := lb["likeButtonViewModel"].(map[string]interface{}); ok {
									if tb, ok := lb2["toggleButtonViewModel"].(map[string]interface{}); ok {
										if tb2, ok := tb["toggleButtonViewModel"].(map[string]interface{}); ok {
											if db, ok := tb2["defaultButtonViewModel"].(map[string]interface{}); ok {
												if bv, ok := db["buttonViewModel"].(map[string]interface{}); ok {
													likeText, _ = bv["accessibilityText"].(string)
												}
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}
		_, stats.Likes = parseViewCount(regexp.MustCompile(`[^0-9.KMBkmb]`).ReplaceAllString(likeText, ""))
		break
	}

	stats.IsLive = strings.Contains(html, `"isLive":true`)
	if m := regexp.MustCompile(`"isLive":true,"viewCount":{"simpleText":"([^"]+)"`).FindStringSubmatch(html); m != nil {
		_, raw := parseViewCount(m[1])
		stats.ViewerCount = int(raw)
	}
	return stats, nil
}

func GetLiveStreamInfo(videoID string) (LiveStreamInfo, error) {
	stats, err := GetVideoStats(videoID)
	if err != nil {
		return LiveStreamInfo{}, err
	}
	html, err := fetchHTML(fmt.Sprintf("https://www.youtube.com/watch?v=%s", videoID))
	if err != nil {
		info := LiveStreamInfo{IsLive: stats.IsLive, ViewerCount: stats.ViewerCount, ViewerCountStr: fmt.Sprintf("%d", stats.ViewerCount)}
		return info, nil
	}
	data := extractJSON(html, "var ytInitialData")

	startTime := ""
	scheduledStart := ""
	if data != nil {
		con, _ := data["contents"].(map[string]interface{})
		tcr, _ := con["twoColumnWatchNextResults"].(map[string]interface{})
		res, _ := tcr["results"].(map[string]interface{})
		rc, _ := res["results"].(map[string]interface{})
		conts, _ := rc["contents"].([]interface{})
		for _, c := range conts {
			cm, ok := c.(map[string]interface{})
			if !ok {
				continue
			}
			primary, ok := cm["videoPrimaryInfoRenderer"].(map[string]interface{})
			if !ok {
				continue
			}
			if dt, ok := primary["dateText"].(map[string]interface{}); ok {
				startTime, _ = dt["simpleText"].(string)
			}
			if ued, ok := primary["upcomingEventData"].(map[string]interface{}); ok {
				scheduledStart, _ = ued["startTime"].(string)
			}
			break
		}
	}

	return LiveStreamInfo{
		IsLive:             stats.IsLive,
		IsUpcoming:         !stats.IsLive && stats.ViewerCount == 0,
		ViewerCount:        stats.ViewerCount,
		ViewerCountStr:     fmt.Sprintf("%d", stats.ViewerCount),
		StartTime:          startTime,
		ScheduledStartTime: scheduledStart,
		LikesCount:         int(stats.Likes),
	}, nil
}

// ─── Retry ─────────────────────────────────────────────

func WithRetry(fn func() error, maxRetries int, baseDelay, maxDelay time.Duration) error {
	var lastErr error
	for a := 0; a <= maxRetries; a++ {
		if err := fn(); err != nil {
			lastErr = err
			if a >= maxRetries {
				return lastErr
			}
			delay := time.Duration(math.Min(float64(baseDelay)*math.Pow(2, float64(a))+float64(rand.Int63n(500))*float64(time.Millisecond), float64(maxDelay)))
			time.Sleep(delay)
			continue
		}
		return nil
	}
	return lastErr
}

// ─── Client Factory ─────────────────────────────────────

var GlobalCache = NewLRUCache(500, 300_000)

type Client struct {
	cache *LRUCache
}

func NewClient() *Client {
	return &Client{cache: GlobalCache}
}

func (c *Client) Search(query string, limit int) ([]VideoResult, error) {
	return Search(query, "", "", limit)
}

func (c *Client) SearchTrending(limit int) ([]VideoResult, error) {
	return SearchTrending("", "", limit)
}

func (c *Client) SearchChannel(channelID string, limit int) ([]VideoResult, error) {
	return SearchChannel(channelID, "", "", limit)
}

func (c *Client) SearchPlaylist(playlistID string, limit int) ([]VideoResult, error) {
	return SearchPlaylist(playlistID, "", "", limit)
}

func (c *Client) GetVideo(videoID string) (*VideoResult, error) {
	return GetVideo(videoID), nil
}

func (c *Client) GetComments(videoID string, limit int) ([]VideoComment, string, error) {
	return GetComments(videoID, limit)
}

func (c *Client) GetRelatedVideos(videoID string, limit int) ([]RelatedVideo, error) {
	return GetRelatedVideos(videoID, limit)
}

func (c *Client) GetVideoStats(videoID string) (VideoStats, error) {
	return GetVideoStats(videoID)
}

func (c *Client) GetLiveStreamInfo(videoID string) (LiveStreamInfo, error) {
	return GetLiveStreamInfo(videoID)
}

func (c *Client) GetChannelMetadata(channelID string) (ChannelMetadata, error) {
	return GetChannelMetadata(channelID)
}

func (c *Client) SearchShorts(query string, limit int) ([]VideoResult, error) {
	return SearchShorts(query, limit)
}

func (c *Client) GetTranscript(videoID string, lang ...string) ([]TranscriptEntry, error) {
	return GetTranscript(videoID, lang...)
}

// ─── Channel Metadata ───────────────────────────────────

type SocialLink struct {
	Title string `json:"title"`
	URL   string `json:"url"`
	Icon  string `json:"icon"`
}

type ChannelMetadata struct {
	ID                string       `json:"id"`
	Name              string       `json:"name"`
	Handle            string       `json:"handle"`
	Description       string       `json:"description"`
	SubscriberCount   string       `json:"subscriberCount"`
	SubscriberCountRaw int64       `json:"subscriberCountRaw"`
	VideoCount        string       `json:"videoCount"`
	VideoCountRaw     int          `json:"videoCountRaw"`
	Avatar            string       `json:"avatar"`
	Banner            string       `json:"banner"`
	IsVerified        bool         `json:"isVerified"`
	SocialLinks       []SocialLink `json:"socialLinks"`
	URL               string       `json:"url"`
}

func GetChannelMetadata(channelID string) (ChannelMetadata, error) {
	empty := ChannelMetadata{
		ID:  channelID,
		URL: fmt.Sprintf("https://www.youtube.com/channel/%s", channelID),
	}

	html, err := fetchHTML(fmt.Sprintf("https://www.youtube.com/channel/%s/about", channelID))
	if err != nil {
		return empty, err
	}

	data := extractJSON(html, "var ytInitialData")
	if data == nil {
		return empty, fmt.Errorf("could not extract ytInitialData")
	}

	metadata, _ := data["metadata"].(map[string]interface{})
	renderer, _ := metadata["channelMetadataRenderer"].(map[string]interface{})
	if renderer == nil {
		return empty, fmt.Errorf("no channel metadata renderer")
	}

	contents, _ := data["contents"].(map[string]interface{})
	tcbr, _ := contents["twoColumnBrowseResultsRenderer"].(map[string]interface{})
	tabs, _ := tcbr["tabs"].([]interface{})

	var about map[string]interface{}
	for _, tab := range tabs {
		tabMap, ok := tab.(map[string]interface{})
		if !ok {
			continue
		}
		tr, _ := tabMap["tabRenderer"].(map[string]interface{})
		sel, _ := tr["selected"].(bool)
		if !sel {
			continue
		}
		ct, _ := tr["content"].(map[string]interface{})
		slr, _ := ct["sectionListRenderer"].(map[string]interface{})
		slrContents, _ := slr["contents"].([]interface{})
		if len(slrContents) > 0 {
			first, _ := slrContents[0].(map[string]interface{})
			isr, _ := first["itemSectionRenderer"].(map[string]interface{})
			isrContents, _ := isr["contents"].([]interface{})
			if len(isrContents) > 0 {
				about, _ = isrContents[0].(map[string]interface{})["channelAboutFullMetadataRenderer"].(map[string]interface{})
			}
		}
		break
	}

	headerC4, _ := data["header"].(map[string]interface{})
	c4, _ := headerC4["c4TabbedHeaderRenderer"].(map[string]interface{})

	subscriberText := ""
	if c4 != nil {
		if sc, ok := c4["subscriberCountText"].(map[string]interface{}); ok {
			subscriberText, _ = sc["simpleText"].(string)
		}
	}
	_, subsRaw := parseViewCount(subscriberText)

	videoText := ""
	vcRaw := 0
	if about != nil {
		if vct, ok := about["videoCountText"].(map[string]interface{}); ok {
			if runs, ok := vct["runs"].([]interface{}); ok && len(runs) > 0 {
				if rm, ok := runs[0].(map[string]interface{}); ok {
					videoText, _ = rm["text"].(string)
				}
			}
		}
		re := regexp.MustCompile(`([\d,]+)`)
		if m := re.FindStringSubmatch(videoText); m != nil {
			clean := strings.ReplaceAll(m[1], ",", "")
			vcRaw, _ = strconv.Atoi(clean)
		}
	}

	links := []SocialLink{}
	if about != nil {
		if pl, ok := about["primaryLinks"].([]interface{}); ok {
			for _, l := range pl {
				lm, ok := l.(map[string]interface{})
				if !ok {
					continue
				}
				title := ""
				if t, ok := lm["title"].(map[string]interface{}); ok {
					title, _ = t["simpleText"].(string)
					if title == "" {
						if runs, ok := t["runs"].([]interface{}); ok && len(runs) > 0 {
							if rm, ok := runs[0].(map[string]interface{}); ok {
								title, _ = rm["text"].(string)
							}
						}
					}
				}
				linkURL := ""
				if ep, ok := lm["navigationEndpoint"].(map[string]interface{}); ok {
					if ue, ok := ep["urlEndpoint"].(map[string]interface{}); ok {
						linkURL, _ = ue["url"].(string)
					}
				}
				icon := ""
				if ic, ok := lm["icon"].(map[string]interface{}); ok {
					if thumbs, ok := ic["thumbnails"].([]interface{}); ok && len(thumbs) > 0 {
						if tm, ok := thumbs[0].(map[string]interface{}); ok {
							icon, _ = tm["url"].(string)
						}
					}
				}
				links = append(links, SocialLink{Title: title, URL: linkURL, Icon: icon})
			}
		}
	}

	handle := ""
	if vu, ok := renderer["vanityChannelUrl"].(string); ok {
		handle = strings.ReplaceAll(strings.ReplaceAll(vu, "http://www.youtube.com/", ""), "https://www.youtube.com/", "")
	}

	name := ""
	if t, ok := renderer["title"].(string); ok {
		name = t
	}
	if name == "" && c4 != nil {
		name, _ = c4["title"].(string)
	}

	desc := ""
	if d, ok := renderer["description"].(string); ok {
		desc = d
	}
	if desc == "" && about != nil {
		if dd, ok := about["description"].(map[string]interface{}); ok {
			desc, _ = dd["simpleText"].(string)
			if desc == "" {
				if runs, ok := dd["runs"].([]interface{}); ok {
					desc = extractRuns(runs)
				}
			}
		}
	}

	avatar := ""
	if av, ok := renderer["avatar"].(map[string]interface{}); ok {
		if thumbs, ok := av["thumbnails"].([]interface{}); ok {
			avatar = bestThumbnail(thumbs)
		}
	}
	if avatar == "" && c4 != nil {
		if av, ok := c4["avatar"].(map[string]interface{}); ok {
			if thumbs, ok := av["thumbnails"].([]interface{}); ok {
				avatar = bestThumbnail(thumbs)
			}
		}
	}

	banner := ""
	if bn, ok := renderer["banner"].(map[string]interface{}); ok {
		if thumbs, ok := bn["thumbnails"].([]interface{}); ok {
			banner = bestThumbnail(thumbs)
		}
	}
	if banner == "" && c4 != nil {
		if bn, ok := c4["banner"].(map[string]interface{}); ok {
			if thumbs, ok := bn["thumbnails"].([]interface{}); ok {
				banner = bestThumbnail(thumbs)
			}
		}
	}

	isVerified := false
	if c4 != nil {
		if badges, ok := c4["badges"].([]interface{}); ok {
			for _, b := range badges {
				bm, ok := b.(map[string]interface{})
				if !ok {
					continue
				}
				mbr, _ := bm["metadataBadgeRenderer"].(map[string]interface{})
				if style, ok := mbr["style"].(string); ok {
					if strings.Contains(strings.ToUpper(style), "VERIFIED") {
						isVerified = true
					}
				}
			}
		}
	}

	return ChannelMetadata{
		ID:                 channelID,
		Name:               name,
		Handle:             handle,
		Description:        desc,
		SubscriberCount:    subscriberText,
		SubscriberCountRaw: subsRaw,
		VideoCount:         videoText,
		VideoCountRaw:      vcRaw,
		Avatar:             avatar,
		Banner:             banner,
		IsVerified:         isVerified,
		SocialLinks:        links,
		URL:                fmt.Sprintf("https://www.youtube.com/channel/%s", channelID),
	}, nil
}

// ─── Shorts ─────────────────────────────────────────────

func SearchShorts(query string, limit ...int) ([]VideoResult, error) {
	maxResults := 15
	if len(limit) > 0 && limit[0] > 0 {
		maxResults = limit[0]
	}
	if maxResults > 50 {
		maxResults = 50
	}

	u := fmt.Sprintf("https://www.youtube.com/results?search_query=%s&sp=EgIYAQ%%3D%%3D", url.QueryEscape(query))
	html, err := fetchHTML(u)
	if err != nil {
		return nil, err
	}

	data := extractJSON(html, "var ytInitialData")
	if data == nil {
		return nil, fmt.Errorf("could not extract ytInitialData")
	}

	var reelItems []interface{}
	contents, _ := data["contents"].(map[string]interface{})
	tcsr, _ := contents["twoColumnSearchResultsRenderer"].(map[string]interface{})
	pc, _ := tcsr["primaryContents"].(map[string]interface{})
	slr, _ := pc["sectionListRenderer"].(map[string]interface{})
	sections, _ := slr["contents"].([]interface{})

	for _, section := range sections {
		sm, ok := section.(map[string]interface{})
		if !ok {
			continue
		}
		isr, _ := sm["itemSectionRenderer"].(map[string]interface{})
		isrContents, _ := isr["contents"].([]interface{})
		if len(isrContents) > 0 {
			if rs, ok := isrContents[0].(map[string]interface{})["reelShelfRenderer"].(map[string]interface{}); ok {
				reelItems, _ = rs["items"].([]interface{})
			}
		}
	}

	var results []VideoResult
	if reelItems == nil {
		return results, nil
	}

	for _, item := range reelItems {
		if len(results) >= maxResults {
			break
		}
		im, ok := item.(map[string]interface{})
		if !ok {
			continue
		}

		vr, _ := im["reelItemRenderer"].(map[string]interface{})
		if vr == nil {
			vr, _ = im["shortsLockupViewModel"].(map[string]interface{})
		}
		if vr == nil {
			continue
		}
		vid, _ := vr["videoId"].(string)
		if vid == "" {
			continue
		}

		title := ""
		if hl, ok := vr["headline"].(map[string]interface{}); ok {
			title = extractRuns(getRuns(hl, "runs")) + getSimpleText(hl, "simpleText")
		}

		duration := 0
		if lt, ok := vr["lengthText"].(map[string]interface{}); ok {
			s, _ := lt["simpleText"].(string)
			duration, _ = strconv.Atoi(s)
		}

		fb := fallbackResult(vid)
		results = append(results, VideoResult{
			ID:              vid,
			Title:           title,
			Author:          fb.Author,
			Thumbnail:       fb.Thumbnail,
			Thumbnails:      fb.Thumbnails,
			FullURL:         fb.FullURL,
			EmbedURL:        fb.EmbedURL,
			Duration:        fmt.Sprintf("%ds", duration),
			DurationSeconds: duration,
			IsLive:          false,
			IsUpcoming:      false,
			IsVerified:      false,
		})
	}

	return results, nil
}

// ─── Transcript / Captions ──────────────────────────────

type TranscriptEntry struct {
	Text     string  `json:"text"`
	Start    float64 `json:"start"`
	Duration float64 `json:"duration"`
}

func GetTranscript(videoID string, lang ...string) ([]TranscriptEntry, error) {
	html, err := fetchHTML(fmt.Sprintf("https://www.youtube.com/watch?v=%s", videoID))
	if err != nil {
		return nil, err
	}

	tracksRe := regexp.MustCompile(`"captionTracks":\s*(\[[^\]]*\{[^}]*"baseUrl":"([^"]+)"[^}]*\}[^\]]*\])`)
	captionsMatch := tracksRe.FindStringSubmatch(html)
	if captionsMatch == nil {
		playerRe := regexp.MustCompile(`"captions":\{[^}]*"playerCaptionsTracklistRenderer":\{[^}]*"captionTracks":(\[[^\]]*\])`)
		if playerRe.FindStringSubmatch(html) == nil {
			return nil, fmt.Errorf("no caption tracks found")
		}
	}

	var tracksStr string
	if captionsMatch != nil {
		tracksStr = captionsMatch[1]
	} else {
		tracksJSONRe := regexp.MustCompile(`"captionTracks":(\[[^\]]*\{[^}]*\}[^\]]*\])`)
		m := tracksJSONRe.FindStringSubmatch(html)
		if m != nil {
			tracksStr = m[1]
		}
	}
	if tracksStr == "" {
		return nil, fmt.Errorf("no caption tracks found")
	}

	var tracks []map[string]interface{}
	if err := json.Unmarshal([]byte(tracksStr), &tracks); err != nil {
		return nil, err
	}

	var trackURL string
	userLang := ""
	if len(lang) > 0 && lang[0] != "" {
		userLang = lang[0]
	}
	if userLang != "" {
		for _, t := range tracks {
			lc, _ := t["languageCode"].(string)
			name := ""
			if nm, ok := t["name"].(map[string]interface{}); ok {
				name, _ = nm["simpleText"].(string)
			}
			if lc == userLang || strings.Contains(strings.ToLower(name), strings.ToLower(userLang)) {
				trackURL, _ = t["baseUrl"].(string)
				break
			}
		}
	}
	if trackURL == "" {
		for _, t := range tracks {
			lc, _ := t["languageCode"].(string)
			if lc == "en" {
				trackURL, _ = t["baseUrl"].(string)
				break
			}
		}
	}
	if trackURL == "" && len(tracks) > 0 {
		trackURL, _ = tracks[0]["baseUrl"].(string)
	}
	if trackURL == "" {
		return nil, fmt.Errorf("no suitable caption track")
	}

	xmlResp, err := fetchHTML(trackURL)
	if err != nil {
		return nil, err
	}

	entries := []TranscriptEntry{}
	textRe := regexp.MustCompile(`<text start="([\d.]+)" dur="([\d.]+)"[^>]*>(.*?)(?:</text>)?$`)
	lines := strings.Split(xmlResp, "\n")
	for _, line := range lines {
		m := textRe.FindStringSubmatch(strings.TrimSpace(line))
		if m == nil {
			continue
		}
		raw := regexp.MustCompile(`<[^>]+>`).ReplaceAllString(m[3], "")
		raw = strings.ReplaceAll(raw, "&amp;", "&")
		raw = strings.ReplaceAll(raw, "&lt;", "<")
		raw = strings.ReplaceAll(raw, "&gt;", ">")
		raw = strings.ReplaceAll(raw, "&quot;", "\"")
		raw = strings.ReplaceAll(raw, "&#39;", "'")
		raw = strings.TrimSpace(raw)
		if raw != "" {
			start, _ := strconv.ParseFloat(m[1], 64)
			dur, _ := strconv.ParseFloat(m[2], 64)
			entries = append(entries, TranscriptEntry{Text: raw, Start: start, Duration: dur})
		}
	}
	return entries, nil
}
