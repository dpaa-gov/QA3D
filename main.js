// QA3D — Electron Main Process
// Manages the BrowserWindow and Julia sidecar subprocess.

const { app, BrowserWindow, ipcMain } = require('electron');
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

ipcMain.handle('browse_directory', async (_event, { path: dirPath }) => {
    try {
        const entries = [];
        const items = fs.readdirSync(dirPath, { withFileTypes: true });

        for (const item of items) {
            const fullPath = path.join(dirPath, item.name);
            const isDir = item.isDirectory();
            const isModel = !isDir && item.name.toLowerCase().endsWith('.xyzrgb');
            entries.push({
                name: item.name,
                path: fullPath,
                isDirectory: isDir,
                isModel,
            });
        }

        // Sort: directories first, then alphabetical
        entries.sort((a, b) => {
            if (a.isDirectory !== b.isDirectory) return a.isDirectory ? -1 : 1;
            return a.name.localeCompare(b.name);
        });

        return { entries, currentPath: dirPath };
    } catch (e) {
        return { error: e.message.replace(/^ENOENT:\s*/, ''), entries: [] };
    }
});

ipcMain.handle('get_homedir', async () => {
    return { path: os.homedir() };
});

ipcMain.handle('get_fileinfo', async (_event, { filepath }) => {
    return sendToSidecar({ command: 'fileinfo', filepath });
});

ipcMain.handle('run_compare', async (_event, { filepath, x, y, z, d }) => {
    return sendToSidecar({ command: 'compare', filepath, x, y, z, d });
});

// ── Window ────────────────────────────────────────────

function createWindow() {
    const win = new BrowserWindow({
        width: 1400,
        height: 900,
        title: 'QA3D - Quality Assurance 3D',
        autoHideMenuBar: true,
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration: false,
        },
    });

    win.setMenu(null);

    win.loadFile(path.join(__dirname, 'public', 'index.html'));
}

// ── App Lifecycle ─────────────────────────────────────

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
