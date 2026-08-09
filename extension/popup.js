const API_BASE = 'https://ytapis.djalokyt27.workers.dev';
const searchInput = document.getElementById('search-input');
const searchBtn = document.getElementById('search-btn');
const resultsContainer = document.getElementById('results-container');

function formatNumber(n) {
  if (!n && n !== 0) return '';
  if (typeof n === 'string') return n;
  if (n >= 1e9) return (n / 1e9).toFixed(1) + 'B';
  if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M';
  if (n >= 1e3) return (n / 1e3).toFixed(1) + 'K';
  return n.toString();
}

function timeAgo(dateStr) {
  if (!dateStr) return '';
  const d = new Date(dateStr);
  const now = new Date();
  const diff = Math.floor((now - d) / 1000);
  if (diff < 60) return 'just now';
  if (diff < 3600) return Math.floor(diff / 60) + 'm ago';
  if (diff < 86400) return Math.floor(diff / 3600) + 'h ago';
  if (diff < 2592000) return Math.floor(diff / 86400) + 'd ago';
  if (diff < 31536000) return Math.floor(diff / 2592000) + 'mo ago';
  return Math.floor(diff / 31536000) + 'y ago';
}

function formatDuration(seconds) {
  if (!seconds) return '';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  return `${m}:${String(s).padStart(2, '0')}`;
}

function showLoading() {
  resultsContainer.innerHTML = `
    <div class="popup-loading">
      <div class="ytp-shimmer" style="width:100%;height:60px;margin-bottom:8px;"></div>
      <div class="ytp-shimmer" style="width:100%;height:60px;margin-bottom:8px;"></div>
      <div class="ytp-shimmer" style="width:100%;height:60px;margin-bottom:8px;"></div>
      <div class="ytp-shimmer" style="width:100%;height:60px;margin-bottom:8px;"></div>
      <div class="ytp-shimmer" style="width:100%;height:60px;"></div>
    </div>
  `;
}

function showError(msg) {
  resultsContainer.innerHTML = `<div class="popup-error">${msg}</div>`;
}

function showEmpty() {
  resultsContainer.innerHTML = `
    <div class="popup-empty">
      <div class="popup-empty-icon">📭</div>
      <div>No results found</div>
    </div>
  `;
}

function renderResults(videos) {
  if (!videos || !videos.length) {
    showEmpty();
    return;
  }
  const top5 = videos.slice(0, 5);
  resultsContainer.innerHTML = top5
    .map(
      (v) => {
        const vid = v.id || v.video_id || '';
        const url = vid ? `https://www.youtube.com/watch?v=${vid}` : '#';
        return `
    <div class="popup-result" data-url="${url}">
      ${v.thumbnail || (Array.isArray(v.thumbnails) ? v.thumbnails[0]?.url : '') ? `<img class="popup-result-thumb" src="${v.thumbnail || v.thumbnails[0]?.url}" onerror="this.style.display='none'">` : ''}
      <div class="popup-result-info">
        <div class="popup-result-title">${v.title || 'Unknown'}</div>
        <div class="popup-result-channel">${v.channel || v.author || v.uploader || ''}</div>
        <div class="popup-result-meta">
          ${v.views || v.view_count ? formatNumber(v.views || v.view_count) + ' views' : ''}
          ${v.duration || v.length_seconds ? ' · ' + formatDuration(v.duration || v.length_seconds) : ''}
          ${v.publish_date || v.upload_date ? ' · ' + timeAgo(v.publish_date || v.upload_date) : ''}
        </div>
      </div>
    </div>`;
      }
    )
    .join('');

  resultsContainer.querySelectorAll('.popup-result').forEach((el) => {
    el.addEventListener('click', () => {
      const url = el.dataset.url;
      if (url && url !== '#') {
        chrome.tabs.create({ url });
      }
    });
  });
}

async function doSearch() {
  const query = searchInput.value.trim();
  if (!query) return;

  showLoading();
  searchBtn.disabled = true;

  try {
    const res = await fetch(`${API_BASE}/search?q=${encodeURIComponent(query)}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    const videos = Array.isArray(data) ? data : data.videos || data.results || data.items || [];
    renderResults(videos);
  } catch (err) {
    showError('Search failed. Check your connection.');
  } finally {
    searchBtn.disabled = false;
  }
}

searchBtn.addEventListener('click', doSearch);
searchInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') doSearch();
});
