#pragma once

#include <nlohmann/json.hpp>

#include <string>
#include <vector>
#include <map>
#include <deque>
#include <set>
#include <stdexcept>
#include <cmath>
#include <cctype>
#include <cstdlib>
#include <functional>
#include <chrono>
#include <thread>
#include <algorithm>
#include <iomanip>
#include <sstream>

#include <curl/curl.h>

namespace ytapis {

struct Thumbnail {
    std::string url;
    int width = 0;
    int height = 0;
    NLOHMANN_DEFINE_TYPE_INTRUSIVE(Thumbnail, url, width, height)
};

struct VideoResult {
    std::string id;
    std::string title;
    std::string author;
    std::string channel_url;
    std::string thumbnail;
    std::string full_url;
    std::string embed_url;
    std::string duration;
    std::string view_count;
    std::string published_time;
    std::string description;
    std::string channel_avatar;
    int duration_seconds = 0;
    long long view_count_raw = 0;
    bool is_live = false;
    bool is_upcoming = false;
    bool is_verified = false;
    std::vector<Thumbnail> thumbnails;
    NLOHMANN_DEFINE_TYPE_INTRUSIVE(VideoResult,
        id, title, author, channel_url, thumbnail, thumbnails,
        full_url, embed_url, duration, duration_seconds,
        view_count, view_count_raw, published_time,
        description, channel_avatar, is_live, is_upcoming, is_verified)
};

struct SearchResponse {
    std::vector<VideoResult> results;
    std::string continuation;
    std::string api_key;
};

// ---------------------------------------------------------------------------
// internal helpers
// ---------------------------------------------------------------------------
namespace detail {

constexpr const char* SEARCH_URL       = "https://www.youtube.com/results?search_query=";
constexpr const char* WATCH_URL        = "https://www.youtube.com/watch?v=";
constexpr const char* INNERTUBE_URL    = "https://www.youtube.com/youtubei/v1/search";
constexpr const char* OEMBED_URL       = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch=";
constexpr const char* FALLBACK_API_KEY = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8";

static size_t write_callback(void* contents, size_t size, size_t nmemb, void* userp) {
    auto* str = static_cast<std::string*>(userp);
    const size_t total = size * nmemb;
    str->append(static_cast<const char*>(contents), total);
    return total;
}

inline std::string http_get(const std::string& url) {
    CURL* curl = curl_easy_init();
    if (!curl) throw std::runtime_error("curl_easy_init failed");

    std::string response;
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 15L);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);

    CURLcode res = curl_easy_perform(curl);
    curl_easy_cleanup(curl);

    if (res != CURLE_OK) throw std::runtime_error(std::string("HTTP GET failed: ") + curl_easy_strerror(res));
    return response;
}

inline std::string http_post(const std::string& url, const std::string& body) {
    CURL* curl = curl_easy_init();
    if (!curl) throw std::runtime_error("curl_easy_init failed");

    std::string response;
    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/json");

    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 15L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);

    CURLcode res = curl_easy_perform(curl);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if (res != CURLE_OK) throw std::runtime_error(std::string("HTTP POST failed: ") + curl_easy_strerror(res));
    return response;
}

inline std::string url_encode(CURL* curl, const std::string& str) {
    char* escaped = curl_easy_escape(curl, str.c_str(), static_cast<int>(str.size()));
    if (!escaped) return str;
    std::string result(escaped);
    curl_free(escaped);
    return result;
}

inline VideoResult fallback_result(const std::string& id) {
    VideoResult vr;
    vr.id = id;
    vr.title = "Video " + id;
    vr.author = "YouTube";
    vr.channel_url = "";
    vr.thumbnail = "https://i.ytimg.com/vi/" + id + "/hqdefault.jpg";
    vr.thumbnails = {{vr.thumbnail, 480, 360}};
    vr.full_url = "https://www.youtube.com/watch?v=" + id;
    vr.embed_url = "https://www.youtube.com/embed/" + id + "?rel=0";
    vr.duration = "";
    vr.duration_seconds = 0;
    vr.view_count = "";
    vr.view_count_raw = 0;
    vr.published_time = "";
    vr.description = "";
    vr.channel_avatar = "";
    vr.is_live = false;
    vr.is_upcoming = false;
    vr.is_verified = false;
    return vr;
}

inline std::pair<int, std::string> parse_duration(const std::string& text) {
    if (text.empty()) return {0, ""};
    std::vector<int> parts;
    std::istringstream ss(text);
    std::string token;
    while (std::getline(ss, token, ':')) {
        try {
            parts.push_back(std::stoi(token));
        } catch (...) {
            return {0, text};
        }
    }
    int seconds = 0;
    if (parts.size() == 3) seconds = parts[0] * 3600 + parts[1] * 60 + parts[2];
    else if (parts.size() == 2) seconds = parts[0] * 60 + parts[1];
    else if (parts.size() == 1) seconds = parts[0];
    return {seconds, text};
}

inline long long parse_view_count(const std::string& text) {
    if (text.empty()) return 0;
    std::string cleaned;
    for (char c : text) {
        if (std::isdigit(static_cast<unsigned char>(c)) || c == '.' || c == 'K' || c == 'k' ||
            c == 'M' || c == 'm' || c == 'B' || c == 'b') {
            cleaned.push_back(c);
        }
    }
    if (cleaned.empty()) return 0;
    long long multiplier = 1;
    for (char c : cleaned) {
        if (c == 'B' || c == 'b') { multiplier = 1000000000LL; break; }
        if (c == 'M' || c == 'm') { multiplier = 1000000LL; break; }
        if (c == 'K' || c == 'k') { multiplier = 1000LL; break; }
    }
    std::string num_str;
    for (char c : cleaned) {
        if (std::isdigit(static_cast<unsigned char>(c)) || c == '.') num_str.push_back(c);
    }
    if (num_str.empty()) return 0;
    double num = std::stod(num_str);
    return static_cast<long long>(std::round(num * multiplier));
}

inline int thumbnail_quality_score(const std::string& url) {
    if (url.empty()) return 0;
    if (url.find("maxresdefault") != std::string::npos) return 1280;
    if (url.find("sddefault") != std::string::npos) return 640;
    if (url.find("hqdefault") != std::string::npos) return 480;
    if (url.find("mqdefault") != std::string::npos) return 320;
    if (url.find("default") != std::string::npos) return 120;
    return 0;
}

inline std::string extract_best_thumbnail(const nlohmann::json& thumbnails) {
    if (!thumbnails.is_array() || thumbnails.empty()) return "";
    const nlohmann::json* best = &thumbnails[0];
    int best_score = thumbnail_quality_score(best->value("url", ""));
    for (const auto& t : thumbnails) {
        int bw = t.value("width", 0);
        int score = bw > 0 ? bw : thumbnail_quality_score(t.value("url", ""));
        if (score > best_score) { best = &t; best_score = score; }
    }
    return best->value("url", "");
}

inline std::string extract_runs(const nlohmann::json& runs) {
    if (!runs.is_array() || runs.empty()) return "";
    std::string result;
    for (const auto& r : runs) {
        if (r.contains("text")) result += r["text"].get<std::string>();
    }
    return result;
}

// Brace-counting JSON extractor - finds a prefix string, locates the first
// '{' after it, then walks characters counting brace depth while skipping
// strings and escape sequences. Returns the substring (inclusive of the
// outer braces) when depth returns to zero.
inline std::string extract_json(const std::string& html, const std::string& prefix) {
    auto idx = html.find(prefix);
    if (idx == std::string::npos) return "";

    auto start = html.find('{', idx);
    if (start == std::string::npos) return "";

    int depth = 0;
    bool in_string = false;
    bool escaped = false;

    for (size_t i = start; i < html.size(); ++i) {
        char ch = html[i];
        if (escaped) {
            escaped = false;
            continue;
        }
        if (ch == '\\') {
            escaped = true;
            continue;
        }
        if (ch == '"') {
            in_string = !in_string;
            continue;
        }
        if (in_string) continue;
        if (ch == '{') ++depth;
        if (ch == '}') {
            --depth;
            if (depth == 0) return html.substr(start, i - start + 1);
        }
    }
    return "";
}

inline std::string extract_api_key(const std::string& html) {
    std::string prefix = "\"INNERTUBE_API_KEY\":\"";
    auto idx = html.find(prefix);
    if (idx == std::string::npos) return "";
    idx += prefix.size();
    auto end = html.find('"', idx);
    if (end == std::string::npos) return "";
    return html.substr(idx, end - idx);
}

inline std::string extract_context_json(const std::string& html) {
    std::string prefix = "\"INNERTUBE_CONTEXT\"";
    return extract_json(html, prefix);
}

inline VideoResult parse_video_renderer(const nlohmann::json& vr) {
    std::string id = vr.value("videoId", "");
    if (id.empty()) throw std::runtime_error("missing videoId");

    auto fallback = fallback_result(id);

    VideoResult result;
    result.id = id;

    std::string title;
    if (vr.contains("title") && vr["title"].contains("runs"))
        title = extract_runs(vr["title"]["runs"]);
    result.title = title.empty() ? fallback.title : title;

    std::string author;
    if (vr.contains("ownerText") && vr["ownerText"].contains("runs"))
        author = extract_runs(vr["ownerText"]["runs"]);
    result.author = author.empty() ? fallback.author : author;

    if (vr.contains("ownerText") && vr["ownerText"].contains("runs") &&
        vr["ownerText"]["runs"].is_array() && !vr["ownerText"]["runs"].empty()) {
        const auto& first_run = vr["ownerText"]["runs"][0];
        if (first_run.contains("navigationEndpoint") &&
            first_run["navigationEndpoint"].contains("browseEndpoint") &&
            first_run["navigationEndpoint"]["browseEndpoint"].contains("canonicalBaseUrl")) {
            result.channel_url = first_run["navigationEndpoint"]["browseEndpoint"]["canonicalBaseUrl"].get<std::string>();
        }
    }

    if (vr.contains("thumbnail") && vr["thumbnail"].contains("thumbnails")) {
        const auto& js_thumbs = vr["thumbnail"]["thumbnails"];
        for (const auto& t : js_thumbs) {
            Thumbnail th;
            th.url = t.value("url", "");
            th.width = t.value("width", 0);
            th.height = t.value("height", 0);
            result.thumbnails.push_back(th);
        }
    }
    result.thumbnail = extract_best_thumbnail(vr["thumbnail"]["thumbnails"]);
    if (result.thumbnail.empty()) result.thumbnail = fallback.thumbnail;
    if (result.thumbnails.empty()) result.thumbnails = fallback.thumbnails;

    std::string dur_text;
    if (vr.contains("lengthText")) {
        const auto& lt = vr["lengthText"];
        if (lt.contains("simpleText")) dur_text = lt["simpleText"].get<std::string>();
        else if (lt.contains("runs")) dur_text = extract_runs(lt["runs"]);
    }
    if (!dur_text.empty()) {
        auto [secs, dur] = parse_duration(dur_text);
        result.duration_seconds = secs;
        result.duration = dur;
    }

    std::string vc_text;
    if (vr.contains("viewCountText")) {
        const auto& vct = vr["viewCountText"];
        if (vct.contains("simpleText")) vc_text = vct["simpleText"].get<std::string>();
        else if (vct.contains("runs")) vc_text = extract_runs(vct["runs"]);
    }
    if (!vc_text.empty()) {
        result.view_count = vc_text;
        result.view_count_raw = parse_view_count(vc_text);
    }

    if (vr.contains("publishedTimeText") && vr["publishedTimeText"].contains("simpleText"))
        result.published_time = vr["publishedTimeText"]["simpleText"].get<std::string>();

    const nlohmann::json* desc_runs = nullptr;
    if (vr.contains("detailedMetadataSnippets") && vr["detailedMetadataSnippets"].is_array() &&
        !vr["detailedMetadataSnippets"].empty() &&
        vr["detailedMetadataSnippets"][0].contains("snippetText") &&
        vr["detailedMetadataSnippets"][0]["snippetText"].contains("runs")) {
        desc_runs = &vr["detailedMetadataSnippets"][0]["snippetText"]["runs"];
    } else if (vr.contains("descriptionSnippet") && vr["descriptionSnippet"].contains("runs")) {
        desc_runs = &vr["descriptionSnippet"]["runs"];
    }
    if (desc_runs) result.description = extract_runs(*desc_runs);

    if (vr.contains("channelThumbnailSupportedRenderers") &&
        vr["channelThumbnailSupportedRenderers"].contains("channelThumbnailWithLinkRenderer") &&
        vr["channelThumbnailSupportedRenderers"]["channelThumbnailWithLinkRenderer"].contains("thumbnail") &&
        vr["channelThumbnailSupportedRenderers"]["channelThumbnailWithLinkRenderer"]["thumbnail"].contains("thumbnails")) {
        result.channel_avatar = extract_best_thumbnail(
            vr["channelThumbnailSupportedRenderers"]["channelThumbnailWithLinkRenderer"]["thumbnail"]["thumbnails"]);
    }

    result.full_url = "https://www.youtube.com/watch?v=" + id;
    result.embed_url = "https://www.youtube.com/embed/" + id + "?rel=0";

    if (vr.contains("badges") && vr["badges"].is_array()) {
        for (const auto& badge : vr["badges"]) {
            std::string style;
            if (badge.contains("metadataBadgeRenderer")) {
                if (badge["metadataBadgeRenderer"].contains("style"))
                    style = badge["metadataBadgeRenderer"]["style"].get<std::string>();
                else if (badge["metadataBadgeRenderer"].contains("label"))
                    style = badge["metadataBadgeRenderer"]["label"].get<std::string>();

                if (style.find("LIVE") != std::string::npos) result.is_live = true;
                if (style.find("UPCOMING") != std::string::npos) result.is_upcoming = true;
                if (style.find("VERIFIED") != std::string::npos) result.is_verified = true;
            }
        }
    }

    return result;
}

