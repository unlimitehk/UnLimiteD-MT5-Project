const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('panelApi', {
  getConfig: () => ipcRenderer.invoke('panel:get-config'),
  setAlwaysOnTop: (enabled) => ipcRenderer.invoke('panel:set-always-on-top', enabled)
});
