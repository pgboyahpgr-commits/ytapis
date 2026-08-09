# Support

## Where to get help

- **GitHub Issues** — Report bugs and request features at [github.com/pgboyahpgr-commits/ytapis/issues](https://github.com/pgboyahpgr-commits/ytapis/issues)
- **GitHub Discussions** — Ask questions and share ideas at [github.com/pgboyahpgr-commits/ytapis/discussions](https://github.com/pgboyahpgr-commits/ytapis/discussions)

## Commercial support

For priority support, custom integrations, or consulting, contact [support@example.com].

## FAQ

### Do I need a YouTube API key?

No. ytapis scrapes YouTube search results and enriches them via the public oEmbed API. No API key, OAuth, or registration is required.

### Which languages are supported?

TypeScript, Python, Go, Dart, C#, PHP, Kotlin, Rust, Swift, and C++. All provide the same `search()` API and `VideoResult` type.

### Does this violate YouTube's Terms of Service?

ytapis only accesses publicly available data. However, you should review YouTube's ToS for your use case. ytapis is intended for personal and non-commercial use.

### Can I use this for commercial projects?

ytapis is MIT licensed, so you're free to use it in commercial projects. Be mindful of YouTube's terms and rate limiting when deploying at scale.

### How do I fix rate limiting?

Use the built-in retry with exponential backoff, or pass `gl` and `hl` parameters to rotate regional endpoints. For high-volume use, consider the LRU cache with TTL to reduce duplicate requests.
