const API_BASE = 'https://ytapis.djalokyt27.workers.dev';

function getVideoId(url) {
  const patterns = [
    /[?&]v=([a-zA-Z0-9_-]{11})/,
    /youtu\.be\/([a-zA-Z0-9_-]{11})/,
    /\/embed\/([a-zA-Z0-9_-]{11})/,
    /\/v\/([a-zA-Z0-9_-]{11})/,
  ];
  for (const p of patterns) {
    const m = url.match(p);
    if (m) return m[1];
  }
  return null;
}

function isYouTube(tab) {
  return tab && tab.url && tab.url.includes('youtube.com');
}

chrome.contextMenus.removeAll(() => {
  chrome.contextMenus.create({
    id: 'metadata',
    title: 'Get Video Metadata',
    contexts: ['link'],
    targetUrlPatterns: ['*://*.youtube.com/watch*', '*://youtu.be/*'],
    documentUrlPatterns: ['*://*.youtube.com/*'],
  });

  chrome.contextMenus.create({
    id: 'comments',
    title: 'Get Comments',
    contexts: ['page'],
    documentUrlPatterns: ['*://*.youtube.com/watch*'],
  });

  chrome.contextMenus.create({
    id: 'related',
    title: 'Get Related Videos',
    contexts: ['page'],
    documentUrlPatterns: ['*://*.youtube.com/watch*'],
  });
});

chrome.action.setBadgeText({ text: 'yt' });
chrome.action.setBadgeBackgroundColor({ color: '#ff0000' });

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (!isYouTube(tab)) return;

  let videoId = null;
  if (info.menuItemId === 'metadata' && info.linkUrl) {
    videoId = getVideoId(info.linkUrl);
  } else if (info.menuItemId === 'comments' || info.menuItemId === 'related') {
    videoId = getVideoId(tab.url);
  }

  if (!videoId) return;

  const action = info.menuItemId;

  chrome.scripting.executeScript(
    {
      target: { tabId: tab.id },
      func: (vid, act, apiBase) => {
        window.__ytapis_videoId = vid;
        window.__ytapis_action = act;
        window.__ytapis_apiBase = apiBase;
      },
      args: [videoId, action, API_BASE],
    },
    () => {
      chrome.scripting.executeScript({
        target: { tabId: tab.id },
        files: ['content.js'],
      });
    }
  );
});
