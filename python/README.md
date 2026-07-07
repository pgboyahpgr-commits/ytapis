# ytapis &mdash; Python

Search YouTube and get video metadata &mdash; **no API key required**.

Part of the [ytapis](https://github.com/pgboyahpgr-commits/ytapis) monorepo. Built and managed by [geethudinoyt](https://github.com/geethudinoyt).

## Install

```bash
pip install ytapis
```

## Usage

```python
from ytapis import search

results = search("cats", limit=5)
for v in results:
    print(v["title"], "-", v["author"])
```

### CLI

```bash
ytapis search cats --limit 5
```

## API

### `search(query, limit=15)`

Returns `list[dict]` with keys: `id`, `title`, `author`, `thumbnail`, `fullUrl`, `embedUrl`.

## License

MIT