inline std::pair<std::vector<VideoResult>, std::string> parse_search_results(
    const nlohmann::json& data, int limit) {
    std::vector<VideoResult> results;
    std::string continuation;

    if (!data.contains("contents") || !data["contents"].contains("twoColumnSearchResultsRenderer"))
        return {results, continuation};

    const auto& renderer = data["contents"]["twoColumnSearchResultsRenderer"];
    if (!renderer.contains("primaryContents") ||
        !renderer["primaryContents"].contains("sectionListRenderer") ||
        !renderer["primaryContents"]["sectionListRenderer"].contains("contents"))
        return {results, continuation};

    const auto& contents = renderer["primaryContents"]["sectionListRenderer"]["contents"];

    for (const auto& section : contents) {
        if (static_cast<int>(results.size()) >= limit) break;

        if (section.contains("itemSectionRenderer") &&
            section["itemSectionRenderer"].contains("contents")) {
            for (const auto& item : section["itemSectionRenderer"]["contents"]) {
                if (static_cast<int>(results.size()) >= limit) break;
                if (item.contains("videoRenderer")) {
                    try {
                        auto vr = parse_video_renderer(item["videoRenderer"]);
                        results.push_back(std::move(vr));
                    } catch (...) {}
                }
            }
        }

        if (section.contains("continuationItemRenderer") &&
            section["continuationItemRenderer"].contains("continuationEndpoint") &&
            section["continuationItemRenderer"]["continuationEndpoint"].contains("continuationCommand") &&
            section["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"].contains("token")) {
            continuation = section["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"]
                               .get<std::string>();
        }
    }

    return {results, continuation};
}

inline std::pair<std::vector<VideoResult>, std::string> parse_continuation_results(
    const nlohmann::json& data, int limit, const std::string& path = "search") {
    std::vector<VideoResult> results;
    std::string continuation;

    const nlohmann::json* items = nullptr;
    if (path == "channel") {
        if (data.contains("onResponseReceivedActions") &&
            data["onResponseReceivedActions"].is_array() && !data["onResponseReceivedActions"].empty() &&
            data["onResponseReceivedActions"][0].contains("appendContinuationItemsAction") &&
            data["onResponseReceivedActions"][0]["appendContinuationItemsAction"].contains("continuationItems")) {
            items = &data["onResponseReceivedActions"][0]["appendContinuationItemsAction"]["continuationItems"];
        }
        if (!items && data.contains("onResponseReceivedEndpoints") &&
            data["onResponseReceivedEndpoints"].is_array() && !data["onResponseReceivedEndpoints"].empty() &&
            data["onResponseReceivedEndpoints"][0].contains("appendContinuationItemsAction") &&
            data["onResponseReceivedEndpoints"][0]["appendContinuationItemsAction"].contains("continuationItems")) {
            items = &data["onResponseReceivedEndpoints"][0]["appendContinuationItemsAction"]["continuationItems"];
        }
    } else if (path == "playlist") {
        if (data.contains("onResponseReceivedActions") &&
            data["onResponseReceivedActions"].is_array() && !data["onResponseReceivedActions"].empty() &&
            data["onResponseReceivedActions"][0].contains("appendContinuationItemsAction") &&
            data["onResponseReceivedActions"][0]["appendContinuationItemsAction"].contains("continuationItems")) {
            items = &data["onResponseReceivedActions"][0]["appendContinuationItemsAction"]["continuationItems"];
        }
    } else {
        if (data.contains("onResponseReceivedEndpoints") &&
            data["onResponseReceivedEndpoints"].is_array() && !data["onResponseReceivedEndpoints"].empty() &&
            data["onResponseReceivedEndpoints"][0].contains("appendContinuationItemsAction") &&
            data["onResponseReceivedEndpoints"][0]["appendContinuationItemsAction"].contains("continuationItems")) {
            items = &data["onResponseReceivedEndpoints"][0]["appendContinuationItemsAction"]["continuationItems"];
        }
    }

    if (!items || !items->is_array()) return {results, continuation};

    for (const auto& item : *items) {
        if (static_cast<int>(results.size()) >= limit) break;

        if (item.contains("continuationItemRenderer") &&
            item["continuationItemRenderer"].contains("continuationEndpoint") &&
            item["continuationItemRenderer"]["continuationEndpoint"].contains("continuationCommand") &&
            item["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"].contains("token")) {
            continuation = item["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"].get<std::string>();
        }

        if (path == "playlist" && item.contains("playlistVideoRenderer")) {
            const auto& pvr = item["playlistVideoRenderer"];
            std::string vid = pvr.value("videoId", "");
            if (!vid.empty()) {
                VideoResult vr = fallback_result(vid);
                std::string title;
                if (pvr.contains("title") && pvr["title"].contains("runs"))
                    title = extract_runs(pvr["title"]["runs"]);
                vr.title = title.empty() ? vr.title : title;
                std::string author;
                if (pvr.contains("shortBylineText") && pvr["shortBylineText"].contains("runs"))
                    author = extract_runs(pvr["shortBylineText"]["runs"]);
                vr.author = author.empty() ? vr.author : author;
                std::string dur_text;
                if (pvr.contains("lengthText")) {
                    const auto& lt = pvr["lengthText"];
                    if (lt.contains("simpleText")) dur_text = lt["simpleText"].get<std::string>();
                    else if (lt.contains("runs")) dur_text = extract_runs(lt["runs"]);
                }
                if (!dur_text.empty()) {
                    auto [secs, dur] = parse_duration(dur_text);
                    vr.duration_seconds = secs;
                    vr.duration = dur;
                }
                results.push_back(std::move(vr));
            }
            continue;
        }

        const nlohmann::json* vr = nullptr;
        if (item.contains("videoRenderer")) {
            vr = &item["videoRenderer"];
        } else if (item.contains("richItemRenderer") &&
                   item["richItemRenderer"].contains("content") &&
                   item["richItemRenderer"]["content"].contains("videoRenderer")) {
            vr = &item["richItemRenderer"]["content"]["videoRenderer"];
        }
        if (vr) {
            try {
                auto parsed = parse_video_renderer(*vr);
                results.push_back(std::move(parsed));
            } catch (...) {}
        }
    }

    return {results, continuation};
}

inline void enrich_with_oembed(VideoResult& vr) {
    try {
        std::string url = std::string(OEMBED_URL) + vr.id + "&format=json";
        std::string resp = http_get(url);
        auto data = nlohmann::json::parse(resp);
        if (data.contains("title")) vr.title = data["title"].get<std::string>();
        if (data.contains("author_name")) vr.author = data["author_name"].get<std::string>();
        if (data.contains("thumbnail_url")) vr.thumbnail = data["thumbnail_url"].get<std::string>();
    } catch (...) {}
}

inline std::string default_context_json() {
    nlohmann::json ctx;
    ctx["client"]["hl"] = "en";
    ctx["client"]["gl"] = "US";
    ctx["client"]["clientName"] = "WEB";
    ctx["client"]["clientVersion"] = "2.20240801.00.00";
    return ctx.dump();
}

// ─── Trending / Channel / Playlist parsers ────────────────────────────────

inline std::pair<std::vector<VideoResult>, std::string> parse_trending_results(
    const nlohmann::json& data, int limit) {
    std::vector<VideoResult> results;
    std::string continuation;

    if (!data.contains("contents") || !data["contents"].contains("twoColumnBrowseResultsRenderer"))
        return {results, continuation};

    const auto& renderer = data["contents"]["twoColumnBrowseResultsRenderer"];
    if (!renderer.contains("tabs") || !renderer["tabs"].is_array())
        return {results, continuation};

    for (const auto& tab : renderer["tabs"]) {
        if (!tab.contains("tabRenderer") || !tab["tabRenderer"].contains("content"))
            continue;
        const auto& content = tab["tabRenderer"]["content"];
        if (!content.contains("sectionListRenderer") || !content["sectionListRenderer"].contains("contents"))
            continue;

        const auto& contents = content["sectionListRenderer"]["contents"];

        for (const auto& section : contents) {
            if (static_cast<int>(results.size()) >= limit) break;

            if (section.contains("itemSectionRenderer") && section["itemSectionRenderer"].contains("contents")) {
                for (const auto& item : section["itemSectionRenderer"]["contents"]) {
                    if (static_cast<int>(results.size()) >= limit) break;
                    if (item.contains("videoRenderer")) {
                        try {
                            auto vr = parse_video_renderer(item["videoRenderer"]);
                            results.push_back(std::move(vr));
                        } catch (...) {}
                    }
                }
            }

            if (section.contains("shelfRenderer") && section["shelfRenderer"].contains("content")) {
                const auto& shelf_content = section["shelfRenderer"]["content"];
                const nlohmann::json* shelf_items = nullptr;
                if (shelf_content.contains("expandedShelfContentsRenderer") &&
                    shelf_content["expandedShelfContentsRenderer"].contains("items")) {
                    shelf_items = &shelf_content["expandedShelfContentsRenderer"]["items"];
                } else if (shelf_content.contains("horizontalListRenderer") &&
                           shelf_content["horizontalListRenderer"].contains("items")) {
                    shelf_items = &shelf_content["horizontalListRenderer"]["items"];
                }
                if (shelf_items && shelf_items->is_array()) {
                    for (const auto& item : *shelf_items) {
                        if (static_cast<int>(results.size()) >= limit) break;
                        if (item.contains("videoRenderer")) {
                            try {
                                auto vr = parse_video_renderer(item["videoRenderer"]);
                                results.push_back(std::move(vr));
                            } catch (...) {}
                        }
                    }
                }
            }

            if (section.contains("continuationItemRenderer") &&
                section["continuationItemRenderer"].contains("continuationEndpoint") &&
                section["continuationItemRenderer"]["continuationEndpoint"].contains("continuationCommand") &&
                section["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"].contains("token")) {
                continuation = section["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"].get<std::string>();
            }
        }

        if (!results.empty()) break;
    }

    return {results, continuation};
}

