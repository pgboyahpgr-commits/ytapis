<?php

declare(strict_types=1);

namespace GeethuDino\Ytapis;

final class VideoResult
{
    public function __construct(
        public readonly string $id,
        public string $title = '',
        public string $author = '',
        public string $channelUrl = '',
        public string $thumbnail = '',
        public array $thumbnails = [],
        public string $fullUrl = '',
        public string $embedUrl = '',
        public string $duration = '',
        public int $durationSeconds = 0,
        public string $viewCount = '',
        public int $viewCountRaw = 0,
        public string $publishedTime = '',
        public string $description = '',
        public string $channelAvatar = '',
        public bool $isLive = false,
        public bool $isUpcoming = false,
        public bool $isVerified = false,
    ) {}

    /**
     * @return array{id: string, title: string, author: string, channelUrl: string, thumbnail: string, thumbnails: array, fullUrl: string, embedUrl: string, duration: string, durationSeconds: int, viewCount: string, viewCountRaw: int, publishedTime: string, description: string, channelAvatar: string, isLive: bool, isUpcoming: bool, isVerified: bool}
     */
    public function toArray(): array
    {
        return [
            'id' => $this->id,
            'title' => $this->title,
            'author' => $this->author,
            'channelUrl' => $this->channelUrl,
            'thumbnail' => $this->thumbnail,
            'thumbnails' => $this->thumbnails,
            'fullUrl' => $this->fullUrl,
            'embedUrl' => $this->embedUrl,
            'duration' => $this->duration,
            'durationSeconds' => $this->durationSeconds,
            'viewCount' => $this->viewCount,
            'viewCountRaw' => $this->viewCountRaw,
            'publishedTime' => $this->publishedTime,
            'description' => $this->description,
            'channelAvatar' => $this->channelAvatar,
            'isLive' => $this->isLive,
            'isUpcoming' => $this->isUpcoming,
            'isVerified' => $this->isVerified,
        ];
    }
}
