# ytapis - YouTube Metadata Extension

A browser extension that shows YouTube video metadata, comments, and related videos via right-click context menu.

## Install (Chrome / Edge / Brave)

1. Open `chrome://extensions/` in your browser.
2. Enable **Developer mode** (toggle in top-right).
3. Click **Load unpacked**.
4. Select the `extension/` folder.
5. The ytapis icon appears in your toolbar.

## Install (Firefox)

1. Open `about:debugging#/runtime/this-firefox`.
2. Click **Load Temporary Add-on...**
3. Select `manifest.json` from the `extension/` folder.
4. For permanent install, use `about:addons` → gear → **Install Add-on From File...** (requires `.xpi` packaging or Mozilla signing for distribution).

## Usage

- **Right-click a video link** on YouTube → *Get Video Metadata*
- **Right-click any watch page** → *Get Comments* or *Get Related Videos*
- **Click the extension icon** → Search YouTube directly from the popup

## Backend

Data is fetched from the Cloudflare Worker API:
- `https://ytapis.djalokyt27.workers.dev/video/{id}` — metadata
- `https://ytapis.djalokyt27.workers.dev/video/{id}/comments` — comments
- `https://ytapis.djalokyt27.workers.dev/video/{id}/related` — related videos
- `https://ytapis.djalokyt27.workers.dev/search?q={query}` — search

## Files

| File | Purpose |
|---|---|
| `manifest.json` | Extension manifest (MV3) |
| `background.js` | Service worker: context menus, badge |
| `content.js` | Floating panel with metadata/comments/related tabs |
| `popup.html` | Extension popup UI |
| `popup.js` | Search logic for popup |
| `icons/` | Extension icons (16, 48, 128, 512) |
