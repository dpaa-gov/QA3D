// QA3D Frontend Application — Electron mode

(function () {
    'use strict';

    const invoke = (channel, data) => window.qa3d.invoke(channel, data);

    // ── State ────────────────────────────────────
    let selectedFilePath = '';
    let scanPointCount = 0;
    let densityManuallySet = false;
    let fileHasFaces = false;
    let lastResultData = null; // store for report generation

    // ── DOM Elements ─────────────────────────────
    const modelPathInput = document.getElementById('model-path');
    const browseBtn = document.getElementById('browse-btn');
    const dimX = document.getElementById('dim-x');
    const dimY = document.getElementById('dim-y');
    const dimZ = document.getElementById('dim-z');
    const dimD = document.getElementById('dim-d');
    const dimTol = document.getElementById('dim-tol');
    const dimTrim = document.getElementById('dim-trim');
    const compareBtn = document.getElementById('compare-btn');
    const clearBtn = document.getElementById('clear-btn');
    const reportBtn = document.getElementById('report-btn');
    const resultsSection = document.getElementById('results-section');
    const resultsContent = document.getElementById('results-content');
    const toggleModeBtn = document.getElementById('toggle-mode-btn');
    const colormapSelect = document.getElementById('colormap-select');
    const pointSizeControl = document.getElementById('point-size-control');
    const pointSizeSlider = document.getElementById('point-size-slider');
    const pointSizeValue = document.getElementById('point-size-value');
    const visibilityControls = document.getElementById('visibility-controls');
    const showScanCheckbox = document.getElementById('show-scan');
    const showSurfaceCheckbox = document.getElementById('show-surface');
    const renderModeControl = document.getElementById('render-mode-control');
    const renderModeSelect = document.getElementById('render-mode-select');
    const dualColorPickers = document.getElementById('dual-color-pickers');
    const scanColorPicker = document.getElementById('scan-color-picker');
    const surfColorPicker = document.getElementById('surf-color-picker');

    // Initialize 3D viewer
    if (typeof Viewer !== 'undefined') Viewer.init('viewer-container');

    // ── Enable/disable Compare button ────────────
    function updateCompareState() {
        const hasFile = selectedFilePath !== '';
        const hasX = dimX.value && parseFloat(dimX.value) > 0;
        const hasY = dimY.value && parseFloat(dimY.value) > 0;
        const hasZ = dimZ.value && parseFloat(dimZ.value) > 0;
        const hasD = dimD.value && parseFloat(dimD.value) > 0;
        compareBtn.disabled = !(hasFile && hasX && hasY && hasZ && hasD);
    }

    dimX.addEventListener('input', () => { updateCompareState(); autoCalcDensity(); });
    dimY.addEventListener('input', () => { updateCompareState(); autoCalcDensity(); });
    dimZ.addEventListener('input', () => { updateCompareState(); autoCalcDensity(); });
    dimD.addEventListener('input', () => { densityManuallySet = true; updateCompareState(); });

    // ── Auto-density calculation ─────────────────
    function autoCalcDensity() {
        if (densityManuallySet || scanPointCount === 0) return;
        const x = parseFloat(dimX.value);
        const y = parseFloat(dimY.value);
        const z = parseFloat(dimZ.value);
        if (x > 0 && y > 0 && z > 0) {
            const surfaceArea = 2 * (x * y + x * z + y * z);
            const d = Math.sqrt(surfaceArea / scanPointCount);
            dimD.value = Math.max(0.01, parseFloat(d.toFixed(3)));
            updateCompareState();
        }
    }

    // ── Browse (native file dialog) ─────────────
    browseBtn.addEventListener('click', async () => {
        const result = await invoke('select_file');
        if (!result.path) return; // user cancelled

        selectedFilePath = result.path;
        modelPathInput.value = result.path.split(/[/\\]/).pop(); // show filename only
        densityManuallySet = false;

        // Fetch point count and face info for auto-density
        try {
            const data = await invoke('get_fileinfo', { filepath: result.path });
            if (data.points) {
                scanPointCount = data.points;
                autoCalcDensity();
            }
            fileHasFaces = data.hasFaces || false;
        } catch (e) {
            console.error('File info error:', e);
            fileHasFaces = false;
        }
        updateCompareState();
    });

    // ── Compare ──────────────────────────────────
    compareBtn.addEventListener('click', async () => {
        compareBtn.disabled = true;
        compareBtn.textContent = '⏳ Comparing...';

        const toleranceVal = parseFloat(dimTol.value) || 0.05;
        const trimPct = parseFloat(dimTrim.value) || 10;

        try {
            const data = await invoke('run_compare', {
                filepath: selectedFilePath,
                x: parseFloat(dimX.value),
                y: parseFloat(dimY.value),
                z: parseFloat(dimZ.value),
                d: parseFloat(dimD.value),
                tolerance: toleranceVal,
                trim_pct: trimPct
            });

            if (data.error) {
                alert('Error: ' + data.error);
                return;
            }

            // Store for report generation
            lastResultData = data;
            lastResultData._tolerance = toleranceVal;
            lastResultData._filepath = selectedFilePath;
            lastResultData._dims = {
                x: parseFloat(dimX.value),
                y: parseFloat(dimY.value),
                z: parseFloat(dimZ.value),
                d: parseFloat(dimD.value)
            };

            // Format signed mean with explicit sign
            const signedStr = data.signedMean >= 0
                ? `+${data.signedMean.toFixed(6)}`
                : data.signedMean.toFixed(6);

            // Display metrics
            resultsSection.classList.remove('hidden');
            resultsContent.innerHTML = `
                <div class="result-row">
                    <span class="result-label">Scan points</span>
                    <span class="result-value">${data.scanPoints.toLocaleString()}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">Surface points</span>
                    <span class="result-value">${data.surfacePoints.toLocaleString()}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">Chamfer Distance</span>
                    <span class="result-value">${data.chamferDist}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">Scan → Reference</span>
                    <span class="result-value">${data.meanAtoB}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">Reference → Scan</span>
                    <span class="result-value">${data.meanBtoA}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">Signed Mean</span>
                    <span class="result-value">${signedStr}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">SD</span>
                    <span class="result-value">${data.sd}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">RMSE</span>
                    <span class="result-value">${data.rmse}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">TEM</span>
                    <span class="result-value">${data.tem}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">Max Distance (S→R)</span>
                    <span class="result-value">${data.maxAtoB}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">Max Distance (R→S)</span>
                    <span class="result-value">${data.maxBtoA}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">95th Percentile (S→R)</span>
                    <span class="result-value">${data.p95AtoB}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">95th Percentile (R→S)</span>
                    <span class="result-value">${data.p95BtoA}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">95th Percentile (Bidirectional)</span>
                    <span class="result-value">${data.p95Bidir}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">In-Tolerance (≤ ${toleranceVal} mm)</span>
                    <span class="result-value">${data.yieldPct}%</span>
                </div>
                <div class="result-row">
                    <span class="result-label">Best reflection</span>
                    <span class="result-value">#${data.bestReflection}</span>
                </div>
                ${data.dimensionalAnalysis ? `
                <div class="dim-analysis-section">
                    <h4>Dimensional Analysis</h4>
                    <table class="dim-table">
                        <thead><tr>
                            <th>Axis</th>
                            <th>Nominal</th>
                            <th>Measured</th>
                            <th>Error</th>
                            <th>∠ Para</th>
                            <th>Flat −/+</th>
                        </tr></thead>
                        <tbody>
                        ${data.dimensionalAnalysis.filter(r => r.valid).map(r => {
                            const errStr = r.error >= 0 ? `+${r.error.toFixed(4)}` : r.error.toFixed(4);
                            const errClass = r.error >= 0 ? 'dim-error-pos' : 'dim-error-neg';
                            return `<tr>
                                <td>${r.axis}</td>
                                <td>${r.nominal.toFixed(2)}</td>
                                <td>${r.measured.toFixed(4)}</td>
                                <td class="${errClass}">${errStr}</td>
                                <td>${r.parallelism.toFixed(3)}°</td>
                                <td>− ${r.flatnessNeg.toFixed(4)}<br>+ ${r.flatnessPos.toFixed(4)}</td>
                            </tr>`;
                        }).join('')}
                        </tbody>
                    </table>
                </div>
                ` : ''}
            `;

            clearBtn.classList.remove('hidden');
            reportBtn.classList.remove('hidden');

            // Load point cloud data into viewer
            if (typeof Viewer !== 'undefined' && data.scanCoords) {
                toggleModeBtn.classList.remove('hidden');
                colormapSelect.classList.remove('hidden');
                pointSizeControl.classList.remove('hidden');
                visibilityControls.classList.remove('hidden');

                // Show render mode toggle (always available — surface always has mesh)
                renderModeControl.classList.remove('hidden');

                // Reset checkboxes
                showScanCheckbox.checked = true;
                showSurfaceCheckbox.checked = true;
                renderModeSelect.value = 'pointcloud';

                Viewer.loadResults(data);
            }
        } catch (e) {
            alert('Error: ' + e);
        } finally {
            compareBtn.textContent = '⚡ Compare';
            updateCompareState();
        }
    });

    // ── Clear ────────────────────────────────────
    clearBtn.addEventListener('click', () => {
        selectedFilePath = '';
        modelPathInput.value = '';
        dimX.value = '20';
        dimY.value = '8.91';
        dimZ.value = '34.90';
        dimD.value = '0.1';
        dimTol.value = '0.05';
        scanPointCount = 0;
        densityManuallySet = false;
        fileHasFaces = false;
        lastResultData = null;
        resultsSection.classList.add('hidden');
        clearBtn.classList.add('hidden');
        reportBtn.classList.add('hidden');
        toggleModeBtn.classList.add('hidden');
        colormapSelect.classList.add('hidden');
        colormapSelect.value = 'green-red';
        pointSizeControl.classList.add('hidden');
        pointSizeSlider.value = '0.4';
        pointSizeValue.textContent = '0.4';
        visibilityControls.classList.add('hidden');
        renderModeControl.classList.add('hidden');
        renderModeSelect.value = 'pointcloud';
        dualColorPickers.classList.add('hidden');
        scanColorPicker.value = '#d9a621';
        surfColorPicker.value = '#4d80e6';
        showScanCheckbox.checked = true;
        showSurfaceCheckbox.checked = true;
        if (typeof Viewer !== 'undefined') Viewer.clear();
        updateCompareState();
    });

    // ── Save Report ─────────────────────────────
    reportBtn.addEventListener('click', async () => {
        if (!lastResultData) return;

        const d = lastResultData;
        const now = new Date();
        const ts = now.getFullYear()
            + '-' + String(now.getMonth() + 1).padStart(2, '0')
            + '-' + String(now.getDate()).padStart(2, '0')
            + ' ' + String(now.getHours()).padStart(2, '0')
            + ':' + String(now.getMinutes()).padStart(2, '0')
            + ':' + String(now.getSeconds()).padStart(2, '0');

        const reportData = {
            timestamp: ts,
            fileName: d._filepath.split(/[/\\]/).pop(),
            filepath: d._filepath,
            dimX: d._dims.x.toFixed(2),
            dimY: d._dims.y.toFixed(2),
            dimZ: d._dims.z.toFixed(2),
            density: d._dims.d,
            tolerance: d._tolerance,
            scanPoints: d.scanPoints,
            surfacePoints: d.surfacePoints,
            chamferDist: d.chamferDist,
            meanAtoB: d.meanAtoB,
            meanBtoA: d.meanBtoA,
            signedMean: d.signedMean,
            sd: d.sd,
            rmse: d.rmse,
            tem: d.tem,
            maxDist: d.maxDist,
            maxAtoB: d.maxAtoB,
            maxBtoA: d.maxBtoA,
            p95AtoB: d.p95AtoB,
            p95BtoA: d.p95BtoA,
            p95Bidir: d.p95Bidir,
            yieldPct: d.yieldPct,
            bestReflection: d.bestReflection,
            dimensionalAnalysis: d.dimensionalAnalysis || [],
            trimPct: parseFloat(dimTrim.value) || 10
        };

        const defaultName = `QA3D_Report_${ts.replace(/[: ]/g, '-').replace(/--/g, '_')}.pdf`;

        try {
            const result = await invoke('save_report', { reportData, defaultName });
            if (result.saved) {
                reportBtn.textContent = '✅ Saved!';
                setTimeout(() => { reportBtn.textContent = '📄 Save Report'; }, 2000);
            }
        } catch (e) {
            console.error('Report save error:', e);
        }
    });

    // ── Toggle viewer color mode ────────────────
    toggleModeBtn.addEventListener('click', () => {
        const mode = typeof Viewer !== 'undefined' ? Viewer.toggleMode() : 'heatmap';
        toggleModeBtn.textContent = mode === 'heatmap' ? '🎨 Dual Color' : '🌡️ Heatmap';
        // Show colormap selector only in heatmap mode
        colormapSelect.classList.toggle('hidden', mode !== 'heatmap');
        // Show dual color pickers only in dual mode
        dualColorPickers.classList.toggle('hidden', mode !== 'dual');
    });

    // ── Colormap selector ───────────────────────
    colormapSelect.addEventListener('change', (e) => {
        if (typeof Viewer !== 'undefined') Viewer.setColormap(e.target.value);
    });

    // ── Point size slider ───────────────────────
    pointSizeSlider.addEventListener('input', (e) => {
        const size = parseFloat(e.target.value);
        pointSizeValue.textContent = size.toFixed(1);
        if (typeof Viewer !== 'undefined') Viewer.setPointSize(size);
    });

    // ── Dual color pickers ──────────────────────
    scanColorPicker.addEventListener('input', (e) => {
        if (typeof Viewer !== 'undefined') Viewer.setDualColors(e.target.value, surfColorPicker.value);
    });
    surfColorPicker.addEventListener('input', (e) => {
        if (typeof Viewer !== 'undefined') Viewer.setDualColors(scanColorPicker.value, e.target.value);
    });

    // ── Visibility checkboxes ───────────────────
    showScanCheckbox.addEventListener('change', (e) => {
        if (typeof Viewer !== 'undefined') Viewer.setScanVisible(e.target.checked);
    });

    showSurfaceCheckbox.addEventListener('change', (e) => {
        if (typeof Viewer !== 'undefined') Viewer.setSurfVisible(e.target.checked);
    });

    // ── Render mode selector ────────────────────
    renderModeSelect.addEventListener('change', (e) => {
        if (typeof Viewer !== 'undefined') Viewer.setRenderMode(e.target.value);
        // Show/hide point size control: keep visible in mesh mode if scan has no faces
        // (scan still renders as points even when surface renders as mesh)
        pointSizeControl.classList.toggle('hidden', e.target.value === 'mesh' && fileHasFaces);
    });

})();
