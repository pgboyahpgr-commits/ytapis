# ytapis/go &mdash; Go

Search YouTube and get video metadata &mdash; **no API key required**.

Part of the [ytapis](https://github.com/pgboyahpgr-commits/ytapis) monorepo. Built and managed by [geethudinoyt](https://github.com/geethudinoyt).

## Install

```bash
go get github.com/pgboyahpgr-commits/ytapis/go
```

## Usage

```go
import "github.com/pgboyahpgr-commits/ytapis/go"

results, err := ytapi.Search("cats", 5)
if err != nil {
  log.Fatal(err)
}
for _, v := range results {
  fmt.Println(v.Title, "-", v.Author)
}
```

## API

### `Search(query string, limit ...int) ([]VideoResult, error)`

### `SearchJSON(query string, limit ...int) (string, error)`

Returns JSON string of results.

## License

MIT
