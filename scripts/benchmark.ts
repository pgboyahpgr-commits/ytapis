import { search, getVideo, searchTrending } from 'ytapis-core';

interface BenchmarkRow {
  Function: string;
  Limit: string;
  'Time (ms)': string;
  Results: string;
}

function fmt(n: number): string {
  return n.toFixed(1);
}

function pad(s: string, len: number): string {
  return s.padEnd(len);
}

function table(rows: BenchmarkRow[]) {
  const cols = ['Function', 'Limit', 'Time (ms)', 'Results'] as const;
  const widths = cols.map(c => Math.max(c.length, ...rows.map(r => String(r[c]).length)));
  const sep = '+' + widths.map(w => '-'.repeat(w + 2)).join('+') + '+';

  console.log(sep);
  const header = '| ' + cols.map((c, i) => pad(c, widths[i])).join(' | ') + ' |';
  console.log(header);
  console.log(sep);
  for (const row of rows) {
    const line = '| ' + cols.map((c, i) => pad(String(row[c]), widths[i])).join(' | ') + ' |';
    console.log(line);
  }
  console.log(sep);
}

async function time<T>(fn: () => Promise<T>): Promise<[number, T]> {
  const start = performance.now();
  const result = await fn();
  const elapsed = performance.now() - start;
  return [elapsed, result];
}

async function main() {
  const rows: BenchmarkRow[] = [];
  const limits = [5, 10, 20, 50];

  for (const limit of limits) {
    try {
      const [elapsed, res] = await time(() => search('cats', { limit }));
      rows.push({ Function: 'search', Limit: String(limit), 'Time (ms)': fmt(elapsed), Results: String(res.results.length) });
    } catch (e: any) {
      rows.push({ Function: 'search', Limit: String(limit), 'Time (ms)': 'ERR', Results: e.message });
    }
  }

  const limitsTrending = [10];
  for (const limit of limitsTrending) {
    try {
      const [elapsed, res] = await time(() => searchTrending({ limit }));
      rows.push({ Function: 'searchTrending', Limit: String(limit), 'Time (ms)': fmt(elapsed), Results: String(res.results.length) });
    } catch (e: any) {
      rows.push({ Function: 'searchTrending', Limit: String(limit), 'Time (ms)': 'ERR', Results: e.message });
    }
  }

  try {
    const [elapsed, res] = await time(() => getVideo('dQw4w9WgXcQ'));
    rows.push({ Function: 'getVideo', Limit: 'dQw4w9WgXcQ', 'Time (ms)': fmt(elapsed), Results: res.title });
  } catch (e: any) {
    rows.push({ Function: 'getVideo', Limit: 'dQw4w9WgXcQ', 'Time (ms)': 'ERR', Results: e.message });
  }

  table(rows);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
