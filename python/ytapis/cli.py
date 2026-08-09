import argparse
import json
import sys
from .core import search, search_dicts

VERSION = "1.0.0"


def main():
    parser = argparse.ArgumentParser(description="Search YouTube and get video metadata")
    parser.add_argument("query", nargs="+", help="Search query")
    parser.add_argument("--limit", "-l", type=int, default=15, help="Max results (default 15)")
    parser.add_argument("--output", "-o", type=str, help="Write results to file")
    parser.add_argument("--version", "-v", action="store_true", help="Show version")
    args = parser.parse_args()

    if args.version:
        print(f"ytapis v{VERSION}")
        return

    query = " ".join(args.query)
    try:
        results = search_dicts(query, limit=args.limit)
        output = json.dumps(results, indent=2)
        if args.output:
            with open(args.output, "w") as f:
                f.write(output)
            print(f"Results written to {args.output}", file=sys.stderr)
        else:
            print(output)
    except Exception as e:
        print(f"Search failed: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
