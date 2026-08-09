const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('ytapis', {
  search: (query) => ipcRenderer.invoke('search', query),
  loadMore: (opts) => ipcRenderer.invoke('loadMore', opts),
});
