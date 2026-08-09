# Contributing to ytapis

## Development setup

```bash
# Clone the repository
git clone https://github.com/pgboyahpgr-commits/ytapis.git
cd ytapis

# Install dependencies
npm install

# Build all packages
npm run build

# Run tests
npm test
```

## Adding a new language

ytapis follows a consistent pattern across languages. To add support for a new language:

1. Copy the directory structure from an existing language (e.g. `go/` or `rust/`).
2. Implement the same public API surface:
   - `search(query, options?)` — returns search results with video metadata
   - `VideoResult` — object/dataclass with all standard fields
3. Use the same scraping strategy: parse YouTube's HTML search results, then enrich via oEmbed.
4. Add language-specific CI to `.github/workflows/`.
5. Update the packages table in `README.md`.

## Code style

### TypeScript
- Strict mode enabled. Use explicit types, avoid `any`.
- Run `npm run lint` before committing.

### Python
- Follow PEP 8. Use type hints on all public functions.
- Run `ruff check . && ruff format --check .` before committing.

### Go
- Follow standard Go conventions (`gofmt`, `golint`, `go vet`).
- Run `go vet ./...` before committing.

## Testing

All PRs must include tests for new functionality and pass existing tests. Run tests for any language you modify:

| Language | Test command |
|----------|-------------|
| TypeScript | `npm test` |
| Python | `pytest` |
| Go | `go test ./...` |

## Pull request process

1. Fork the repo and create a branch from `main`.
2. Make your changes, including tests and documentation updates.
3. Ensure all tests pass and lint is clean.
4. Open a PR against `main` using the pull request template.
5. A maintainer will review your PR. Address any feedback.
6. Once approved, your PR will be merged.
