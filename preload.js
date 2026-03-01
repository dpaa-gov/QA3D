// QA3D — Electron Preload Script
// Exposes a secure IPC bridge to the renderer process.

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('qa3d', {
    invoke: (channel, data) => ipcRenderer.invoke(channel, data),
});
