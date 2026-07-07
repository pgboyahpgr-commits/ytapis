const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('ytapis', {
  search: (query) => ipcRenderer.invoke('search', query),
});
