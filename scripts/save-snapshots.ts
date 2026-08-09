import { search, searchTrending, getComments, getRelatedVideos, getVideo } from 'ytapis-core';
import { writeFileSync, mkdirSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const snapshotsDir = resolve(__dirname, '..', 'tests', '__snapshots__');
const VIDEO_ID = 'dQw4w9WgXcQ';

mkdirSync(snapshotsDir, { recursive: true });

function save(name: string, data: unknown) {
  const path = resolve(snapshotsDir, name);
  writeFileSync(path, JSON.stringify(data, null, 2), 'utf-8');
  console.log(`  saved ${name}`);
}

async function main() {
  console.log('Fetching live data from YouTube...\n');

  try {
    const searchRes = await search('cats', { limit: 5 });
    save('search_cats.json', searchRes);
    console.log(`  search("cats", 5) -> ${searchRes.results.length} results`);
  } catch (e: any) {
    console.error(`  search failed: ${e.message}`);
  }

  try {
    const trending = await searchTrending({ limit: 5 });
    save('trending.json', trending);
    console.log(`  trending -> ${trending.results.length} results`);
  } catch (e: any) {
    console.error(`  trending failed: ${e.message}`);
  }

  try {
    const comments = await getComments(VIDEO_ID, { limit: 3 });
    save('comments.json', comments);
    console.log(`  comments("${VIDEO_ID}", 3) -> ${comments.comments.length} comments`);
  } catch (e: any) {
    console.error(`  comments failed: ${e.message}`);
  }

  try {
    const related = await getRelatedVideos(VIDEO_ID, { limit: 3 });
    save('related.json', related);
    console.log(`  related("${VIDEO_ID}", 3) -> ${related.length} videos`);
  } catch (e: any) {
    console.error(`  related failed: ${e.message}`);
  }

  try {
    const video = await getVideo(VIDEO_ID);
    save('video.json', video);
    console.log(`  video("${VIDEO_ID}") -> ${video.title}`);
  } catch (e: any) {
    console.error(`  video failed: ${e.message}`);
  }

  console.log('\nDone.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
