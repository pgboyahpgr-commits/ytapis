#!/usr/bin/env node
import { search, searchTrending, searchChannel, searchPlaylist, getVideo } from 'ytapis-core';
import * as fs from 'fs';

const VERSION = '1.0.0';

function showHelp() {
  console.log(`ytapis-cli v${VERSION}
  Search YouTube and get video metadata — no API key required.

Usage:
  ytapis search <query> [options]
  ytapis s <query> [options]
  ytapis trending [options]
  ytapis channel <id> [options]
  ytapis playlist <id> [options]
  ytapis video <id>

Options:
  --limit, -l  <N>   Max results (default 15)
  --format, -f       Output format: json, table, csv (default json)
  --output, -o       Write results to file
  --json             Output raw JSON (alias for --format json)
  --version, -v      Show version
  --help, -h         Show this help
`);
}

interface ResultItem {
  id: string;
  title: string;
  author: string;
  thumbnail: string;
  fullUrl: string;
  embedUrl: string;
  duration?: string;
  viewCount?: number;
  publishedTime?: string;
  description?: string;
  channelAvatar?: string;
  isLive?: boolean;
  isVerified?: boolean;
}

function formatResults(results: ResultItem[], format: string): string {
  switch (format) {
    case 'table':
      if (results.length === 0) return 'No results found.';
      if (results.length === 1) {
        const r = results[0];
        return [
          `Title:       ${r.title}`,
          `Author:      ${r.author}`,
          `ID:          ${r.id}`,
          `URL:         ${r.fullUrl}`,
          `Thumbnail:   ${r.thumbnail}`,
          `Embed:       ${r.embedUrl}`,
          `Duration:    ${r.duration ?? 'N/A'}`,
          `Views:       ${r.viewCount ?? 'N/A'}`,
          `Published:   ${r.publishedTime ?? 'N/A'}`,
          `Description: ${r.description ?? 'N/A'}`,
          `Live:        ${r.isLive ? 'Yes' : 'No'}`,
          `Verified:    ${r.isVerified ? 'Yes' : 'No'}`,
          r.channelAvatar ? `Avatar:      ${r.channelAvatar}` : null,
        ].filter(Boolean).join('\n');
      }
      return [
        'ID           TITLE                                     AUTHOR',
        '--           -----                                     ------',
        ...results.map((r) =>
          `${r.id.padEnd(12)} ${r.title.substring(0, 40).padEnd(40)} ${r.author}`,
        ),
      ].join('\n');
    case 'csv':
      return [
        'id,title,author,thumbnail,fullUrl,embedUrl,duration,viewCount,publishedTime,description,channelAvatar,isLive,isVerified',
        ...results.map((r) =>
          [
            `"${r.id}"`,
            `"${(r.title || '').replace(/"/g, '""')}"`,
            `"${(r.author || '').replace(/"/g, '""')}"`,
            `"${r.thumbnail || ''}"`,
            `"${r.fullUrl || ''}"`,
            `"${r.embedUrl || ''}"`,
            `"${r.duration || ''}"`,
            `"${r.viewCount ?? ''}"`,
            `"${(r.publishedTime || '').replace(/"/g, '""')}"`,
            `"${(r.description || '').replace(/"/g, '""')}"`,
            `"${r.channelAvatar || ''}"`,
            `"${r.isLive ?? false}"`,
            `"${r.isVerified ?? false}"`,
          ].join(','),
        ),
      ].join('\n');
    case 'json':
    default:
      return JSON.stringify(results, null, 2);
  }
}

interface ParsedArgs {
  limit: number;
  format: string;
  outputFile: string | null;
  positional: string[];
}

function parseArgs(raw: string[]): ParsedArgs {
  const opts: ParsedArgs = { limit: 15, format: 'json', outputFile: null, positional: [] };
  for (let i = 0; i < raw.length; i++) {
    const arg = raw[i];
    if ((arg === '--limit' || arg === '-l') && i + 1 < raw.length) {
      opts.limit = parseInt(raw[++i], 10) || 15;
    } else if ((arg === '--format' || arg === '-f') && i + 1 < raw.length) {
      opts.format = raw[++i];
    } else if ((arg === '--output' || arg === '-o') && i + 1 < raw.length) {
      opts.outputFile = raw[++i];
    } else if (arg === '--json') {
      opts.format = 'json';
    } else if (arg === '--version' || arg === '-v') {
      console.log(`ytapis-cli v${VERSION}`);
      process.exit(0);
    } else if (arg === '--help' || arg === '-h') {
      showHelp();
      process.exit(0);
    } else if (!arg.startsWith('--') && !arg.startsWith('-')) {
      opts.positional.push(arg);
    }
  }
  return opts;
}

function writeOutput(output: string, file: string | null) {
  if (file) {
    fs.writeFileSync(file, output, 'utf-8');
    console.error(`Results written to ${file}`);
  } else {
    console.log(output);
  }
}

async function main() {
  const args = process.argv.slice(2);
  const cmd = args[0];

  if (!cmd || cmd === '--help' || cmd === '-h') {
    showHelp();
    process.exit(cmd === '--help' || cmd === '-h' ? 0 : 1);
  }

  if (cmd === '--version' || cmd === '-v') {
    console.log(`ytapis-cli v${VERSION}`);
    process.exit(0);
  }

  const validCommands = ['search', 's', 'trending', 'channel', 'playlist', 'video'];
  if (!validCommands.includes(cmd)) {
    console.error(`Unknown command: ${cmd}`);
    showHelp();
    process.exit(1);
  }

  const rest = parseArgs(args.slice(1));

  try {
    if (cmd === 'search' || cmd === 's') {
      if (rest.positional.length === 0) {
        console.error('Error: search query required');
        process.exit(1);
      }
      const query = rest.positional.join(' ');
      const { results } = await search(query, { limit: rest.limit });
      writeOutput(formatResults(results, rest.format), rest.outputFile);
    } else if (cmd === 'trending') {
      const { results } = await searchTrending({ limit: rest.limit });
      writeOutput(formatResults(results, rest.format), rest.outputFile);
    } else if (cmd === 'channel') {
      if (rest.positional.length === 0) {
        console.error('Error: channel ID required');
        process.exit(1);
      }
      const { results } = await searchChannel(rest.positional[0], { limit: rest.limit });
      writeOutput(formatResults(results, rest.format), rest.outputFile);
    } else if (cmd === 'playlist') {
      if (rest.positional.length === 0) {
        console.error('Error: playlist ID required');
        process.exit(1);
      }
      const { results } = await searchPlaylist(rest.positional[0], { limit: rest.limit });
      writeOutput(formatResults(results, rest.format), rest.outputFile);
    } else if (cmd === 'video') {
      if (rest.positional.length === 0) {
        console.error('Error: video ID required');
        process.exit(1);
      }
      const result = await getVideo(rest.positional[0]);
      writeOutput(formatResults([result], 'table'), rest.outputFile);
    }
  } catch (err) {
    console.error('Error:', (err as Error).message);
    process.exit(1);
  }
}

main();
