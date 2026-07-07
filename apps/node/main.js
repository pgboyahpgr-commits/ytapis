const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const { search } = require('ytapis-core');

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1000,
    height: 700,
    minWidth: 600,
    minHeight: 400,
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
    const results = await search(query, { limit: 15 });
    return { ok: true, data: results };
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

app.whenReady().then(createWindow);
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
