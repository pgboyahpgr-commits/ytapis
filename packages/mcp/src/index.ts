#!/usr/bin/env node
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { search, getVideo, searchTrending, searchChannel, searchPlaylist } from 'ytapis-core';

const server = new Server(
  { name: 'ytapis-mcp', version: '1.0.0' },
  { capabilities: { tools: {} } },
);

function formatResult(r: Record<string, unknown>) {
  return [
    `**${r.title}** by ${r.author}`,
    `  URL: ${r.fullUrl}`,
    `  Thumbnail: ${r.thumbnail}`,
    `  Duration: ${r.duration ?? 'N/A'}`,
    `  Views: ${r.viewCount ?? 'N/A'}`,
    `  Published: ${r.publishedTime ?? 'N/A'}`,
    r.description ? `  Description: ${(r.description as string).substring(0, 120)}...` : null,
    r.channelAvatar ? `  Channel Avatar: ${r.channelAvatar}` : null,
    `  Live: ${r.isLive ? 'Yes' : 'No'}`,
    `  Verified: ${r.isVerified ? 'Yes' : 'No'}`,
  ].filter(Boolean).join('\n');
}

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'search_youtube',
      description: 'Search YouTube videos and return metadata (title, author, thumbnail, URL)',
      inputSchema: {
        type: 'object',
        properties: {
          query: { type: 'string', description: 'Search query' },
          limit: { type: 'number', description: 'Max results (default 15, max 50)', default: 15 },
        },
        required: ['query'],
      },
    },
    {
      name: 'get_video_info',
      description: 'Get metadata for a single YouTube video by its ID',
      inputSchema: {
        type: 'object',
        properties: {
          video_id: { type: 'string', description: 'YouTube video ID (11 characters)' },
        },
        required: ['video_id'],
      },
    },
    {
      name: 'search_trending',
      description: 'Search trending YouTube videos',
      inputSchema: {
        type: 'object',
        properties: {
          limit: { type: 'number', description: 'Max results (default 15, max 50)', default: 15 },
        },
      },
    },
    {
      name: 'search_channel',
      description: "Search a channel's videos by channel ID",
      inputSchema: {
        type: 'object',
        properties: {
          channel_id: { type: 'string', description: 'YouTube channel ID' },
          limit: { type: 'number', description: 'Max results (default 15, max 50)', default: 15 },
        },
        required: ['channel_id'],
      },
    },
    {
      name: 'search_playlist',
      description: 'Get videos from a YouTube playlist',
      inputSchema: {
        type: 'object',
        properties: {
          playlist_id: { type: 'string', description: 'YouTube playlist ID' },
          limit: { type: 'number', description: 'Max results (default 15, max 50)', default: 15 },
        },
        required: ['playlist_id'],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name } = request.params;

  if (name === 'search_youtube') {
    const { query, limit } = request.params.arguments as { query: string; limit?: number };
    const results = await search(query, { limit: limit || 15 });
    const text = results.results.length === 0
      ? `No results found for "${query}".`
      : `Found ${results.results.length} result(s) for "${query}":\n\n${results.results
          .map((r) => formatResult(r))
          .join('\n\n')}`;
    return {
      content: [
        { type: 'text', text },
        { type: 'text', text: JSON.stringify(results.results, null, 2) },
      ],
    };
  }

  if (name === 'get_video_info') {
    const { video_id } = request.params.arguments as { video_id: string };
    const result = await getVideo(video_id);
    const text = formatResult(result);
    return {
      content: [
        { type: 'text', text },
        { type: 'text', text: JSON.stringify(result, null, 2) },
      ],
    };
  }

  if (name === 'search_trending') {
    const { limit } = (request.params.arguments || {}) as { limit?: number };
    const results = await searchTrending({ limit: limit || 15 });
    const text = results.results.length === 0
      ? 'No trending results found.'
      : `Found ${results.results.length} trending result(s):\n\n${results.results
          .map((r) => formatResult(r))
          .join('\n\n')}`;
    return {
      content: [
        { type: 'text', text },
        { type: 'text', text: JSON.stringify(results.results, null, 2) },
      ],
    };
  }

  if (name === 'search_channel') {
    const { channel_id, limit } = request.params.arguments as { channel_id: string; limit?: number };
    const results = await searchChannel(channel_id, { limit: limit || 15 });
    const text = results.results.length === 0
      ? `No videos found for channel "${channel_id}".`
      : `Found ${results.results.length} video(s) for channel "${channel_id}":\n\n${results.results
          .map((r) => formatResult(r))
          .join('\n\n')}`;
    return {
      content: [
        { type: 'text', text },
        { type: 'text', text: JSON.stringify(results.results, null, 2) },
      ],
    };
  }

  if (name === 'search_playlist') {
    const { playlist_id, limit } = request.params.arguments as { playlist_id: string; limit?: number };
    const results = await searchPlaylist(playlist_id, { limit: limit || 15 });
    const text = results.results.length === 0
      ? `No videos found for playlist "${playlist_id}".`
      : `Found ${results.results.length} video(s) for playlist "${playlist_id}":\n\n${results.results
          .map((r) => formatResult(r))
          .join('\n\n')}`;
    return {
      content: [
        { type: 'text', text },
        { type: 'text', text: JSON.stringify(results.results, null, 2) },
      ],
    };
  }

  throw new Error(`Unknown tool: ${request.params.name}`);
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch(console.error);
