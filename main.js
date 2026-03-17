// QA3D — Electron Main Process
// Manages the BrowserWindow and Julia sidecar subprocess.

const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');
const readline = require('readline');

// ── Julia Sidecar ─────────────────────────────────────

let sidecarProcess = null;
let sidecarRL = null;          // readline interface on stdout
let pendingResolve = null;     // single in-flight request

function startSidecar() {
    const projectDir = app.isPackaged
        ? path.dirname(process.execPath)
        : __dirname;

    const cpus = os.cpus().length;
    const threads = Math.min(cpus, 8);

    // Try compiled sidecar first, fall back to Julia dev mode
    const exeName = process.platform === 'win32' ? 'qa3d.exe' : 'qa3d';
    const sidecarPath = app.isPackaged
        ? path.join(process.resourcesPath, 'sidecar', 'bin', exeName)
        : path.join(projectDir, 'sidecar', 'bin', exeName);

    if (fs.existsSync(sidecarPath)) {
        console.log('Starting compiled sidecar:', sidecarPath);
        sidecarProcess = spawn(sidecarPath, [], {
            stdio: ['pipe', 'pipe', 'pipe'],
            env: { ...process.env, JULIA_NUM_THREADS: String(threads) },
            windowsHide: true,
        });
    } else {
        console.log('No compiled sidecar found, using Julia dev mode...');

        sidecarProcess = spawn('julia', [
            `--threads=${threads}`,
            '--project=.',
            '-e',
            'using QA3D; QA3D.sidecar_main()',
        ], {
            cwd: projectDir,
            stdio: ['pipe', 'pipe', 'pipe'],
            windowsHide: true,
        });
    }

    sidecarRL = readline.createInterface({ input: sidecarProcess.stdout });

    sidecarRL.on('line', (line) => {
        if (pendingResolve) {
            const resolve = pendingResolve;
            pendingResolve = null;
            try {
                resolve(JSON.parse(line));
            } catch (e) {
                resolve({ error: `Failed to parse sidecar response: ${e.message}` });
            }
        }
    });

    sidecarProcess.on('error', (err) => {
        console.error('Sidecar error:', err.message);
    });

    sidecarProcess.on('exit', (code) => {
        console.log('Sidecar exited with code', code);
        sidecarProcess = null;
    });
}

function sendToSidecar(command) {
    return new Promise((resolve, reject) => {
        if (!sidecarProcess || !sidecarProcess.stdin.writable) {
            return reject(new Error('Julia sidecar is not running'));
        }
        pendingResolve = resolve;
        sidecarProcess.stdin.write(JSON.stringify(command) + '\n');
    });
}

// ── IPC Handlers ──────────────────────────────────────

ipcMain.handle('select_file', async () => {
    const result = await dialog.showOpenDialog({
        title: 'Select .xyzrgb File',
        filters: [{ name: 'XYZRGB Models', extensions: ['xyzrgb'] }],
        properties: ['openFile'],
    });
    if (result.canceled || result.filePaths.length === 0) return { path: null };
    return { path: result.filePaths[0] };
});

ipcMain.handle('get_fileinfo', async (_event, { filepath }) => {
    return sendToSidecar({ command: 'fileinfo', filepath });
});

ipcMain.handle('run_compare', async (_event, { filepath, x, y, z, d }) => {
    return sendToSidecar({ command: 'compare', filepath, x, y, z, d });
});

// ── Window ────────────────────────────────────────────

let mainWindow = null;

function createWindow() {
    const win = new BrowserWindow({
        width: 1400,
        height: 900,
        title: 'QA3D - Quality Assurance 3D',
        icon: path.join(__dirname, 'public', 'icon.png'),
        autoHideMenuBar: true,
        show: false,
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration: false,
        },
    });

    win.maximize();
    win.show();

    win.setMenu(null);

    win.loadFile(path.join(__dirname, 'public', 'index.html'));

    // Block DevTools and zoom shortcuts on all platforms
    win.webContents.on('before-input-event', (_event, input) => {
        if (input.type !== 'keyDown') return;
        const ctrl = input.control || input.meta;
        // Block F12, Ctrl+Shift+I (DevTools)
        if (input.key === 'F12' || (ctrl && input.shift && input.key.toLowerCase() === 'i')) {
            _event.preventDefault();
            return;
        }
        // Block Ctrl+/-/0 (zoom)
        if (ctrl && ['+', '-', '=', '0'].includes(input.key)) {
            _event.preventDefault();
        }
    });
    mainWindow = win;
}
// ── App Lifecycle ─────────────────────────────────────

// Single instance lock — focus existing window if user tries to open a second
const gotTheLock = app.requestSingleInstanceLock();
if (!gotTheLock) {
    app.quit();
} else {
    app.on('second-instance', () => {
        if (mainWindow) {
            if (mainWindow.isMinimized()) mainWindow.restore();
            mainWindow.focus();
        }
    });
}

// Suppress gl_surface warnings on Linux
app.commandLine.appendSwitch('disable-gpu-sandbox');

app.whenReady().then(() => {
    startSidecar();
    createWindow();
});

app.on('window-all-closed', () => {
    if (sidecarProcess) {
        // Close stdin so Julia's readline() hits EOF and exits cleanly
        try { sidecarProcess.stdin.end(); } catch (_) { }
        if (sidecarRL) { sidecarRL.close(); sidecarRL = null; }

        // Force-kill after 2s if it hasn't exited
        const proc = sidecarProcess;
        const timer = setTimeout(() => {
            try { proc.kill('SIGKILL'); } catch (_) { }
        }, 2000);

        proc.on('exit', () => clearTimeout(timer));
        sidecarProcess = null;
    }
    app.quit();
});
