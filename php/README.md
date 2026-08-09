# Ytapis (PHP)

YouTube search engine for PHP 8.1+. Parses `ytInitialData` for rich video metadata with oEmbed fallback and InnerTube pagination. Zero dependencies beyond PHP extensions.

## Install

```bash
composer require geethudinoyt/ytapis
```

## Usage

```php
use GeethuDino\Ytapis\Ytapis;

// Search
$response = Ytapis::search('rick astley', 10);
foreach ($response['results'] as $video) {
    echo $video->title . ' (' . $video->duration . ')' . PHP_EOL;
    echo $video->viewCount . PHP_EOL;
    echo $video->thumbnail . PHP_EOL;
    print_r($video->toArray());
}

// Paginate
if ($response['continuation']) {
    $page2 = Ytapis::searchContinue(
        $response['continuation'],
        10,
        $response['apiKey'],
        $response['context']
    );
    foreach ($page2['results'] as $video) {
        echo $video->title . PHP_EOL;
    }
}

// Single video
$video = Ytapis::getVideo('dQw4w9WgXcQ');
echo $video->title;       // Rick Astley - Never Gonna Give You Up
echo $video->author;      // Rick Astley
echo $video->duration;    // 3:33
echo $video->viewCount;   // 1.5B views
```

## VideoResult properties

| Property | Type | Description |
|---|---|---|
| `id` | string | Video ID (11 chars) |
| `title` | string | Video title |
| `author` | string | Channel name |
| `channelUrl` | string | Channel URL |
| `thumbnail` | string | Best thumbnail URL |
| `thumbnails` | array | All thumbnails (url, width, height) |
| `fullUrl` | string | youtube.com/watch?v= link |
| `embedUrl` | string | youtube.com/embed/ link |
| `duration` | string | Formatted e.g. "12:34" |
| `durationSeconds` | int | Total seconds |
| `viewCount` | string | Formatted e.g. "1.2M views" |
| `viewCountRaw` | int | Raw number |
| `publishedTime` | string | "2 days ago" etc. |
| `description` | string | Snippet text |
| `channelAvatar` | string | Channel icon URL |
| `isLive` | bool | Currently streaming |
| `isUpcoming` | bool | Scheduled stream |
| `isVerified` | bool | Verified channel |

`toArray()` converts to an associative array of all 18 properties.
