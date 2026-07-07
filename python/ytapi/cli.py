import argparse
import json
import sys
from .core import search


def main():
    parser = argparse.ArgumentParser(description="Search YouTube and get video metadata")
    parser.add_argument("query", nargs="+", help="Search query")
    parser.add_argument("--limit", type=int, default=15, help="Max results")
    args = parser.parse_args()

    query = " ".join(args.query)
    try:
        results = search(query, limit=args.limit)
        print(json.dumps(results, indent=2))
    except Exception as e:
        print(f"Search failed: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
