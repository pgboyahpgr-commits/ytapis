# ytapis Dashboard

A self-hosted analytics dashboard for YouTube search API usage. Built with vanilla HTML/CSS/JS and Chart.js.

![Dashboard preview showing stat cards, charts, and search tables on a dark YouTube-themed UI](screenshot.png)

## Quick Start

```bash
npm run dashboard
```

Dashboard opens at **http://localhost:4000**

## How It Integrates

Send search events from your app to the dashboard:

```bash
curl -X POST http://localhost:4000/api/event \
  -H "Content-Type: application/json" \
  -d '{"query":"cat videos","platform":"node","type":"search","channel_id":"UC123","ip":"192.168.1.1"}'
```

### Event Fields

| Field      | Type   | Description                          |
|-----------|--------|--------------------------------------|
| query     | string | Search query text                    |
| platform  | string | SDK used (node, go, python, etc.)    |
| type      | string | Event type: `search`, `trending`, `comment` |
| channel_id| string | Channel ID (optional)                |
| ip        | string | Client IP (optional)                 |
| timestamp | number | Unix ms (auto-set if omitted)        |

### Fetch Aggregated Stats

```bash
curl http://localhost:4000/api/analytics
```

Returns:

```json
{
  "total_searches": 1534,
  "trending_videos": 89,
  "channels_tracked": 42,
  "comments_fetched": 312,
  "top_queries": [{"query": "music", "count": 120}, ...],
  "last_24h_hits": [{"time": "14:00", "count": 5}, ...],
  "platform_breakdown": {"node": 600, "python": 400, "go": 300}
}
```

## Features

- Dark YouTube-themed UI
- 4 summary stat cards
- Searches over time (line chart, last 24h)
- Top 10 queries (bar chart)
- Platform/language breakdown (pie chart)
- Recent searches table (scrollable, 10 rows)
- Top videos table with thumbnails
- Date range filter (Today, This Week, This Month)
- Fully responsive / mobile-friendly
- Zero dependencies on the frontend (Chart.js via CDN)
- Zero dependencies on the backend (built-in Node.js modules only)