inline std::pair<std::vector<VideoResult>, std::string> parse_channel_results(
    const nlohmann::json& data, int limit) {
    std::vector<VideoResult> results;
    std::string continuation;

    if (!data.contains("contents") || !data["contents"].contains("twoColumnBrowseResultsRenderer"))
        return {results, continuation};

    const auto& renderer = data["contents"]["twoColumnBrowseResultsRenderer"];
    if (!renderer.contains("tabs") || !renderer["tabs"].is_array())
        return {results, continuation};

    for (const auto& tab : renderer["tabs"]) {
        if (!tab.contains("tabRenderer") || !tab["tabRenderer"].contains("content"))
            continue;

        const auto& content = tab["tabRenderer"]["content"];
        const nlohmann::json* items = nullptr;

        if (content.contains("richGridRenderer") && content["richGridRenderer"].contains("contents")) {
            items = &content["richGridRenderer"]["contents"];
        } else if (content.contains("sectionListRenderer") && content["sectionListRenderer"].contains("contents")) {
            items = &content["sectionListRenderer"]["contents"];
        }

        if (!items || !items->is_array()) continue;

        for (const auto& item : *items) {
            if (static_cast<int>(results.size()) >= limit) break;

            if (item.contains("continuationItemRenderer") &&
                item["continuationItemRenderer"].contains("continuationEndpoint") &&
                item["continuationItemRenderer"]["continuationEndpoint"].contains("continuationCommand") &&
                item["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"].contains("token")) {
                continuation = item["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"].get<std::string>();
            }

            if (item.contains("richItemRenderer") &&
                item["richItemRenderer"].contains("content") &&
                item["richItemRenderer"]["content"].contains("videoRenderer")) {
                try {
                    auto vr = parse_video_renderer(item["richItemRenderer"]["content"]["videoRenderer"]);
                    results.push_back(std::move(vr));
                } catch (...) {}
            }

            if (item.contains("videoRenderer")) {
                try {
                    auto vr = parse_video_renderer(item["videoRenderer"]);
                    results.push_back(std::move(vr));
                } catch (...) {}
            }
        }

        if (!results.empty()) break;
    }

    return {results, continuation};
}

inline std::pair<std::vector<VideoResult>, std::string> parse_playlist_results(
    const nlohmann::json& data, int limit) {
    std::vector<VideoResult> results;
    std::string continuation;

    const nlohmann::json* contents = nullptr;

    if (data.contains("contents") &&
        data["contents"].contains("twoColumnBrowseResultsRenderer") &&
        data["contents"]["twoColumnBrowseResultsRenderer"].contains("tabs") &&
        data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"].is_array() &&
        !data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"].empty() &&
        data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][0].contains("tabRenderer") &&
        data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][0]["tabRenderer"].contains("content") &&
        data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][0]["tabRenderer"]["content"].contains("sectionListRenderer") &&
        data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][0]["tabRenderer"]["content"]["sectionListRenderer"].contains("contents") &&
        !data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][0]["tabRenderer"]["content"]["sectionListRenderer"]["contents"].empty() &&
        data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][0]["tabRenderer"]["content"]["sectionListRenderer"]["contents"][0].contains("itemSectionRenderer") &&
        data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][0]["tabRenderer"]["content"]["sectionListRenderer"]["contents"][0]["itemSectionRenderer"].contains("contents") &&
        !data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][0]["tabRenderer"]["content"]["sectionListRenderer"]["contents"][0]["itemSectionRenderer"]["contents"].empty() &&
        data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][0]["tabRenderer"]["content"]["sectionListRenderer"]["contents"][0]["itemSectionRenderer"]["contents"][0].contains("playlistVideoListRenderer") &&
        data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][0]["tabRenderer"]["content"]["sectionListRenderer"]["contents"][0]["itemSectionRenderer"]["contents"][0]["playlistVideoListRenderer"].contains("contents")) {
        contents = &data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][0]["tabRenderer"]["content"]["sectionListRenderer"]["contents"][0]["itemSectionRenderer"]["contents"][0]["playlistVideoListRenderer"]["contents"];
    }

    if (!contents) {
        if (data.contains("contents") &&
            data["contents"].contains("twoColumnWatchNextResults") &&
            data["contents"]["twoColumnWatchNextResults"].contains("playlist") &&
            data["contents"]["twoColumnWatchNextResults"]["playlist"].contains("playlist") &&
            data["contents"]["twoColumnWatchNextResults"]["playlist"]["playlist"].contains("contents")) {
            contents = &data["contents"]["twoColumnWatchNextResults"]["playlist"]["playlist"]["contents"];
        }
    }

    if (!contents || !contents->is_array()) return {results, continuation};

    for (const auto& item : *contents) {
        if (static_cast<int>(results.size()) >= limit) break;

        if (item.contains("continuationItemRenderer") &&
            item["continuationItemRenderer"].contains("continuationEndpoint") &&
            item["continuationItemRenderer"]["continuationEndpoint"].contains("continuationCommand") &&
            item["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"].contains("token")) {
            continuation = item["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"].get<std::string>();
        }

        if (!item.contains("playlistVideoRenderer")) continue;

        const auto& pvr = item["playlistVideoRenderer"];
        std::string vid = pvr.value("videoId", "");
        if (vid.empty()) continue;

        auto vr = fallback_result(vid);

        std::string title;
        if (pvr.contains("title") && pvr["title"].contains("runs"))
            title = extract_runs(pvr["title"]["runs"]);
        vr.title = title.empty() ? vr.title : title;

        std::string author;
        if (pvr.contains("shortBylineText") && pvr["shortBylineText"].contains("runs"))
            author = extract_runs(pvr["shortBylineText"]["runs"]);
        vr.author = author.empty() ? vr.author : author;

        std::string dur_text;
        if (pvr.contains("lengthText")) {
            const auto& lt = pvr["lengthText"];
            if (lt.contains("simpleText")) dur_text = lt["simpleText"].get<std::string>();
            else if (lt.contains("runs")) dur_text = extract_runs(lt["runs"]);
        }
        if (!dur_text.empty()) {
            auto [secs, dur] = parse_duration(dur_text);
            vr.duration_seconds = secs;
            vr.duration = dur;
        }

        results.push_back(std::move(vr));
    }

    return {results, continuation};
}

} // namespace detail

// ---------------------------------------------------------------------------
// public API
// ---------------------------------------------------------------------------

inline SearchResponse search(const std::string& query, int limit = 15) {
    limit = std::max(1, std::min(limit, 50));

    CURL* curl = curl_easy_init();
    if (!curl) throw std::runtime_error("curl_easy_init failed");

    std::string url = std::string(detail::SEARCH_URL) + detail::url_encode(curl, query);
    curl_easy_cleanup(curl);

    std::string html = detail::http_get(url);

    std::string json_str = detail::extract_json(html, "var ytInitialData");
    if (json_str.empty()) return {{}};

    auto data = nlohmann::json::parse(json_str);

    std::string api_key = detail::extract_api_key(html);

    auto [results, continuation] = detail::parse_search_results(data, limit);

    for (auto& r : results) {
        auto fb = detail::fallback_result(r.id);
        if (r.title.empty() || r.title == fb.title || r.author == fb.author) {
            detail::enrich_with_oembed(r);
        }
    }

    SearchResponse resp;
    resp.results = std::move(results);
    resp.continuation = std::move(continuation);
    resp.api_key = std::move(api_key);
    return resp;
}

inline VideoResult get_video(const std::string& id) {
    auto fallback = detail::fallback_result(id);

    try {
        std::string url = std::string(detail::WATCH_URL) + id;
        std::string html = detail::http_get(url);

        std::string json_str = detail::extract_json(html, "var ytInitialPlayerResponse");
        if (json_str.empty()) json_str = detail::extract_json(html, "var ytInitialData");

        if (!json_str.empty()) {
            auto data = nlohmann::json::parse(json_str);

            if (data.contains("videoDetails")) {
                const auto& vd = data["videoDetails"];

                fallback.title = vd.value("title", fallback.title);
                fallback.author = vd.value("author", fallback.author);

                if (vd.contains("channelId")) {
                    fallback.channel_url = "https://www.youtube.com/" + vd["channelId"].get<std::string>();
                }

                int dur_sec = 0;
                if (vd.contains("lengthSeconds")) {
                    std::string len_str = vd["lengthSeconds"].get<std::string>();
                    dur_sec = std::stoi(len_str);
                }
                fallback.duration_seconds = dur_sec;
                if (dur_sec > 0) {
                    int hours = dur_sec / 3600;
                    int mins = (dur_sec % 3600) / 60;
                    int secs = dur_sec % 60;
                    if (hours > 0) {
                        std::ostringstream oss;
                        oss << hours << ":" << std::setw(2) << std::setfill('0') << mins
                            << ":" << std::setw(2) << std::setfill('0') << secs;
                        fallback.duration = oss.str();
                    } else {
                        std::ostringstream oss;
                        oss << mins << ":" << std::setw(2) << std::setfill('0') << secs;
                        fallback.duration = oss.str();
                    }
                }

                if (vd.contains("viewCount")) {
                    long long raw = 0;
                    try { raw = std::stoll(vd["viewCount"].get<std::string>()); } catch (...) {}
                    fallback.view_count_raw = raw;
                    fallback.view_count = vd["viewCount"].get<std::string>() + " views";
                }

                fallback.description = vd.value("shortDescription", "");

                if (vd.contains("thumbnail") && vd["thumbnail"].contains("thumbnails")) {
                    fallback.thumbnails.clear();
                    for (const auto& t : vd["thumbnail"]["thumbnails"]) {
                        Thumbnail th;
                        th.url = t.value("url", "");
                        th.width = t.value("width", 0);
                        th.height = t.value("height", 0);
                        fallback.thumbnails.push_back(th);
                    }
                    fallback.thumbnail = detail::extract_best_thumbnail(vd["thumbnail"]["thumbnails"]);
                }

                if (vd.contains("authorThumbnails") && vd["authorThumbnails"].is_array() &&
                    !vd["authorThumbnails"].empty()) {
                    fallback.channel_avatar = vd["authorThumbnails"][0].value("url", "");
                }

                return fallback;
            }
        }

        detail::enrich_with_oembed(fallback);
    } catch (...) {}

    return fallback;
}

