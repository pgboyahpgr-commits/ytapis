# ytapis-mcp

MCP (Model Context Protocol) server for YouTube search &mdash; lets AI assistants search YouTube without an API key.

Part of the [ytapis](https://github.com/pgboyahpgr-commits/ytapis) monorepo. Built and managed by [geethudinoyt](https://github.com/geethudinoyt).

## Usage

```bash
npx ytapis-mcp
```

### Configure with AI Assistants

**Claude Desktop** &mdash; add to `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "ytapis": {
      "command": "npx",
      "args": ["ytapis-mcp"]
    }
  }
}
```

**Cline / Continue / other MCP clients** &mdash; same config format.

## Available Tools

| Tool | Description |
|------|-------------|
| `search` | Search YouTube and return video metadata |

## License

MIT
