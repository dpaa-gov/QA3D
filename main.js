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
        title: 'Select 3D Model',
        filters: [{ name: '3D Models', extensions: ['xyzrgb', 'obj', 'ply', 'stl'] }],
        properties: ['openFile'],
    });
    if (result.canceled || result.filePaths.length === 0) return { path: null };
    return { path: result.filePaths[0] };
});

ipcMain.handle('get_fileinfo', async (_event, { filepath }) => {
    return sendToSidecar({ command: 'fileinfo', filepath });
});

ipcMain.handle('run_compare', async (_event, { filepath, x, y, z, d, tolerance, trim_pct }) => {
    return sendToSidecar({ command: 'compare', filepath, x, y, z, d, tolerance, trim_pct });
});

ipcMain.handle('save_report', async (_event, { reportData, defaultName }) => {
    const result = await dialog.showSaveDialog({
        title: 'Save QA3D Report',
        defaultPath: defaultName || 'QA3D_Report.pdf',
        filters: [{ name: 'PDF Files', extensions: ['pdf'] }],
    });
    if (result.canceled || !result.filePath) return { saved: false };

    const d = reportData;
    const signedStr = d.signedMean >= 0
        ? `+${d.signedMean.toFixed(6)}`
        : d.signedMean.toFixed(6);

    // Build dimensional analysis rows for the PDF
    const dimRows = (d.dimensionalAnalysis || [])
        .filter(r => r.valid)
        .map(r => {
            const errStr = r.error >= 0 ? `+${r.error.toFixed(4)}` : r.error.toFixed(4);
            const errClass = r.error >= 0 ? 'signed-pos' : 'signed-neg';
            return `<tr>
                <td class="dim-axis">${r.axis}</td>
                <td>${r.nominal.toFixed(2)}</td>
                <td>${r.measured.toFixed(4)}</td>
                <td class="${errClass}">${errStr}</td>
                <td>${r.parallelism.toFixed(3)}°</td>
                <td>${r.flatnessNeg.toFixed(4)} / ${r.flatnessPos.toFixed(4)}</td>
            </tr>`;
        }).join('');

    const html = `<!DOCTYPE html>
<html><head><meta charset="UTF-8">
<style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
        background: #fff; color: #1a1d23; padding: 30px 50px;
        font-size: 12px; line-height: 1.45;
    }
    .header {
        display: flex; justify-content: space-between; align-items: flex-end;
        border-bottom: 3px solid #d4a843; padding-bottom: 8px; margin-bottom: 14px;
    }
    .header h1 { font-size: 24px; font-weight: 700; color: #1a1d23; }
    .header h1 span { color: #d4a843; }
    .header .subtitle { font-size: 11px; color: #6b7280; text-align: right; }
    .section { margin-bottom: 10px; }
    .section h2 {
        font-size: 10px; font-weight: 600; text-transform: uppercase;
        letter-spacing: 1.5px; color: #d4a843; margin-bottom: 4px;
        border-bottom: 1px solid #e5e7eb; padding-bottom: 3px;
    }
    table { width: 100%; border-collapse: collapse; }
    td { padding: 2px 0; vertical-align: top; }
    td:first-child { color: #6b7280; width: 55%; }
    td:last-child { font-weight: 500; text-align: right; font-family: 'Consolas', 'Monaco', monospace; }
    .input-table td:first-child { width: 30%; }
    .pass { color: #16a34a; font-weight: 600; }
    .warn { color: #ea580c; font-weight: 600; }
    .fail { color: #dc2626; font-weight: 600; }
    .signed-pos { color: #ea580c; }
    .signed-neg { color: #2563eb; }
    .dim-table { border-top: 1px solid #e5e7eb; margin-top: 4px; }
    .dim-table th {
        font-size: 9px; font-weight: 600; text-transform: uppercase;
        letter-spacing: 0.5px; color: #6b7280; padding: 4px 2px;
        text-align: right; border-bottom: 1px solid #e5e7eb;
    }
    .dim-table th:first-child { text-align: left; }
    .dim-table td {
        padding: 3px 2px; text-align: right;
        font-family: 'Consolas', 'Monaco', monospace; font-size: 11px;
        color: #1a1d23; width: auto;
    }
    .dim-table td:first-child { text-align: left; color: #6b7280; width: auto; }
    .dim-table td.dim-axis { font-weight: 600; color: #d4a843; }
    .dim-table tr + tr td { border-top: 1px solid #f3f4f6; }
    .footer {
        margin-top: 16px; padding-top: 8px; border-top: 1px solid #e5e7eb;
        font-size: 10px; color: #9ca3af; text-align: center;
    }
</style></head><body>

<div class="header">
    <h1>QA<span>3D</span> &mdash; Quality Assurance Report</h1>
    <div class="subtitle">Generated: ${d.timestamp}<br>QA3D v1.2.0</div>
</div>

<div class="section">
    <h2>Input</h2>
    <table class="input-table">
        <tr><td>File</td><td>${d.fileName}</td></tr>
        <tr><td>Dimensions</td><td>${d.dimX} × ${d.dimY} × ${d.dimZ} mm</td></tr>
        <tr><td>Density</td><td>${d.density}</td></tr>
        <tr><td>Tolerance</td><td>${d.tolerance} mm</td></tr>
        <tr><td>Edge Trim</td><td>${d.trimPct}%</td></tr>
    </table>
</div>

<div class="section">
    <h2>Point Counts</h2>
    <table>
        <tr><td>Scan Points</td><td>${d.scanPoints.toLocaleString()}</td></tr>
        <tr><td>Surface Points</td><td>${d.surfacePoints.toLocaleString()}</td></tr>
    </table>
</div>

<div class="section">
    <h2>Distance Metrics</h2>
    <table>
        <tr><td>Chamfer Distance</td><td>${d.chamferDist}</td></tr>
        <tr><td>Scan → Reference</td><td>${d.meanAtoB}</td></tr>
        <tr><td>Reference → Scan</td><td>${d.meanBtoA}</td></tr>
        <tr><td>Signed Mean</td><td class="${d.signedMean >= 0 ? 'signed-pos' : 'signed-neg'}">${signedStr}</td></tr>
        <tr><td>SD</td><td>${d.sd}</td></tr>
        <tr><td>RMSE</td><td>${d.rmse}</td></tr>
        <tr><td>TEM</td><td>${d.tem}</td></tr>
        <tr><td>Max Distance (S→R)</td><td>${d.maxAtoB}</td></tr>
        <tr><td>Max Distance (R→S)</td><td>${d.maxBtoA}</td></tr>
    </table>
</div>

<div class="section">
    <h2>Percentile Metrics</h2>
    <table>
        <tr><td>95th Percentile (S→R)</td><td>${d.p95AtoB}</td></tr>
        <tr><td>95th Percentile (R→S)</td><td>${d.p95BtoA}</td></tr>
        <tr><td>95th Percentile (Bidirectional)</td><td>${d.p95Bidir}</td></tr>
    </table>
</div>

<div class="section">
    <h2>Tolerance Analysis</h2>
    <table>
        <tr>
            <td>In-Tolerance (≤ ${d.tolerance} mm)</td>
            <td class="${d.yieldPct >= 95 ? 'pass' : d.yieldPct >= 80 ? 'warn' : 'fail'}">${d.yieldPct}%</td>
        </tr>
    </table>
</div>

<div class="section">
    <h2>Registration</h2>
    <table>
        <tr><td>Best Reflection</td><td>#${d.bestReflection}</td></tr>
    </table>
</div>

${dimRows ? `
<div class="section">
    <h2>Dimensional Analysis</h2>
    <table class="dim-table">
        <thead><tr>
            <th>Axis</th><th>Nominal</th><th>Measured</th>
            <th>Error</th><th>Parallelism</th><th>Flatness −/+</th>
        </tr></thead>
        <tbody>${dimRows}</tbody>
    </table>
</div>
` : ''}

<div class="footer">
    QA3D — Quality Assurance 3D &bull; Defense POW/MIA Accounting Agency
</div>

</body></html>`;

    // Render PDF via hidden BrowserWindow
    let pdfWin = null;
    try {
        pdfWin = new BrowserWindow({
            show: false, width: 800, height: 1000,
            webPreferences: { contextIsolation: true, nodeIntegration: false }
        });

        await pdfWin.loadURL('data:text/html;charset=utf-8,' + encodeURIComponent(html));

        const pdfBuffer = await pdfWin.webContents.printToPDF({
            printBackground: true,
            pageSize: 'Letter',
            margins: { top: 0, bottom: 0, left: 0, right: 0 }
        });

        fs.writeFileSync(result.filePath, pdfBuffer);
        return { saved: true, path: result.filePath };
    } catch (e) {
        return { saved: false, error: e.message };
    } finally {
        if (pdfWin) pdfWin.destroy();
    }
});

// ── Window ────────────────────────────────────────────

let mainWindow = null;

function createWindow() {
    const win = new BrowserWindow({
        width: 1400,
        height: 1000,
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