inline SearchResponse search_continue(const std::string& continuation, int limit,
                                       const std::string& api_key,
                                       const std::string& context_json,
                                       const std::string& path = "search") {
    limit = std::max(1, std::min(limit, 50));

    std::string key = api_key.empty() ? detail::FALLBACK_API_KEY : api_key;

    std::string ctx_str = context_json;
    if (ctx_str.empty()) ctx_str = detail::default_context_json();

    auto context = nlohmann::json::parse(ctx_str);

    nlohmann::json body;
    body["context"] = context;
    body["continuation"] = continuation;

    std::string url = std::string(detail::INNERTUBE_URL) + "?key=" + key;
    std::string resp = detail::http_post(url, body.dump());

    auto data = nlohmann::json::parse(resp);
    auto [results, next_continuation] = detail::parse_continuation_results(data, limit, path);

    for (auto& r : results) {
        auto fb = detail::fallback_result(r.id);
        if (r.title.empty() || r.title == fb.title || r.author == fb.author) {
            detail::enrich_with_oembed(r);
        }
    }

    SearchResponse sr;
    sr.results = std::move(results);
    sr.continuation = std::move(next_continuation);
    sr.api_key = key;
    return sr;
}

inline SearchResponse search_continue(const std::string& continuation, int limit = 15,
                                       const std::string& api_key = "",
                                       const std::string& context_json = "") {
    return search_continue(continuation, limit, api_key, context_json, "search");
}

inline std::string default_continuation_context() {
    return detail::default_context_json();
}

inline std::string default_api_key() {
    return detail::FALLBACK_API_KEY;
}

// ─── Trending / Channel / Playlist public API ─────────────────────────────

inline SearchResponse search_trending(int limit = 15) {
    limit = std::max(1, std::min(limit, 50));

    std::string html = detail::http_get("https://www.youtube.com/feed/trending");
    std::string json_str = detail::extract_json(html, "var ytInitialData");
    if (json_str.empty()) return {{}};

    auto data = nlohmann::json::parse(json_str);
    std::string api_key = detail::extract_api_key(html);

    auto [results, continuation] = detail::parse_trending_results(data, limit);

    SearchResponse resp;
    resp.results = std::move(results);
    resp.continuation = std::move(continuation);
    resp.api_key = std::move(api_key);
    return resp;
}

inline SearchResponse search_channel(const std::string& channel_id, int limit = 15) {
    limit = std::max(1, std::min(limit, 50));

    std::string url = std::string("https://www.youtube.com/channel/") + channel_id + "/videos";
    std::string html = detail::http_get(url);
    std::string json_str = detail::extract_json(html, "var ytInitialData");
    if (json_str.empty()) return {{}};

    auto data = nlohmann::json::parse(json_str);
    std::string api_key = detail::extract_api_key(html);

    auto [results, continuation] = detail::parse_channel_results(data, limit);

    for (auto& r : results) {
        auto fb = detail::fallback_result(r.id);
        if (r.title.empty() || r.title == fb.title || r.author == fb.author) {
            detail::enrich_with_oembed(r);
        }
    }

    SearchResponse resp;
    resp.results = std::move(results);
    resp.continuation = std::move(continuation);
    resp.api_key = std::move(api_key);
    return resp;
}

inline SearchResponse search_playlist(const std::string& playlist_id, int limit = 15) {
    limit = std::max(1, std::min(limit, 50));

    std::string url = std::string("https://www.youtube.com/playlist?list=") + playlist_id;
    std::string html = detail::http_get(url);
    std::string json_str = detail::extract_json(html, "var ytInitialData");
    if (json_str.empty()) return {{}};

    auto data = nlohmann::json::parse(json_str);
    std::string api_key = detail::extract_api_key(html);

    auto [results, continuation] = detail::parse_playlist_results(data, limit);

    for (auto& r : results) {
        auto fb = detail::fallback_result(r.id);
        if (r.title.empty() || r.title == fb.title || r.author == fb.author) {
            detail::enrich_with_oembed(r);
        }
    }

    SearchResponse resp;
    resp.results = std::move(results);
    resp.continuation = std::move(continuation);
    resp.api_key = std::move(api_key);
    return resp;
}

// ─── New Types ────────────────────────────────────────────────────────────────

struct CommentAuthor {
    std::string name;
    std::string channel_id;
    std::string avatar;
    bool is_verified = false;
    bool is_owner = false;
    NLOHMANN_DEFINE_TYPE_INTRUSIVE(CommentAuthor, name, channel_id, avatar, is_verified, is_owner)
};

struct CommentReply {
    std::string id;
    CommentAuthor author;
    std::string text;
    long long like_count = 0;
    long long like_count_raw = 0;
    std::string published_time;
    bool is_liked_by_creator = false;
    NLOHMANN_DEFINE_TYPE_INTRUSIVE(CommentReply, id, author, text, like_count, like_count_raw, published_time, is_liked_by_creator)
};

struct VideoComment {
    std::string id;
    CommentAuthor author;
    std::string text;
    long long like_count = 0;
    long long like_count_raw = 0;
    std::string published_time;
    int reply_count = 0;
    bool is_liked_by_creator = false;
    bool is_pinned = false;
    std::vector<CommentReply> replies;
    std::string reply_continuation;
    NLOHMANN_DEFINE_TYPE_INTRUSIVE(VideoComment, id, author, text, like_count, like_count_raw, published_time, reply_count, is_liked_by_creator, is_pinned, replies, reply_continuation)
};

struct RelatedVideo {
    std::string id;
    std::string title;
    std::string author;
    std::string channel_url;
    std::string duration;
    int duration_seconds = 0;
    std::string view_count;
    long long view_count_raw = 0;
    std::string published_time;
    std::string thumbnail;
    bool is_live = false;
    NLOHMANN_DEFINE_TYPE_INTRUSIVE(RelatedVideo, id, title, author, channel_url, duration, duration_seconds, view_count, view_count_raw, published_time, thumbnail, is_live)
};

struct LiveStreamInfo {
    bool is_live = false;
    bool is_upcoming = false;
    long long viewer_count = 0;
    std::string viewer_count_str;
    std::string start_time;
    std::string scheduled_start_time;
    long long likes_count = 0;
    long long dislikes_count = 0;
    NLOHMANN_DEFINE_TYPE_INTRUSIVE(LiveStreamInfo, is_live, is_upcoming, viewer_count, viewer_count_str, start_time, scheduled_start_time, likes_count, dislikes_count)
};

// ─── LRU Cache ──────────────────────────────────────────────────────────────

template <typename V>
class LRUCache {
public:
    LRUCache(int max_size = 500, long long ttl_ms = 300000)
        : max_size_(max_size), ttl_ms_(ttl_ms) {}

    V* get(const std::string& key) {
        auto it = map_.find(key);
        if (it == map_.end()) return nullptr;
        auto now = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count();
        if (now > it->second.expires) {
            map_.erase(it);
            order_.erase(std::find(order_.begin(), order_.end(), key));
            return nullptr;
        }
        order_.erase(std::find(order_.begin(), order_.end(), key));
        order_.push_back(key);
        return &it->second.value;
    }

    void set(const std::string& key, const V& value) {
        auto it = map_.find(key);
        if (it != map_.end()) {
            order_.erase(std::find(order_.begin(), order_.end(), key));
        } else if ((int)map_.size() >= max_size_) {
            std::string oldest = order_.front();
            order_.erase(order_.begin());
            map_.erase(oldest);
        }
        order_.push_back(key);
        auto now = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count();
        map_[key] = {value, now + ttl_ms_};
    }

    void clear() {
        map_.clear();
        order_.clear();
    }

    int size() const { return (int)map_.size(); }

private:
    struct Entry {
        V value;
        long long expires;
    };
    int max_size_;
    long long ttl_ms_;
    std::map<std::string, Entry> map_;
    std::deque<std::string> order_;
};

// ─── Retry ─────────────────────────────────────────────────────────────────

template <typename F>
auto with_retry(F&& fn, int max_retries = 3, int base_delay = 500, int max_delay = 5000)
    -> decltype(fn())
{
    std::exception_ptr last_err;
    for (int a = 0; a <= max_retries; a++) {
        try {
            return fn();
        } catch (...) {
            last_err = std::current_exception();
            if (a >= max_retries) std::rethrow_exception(last_err);
            int delay = std::min(base_delay * (1 << a) + (std::rand() % 500), max_delay);
            std::this_thread::sleep_for(std::chrono::milliseconds(delay));
        }
    }
    std::rethrow_exception(last_err);
}

// ─── Comment Parser ─────────────────────────────────────────────────────────

