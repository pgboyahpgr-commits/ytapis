# ytapis-cli

CLI tool to search YouTube and get video metadata right from your terminal &mdash; **no API key required**.

Part of the [ytapis](https://github.com/pgboyahpgr-commits/ytapis) monorepo. Built and managed by [geethudinoyt](https://github.com/geethudinoyt).

## Usage

```bash
# without installing
npx ytapis search cats --limit 5

# or install globally
npm i -g ytapis-cli
ytapis search cats --limit 5
```

## Options

| Flag | Description |
|------|-------------|
| `--limit`, `-l` | Maximum results (default: 15) |
| `--json` | Output raw JSON |

## License

MIT
