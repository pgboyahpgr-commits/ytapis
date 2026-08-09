const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const { search, searchContinue } = require('ytapis-core');

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1100,
    height: 750,
    minWidth: 800,
    minHeight: 500,
    backgroundColor: '#1e1e1e',
    title: 'ytapis - YouTube Search',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));
}

ipcMain.handle('search', async (event, query) => {
  try {
    const response = await search(query, { limit: 20 });
    return {
      ok: true,
      data: response.results,
      continuation: response.continuation || null,
      apiKey: response.apiKey || null,
      context: response.context || null,
    };
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle('loadMore', async (event, { continuation, apiKey, context }) => {
  try {
    const response = await searchContinue(continuation, {
      limit: 20,
      apiKey,
      context,
      path: 'search',
    });
    return {
      ok: true,
      data: response.results,
      continuation: response.continuation || null,
    };
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

app.whenReady().then(createWindow);
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