inline VideoComment parse_comment_renderer(const nlohmann::json& cr) {
    VideoComment vc;
    vc.id = cr.value("commentId", "");
    if (vc.id.empty() && cr.contains("properties") && cr["properties"].contains("commentId"))
        vc.id = cr["properties"]["commentId"].get<std::string>();

    std::string author_name;
    if (cr.contains("authorText")) {
        const auto& at = cr["authorText"];
        if (at.contains("simpleText")) author_name = at["simpleText"].get<std::string>();
        else if (at.contains("runs")) author_name = detail::extract_runs(at["runs"]);
    }
    vc.author.name = author_name;

    if (cr.contains("authorEndpoint") && cr["authorEndpoint"].contains("browseEndpoint") &&
        cr["authorEndpoint"]["browseEndpoint"].contains("browseId"))
        vc.author.channel_id = cr["authorEndpoint"]["browseEndpoint"]["browseId"].get<std::string>();

    if (cr.contains("authorThumbnail") && cr["authorThumbnail"].contains("thumbnails") &&
        cr["authorThumbnail"]["thumbnails"].is_array() && !cr["authorThumbnail"]["thumbnails"].empty()) {
        const auto& arr = cr["authorThumbnail"]["thumbnails"];
        vc.author.avatar = arr[arr.size() - 1].value("url", "");
    }

    if (cr.contains("authorCommentBadge") &&
        cr["authorCommentBadge"].contains("authorCommentBadgeRenderer") &&
        cr["authorCommentBadge"]["authorCommentBadgeRenderer"].contains("icon") &&
        cr["authorCommentBadge"]["authorCommentBadgeRenderer"]["icon"].contains("iconType"))
        vc.author.is_verified = cr["authorCommentBadge"]["authorCommentBadgeRenderer"]["icon"]["iconType"].get<std::string>() == "CHECK";

    vc.author.is_owner = cr.value("authorIsChannelOwner", false);

    if (cr.contains("contentText")) {
        const auto& ct = cr["contentText"];
        if (ct.contains("simpleText")) vc.text = ct["simpleText"].get<std::string>();
        else if (ct.contains("runs")) vc.text = detail::extract_runs(ct["runs"]);
    }

    if (cr.contains("voteCount") && cr["voteCount"].contains("simpleText"))
        vc.like_count = cr["voteCount"]["simpleText"].is_string()
            ? std::stoll(cr["voteCount"]["simpleText"].get<std::string>()) : cr["voteCount"]["simpleText"].get<long long>();
    else if (cr.contains("likeCount"))
        vc.like_count = cr["likeCount"].is_string() ? std::stoll(cr["likeCount"].get<std::string>()) : cr["likeCount"].get<long long>();
    vc.like_count_raw = vc.like_count;

    if (cr.contains("publishedTimeText") && cr["publishedTimeText"].contains("runs") &&
        cr["publishedTimeText"]["runs"].is_array() && !cr["publishedTimeText"]["runs"].empty() &&
        cr["publishedTimeText"]["runs"][0].contains("text"))
        vc.published_time = cr["publishedTimeText"]["runs"][0]["text"].get<std::string>();

    vc.reply_count = cr.value("replyCount", 0);
    vc.is_liked_by_creator = cr.value("isLiked", false);
    vc.is_pinned = cr.contains("pinnedCommentBadge") && cr["pinnedCommentBadge"].contains("pinnedCommentBadgeRenderer");

    if (cr.contains("replies") && cr["replies"].contains("commentRepliesRenderer") &&
        cr["replies"]["commentRepliesRenderer"].contains("contents") &&
        cr["replies"]["commentRepliesRenderer"]["contents"].is_array()) {
        for (const auto& ri : cr["replies"]["commentRepliesRenderer"]["contents"]) {
            if (ri.contains("continuationItemRenderer")) {
                if (ri["continuationItemRenderer"].contains("continuationEndpoint") &&
                    ri["continuationItemRenderer"]["continuationEndpoint"].contains("continuationCommand") &&
                    ri["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"].contains("token"))
                    vc.reply_continuation = ri["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"].get<std::string>();
                continue;
            }
            if (!ri.contains("commentRenderer")) continue;
            const auto& rr = ri["commentRenderer"];
            CommentReply reply;
            reply.id = rr.value("commentId", "");

            std::string rr_name;
            if (rr.contains("authorText")) {
                const auto& at = rr["authorText"];
                if (at.contains("simpleText")) rr_name = at["simpleText"].get<std::string>();
                else if (at.contains("runs")) rr_name = detail::extract_runs(at["runs"]);
            }
            reply.author.name = rr_name;
            if (rr.contains("authorEndpoint") && rr["authorEndpoint"].contains("browseEndpoint") &&
                rr["authorEndpoint"]["browseEndpoint"].contains("browseId"))
                reply.author.channel_id = rr["authorEndpoint"]["browseEndpoint"]["browseId"].get<std::string>();
            if (rr.contains("authorThumbnail") && rr["authorThumbnail"].contains("thumbnails") &&
                rr["authorThumbnail"]["thumbnails"].is_array() && !rr["authorThumbnail"]["thumbnails"].empty()) {
                const auto& arr = rr["authorThumbnail"]["thumbnails"];
                reply.author.avatar = arr[arr.size() - 1].value("url", "");
            }
            reply.author.is_owner = rr.value("authorIsChannelOwner", false);

            if (rr.contains("contentText")) {
                const auto& ct = rr["contentText"];
                if (ct.contains("simpleText")) reply.text = ct["simpleText"].get<std::string>();
                else if (ct.contains("runs")) reply.text = detail::extract_runs(ct["runs"]);
            }
            if (rr.contains("voteCount") && rr["voteCount"].contains("simpleText"))
                reply.like_count = rr["voteCount"]["simpleText"].is_string()
                    ? std::stoll(rr["voteCount"]["simpleText"].get<std::string>()) : rr["voteCount"]["simpleText"].get<long long>();
            reply.like_count_raw = reply.like_count;

            if (rr.contains("publishedTimeText") && rr["publishedTimeText"].contains("runs") &&
                rr["publishedTimeText"]["runs"].is_array() && !rr["publishedTimeText"]["runs"].empty() &&
                rr["publishedTimeText"]["runs"][0].contains("text"))
                reply.published_time = rr["publishedTimeText"]["runs"][0]["text"].get<std::string>();

            if (rr.contains("actionButtons") && rr["actionButtons"].contains("commentActionButtonsRenderer") &&
                rr["actionButtons"]["commentActionButtonsRenderer"].contains("creatorHeart") &&
                rr["actionButtons"]["commentActionButtonsRenderer"]["creatorHeart"].contains("creatorHeartRenderer") &&
                rr["actionButtons"]["commentActionButtonsRenderer"]["creatorHeart"]["creatorHeartRenderer"].contains("isHearted"))
                reply.is_liked_by_creator = rr["actionButtons"]["commentActionButtonsRenderer"]["creatorHeart"]["creatorHeartRenderer"]["isHearted"].get<bool>();

            vc.replies.push_back(std::move(reply));
        }
    }

    return vc;
}

inline std::pair<std::vector<VideoComment>, std::string> parse_comment_threads(const nlohmann::json& items, int limit) {
    std::vector<VideoComment> comments;
    std::string nc;
    for (const auto& item : items) {
        if ((int)comments.size() >= limit) break;
        if (item.contains("continuationItemRenderer") &&
            item["continuationItemRenderer"].contains("continuationEndpoint") &&
            item["continuationItemRenderer"]["continuationEndpoint"].contains("continuationCommand") &&
            item["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"].contains("token")) {
            nc = item["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"].get<std::string>();
        }
        if (item.contains("commentThreadRenderer") && item["commentThreadRenderer"].contains("comment") &&
            item["commentThreadRenderer"]["comment"].contains("commentRenderer")) {
            comments.push_back(parse_comment_renderer(item["commentThreadRenderer"]["comment"]["commentRenderer"]));
        }
    }
    return {comments, nc};
}

// ─── Public: Comments ────────────────────────────────────────────────────────

inline std::pair<std::vector<VideoComment>, std::string> get_comments(
    const std::string& video_id, int limit = 20, const std::string& continuation = "") {
    limit = std::max(1, std::min(limit, 100));

    try {
        std::string url = "https://www.youtube.com/watch?v=" + video_id;
        std::string html = detail::http_get(url);

        if (!continuation.empty()) {
            std::string api_key = detail::extract_api_key(html);
            if (api_key.empty()) api_key = detail::FALLBACK_API_KEY;
            std::string ctx_str = detail::extract_context_json(html);
            if (ctx_str.empty()) ctx_str = detail::default_context_json();

            nlohmann::json body;
            body["context"] = nlohmann::json::parse(ctx_str);
            body["continuation"] = continuation;

            std::string resp = detail::http_post(
                "https://www.youtube.com/youtubei/v1/next?key=" + api_key, body.dump());
            auto data = nlohmann::json::parse(resp);

            const nlohmann::json* items = nullptr;
            if (data.contains("onResponseReceivedEndpoints") && data["onResponseReceivedEndpoints"].is_array() &&
                !data["onResponseReceivedEndpoints"].empty()) {
                const auto& ep0 = data["onResponseReceivedEndpoints"][0];
                if (ep0.contains("reloadContinuationItemsCommand") &&
                    ep0["reloadContinuationItemsCommand"].contains("continuationItems"))
                    items = &ep0["reloadContinuationItemsCommand"]["continuationItems"];
                else if (ep0.contains("appendContinuationItemsAction") &&
                         ep0["appendContinuationItemsAction"].contains("continuationItems"))
                    items = &ep0["appendContinuationItemsAction"]["continuationItems"];
            }
            if (items && items->is_array())
                return parse_comment_threads(*items, limit);
            return {{}, ""};
        }

        std::string json_str = detail::extract_json(html, "var ytInitialData");
        if (json_str.empty()) return {{}, ""};

        auto data = nlohmann::json::parse(json_str);
        std::string api_key = detail::extract_api_key(html);
        if (api_key.empty()) api_key = detail::FALLBACK_API_KEY;
        std::string ctx_str = detail::extract_context_json(html);
        if (ctx_str.empty()) ctx_str = detail::default_context_json();

        std::string token;
        if (data.contains("contents") &&
            data["contents"].contains("twoColumnWatchNextResults") &&
            data["contents"]["twoColumnWatchNextResults"].contains("results") &&
            data["contents"]["twoColumnWatchNextResults"]["results"].contains("results") &&
            data["contents"]["twoColumnWatchNextResults"]["results"]["results"].contains("contents")) {
            const auto& all_results = data["contents"]["twoColumnWatchNextResults"]["results"]["results"]["contents"];
            for (const auto& c : all_results) {
                if (!c.contains("itemSectionRenderer") || !c["itemSectionRenderer"].contains("contents")) continue;
                const auto& ic = c["itemSectionRenderer"]["contents"];
                for (const auto& item : ic) {
                    if (item.contains("continuationItemRenderer") &&
                        item["continuationItemRenderer"].contains("continuationEndpoint") &&
                        item["continuationItemRenderer"]["continuationEndpoint"].contains("continuationCommand") &&
                        item["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"].contains("token")) {
                        token = item["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"].get<std::string>();
                        break;
                    }
                    if (item.contains("commentsEntryPointHeaderRenderer") &&
                        item["commentsEntryPointHeaderRenderer"].contains("contents") &&
                        item["commentsEntryPointHeaderRenderer"]["contents"].is_array() &&
                        !item["commentsEntryPointHeaderRenderer"]["contents"].empty()) {
                        const auto& cep = item["commentsEntryPointHeaderRenderer"]["contents"][0];
                        if (cep.contains("continuationItemRenderer") &&
                            cep["continuationItemRenderer"].contains("continuationEndpoint") &&
                            cep["continuationItemRenderer"]["continuationEndpoint"].contains("continuationCommand") &&
                            cep["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"].contains("token")) {
                            token = cep["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"].get<std::string>();
                            break;
                        }
                    }
                }
                if (!token.empty()) break;
            }
        }
        if (token.empty()) return {{}, ""};

        nlohmann::json body;
        body["context"] = nlohmann::json::parse(ctx_str);
        body["continuation"] = token;

        std::string resp = detail::http_post(
            "https://www.youtube.com/youtubei/v1/next?key=" + api_key, body.dump());
        auto nd = nlohmann::json::parse(resp);

        const nlohmann::json* n_items = nullptr;
        if (nd.contains("onResponseReceivedEndpoints") && nd["onResponseReceivedEndpoints"].is_array()) {
            const auto& eps = nd["onResponseReceivedEndpoints"];
            for (auto it = eps.begin(); it != eps.end() && !n_items; ++it) {
                if (it->contains("reloadContinuationItemsCommand") &&
                    (*it)["reloadContinuationItemsCommand"].contains("continuationItems"))
                    n_items = &(*it)["reloadContinuationItemsCommand"]["continuationItems"];
                else if (it->contains("appendContinuationItemsAction") &&
                         (*it)["appendContinuationItemsAction"].contains("continuationItems"))
                    n_items = &(*it)["appendContinuationItemsAction"]["continuationItems"];
            }
        }
        if (n_items && n_items->is_array())
            return parse_comment_threads(*n_items, limit);
        return {{}, ""};
    } catch (...) {
        return {{}, ""};
    }
}

// ─── Public: Related Videos ──────────────────────────────────────────────────

