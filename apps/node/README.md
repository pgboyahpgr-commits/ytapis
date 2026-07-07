# ytapis &mdash; Electron Desktop App

Native Windows GUI app for searching YouTube with embedded video playback. Built with Electron using the `ytapis-core` npm package.

Built and managed by [geethudinoyt](https://github.com/geethudinoyt).

## Features

- Search YouTube with text queries
- Browse results in a side panel
- Click any result to play the video **directly in the app** via embedded iframe
- Watch on YouTube or view thumbnail links

## Run from source

```bash
npm install
npm start
```

## Build .exe

Run `build.bat` or:

```bash
npx electron-builder --win portable
```

Output: `dist/ytapis-search-win32-x64/ytapis-search.exe` (approx 188 MB)

> Note: electron-builder may take several minutes and download Electron binaries on first run. Use `electron-packager` as a faster alternative:
> ```bash
> npx electron-packager . ytapis-search --platform=win32 --arch=x64 --out=dist --overwrite
> ```

## Download

Pre-built `.exe` available on the [Releases](https://github.com/pgboyahpgr-commits/ytapis/releases) page.

## License

MIT
