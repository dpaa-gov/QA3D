// QA3D Frontend Application

(function () {
    'use strict';

    // ── State ────────────────────────────────────
    let selectedFilePath = '';
    let currentBrowsePath = '/';
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

    // Initialize 3D viewer
    Viewer.init('viewer-container');

    // Modal elements
    const modal = document.getElementById('browser-modal');
    const modalPath = document.getElementById('modal-current-path');
    const dirListing = document.getElementById('directory-listing');
    const parentDirBtn = document.getElementById('parent-dir-btn');
    const goToPathBtn = document.getElementById('go-to-path-btn');
    const selectFileBtn = document.getElementById('select-file-btn');
    const modalClose = modal.querySelector('.modal-close');
    const modalCancel = modal.querySelector('.modal-cancel');

    // ── Heartbeat ────────────────────────────────
    setInterval(() => {
        fetch('/api/heartbeat', { method: 'POST' }).catch(() => { });
    }, 5000);

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

    // ── File Browser Modal ───────────────────────
    browseBtn.addEventListener('click', async () => {
        // Get home directory on first open
        if (currentBrowsePath === '/') {
            try {
                const res = await fetch('/api/homedir');
                const data = await res.json();
                currentBrowsePath = data.path;
            } catch (e) { /* use default */ }
        }
        openModal();
        loadDirectory(currentBrowsePath);
    });

    function openModal() {
        modal.classList.add('active');
        selectFileBtn.disabled = true;
    }

    function closeModal() {
        modal.classList.remove('active');
    }

    modalClose.addEventListener('click', closeModal);
    modalCancel.addEventListener('click', closeModal);
    modal.addEventListener('click', (e) => {
        if (e.target === modal) closeModal();
    });

    parentDirBtn.addEventListener('click', () => {
        const parent = currentBrowsePath.replace(/[/\\][^/\\]*$/, '') || '/';
        loadDirectory(parent);
    });

    goToPathBtn.addEventListener('click', () => {
        loadDirectory(modalPath.value);
    });

    modalPath.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') loadDirectory(modalPath.value);
    });

    async function loadDirectory(path) {
        try {
            const res = await fetch('/api/browse', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ path })
            });
            const data = await res.json();
            if (data.error) return;

            currentBrowsePath = data.currentPath;
            modalPath.value = data.currentPath;
            selectFileBtn.disabled = true;

            dirListing.innerHTML = '';
            let selectedEntry = null;

            for (const entry of data.entries) {
                const div = document.createElement('div');
                div.className = 'dir-entry';
                div.innerHTML = `
                    <span class="dir-entry-icon">${entry.isDirectory ? '📁' : (entry.isModel ? '📐' : '📄')}</span>
                    <span class="dir-entry-name">${entry.name}</span>
                `;

                if (entry.isDirectory) {
                    div.addEventListener('dblclick', () => loadDirectory(entry.path));
                } else if (entry.isModel) {
                    div.addEventListener('click', () => {
                        if (selectedEntry) selectedEntry.classList.remove('selected');
                        div.classList.add('selected');
                        selectedEntry = div;
                        selectFileBtn.disabled = false;
                        selectFileBtn._selectedPath = entry.path;
                        selectFileBtn._selectedName = entry.name;
                    });
                    div.addEventListener('dblclick', () => {
                        selectFile(entry.path, entry.name);
                    });
                }

                dirListing.appendChild(div);
            }
        } catch (e) {
            console.error('Browse error:', e);
        }
    }

    selectFileBtn.addEventListener('click', () => {
        if (selectFileBtn._selectedPath) {
            selectFile(selectFileBtn._selectedPath, selectFileBtn._selectedName);
        }
    });

    async function selectFile(path, name) {
        selectedFilePath = path;
        modelPathInput.value = name;
        densityManuallySet = false;
        closeModal();

        // Fetch point count for auto-density
        try {
            const res = await fetch('/api/fileinfo', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ filepath: path })
            });
            const data = await res.json();
            if (data.points) {
                scanPointCount = data.points;
                autoCalcDensity();
            }
        } catch (e) {
            console.error('File info error:', e);
        }
        updateCompareState();
    }

    // ── Compare ──────────────────────────────────
    compareBtn.addEventListener('click', async () => {
        compareBtn.disabled = true;
        compareBtn.textContent = '⏳ Comparing...';

        try {
            const res = await fetch('/api/compare', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    filepath: selectedFilePath,
                    x: parseFloat(dimX.value),
                    y: parseFloat(dimY.value),
                    z: parseFloat(dimZ.value),
                    d: parseFloat(dimD.value)
                })
            });
            const data = await res.json();

            if (data.error) {
                alert('Error: ' + data.error);
                return;
            }


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
                    <span class="result-label">Best reflection</span>
                    <span class="result-value">#${data.bestReflection}</span>
                </div>
            `;

            clearBtn.classList.remove('hidden');
            toggleModeBtn.classList.remove('hidden');

            // Load 3D viewer
            Viewer.loadResults(data);
        } catch (e) {
            alert('Error: ' + e.message);
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
        Viewer.clear();
        updateCompareState();
    });

    // ── Toggle viewer mode ──────────────────────────
    toggleModeBtn.addEventListener('click', () => {
        const mode = Viewer.toggleMode();
        toggleModeBtn.textContent = mode === 'heatmap' ? '🎨 Dual Color' : '🌡️ Heatmap';
    });

})();