inline std::vector<RelatedVideo> get_related_videos(const std::string& video_id, int limit = 15) {
    limit = std::max(1, std::min(limit, 50));

    try {
        std::string url = "https://www.youtube.com/watch?v=" + video_id;
        std::string html = detail::http_get(url);
        std::string json_str = detail::extract_json(html, "var ytInitialData");
        if (json_str.empty()) return {};

        auto data = nlohmann::json::parse(json_str);
        if (!data.contains("contents") || !data["contents"].contains("twoColumnWatchNextResults"))
            return {};
        const auto& tnr = data["contents"]["twoColumnWatchNextResults"];
        if (!tnr.contains("secondaryResults") || !tnr["secondaryResults"].contains("secondaryResults") ||
            !tnr["secondaryResults"]["secondaryResults"].contains("results"))
            return {};

        const auto& watch_next = tnr["secondaryResults"]["secondaryResults"]["results"];
        std::vector<RelatedVideo> results;

        for (const auto& item : watch_next) {
            if ((int)results.size() >= limit) break;

            const nlohmann::json* vr = nullptr;
            if (item.contains("compactVideoRenderer")) vr = &item["compactVideoRenderer"];
            else if (item.contains("compactRadioRenderer")) vr = &item["compactRadioRenderer"];
            if (!vr) continue;

            std::string vid = vr->value("videoId", "");
            if (vid.empty()) continue;

            RelatedVideo rv;
            rv.id = vid;

            if (vr->contains("title")) {
                const auto& t = (*vr)["title"];
                if (t.contains("simpleText")) rv.title = t["simpleText"].get<std::string>();
                else if (t.contains("runs")) rv.title = detail::extract_runs(t["runs"]);
            }

            if (vr->contains("shortBylineText")) {
                const auto& sbt = (*vr)["shortBylineText"];
                if (sbt.contains("simpleText")) rv.author = sbt["simpleText"].get<std::string>();
                else if (sbt.contains("runs")) rv.author = detail::extract_runs(sbt["runs"]);
            }

            std::string dur_text;
            if (vr->contains("lengthText")) {
                const auto& lt = (*vr)["lengthText"];
                if (lt.contains("simpleText")) dur_text = lt["simpleText"].get<std::string>();
                else if (lt.contains("runs")) dur_text = detail::extract_runs(lt["runs"]);
            }
            auto [secs, dur] = detail::parse_duration(dur_text);
            rv.duration = dur;
            rv.duration_seconds = secs;

            std::string views_text;
            if (vr->contains("viewCountText")) {
                const auto& vct = (*vr)["viewCountText"];
                if (vct.contains("simpleText")) views_text = vct["simpleText"].get<std::string>();
                else if (vct.contains("runs")) views_text = detail::extract_runs(vct["runs"]);
            }
            rv.view_count = views_text;
            rv.view_count_raw = detail::parse_view_count(views_text);

            if (vr->contains("publishedTimeText") && (*vr)["publishedTimeText"].contains("simpleText"))
                rv.published_time = (*vr)["publishedTimeText"]["simpleText"].get<std::string>();

            if (vr->contains("thumbnail") && (*vr)["thumbnail"].contains("thumbnails"))
                rv.thumbnail = detail::extract_best_thumbnail((*vr)["thumbnail"]["thumbnails"]);
            if (rv.thumbnail.empty())
                rv.thumbnail = "https://i.ytimg.com/vi/" + vid + "/hqdefault.jpg";

            if (vr->contains("shortBylineText") && (*vr)["shortBylineText"].contains("runs") &&
                (*vr)["shortBylineText"]["runs"].is_array() && !(*vr)["shortBylineText"]["runs"].empty() &&
                (*vr)["shortBylineText"]["runs"][0].contains("navigationEndpoint") &&
                (*vr)["shortBylineText"]["runs"][0]["navigationEndpoint"].contains("browseEndpoint") &&
                (*vr)["shortBylineText"]["runs"][0]["navigationEndpoint"]["browseEndpoint"].contains("canonicalBaseUrl"))
                rv.channel_url = (*vr)["shortBylineText"]["runs"][0]["navigationEndpoint"]["browseEndpoint"]["canonicalBaseUrl"].get<std::string>();

            if (vr->contains("badges") && (*vr)["badges"].is_array() && !(*vr)["badges"].empty()) {
                const auto& b0 = (*vr)["badges"][0];
                if (b0.contains("metadataBadgeRenderer")) {
                    std::string style;
                    if (b0["metadataBadgeRenderer"].contains("style"))
                        style = b0["metadataBadgeRenderer"]["style"].get<std::string>();
                    else if (b0["metadataBadgeRenderer"].contains("label"))
                        style = b0["metadataBadgeRenderer"]["label"].get<std::string>();
                    rv.is_live = style.find("LIVE") != std::string::npos;
                }
            }

            results.push_back(std::move(rv));
        }
        return results;
    } catch (...) {
        return {};
    }
}

// ─── Public: Video Stats ─────────────────────────────────────────────────────

inline std::tuple<long long, long long, long long, bool, long long> get_video_stats(const std::string& video_id) {
    try {
        std::string url = "https://www.youtube.com/watch?v=" + video_id;
        std::string html = detail::http_get(url);
        std::string json_str = detail::extract_json(html, "var ytInitialData");
        if (json_str.empty()) return {0, 0, 0, false, 0};

        auto data = nlohmann::json::parse(json_str);

        const nlohmann::json* primary = nullptr;
        if (data.contains("contents") &&
            data["contents"].contains("twoColumnWatchNextResults") &&
            data["contents"]["twoColumnWatchNextResults"].contains("results") &&
            data["contents"]["twoColumnWatchNextResults"]["results"].contains("results") &&
            data["contents"]["twoColumnWatchNextResults"]["results"]["results"].contains("contents")) {
            for (const auto& c : data["contents"]["twoColumnWatchNextResults"]["results"]["results"]["contents"]) {
                if (c.contains("videoPrimaryInfoRenderer")) {
                    primary = &c["videoPrimaryInfoRenderer"];
                    break;
                }
            }
        }

        long long views = 0;
        if (primary && primary->contains("viewCount") && (*primary)["viewCount"].contains("videoViewCountRenderer")) {
            const auto& vcr = (*primary)["viewCount"]["videoViewCountRenderer"];
            std::string views_text;
            if (vcr.contains("shortViewCount") && vcr["shortViewCount"].contains("simpleText"))
                views_text = vcr["shortViewCount"]["simpleText"].get<std::string>();
            else if (vcr.contains("viewCount") && vcr["viewCount"].contains("simpleText"))
                views_text = vcr["viewCount"]["simpleText"].get<std::string>();
            views = detail::parse_view_count(views_text);
        }

        long long likes = 0;
        if (primary && primary->contains("videoActions") && (*primary)["videoActions"].contains("menuRenderer") &&
            (*primary)["videoActions"]["menuRenderer"].contains("topLevelButtons") &&
            (*primary)["videoActions"]["menuRenderer"]["topLevelButtons"].is_array() &&
            !(*primary)["videoActions"]["menuRenderer"]["topLevelButtons"].empty()) {
            const auto& tlb = (*primary)["videoActions"]["menuRenderer"]["topLevelButtons"][0];
            if (tlb.contains("segmentedLikeDislikeButtonViewModel")) {
                const auto& sld = tlb["segmentedLikeDislikeButtonViewModel"];
                if (sld.contains("likeButtonViewModel")) {
                    const auto& lbvm = sld["likeButtonViewModel"];
                    if (lbvm.contains("likeButtonViewModel") &&
                        lbvm["likeButtonViewModel"].contains("toggleButtonViewModel") &&
                        lbvm["likeButtonViewModel"]["toggleButtonViewModel"].contains("toggleButtonViewModel") &&
                        lbvm["likeButtonViewModel"]["toggleButtonViewModel"]["toggleButtonViewModel"].contains("defaultButtonViewModel") &&
                        lbvm["likeButtonViewModel"]["toggleButtonViewModel"]["toggleButtonViewModel"]["defaultButtonViewModel"].contains("buttonViewModel") &&
                        lbvm["likeButtonViewModel"]["toggleButtonViewModel"]["toggleButtonViewModel"]["defaultButtonViewModel"]["buttonViewModel"].contains("accessibilityText")) {
                        std::string likes_str = lbvm["likeButtonViewModel"]["toggleButtonViewModel"]["toggleButtonViewModel"]["defaultButtonViewModel"]["buttonViewModel"]["accessibilityText"].get<std::string>();
                        std::string cleaned;
                        for (char c : likes_str) {
                            if (std::isdigit(static_cast<unsigned char>(c)) || c == '.' || c == 'K' || c == 'k' ||
                                c == 'M' || c == 'm' || c == 'B' || c == 'b') cleaned.push_back(c);
                        }
                        likes = detail::parse_view_count(cleaned);
                    }
                }
            }
        }

        bool is_live = html.find("\"isLive\":true") != std::string::npos;
        long long viewer_count = 0;
        if (is_live) {
            std::string prefix = "\"viewCount\":{\"videoViewCountRenderer\":{\"isLive\":true,\"viewCount\":{\"simpleText\":\"";
            auto pos = html.find(prefix);
            if (pos != std::string::npos) {
                pos += prefix.size();
                auto end = html.find('"', pos);
                if (end != std::string::npos) {
                    viewer_count = detail::parse_view_count(html.substr(pos, end - pos));
                }
            }
        }

        return {views, likes, 0, is_live, viewer_count};
    } catch (...) {
        return {0, 0, 0, false, 0};
    }
}

inline LiveStreamInfo get_live_stream_info(const std::string& video_id) {
    auto [_, likes, __, is_live, viewer_count] = get_video_stats(video_id);
    LiveStreamInfo info;
    info.is_live = is_live;
    info.is_upcoming = !is_live && viewer_count == 0;
    info.viewer_count = viewer_count;
    info.viewer_count_str = std::to_string(viewer_count);
    info.likes_count = likes;
    info.dislikes_count = 0;

    try {
        std::string url = "https://www.youtube.com/watch?v=" + video_id;
        std::string html = detail::http_get(url);
        std::string json_str = detail::extract_json(html, "var ytInitialData");
        if (!json_str.empty()) {
            auto data = nlohmann::json::parse(json_str);
            if (data.contains("contents") &&
                data["contents"].contains("twoColumnWatchNextResults") &&
                data["contents"]["twoColumnWatchNextResults"].contains("results") &&
                data["contents"]["twoColumnWatchNextResults"]["results"].contains("results") &&
                data["contents"]["twoColumnWatchNextResults"]["results"]["results"].contains("contents")) {
                for (const auto& c : data["contents"]["twoColumnWatchNextResults"]["results"]["results"]["contents"]) {
                    if (c.contains("videoPrimaryInfoRenderer")) {
                        const auto& p = c["videoPrimaryInfoRenderer"];
                        if (p.contains("dateText") && p["dateText"].contains("simpleText"))
                            info.start_time = p["dateText"]["simpleText"].get<std::string>();
                        if (p.contains("upcomingEventData") && p["upcomingEventData"].contains("startTime"))
                            info.scheduled_start_time = p["upcomingEventData"]["startTime"].get<std::string>();
                        break;
                    }
                }
            }
        }
    } catch (...) {}

    return info;
}

// ─── Channel Metadata ──────────────────────────────────────────────────────────

struct SocialLink {
    std::string title;
    std::string url;
    std::string icon;
};

struct ChannelMetadata {
    std::string id;
    std::string name;
    std::string handle;
    std::string description;
    std::string subscriber_count;
    long long subscriber_count_raw = 0;
    std::string video_count;
    long long video_count_raw = 0;
    std::string avatar;
    std::string banner;
    bool is_verified = false;
    std::vector<SocialLink> social_links;
    std::string url;
};

struct TranscriptEntry {
    std::string text;
    double start = 0.0;
    double duration = 0.0;
};

