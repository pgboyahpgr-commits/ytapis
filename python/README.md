# ytapi — Python

Search YouTube and get video metadata. No API key required.

## Install

```bash
pip install ytapi
```

## Usage

```python
from ytapi import search

results = search("cats", limit=5)
for v in results:
    print(v["title"], "-", v["author"])
```

### CLI

```bash
ytapi search cats --limit 5
```
