# ytapis

YouTube search engine in Rust. Scrapes youtube.com results, parses `ytInitialData` via
brace counting, supports InnerTube continuation/pagination, and falls back to oEmbed.

## Usage

```rust
use ytapis::{search, get_video, search_continue};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Search
    let resp = search("rust programming", 10)?;
    for v in &resp.results {
        println!("{} - {} ({})", v.title, v.author, v.duration);
    }

    // Paginate
    if let Some(ct) = &resp.continuation {
        let more = search_continue(ct, 10, resp.api_key.as_deref(), None)?;
        println!("Got {} more results", more.results.len());
    }

    // Single video (via watch-page scrape + oEmbed fallback)
    let video = get_video("dQw4w9WgXcQ")?;
    println!("{} — {} views", video.title, video.view_count);

    Ok(())
}
```

## Dependencies

- `reqwest` (blocking, json) — HTTP client
- `serde` + `serde_json` — JSON deserialisation

No other external crates. All HTML/JSON extraction is hand-rolled (brace-counting parser, no regex).