inline ChannelMetadata get_channel_metadata(const std::string& channel_id) {
    ChannelMetadata empty;
    empty.id = channel_id;
    empty.url = "https://www.youtube.com/channel/" + channel_id;

    try {
        std::string url = "https://www.youtube.com/channel/" + channel_id + "/about";
        std::string html = detail::http_get(url);
        std::string json_str = detail::extract_json(html, "var ytInitialData");
        if (json_str.empty()) return empty;

        auto data = nlohmann::json::parse(json_str);

        auto metadata = data.contains("metadata") && data["metadata"].contains("channelMetadataRenderer")
            ? &data["metadata"]["channelMetadataRenderer"] : nullptr;

        auto header = data.contains("header") && data["header"].contains("c4TabbedHeaderRenderer")
            ? &data["header"]["c4TabbedHeaderRenderer"] : nullptr;

        const nlohmann::json* about_renderer = nullptr;
        if (data.contains("contents") && data["contents"].contains("twoColumnBrowseResultsRenderer")) {
            const auto& tabs = data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"];
            for (const auto& tab : tabs) {
                if (tab.contains("tabRenderer") && tab["tabRenderer"].value("selected", false)) {
                    const auto& tr = tab["tabRenderer"];
                    if (tr.contains("content") && tr["content"].contains("sectionListRenderer") &&
                        tr["content"]["sectionListRenderer"].contains("contents") &&
                        !tr["content"]["sectionListRenderer"]["contents"].empty()) {
                        const auto& slc = tr["content"]["sectionListRenderer"]["contents"][0];
                        if (slc.contains("itemSectionRenderer") && slc["itemSectionRenderer"].contains("contents") &&
                            !slc["itemSectionRenderer"]["contents"].empty() &&
                            slc["itemSectionRenderer"]["contents"][0].contains("channelAboutFullMetadataRenderer")) {
                            about_renderer = &slc["itemSectionRenderer"]["contents"][0]["channelAboutFullMetadataRenderer"];
                        }
                    }
                    break;
                }
            }
        }

        std::string sub_text;
        if (header && header->contains("subscriberCountText") &&
            (*header)["subscriberCountText"].contains("simpleText"))
            sub_text = (*header)["subscriberCountText"]["simpleText"].get<std::string>();
        long long subs_raw = detail::parse_view_count(sub_text);
        empty.subscriber_count = sub_text;
        empty.subscriber_count_raw = subs_raw;

        std::string video_text;
        if (about_renderer && about_renderer->contains("videoCountText") &&
            (*about_renderer)["videoCountText"].contains("runs") &&
            (*about_renderer)["videoCountText"]["runs"].is_array() &&
            !(*about_renderer)["videoCountText"]["runs"].empty() &&
            (*about_renderer)["videoCountText"]["runs"][0].contains("text"))
            video_text = (*about_renderer)["videoCountText"]["runs"][0]["text"].get<std::string>();
        empty.video_count = video_text;

        long long vc_raw = 0;
        std::string num_str;
        for (char c : video_text) { if (std::isdigit(static_cast<unsigned char>(c))) num_str.push_back(c); }
        if (!num_str.empty()) vc_raw = std::stoll(num_str);
        empty.video_count_raw = vc_raw;

        if (about_renderer && about_renderer->contains("primaryLinks") && (*about_renderer)["primaryLinks"].is_array()) {
            for (const auto& l : (*about_renderer)["primaryLinks"]) {
                SocialLink link;
                if (l.contains("title")) {
                    if (l["title"].contains("simpleText")) link.title = l["title"]["simpleText"].get<std::string>();
                    else if (l["title"].contains("runs") && l["title"]["runs"].is_array() &&
                             !l["title"]["runs"].empty() && l["title"]["runs"][0].contains("text"))
                        link.title = l["title"]["runs"][0]["text"].get<std::string>();
                }
                if (l.contains("navigationEndpoint") && l["navigationEndpoint"].contains("urlEndpoint") &&
                    l["navigationEndpoint"]["urlEndpoint"].contains("url"))
                    link.url = l["navigationEndpoint"]["urlEndpoint"]["url"].get<std::string>();
                if (l.contains("icon") && l["icon"].contains("thumbnails") &&
                    l["icon"]["thumbnails"].is_array() && !l["icon"]["thumbnails"].empty() &&
                    l["icon"]["thumbnails"][0].contains("url"))
                    link.icon = l["icon"]["thumbnails"][0]["url"].get<std::string>();
                empty.social_links.push_back(std::move(link));
            }
        }

        if (metadata && metadata->contains("title")) empty.name = (*metadata)["title"].get<std::string>();
        else if (header && header->contains("title")) empty.name = (*header)["title"].get<std::string>();

        std::string vanity_url;
        if (metadata && metadata->contains("vanityChannelUrl"))
            vanity_url = (*metadata)["vanityChannelUrl"].get<std::string>();
        if (!vanity_url.empty()) {
            size_t pos;
            if ((pos = vanity_url.find("http://www.youtube.com/")) != std::string::npos)
                empty.handle = vanity_url.substr(pos + 24);
            else if ((pos = vanity_url.find("https://www.youtube.com/")) != std::string::npos)
                empty.handle = vanity_url.substr(pos + 25);
        }

        if (metadata && metadata->contains("description")) empty.description = (*metadata)["description"].get<std::string>();
        else if (about_renderer) {
            if (about_renderer->contains("description")) {
                const auto& desc = (*about_renderer)["description"];
                if (desc.contains("simpleText")) empty.description = desc["simpleText"].get<std::string>();
                else if (desc.contains("runs")) empty.description = detail::extract_runs(desc["runs"]);
            }
        }

        const nlohmann::json* avatar_arr = nullptr;
        if (metadata && metadata->contains("avatar") && (*metadata)["avatar"].contains("thumbnails"))
            avatar_arr = &(*metadata)["avatar"]["thumbnails"];
        else if (header && header->contains("avatar") && (*header)["avatar"].contains("thumbnails"))
            avatar_arr = &(*header)["avatar"]["thumbnails"];
        if (avatar_arr && avatar_arr->is_array()) empty.avatar = detail::extract_best_thumbnail(*avatar_arr);

        const nlohmann::json* banner_arr = nullptr;
        if (metadata && metadata->contains("banner") && (*metadata)["banner"].contains("thumbnails"))
            banner_arr = &(*metadata)["banner"]["thumbnails"];
        else if (header && header->contains("banner") && (*header)["banner"].contains("thumbnails"))
            banner_arr = &(*header)["banner"]["thumbnails"];
        if (banner_arr && banner_arr->is_array()) empty.banner = detail::extract_best_thumbnail(*banner_arr);

        if (header && header->contains("badges") && (*header)["badges"].is_array()) {
            for (const auto& badge : (*header)["badges"]) {
                if (badge.contains("metadataBadgeRenderer") && badge["metadataBadgeRenderer"].contains("style")) {
                    std::string style = badge["metadataBadgeRenderer"]["style"].get<std::string>();
                    if (style.find("VERIFIED") != std::string::npos) {
                        empty.is_verified = true;
                        break;
                    }
                }
            }
        }
    } catch (...) {}

    return empty;
}

// ─── Transcript ────────────────────────────────────────────────────────────────

inline std::vector<TranscriptEntry> get_transcript(const std::string& video_id, const std::string& lang = "") {
    try {
        std::string url = "https://www.youtube.com/watch?v=" + video_id;
        std::string html = detail::http_get(url);

        std::string tracks_str;
        {
            std::string prefix = "\"captionTracks\":";
            auto idx = html.find(prefix);
            if (idx != std::string::npos) {
                idx += prefix.size();
                while (idx < html.size() && std::isspace(static_cast<unsigned char>(html[idx]))) ++idx;
                if (idx < html.size() && html[idx] == '[') {
                    int depth = 1;
                    bool in_str = false;
                    bool esc = false;
                    size_t start = idx;
                    ++idx;
                    for (; idx < html.size(); ++idx) {
                        char c = html[idx];
                        if (esc) { esc = false; continue; }
                        if (c == '\\') { esc = true; continue; }
                        if (c == '"') { in_str = !in_str; continue; }
                        if (in_str) continue;
                        if (c == '[') ++depth;
                        if (c == ']') { --depth; if (depth == 0) { ++idx; break; } }
                    }
                    if (depth == 0) tracks_str = html.substr(start, idx - start);
                }
            }
        }
        if (tracks_str.empty()) {
            std::string prefix = "\"captions\":{";
            auto idx = html.find(prefix);
            if (idx != std::string::npos) {
                std::string sub = html.substr(idx + prefix.size());
                auto cts = sub.find("\"captionTracks\":");
                if (cts != std::string::npos) {
                    cts += 16;
                    while (cts < sub.size() && std::isspace(static_cast<unsigned char>(sub[cts]))) ++cts;
                    if (cts < sub.size() && sub[cts] == '[') {
                        int depth = 1;
                        bool in_str = false;
                        bool esc = false;
                        size_t start = cts;
                        ++cts;
                        for (; cts < sub.size(); ++cts) {
                            char c = sub[cts];
                            if (esc) { esc = false; continue; }
                            if (c == '\\') { esc = true; continue; }
                            if (c == '"') { in_str = !in_str; continue; }
                            if (in_str) continue;
                            if (c == '[') ++depth;
                            if (c == ']') { --depth; if (depth == 0) { ++cts; break; } }
                        }
                        if (depth == 0) tracks_str = sub.substr(start, cts - start);
                    }
                }
            }
        }
        if (tracks_str.empty()) return {};

        auto tracks = nlohmann::json::parse(tracks_str);
        if (!tracks.is_array()) return {};

        std::string track_url;
        if (!lang.empty()) {
            for (const auto& track : tracks) {
                std::string lc = track.value("languageCode", "");
                std::string tn;
                if (track.contains("name") && track["name"].contains("simpleText"))
                    tn = track["name"]["simpleText"].get<std::string>();
                auto tn_lower = tn;
                auto lang_lower = lang;
                std::transform(tn_lower.begin(), tn_lower.end(), tn_lower.begin(), ::tolower);
                std::transform(lang_lower.begin(), lang_lower.end(), lang_lower.begin(), ::tolower);
                if (lc == lang || tn_lower.find(lang_lower) != std::string::npos) {
                    track_url = track["baseUrl"].get<std::string>();
                    break;
                }
            }
        }
        if (track_url.empty()) {
            for (const auto& track : tracks) {
                if (track.value("languageCode", "") == "en") {
                    track_url = track["baseUrl"].get<std::string>();
                    break;
                }
            }
        }
        if (track_url.empty() && !tracks.empty()) {
            track_url = tracks[0]["baseUrl"].get<std::string>();
        }
        if (track_url.empty()) return {};

        std::string xml = detail::http_get(track_url);
        std::vector<TranscriptEntry> entries;

        std::string pattern = "<text start=\"";
        size_t pos = 0;
        while ((pos = xml.find(pattern, pos)) != std::string::npos) {
            size_t val_start = pos + pattern.size();
            size_t val_end = xml.find('"', val_start);
            if (val_end == std::string::npos) break;
            double start_val = std::stod(xml.substr(val_start, val_end - val_start));

            std::string dur_pat = " dur=\"";
            size_t dur_pos = xml.find(dur_pat, val_end);
            if (dur_pos == std::string::npos) break;
            size_t dur_start = dur_pos + dur_pat.size();
            size_t dur_end = xml.find('"', dur_start);
            if (dur_end == std::string::npos) break;
            double dur_val = std::stod(xml.substr(dur_start, dur_end - dur_start));

            size_t text_start = xml.find('>', dur_end);
            if (text_start == std::string::npos) break;
            ++text_start;
            size_t text_end = xml.find("</text>", text_start);
            bool is_closed = (text_end != std::string::npos);
            if (!is_closed) text_end = xml.find('\n', text_start);
            if (text_end == std::string::npos) text_end = xml.size();

            std::string raw_text = xml.substr(text_start, text_end - text_start);
            // strip HTML tags
            {
                std::string stripped;
                bool in_tag = false;
                for (char c : raw_text) {
                    if (c == '<') in_tag = true;
                    else if (c == '>') in_tag = false;
                    else if (!in_tag) stripped.push_back(c);
                }
                raw_text = stripped;
            }
            // decode entities
            auto replace_all = [](std::string& s, const std::string& from, const std::string& to) {
                size_t p = 0;
                while ((p = s.find(from, p)) != std::string::npos) {
                    s.replace(p, from.size(), to);
                    p += to.size();
                }
            };
            replace_all(raw_text, "&amp;", "&");
            replace_all(raw_text, "&lt;", "<");
            replace_all(raw_text, "&gt;", ">");
            replace_all(raw_text, "&quot;", "\"");
            replace_all(raw_text, "&#39;", "'");

            auto trimmed = raw_text;
            while (!trimmed.empty() && std::isspace(static_cast<unsigned char>(trimmed.front()))) trimmed.erase(0, 1);
            while (!trimmed.empty() && std::isspace(static_cast<unsigned char>(trimmed.back()))) trimmed.pop_back();
            if (!trimmed.empty()) {
                entries.push_back({trimmed, start_val, dur_val});
            }

            pos = text_end + (is_closed ? 7 : 0);
        }

        return entries;
    } catch (...) {
        return {};
    }
}

