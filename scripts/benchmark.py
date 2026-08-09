import time
from ytapis import search, get_video
from ytapis.core import search_trending


def fmt(n: float) -> str:
    return f"{n:.1f}"


def pad(s: str, length: int) -> str:
    return s.ljust(length)


def render_table(rows: list[dict]) -> None:
    cols = ["Function", "Limit", "Time (ms)", "Results"]
    widths = [len(c) for c in cols]
    for row in rows:
        for i, c in enumerate(cols):
            widths[i] = max(widths[i], len(str(row[c])))
    sep = "+" + "+".join("-" * (w + 2) for w in widths) + "+"
    print(sep)
    header = "| " + " | ".join(pad(c, widths[i]) for i, c in enumerate(cols)) + " |"
    print(header)
    print(sep)
    for row in rows:
        line = "| " + " | ".join(pad(str(row[c]), widths[i]) for i, c in enumerate(cols)) + " |"
        print(line)
    print(sep)


def main() -> None:
    rows: list[dict] = []

    for limit in [5, 10, 20, 50]:
        try:
            t0 = time.perf_counter()
            results = search("cats", limit=limit)
            elapsed = (time.perf_counter() - t0) * 1000
            rows.append({"Function": "search", "Limit": str(limit), "Time (ms)": fmt(elapsed), "Results": str(len(results))})
        except Exception as e:
            rows.append({"Function": "search", "Limit": str(limit), "Time (ms)": "ERR", "Results": str(e)[:50]})

    for limit in [10]:
        try:
            t0 = time.perf_counter()
            results = search_trending(limit=limit)
            elapsed = (time.perf_counter() - t0) * 1000
            rows.append({"Function": "search_trending", "Limit": str(limit), "Time (ms)": fmt(elapsed), "Results": str(len(results))})
        except Exception as e:
            rows.append({"Function": "search_trending", "Limit": str(limit), "Time (ms)": "ERR", "Results": str(e)[:50]})

    try:
        t0 = time.perf_counter()
        video = get_video("dQw4w9WgXcQ")
        elapsed = (time.perf_counter() - t0) * 1000
        rows.append({"Function": "get_video", "Limit": "dQw4w9WgXcQ", "Time (ms)": fmt(elapsed), "Results": video.title})
    except Exception as e:
        rows.append({"Function": "get_video", "Limit": "dQw4w9WgXcQ", "Time (ms)": "ERR", "Results": str(e)[:50]})

    render_table(rows)


if __name__ == "__main__":
    main()
