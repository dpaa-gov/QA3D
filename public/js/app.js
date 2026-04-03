// QA3D Frontend Application — Electron mode

(function () {
    'use strict';

    const invoke = (channel, data) => window.qa3d.invoke(channel, data);

    // ── State ────────────────────────────────────
    let selectedFilePath = '';
    let scanPointCount = 0;
    let densityManuallySet = false;

    // ── DOM Elements ─────────────────────────────
    const modelPathInput = document.getElementById('model-path');
    const browseBtn = document.getElementById('browse-btn');
    const dimX = document.getElementById('dim-x');
    const dimY = document.getElementById('dim-y');
    const dimZ = document.getElementById('dim-z');
    const dimD = document.getElementById('dim-d');
    const compareBtn = document.getElementById('compare-btn');
    const clearBtn = document.getElementById('clear-btn');
    const resultsSection = document.getElementById('results-section');
    const resultsContent = document.getElementById('results-content');
    const toggleModeBtn = document.getElementById('toggle-mode-btn');
    const colormapSelect = document.getElementById('colormap-select');
    const pointSizeControl = document.getElementById('point-size-control');
    const pointSizeSlider = document.getElementById('point-size-slider');
    const pointSizeValue = document.getElementById('point-size-value');

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

        // Fetch point count for auto-density
        try {
            const data = await invoke('get_fileinfo', { filepath: result.path });
            if (data.points) {
                scanPointCount = data.points;
                autoCalcDensity();
            }
        } catch (e) {
            console.error('File info error:', e);
        }
        updateCompareState();
    });

    // ── Compare ──────────────────────────────────
    compareBtn.addEventListener('click', async () => {
        compareBtn.disabled = true;
        compareBtn.textContent = '⏳ Comparing...';

        try {
            const data = await invoke('run_compare', {
                filepath: selectedFilePath,
                x: parseFloat(dimX.value),
                y: parseFloat(dimY.value),
                z: parseFloat(dimZ.value),
                d: parseFloat(dimD.value)
            });

            if (data.error) {
                alert('Error: ' + data.error);
                return;
            }

            // Display metrics immediately
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
                    <span class="result-label">Hausdorff (mean)</span>
                    <span class="result-value">${data.bestDistance}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">A → B</span>
                    <span class="result-value">${data.meanAtoB}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">B → A</span>
                    <span class="result-value">${data.meanBtoA}</span>
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
                    <span class="result-label">Max distance</span>
                    <span class="result-value">${data.maxDist}</span>
                </div>
                <div class="result-row">
                    <span class="result-label">Best reflection</span>
                    <span class="result-value">#${data.bestReflection}</span>
                </div>
            `;

            clearBtn.classList.remove('hidden');

            // Load point cloud data into viewer
            if (typeof Viewer !== 'undefined' && data.scanCoords) {
                toggleModeBtn.classList.remove('hidden');
                colormapSelect.classList.remove('hidden');
                pointSizeControl.classList.remove('hidden');
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
        scanPointCount = 0;
        densityManuallySet = false;
        resultsSection.classList.add('hidden');
        clearBtn.classList.add('hidden');
        toggleModeBtn.classList.add('hidden');
        colormapSelect.classList.add('hidden');
        colormapSelect.value = 'green-red';
        pointSizeControl.classList.add('hidden');
        pointSizeSlider.value = '0.4';
        pointSizeValue.textContent = '0.4';
        if (typeof Viewer !== 'undefined') Viewer.clear();
        updateCompareState();
    });

    // ── Toggle viewer mode ──────────────────────────
    toggleModeBtn.addEventListener('click', () => {
        const mode = typeof Viewer !== 'undefined' ? Viewer.toggleMode() : 'heatmap';
        toggleModeBtn.textContent = mode === 'heatmap' ? '🎨 Dual Color' : '🌡️ Heatmap';
        // Show colormap selector only in heatmap mode
        colormapSelect.classList.toggle('hidden', mode !== 'heatmap');
    });

    // ── Colormap selector ───────────────────────────
    colormapSelect.addEventListener('change', (e) => {
        if (typeof Viewer !== 'undefined') Viewer.setColormap(e.target.value);
    });

    // ── Point size slider ───────────────────────────
    pointSizeSlider.addEventListener('input', (e) => {
        const size = parseFloat(e.target.value);
        pointSizeValue.textContent = size.toFixed(1);
        if (typeof Viewer !== 'undefined') Viewer.setPointSize(size);
    });

})();