// ─── Shorts Search ─────────────────────────────────────────────────────────────

inline SearchResponse search_shorts(const std::string& query, int limit = 15,
                                     const std::string& gl = "", const std::string& hl = "") {
    limit = std::max(1, std::min(limit, 50));

    std::string region;
    if (!gl.empty()) region += "&gl=" + gl;
    if (!hl.empty()) region += "&hl=" + hl;

    CURL* curl = curl_easy_init();
    if (!curl) throw std::runtime_error("curl_easy_init failed");
    std::string url = std::string(detail::SEARCH_URL) + detail::url_encode(curl, query) + "&sp=EgIYAQ%3D%3D" + region;
    curl_easy_cleanup(curl);

    std::string html = detail::http_get(url);
    std::string json_str = detail::extract_json(html, "var ytInitialData");
    if (json_str.empty()) return {{}};
    auto data = nlohmann::json::parse(json_str);
    std::string api_key = detail::extract_api_key(html);

    const nlohmann::json* reel_items = nullptr;
    if (data.contains("contents") && data["contents"].contains("twoColumnSearchResultsRenderer") &&
        data["contents"]["twoColumnSearchResultsRenderer"].contains("primaryContents") &&
        data["contents"]["twoColumnSearchResultsRenderer"]["primaryContents"].contains("sectionListRenderer") &&
        data["contents"]["twoColumnSearchResultsRenderer"]["primaryContents"]["sectionListRenderer"].contains("contents")) {
        const auto& contents = data["contents"]["twoColumnSearchResultsRenderer"]["primaryContents"]["sectionListRenderer"]["contents"];
        for (const auto& section : contents) {
            if (section.contains("itemSectionRenderer") && section["itemSectionRenderer"].contains("contents") &&
                !section["itemSectionRenderer"]["contents"].empty()) {
                const auto& first = section["itemSectionRenderer"]["contents"][0];
                if (first.contains("reelShelfRenderer") && first["reelShelfRenderer"].contains("items")) {
                    reel_items = &first["reelShelfRenderer"]["items"];
                    break;
                }
            }
        }
    }

    if (reel_items && reel_items->is_array()) {
        std::vector<VideoResult> short_results;
        for (const auto& item : *reel_items) {
            if ((int)short_results.size() >= limit) break;
            const nlohmann::json* ri = nullptr;
            if (item.contains("reelItemRenderer")) ri = &item["reelItemRenderer"];
            else if (item.contains("shortsLockupViewModel")) ri = &item["shortsLockupViewModel"];
            if (!ri) continue;

            std::string vid;
            if (ri->contains("videoId")) vid = (*ri)["videoId"].get<std::string>();
            else if (item.contains("reelItemRenderer") && item["reelItemRenderer"].contains("videoId"))
                vid = item["reelItemRenderer"]["videoId"].get<std::string>();
            if (vid.empty()) continue;

            std::string title;
            if (ri->contains("headline")) {
                const auto& hl = (*ri)["headline"];
                if (hl.contains("simpleText")) title = hl["simpleText"].get<std::string>();
                else if (hl.contains("runs")) title = detail::extract_runs(hl["runs"]);
            }
            int dur_sec = 0;
            if (ri->contains("lengthText") && (*ri)["lengthText"].contains("simpleText"))
                dur_sec = std::stoi((*ri)["lengthText"]["simpleText"].get<std::string>());

            auto vr = detail::fallback_result(vid);
            vr.title = title.empty() ? ("Shorts " + vid) : title;
            vr.duration = std::to_string(dur_sec) + "s";
            vr.duration_seconds = dur_sec;
            vr.is_live = false;
            vr.is_upcoming = false;
            vr.is_verified = false;
            short_results.push_back(std::move(vr));
        }

        auto [all_results, continuation] = detail::parse_search_results(data, limit);
        std::vector<VideoResult> combined;
        std::set<std::string> seen;
        for (auto& r : short_results) {
            if (seen.insert(r.id).second) combined.push_back(std::move(r));
        }
        for (auto& r : all_results) {
            if (seen.insert(r.id).second && (int)combined.size() < limit) combined.push_back(std::move(r));
        }

        SearchResponse resp;
        resp.results = std::move(combined);
        resp.continuation = std::move(continuation);
        resp.api_key = std::move(api_key);
        return resp;
    }

    return search(query, limit);
}

// ─── Region-aware search overloads ─────────────────────────────────────────────

inline std::string build_region_params(const std::string& gl, const std::string& hl) {
    std::string p;
    if (!gl.empty()) p += "&gl=" + gl;
    if (!hl.empty()) p += "&hl=" + hl;
    return p;
}

inline SearchResponse search_with_region(const std::string& query, int limit = 15,
                                          const std::string& gl = "", const std::string& hl = "") {
    limit = std::max(1, std::min(limit, 50));
    CURL* curl = curl_easy_init();
    if (!curl) throw std::runtime_error("curl_easy_init failed");
    std::string url = std::string(detail::SEARCH_URL) + detail::url_encode(curl, query) + build_region_params(gl, hl);
    curl_easy_cleanup(curl);

    std::string html = detail::http_get(url);
    std::string json_str = detail::extract_json(html, "var ytInitialData");
    if (json_str.empty()) return {{}};
    auto data = nlohmann::json::parse(json_str);
    std::string api_key = detail::extract_api_key(html);
    auto [results, continuation] = detail::parse_search_results(data, limit);

    for (auto& r : results) {
        auto fb = detail::fallback_result(r.id);
        if (r.title.empty() || r.title == fb.title || r.author == fb.author) {
            detail::enrich_with_oembed(r);
        }
    }

    SearchResponse resp;
    resp.results = std::move(results);
    resp.continuation = std::move(continuation);
    resp.api_key = std::move(api_key);
    return resp;
}

inline SearchResponse search_trending_with_region(int limit = 15,
                                                    const std::string& gl = "", const std::string& hl = "") {
    limit = std::max(1, std::min(limit, 50));
    std::string region = build_region_params(gl, hl);
    std::string url_str = "https://www.youtube.com/feed/trending";
    if (!region.empty()) url_str += region;
    std::string html = detail::http_get(url_str);
    std::string json_str = detail::extract_json(html, "var ytInitialData");
    if (json_str.empty()) return {{}};

    auto data = nlohmann::json::parse(json_str);
    std::string api_key = detail::extract_api_key(html);
    auto [results, continuation] = detail::parse_trending_results(data, limit);

    SearchResponse resp;
    resp.results = std::move(results);
    resp.continuation = std::move(continuation);
    resp.api_key = std::move(api_key);
    return resp;
}

inline SearchResponse search_channel_with_region(const std::string& channel_id, int limit = 15,
                                                   const std::string& gl = "", const std::string& hl = "") {
    limit = std::max(1, std::min(limit, 50));
    std::string region = build_region_params(gl, hl);
    std::string url = "https://www.youtube.com/channel/" + channel_id + "/videos" + region;
    std::string html = detail::http_get(url);
    std::string json_str = detail::extract_json(html, "var ytInitialData");
    if (json_str.empty()) return {{}};

    auto data = nlohmann::json::parse(json_str);
    std::string api_key = detail::extract_api_key(html);
    auto [results, continuation] = detail::parse_channel_results(data, limit);

    for (auto& r : results) {
        auto fb = detail::fallback_result(r.id);
        if (r.title.empty() || r.title == fb.title || r.author == fb.author) {
            detail::enrich_with_oembed(r);
        }
    }

    SearchResponse resp;
    resp.results = std::move(results);
    resp.continuation = std::move(continuation);
    resp.api_key = std::move(api_key);
    return resp;
}

inline SearchResponse search_playlist_with_region(const std::string& playlist_id, int limit = 15,
                                                    const std::string& gl = "", const std::string& hl = "") {
    limit = std::max(1, std::min(limit, 50));
    std::string region = build_region_params(gl, hl);
    std::string url = "https://www.youtube.com/playlist?list=" + playlist_id + region;
    std::string html = detail::http_get(url);
    std::string json_str = detail::extract_json(html, "var ytInitialData");
    if (json_str.empty()) return {{}};

    auto data = nlohmann::json::parse(json_str);
    std::string api_key = detail::extract_api_key(html);
    auto [results, continuation] = detail::parse_playlist_results(data, limit);

    for (auto& r : results) {
        auto fb = detail::fallback_result(r.id);
        if (r.title.empty() || r.title == fb.title || r.author == fb.author) {
            detail::enrich_with_oembed(r);
        }
    }

    SearchResponse resp;
    resp.results = std::move(results);
    resp.continuation = std::move(continuation);
    resp.api_key = std::move(api_key);
    return resp;
}

// ─── Global Cache ──────────────────────────────────────────────────────────

static LRUCache<std::string> global_cache(500, 300000);

// ─── Client Factory ─────────────────────────────────────────────────────────

struct YtapisClient {
    std::function<SearchResponse(const std::string&, int)> search;
    std::function<SearchResponse(int)> search_trending;
    std::function<SearchResponse(const std::string&, int)> search_channel;
    std::function<SearchResponse(const std::string&, int)> search_playlist;
    std::function<SearchResponse(const std::string&, int, const std::string&, const std::string&)> search_continue_fn;
    std::function<VideoResult(const std::string&)> get_video;
    std::function<std::pair<std::vector<VideoComment>, std::string>(const std::string&, int)> get_comments_fn;
    std::function<std::vector<RelatedVideo>(const std::string&, int)> get_related_videos_fn;
    std::function<std::tuple<long long, long long, long long, bool, long long>(const std::string&)> get_video_stats_fn;
    std::function<LiveStreamInfo(const std::string&)> get_live_stream_info_fn;
    std::function<ChannelMetadata(const std::string&)> get_channel_metadata_fn;
    std::function<std::vector<TranscriptEntry>(const std::string&)> get_transcript_fn;
    std::function<SearchResponse(const std::string&, int)> search_shorts_fn;
    LRUCache<std::string>* cache;
};

inline YtapisClient create_client() {
    return YtapisClient{
        [](const std::string& q, int l) { return search(q, l); },
        [](int l) { return search_trending(l); },
        [](const std::string& cid, int l) { return search_channel(cid, l); },
        [](const std::string& pid, int l) { return search_playlist(pid, l); },
        [](const std::string& c, int l, const std::string& ak, const std::string& ctx) { return search_continue(c, l, ak, ctx); },
        [](const std::string& id) { return get_video(id); },
        [](const std::string& vid, int l) { return get_comments(vid, l); },
        [](const std::string& vid, int l) { return get_related_videos(vid, l); },
        [](const std::string& vid) { return get_video_stats(vid); },
        [](const std::string& vid) { return get_live_stream_info(vid); },
        [](const std::string& cid) { return get_channel_metadata(cid); },
        [](const std::string& vid) { return get_transcript(vid); },
        [](const std::string& q, int l) { return search_shorts(q, l); },
        &global_cache
    };
}

} // namespace ytapis
