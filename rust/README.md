# ytapis — Rust

YouTube search engine for Rust. Zero API key required.

Part of the [ytapis](https://github.com/pgboyahpgr-commits/ytapis) ecosystem.
Built by [geethudinoyt](https://github.com/geethudinoyt) and [geethudino (Ruthvik)](https://github.com/geethudino).

## Install

```toml
[dependencies]
ytapis = "2.0"
```

## Quick Start

```rust
use ytapis;

let results = ytapis::search("cats", Some(5), None, None)?;
for v in &results {
    println!("{} - {} - {} - {}", v.title, v.author, v.duration, v.view_count);
}

let trends = ytapis::search_trending(Some(10))?;
let channel = ytapis::search_channel("UC-lHJZR3Gqxm24_Vd_AJ5Yw", Some(10))?;
let playlist = ytapis::search_playlist("PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf", Some(10))?;
let video = ytapis::get_video("dQw4w9WgXcQ")?;
println!("{} - {} views", video.title, video.view_count_raw);
```

## CLI

```bash
cargo run -- search cats --limit 5
cargo run -- trending --limit 10
cargo run -- video dQw4w9WgXcQ
cargo run -- channel UC-lHJZR3Gqxm24_Vd_AJ5Yw --limit 10
```

## API

| Function | Args | Returns |
|----------|------|---------|
| `search(query, limit?, gl?, hl?)` | query, limit Option, gl Option, hl Option | `Result<Vec<VideoResult>>` |
| `search_trending(limit?)` | limit Option | `Result<Vec<VideoResult>>` |
| `search_channel(channel_id, limit?)` | channel_id, limit Option | `Result<Vec<VideoResult>>` |
| `search_playlist(playlist_id, limit?)` | playlist_id, limit Option | `Result<Vec<VideoResult>>` |
| `get_video(id)` | video id | `Result<VideoResult>` |

## License

MIT
