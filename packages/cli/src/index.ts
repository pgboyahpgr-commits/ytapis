#!/usr/bin/env node
import { search } from 'ytapis-core';

async function main() {
  const args = process.argv.slice(2);
  const cmd = args[0];

  if (cmd !== 'search' && cmd !== 's') {
    console.log('Usage: ytapi search <query> [--limit N]');
    console.log('       ytapi s <query> [--limit N]');
    process.exit(1);
  }

  const queryParts: string[] = [];
  let limit = 15;
  for (let i = 1; i < args.length; i++) {
    if (args[i] === '--limit' && i + 1 < args.length) {
      limit = parseInt(args[++i], 10) || 15;
    } else if (!args[i].startsWith('--')) {
      queryParts.push(args[i]);
    }
  }

  if (queryParts.length === 0) {
    console.error('Error: search query required');
    process.exit(1);
  }

  const query = queryParts.join(' ');

  try {
    const results = await search(query, { limit });
    console.log(JSON.stringify(results, null, 2));
  } catch (err) {
    console.error('Search failed:', (err as Error).message);
    process.exit(1);
  }
}

main();
