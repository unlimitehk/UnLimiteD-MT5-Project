const { app, BrowserWindow, ipcMain, nativeTheme } = require('electron');
const path = require('path');
const fs = require('fs');

const configPath = path.join(app.getPath('userData'), 'rr-panel-config.json');

function loadConfig() {
  try {
    const raw = fs.readFileSync(configPath, 'utf8');
    return JSON.parse(raw);
  } catch {
    return { alwaysOnTop: false };
  }
}

function saveConfig(cfg) {
  fs.mkdirSync(path.dirname(configPath), { recursive: true });
  fs.writeFileSync(configPath, JSON.stringify(cfg, null, 2), 'utf8');
}

function createWindow() {
  const cfg = loadConfig();
  const win = new BrowserWindow({
    width: 460,
    height: 700,
    title: 'UnLimiteD Electron Panel',
    autoHideMenuBar: true,
    alwaysOnTop: Boolean(cfg.alwaysOnTop),
    backgroundColor: nativeTheme.shouldUseDarkColors ? '#14161d' : '#f4f6fb',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js')
    }
  });

  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  ipcMain.handle('panel:get-config', () => cfg);
  ipcMain.handle('panel:set-always-on-top', (_, enabled) => {
    cfg.alwaysOnTop = Boolean(enabled);
    win.setAlwaysOnTop(cfg.alwaysOnTop);
    saveConfig(cfg);
    return cfg;
  });
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
