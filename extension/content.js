(function () {
  if (document.getElementById('ytapis-panel')) return;

  const videoId = window.__ytapis_videoId;
  const action = window.__ytapis_action || 'metadata';
  const API_BASE = window.__ytapis_apiBase || 'https://ytapis.djalokyt27.workers.dev';

  if (!videoId) return;

  let activeTab = action === 'comments' ? 'comments' : action === 'related' ? 'related' : 'metadata';
  let videoData = null;
  let commentsData = [];
  let relatedData = [];

  const panel = document.createElement('div');
  panel.id = 'ytapis-panel';
  panel.innerHTML = `
    <style>
      #ytapis-panel, #ytapis-panel * { box-sizing: border-box; margin: 0; padding: 0; }
      #ytapis-panel {
        position: fixed; top: 80px; right: 20px; width: 440px; max-height: 85vh;
        background: #1e1e1e; border: 1px solid #333; border-radius: 12px;
        color: #fff; font-family: 'Roboto', Arial, sans-serif; font-size: 13px;
        z-index: 2147483646; box-shadow: 0 8px 40px rgba(0,0,0,0.7);
        display: flex; flex-direction: column; resize: both; overflow: hidden;
        min-width: 320px; min-height: 300px;
      }
      #ytapis-panel .ytp-header {
        display: flex; align-items: center; padding: 10px 14px;
        background: #111; border-radius: 12px 12px 0 0; cursor: move;
        user-select: none; flex-shrink: 0;
      }
      #ytapis-panel .ytp-logo { color: #ff0000; font-weight: 900; font-size: 16px; margin-right: 10px; }
      #ytapis-panel .ytp-title { font-weight: 600; font-size: 14px; flex: 1; }
      #ytapis-panel .ytp-close {
        background: none; border: none; color: #aaa; font-size: 20px; cursor: pointer;
        padding: 0 4px; line-height: 1; transition: color 0.15s;
      }
      #ytapis-panel .ytp-close:hover { color: #fff; }
      #ytapis-panel .ytp-tabs {
        display: flex; border-bottom: 1px solid #333; flex-shrink: 0;
      }
      #ytapis-panel .ytp-tab {
        flex: 1; padding: 10px; text-align: center; cursor: pointer; font-size: 13px;
        font-weight: 500; color: #aaa; background: transparent; border: none;
        border-bottom: 2px solid transparent; transition: all 0.15s;
      }
      #ytapis-panel .ytp-tab:hover { background: #2a2a2a; }
      #ytapis-panel .ytp-tab.active { color: #ff4444; border-bottom-color: #ff4444; }
      #ytapis-panel .ytp-body {
        flex: 1; overflow-y: auto; padding: 14px; display: none;
        scrollbar-width: thin; scrollbar-color: #555 #1e1e1e;
      }
      #ytapis-panel .ytp-body.active { display: block; }
      #ytapis-panel .ytp-body::-webkit-scrollbar { width: 6px; }
      #ytapis-panel .ytp-body::-webkit-scrollbar-track { background: #1e1e1e; }
      #ytapis-panel .ytp-body::-webkit-scrollbar-thumb { background: #555; border-radius: 3px; }
      #ytapis-panel .ytp-thumb {
        width: 100%; border-radius: 8px; margin-bottom: 12px; aspect-ratio: 16/9;
        object-fit: cover; background: #2a2a2a;
      }
      #ytapis-panel .ytp-video-title { font-size: 16px; font-weight: 600; margin-bottom: 8px; line-height: 1.3; }
      #ytapis-panel .ytp-channel-row { display: flex; align-items: center; gap: 8px; margin-bottom: 10px; }
      #ytapis-panel .ytp-channel-avatar {
        width: 32px; height: 32px; border-radius: 50%; background: #444;
      }
      #ytapis-panel .ytp-channel-name { font-weight: 500; color: #ddd; }
      #ytapis-panel .ytp-meta-row {
        display: flex; gap: 12px; color: #aaa; font-size: 12px; margin-bottom: 8px; flex-wrap: wrap;
      }
      #ytapis-panel .ytp-meta-row span { white-space: nowrap; }
      #ytapis-panel .ytp-desc {
        background: #151515; border-radius: 8px; padding: 10px 12px; margin-top: 8px;
        font-size: 12px; color: #bbb; line-height: 1.5; white-space: pre-wrap;
        max-height: 140px; overflow-y: auto;
      }
      #ytapis-panel .ytp-comment {
        display: flex; gap: 10px; padding: 10px 0; border-bottom: 1px solid #2a2a2a;
      }
      #ytapis-panel .ytp-comment-avatar {
        width: 36px; height: 36px; border-radius: 50%; background: #444; flex-shrink: 0;
      }
      #ytapis-panel .ytp-comment-body { flex: 1; min-width: 0; }
      #ytapis-panel .ytp-comment-author { font-weight: 500; font-size: 12px; margin-bottom: 2px; }
      #ytapis-panel .ytp-comment-time { color: #888; font-size: 11px; margin-left: 6px; }
      #ytapis-panel .ytp-comment-text { font-size: 12px; color: #ddd; line-height: 1.4; word-break: break-word; }
      #ytapis-panel .ytp-comment-likes { color: #888; font-size: 11px; margin-top: 4px; }
      #ytapis-panel .ytp-related-card {
        display: flex; gap: 8px; padding: 8px 0; border-bottom: 1px solid #2a2a2a;
        cursor: pointer; transition: background 0.1s;
      }
      #ytapis-panel .ytp-related-card:hover { background: #252525; }
      #ytapis-panel .ytp-related-thumb {
        width: 140px; aspect-ratio: 16/9; object-fit: cover; border-radius: 6px;
        background: #2a2a2a; flex-shrink: 0;
      }
      #ytapis-panel .ytp-related-info { min-width: 0; }
      #ytapis-panel .ytp-related-title { font-size: 13px; font-weight: 500; line-height: 1.3; margin-bottom: 4px; }
      #ytapis-panel .ytp-related-channel { font-size: 11px; color: #aaa; }
      #ytapis-panel .ytp-related-views { font-size: 11px; color: #888; }
      #ytapis-panel .ytp-shimmer {
        background: linear-gradient(90deg, #2a2a2a 25%, #333 50%, #2a2a2a 75%);
        background-size: 200% 100%; animation: ytp-shimmer 1.5s infinite; border-radius: 4px;
      }
      @keyframes ytp-shimmer { 0% { background-position: 200% 0; } 100% { background-position: -200% 0; } }
      #ytapis-panel .ytp-error { color: #ff4444; text-align: center; padding: 20px; }
    </style>
    <div class="ytp-header" id="ytp-drag-handle">
      <span class="ytp-logo">▶ ytapis</span>
      <span class="ytp-title" id="ytp-panel-title">Loading...</span>
      <button class="ytp-close" id="ytp-close-btn">&times;</button>
    </div>
    <div class="ytp-tabs">
      <button class="ytp-tab" data-tab="metadata">Metadata</button>
      <button class="ytp-tab" data-tab="comments">Comments</button>
      <button class="ytp-tab" data-tab="related">Related</button>
    </div>
    <div class="ytp-body ytp-body-loading" id="ytp-body-metadata">
      <div class="ytp-shimmer" style="width:100%;height:200px;margin-bottom:12px;"></div>
      <div class="ytp-shimmer" style="width:80%;height:18px;margin-bottom:8px;"></div>
      <div class="ytp-shimmer" style="width:40%;height:14px;margin-bottom:12px;"></div>
      <div class="ytp-shimmer" style="width:100%;height:60px;"></div>
    </div>
    <div class="ytp-body" id="ytp-body-comments">
      <div class="ytp-shimmer" style="width:100%;height:60px;margin-bottom:10px;"></div>
      <div class="ytp-shimmer" style="width:100%;height:60px;margin-bottom:10px;"></div>
      <div class="ytp-shimmer" style="width:100%;height:60px;"></div>
    </div>
    <div class="ytp-body" id="ytp-body-related">
      <div class="ytp-shimmer" style="width:100%;height:70px;margin-bottom:8px;"></div>
      <div class="ytp-shimmer" style="width:100%;height:70px;margin-bottom:8px;"></div>
      <div class="ytp-shimmer" style="width:100%;height:70px;"></div>
    </div>
  `;

  document.body.appendChild(panel);

  const closeBtn = document.getElementById('ytp-close-btn');
  const tabs = panel.querySelectorAll('.ytp-tab');
  const bodyMeta = document.getElementById('ytp-body-metadata');
  const bodyComments = document.getElementById('ytp-body-comments');
  const bodyRelated = document.getElementById('ytp-body-related');
  const panelTitle = document.getElementById('ytp-panel-title');
  const dragHandle = document.getElementById('ytp-drag-handle');

  closeBtn.addEventListener('click', () => panel.remove());

  let isDragging = false;
  let dragStartX, dragStartY, panelStartLeft, panelStartTop;

  dragHandle.addEventListener('mousedown', (e) => {
    if (e.target.tagName === 'BUTTON') return;
    isDragging = true;
    dragStartX = e.clientX;
    dragStartY = e.clientY;
    const rect = panel.getBoundingClientRect();
    panelStartLeft = rect.left;
    panelStartTop = rect.top;
    panel.style.right = 'auto';
    panel.style.left = panelStartLeft + 'px';
    panel.style.top = panelStartTop + 'px';
    e.preventDefault();
  });

  document.addEventListener('mousemove', (e) => {
    if (!isDragging) return;
    panel.style.left = (panelStartLeft + e.clientX - dragStartX) + 'px';
    panel.style.top = (panelStartTop + e.clientY - dragStartY) + 'px';
  });

  document.addEventListener('mouseup', () => {
    isDragging = false;
  });

  function switchTab(tabName) {
    activeTab = tabName;
    tabs.forEach((t) => t.classList.toggle('active', t.dataset.tab === tabName));
    bodyMeta.classList.toggle('active', tabName === 'metadata');
    bodyComments.classList.toggle('active', tabName === 'comments');
    bodyRelated.classList.toggle('active', tabName === 'related');
  }

  function formatNumber(n) {
    if (!n && n !== 0) return 'N/A';
    if (typeof n === 'string') return n;
    if (n >= 1e9) return (n / 1e9).toFixed(1) + 'B';
    if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M';
    if (n >= 1e3) return (n / 1e3).toFixed(1) + 'K';
    return n.toString();
  }

  function formatDuration(seconds) {
    if (!seconds) return 'N/A';
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
    return `${m}:${String(s).padStart(2, '0')}`;
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

  async function fetchData() {
    const endpoints = {
      metadata: `${API_BASE}/video/${videoId}`,
      comments: `${API_BASE}/video/${videoId}/comments`,
      related: `${API_BASE}/video/${videoId}/related`,
    };

    const promises = [
      fetch(endpoints.metadata).then((r) => r.json()).catch(() => null),
      fetch(endpoints.comments).then((r) => r.json()).catch(() => null),
      fetch(endpoints.related).then((r) => r.json()).catch(() => null),
    ];

    const [meta, comments, related] = await Promise.all(promises);
    videoData = meta;
    commentsData = Array.isArray(comments) ? comments : [];
    relatedData = Array.isArray(related) ? related : [];

    renderMetadata();
    renderComments();
    renderRelated();
    switchTab(activeTab);
  }

  function renderMetadata() {
    if (!videoData) {
      bodyMeta.innerHTML = '<div class="ytp-error">Failed to load metadata</div>';
      return;
    }
    const v = videoData;
    panelTitle.textContent = (v.title || 'Video').slice(0, 40) + (v.title && v.title.length > 40 ? '...' : '');

    bodyMeta.innerHTML = `
      ${v.thumbnail || v.thumbnails ? `<img class="ytp-thumb" src="${v.thumbnail || (Array.isArray(v.thumbnails) ? v.thumbnails[v.thumbnails.length - 1].url : '')}" alt="thumbnail" onerror="this.style.display='none'">` : ''}
      <div class="ytp-video-title">${v.title || 'Unknown Title'}</div>
      <div class="ytp-channel-row">
        ${v.channel_thumbnail || v.author_thumbnail ? `<img class="ytp-channel-avatar" src="${v.channel_thumbnail || v.author_thumbnail}" onerror="this.style.display='none'">` : ''}
        <span class="ytp-channel-name">${v.channel || v.author || v.uploader || 'Unknown Channel'}</span>
      </div>
      <div class="ytp-meta-row">
        <span>👁 ${formatNumber(v.views || v.view_count)} views</span>
        <span>⏱ ${formatDuration(v.duration || v.length_seconds)}</span>
        <span>📅 ${v.publish_date || v.upload_date || 'N/A'}</span>
        ${v.likes ? `<span>👍 ${formatNumber(v.likes)}</span>` : ''}
      </div>
      <div class="ytp-desc">${v.description || 'No description'}</div>
    `;
  }

  function renderComments() {
    if (!commentsData.length) {
      bodyComments.innerHTML = '<div style="color:#aaa;text-align:center;padding:20px;">No comments loaded</div>';
      return;
    }
    bodyComments.innerHTML = commentsData
      .map(
        (c) => `
      <div class="ytp-comment">
        ${c.author_thumbnail ? `<img class="ytp-comment-avatar" src="${c.author_thumbnail}" onerror="this.style.display='none'">` : ''}
        <div class="ytp-comment-body">
          <div>
            <span class="ytp-comment-author">${c.author || 'Unknown'}</span>
            <span class="ytp-comment-time">${timeAgo(c.timestamp || c.published)}</span>
          </div>
          <div class="ytp-comment-text">${c.text || c.comment || ''}</div>
          ${c.likes !== undefined ? `<div class="ytp-comment-likes">👍 ${formatNumber(c.likes)} likes</div>` : ''}
        </div>
      </div>`
      )
      .join('');
  }

  function renderRelated() {
    if (!relatedData.length) {
      bodyRelated.innerHTML = '<div style="color:#aaa;text-align:center;padding:20px;">No related videos loaded</div>';
      return;
    }
    bodyRelated.innerHTML = relatedData
      .map(
        (r) => {
          const vid = r.id || r.video_id || '';
          const url = vid ? `https://www.youtube.com/watch?v=${vid}` : '#';
          return `
      <div class="ytp-related-card" data-url="${url}">
        ${r.thumbnail || (Array.isArray(r.thumbnails) ? r.thumbnails[0]?.url : '') ? `<img class="ytp-related-thumb" src="${r.thumbnail || r.thumbnails[0]?.url}" onerror="this.style.display='none'">` : ''}
        <div class="ytp-related-info">
          <div class="ytp-related-title">${r.title || 'Unknown'}</div>
          <div class="ytp-related-channel">${r.channel || r.author || ''}</div>
          <div class="ytp-related-views">${formatNumber(r.views || r.view_count)} views</div>
        </div>
      </div>`;
        }
      )
      .join('');

    bodyRelated.querySelectorAll('.ytp-related-card').forEach((card) => {
      card.addEventListener('click', () => {
        const url = card.dataset.url;
        if (url && url !== '#') window.open(url, '_blank');
      });
    });
  }

  tabs.forEach((tab) => {
    tab.addEventListener('click', () => switchTab(tab.dataset.tab));
  });

  switchTab(activeTab);
  fetchData();
})();
