// QA3D 3D Viewer — Three.js point cloud visualization with distance heatmap
// Depends on THREE + TrackballControls

const Viewer = (function () {
    'use strict';

    let scene, camera, renderer, controls;
    let scanCloud = null, surfCloud = null;
    let legendEl = null;
    let currentMode = 'heatmap'; // 'heatmap' or 'dual'
    let storedData = null;
    let containerId = null;
    let initialized = false;
    let currentColormap = 'green-red';
    let currentPointSize = 0.4;

    // ── Colormap definitions ────────────────────────
    const colormaps = {
        'green-red': {
            label: 'Green → Red',
            css: 'linear-gradient(to right, #00ff1a, #ffff00, #ff0000)',
            map(t) {
                let r, g, b;
                if (t < 0.5) {
                    r = t * 2; g = 1.0; b = 0.0;
                } else {
                    r = 1.0; g = 1.0 - (t - 0.5) * 2; b = 0.0;
                }
                return { r, g, b };
            }
        },
        'viridis': {
            label: 'Viridis',
            css: 'linear-gradient(to right, #440154, #31688e, #35b779, #fde725)',
            map(t) {
                const stops = [
                    [0.267, 0.004, 0.329],
                    [0.283, 0.141, 0.458],
                    [0.254, 0.265, 0.530],
                    [0.207, 0.372, 0.553],
                    [0.164, 0.471, 0.558],
                    [0.128, 0.567, 0.551],
                    [0.135, 0.659, 0.518],
                    [0.267, 0.749, 0.441],
                    [0.478, 0.821, 0.318],
                    [0.741, 0.873, 0.150],
                    [0.993, 0.906, 0.144]
                ];
                return sampleStops(stops, t);
            }
        },
        'inferno': {
            label: 'Inferno',
            css: 'linear-gradient(to right, #000004, #420a68, #932667, #dd513a, #fca50a, #fcffa4)',
            map(t) {
                const stops = [
                    [0.001, 0.000, 0.014],
                    [0.133, 0.027, 0.329],
                    [0.341, 0.063, 0.431],
                    [0.545, 0.114, 0.380],
                    [0.735, 0.216, 0.263],
                    [0.878, 0.376, 0.122],
                    [0.957, 0.553, 0.039],
                    [0.982, 0.733, 0.114],
                    [0.945, 0.894, 0.319],
                    [0.988, 1.000, 0.644]
                ];
                return sampleStops(stops, t);
            }
        }
    };

    function sampleStops(stops, t) {
        const n = stops.length - 1;
        const idx = t * n;
        const lo = Math.min(Math.floor(idx), n - 1);
        const hi = lo + 1;
        const f = idx - lo;
        return {
            r: stops[lo][0] + (stops[hi][0] - stops[lo][0]) * f,
            g: stops[lo][1] + (stops[hi][1] - stops[lo][1]) * f,
            b: stops[lo][2] + (stops[hi][2] - stops[lo][2]) * f
        };
    }

    // ── Color helpers ────────────────────────────────
    function distanceToColor(t) {
        return colormaps[currentColormap].map(t);
    }

    // ── Initialize (deferred) ───────────────────────
    function init(id) {
        containerId = id;
    }

    function ensureInitialized() {
        if (initialized) return;
        initialized = true;

        const container = document.getElementById(containerId);
        if (!container) return;

        // Clear placeholder
        container.innerHTML = '';

        scene = new THREE.Scene();
        scene.background = new THREE.Color(0x1a1d23);

        camera = new THREE.PerspectiveCamera(60, container.clientWidth / container.clientHeight, 0.1, 10000);
        camera.position.set(0, 0, 50);

        renderer = new THREE.WebGLRenderer({ antialias: true });
        renderer.setPixelRatio(window.devicePixelRatio);
        renderer.setSize(container.clientWidth, container.clientHeight);
        container.appendChild(renderer.domElement);

        controls = new THREE.TrackballControls(camera, renderer.domElement);
        controls.rotateSpeed = 1.2;
        controls.zoomSpeed = 1.2;
        controls.panSpeed = 0.3;
        controls.staticMoving = true;
        controls.mouseButtons = {
            LEFT: 0,     // left-click triggers ROTATE (no landmarks in QA3D)
            MIDDLE: 1,   // middle-click triggers ZOOM
            RIGHT: 2     // right-click triggers PAN
        };

        // Ambient light
        scene.add(new THREE.AmbientLight(0xffffff, 1.0));

        // Resize handling
        const ro = new ResizeObserver(() => {
            const w = container.clientWidth;
            const h = container.clientHeight;
            camera.aspect = w / h;
            camera.updateProjectionMatrix();
            renderer.setSize(w, h);
            controls.handleResize();
        });
        ro.observe(container);

        animate();
    }

    function animate() {
        requestAnimationFrame(animate);
        if (controls) controls.update();
        if (renderer && scene && camera) renderer.render(scene, camera);
    }

    // ── Build point cloud geometry ──────────────────
    function createPointCloud(coords, colors, size) {
        const geometry = new THREE.BufferGeometry();
        geometry.setAttribute('position', new THREE.Float32BufferAttribute(coords, 3));
        geometry.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));

        const material = new THREE.PointsMaterial({
            size: size || 0.3,
            vertexColors: true,
            sizeAttenuation: true
        });

        return new THREE.Points(geometry, material);
    }

    // ── Recompute heatmap colors from stored distances ──
    function recomputeHeatColors() {
        if (!storedData) return;
        const range = storedData.maxDist - storedData.minDist || 1;

        for (let i = 0; i < storedData.nScan; i++) {
            const t = (storedData.scanDistances[i] - storedData.minDist) / range;
            const c = distanceToColor(Math.min(1, Math.max(0, t)));
            storedData.scanHeatColors[i * 3] = c.r;
            storedData.scanHeatColors[i * 3 + 1] = c.g;
            storedData.scanHeatColors[i * 3 + 2] = c.b;
        }

        for (let i = 0; i < storedData.nSurf; i++) {
            const t = (storedData.surfDistances[i] - storedData.minDist) / range;
            const c = distanceToColor(Math.min(1, Math.max(0, t)));
            storedData.surfHeatColors[i * 3] = c.r;
            storedData.surfHeatColors[i * 3 + 1] = c.g;
            storedData.surfHeatColors[i * 3 + 2] = c.b;
        }
    }

    // ── Load comparison results ─────────────────────
    function loadResults(data) {
        ensureInitialized();
        storedData = data;

        // Remove old clouds
        if (scanCloud) { scene.remove(scanCloud); scanCloud.geometry.dispose(); }
        if (surfCloud) { scene.remove(surfCloud); surfCloud.geometry.dispose(); }

        // Build heatmap colors for scan
        const scanCoords = new Float32Array(data.scanCoords);
        const surfCoords = new Float32Array(data.surfCoords);
        const scanDists = data.scanDistances;
        const surfDists = data.surfDistances;

        const nScan = scanDists.length;
        const nSurf = surfDists.length;

        // Store for mode switching
        storedData.nScan = nScan;
        storedData.nSurf = nSurf;
        storedData.scanCoordsF32 = scanCoords;
        storedData.surfCoordsF32 = surfCoords;

        // Find global min/max for consistent scale (loop to avoid stack overflow with large arrays)
        let minDist = Infinity, maxDist = -Infinity;
        for (let i = 0; i < scanDists.length; i++) {
            if (scanDists[i] < minDist) minDist = scanDists[i];
            if (scanDists[i] > maxDist) maxDist = scanDists[i];
        }
        for (let i = 0; i < surfDists.length; i++) {
            if (surfDists[i] < minDist) minDist = surfDists[i];
            if (surfDists[i] > maxDist) maxDist = surfDists[i];
        }
        storedData.minDist = minDist;
        storedData.maxDist = maxDist;

        // Compute heatmap colors
        storedData.scanHeatColors = new Float32Array(nScan * 3);
        storedData.surfHeatColors = new Float32Array(nSurf * 3);
        recomputeHeatColors();

        // Dual-color: scan = gold, surface = blue
        storedData.scanDualColors = new Float32Array(nScan * 3);
        for (let i = 0; i < nScan; i++) {
            storedData.scanDualColors[i * 3] = 0.85;
            storedData.scanDualColors[i * 3 + 1] = 0.65;
            storedData.scanDualColors[i * 3 + 2] = 0.13;
        }

        storedData.surfDualColors = new Float32Array(nSurf * 3);
        for (let i = 0; i < nSurf; i++) {
            storedData.surfDualColors[i * 3] = 0.3;
            storedData.surfDualColors[i * 3 + 1] = 0.5;
            storedData.surfDualColors[i * 3 + 2] = 0.9;
        }

        // Default to heatmap mode
        applyMode('heatmap');

        // Auto-fit camera
        fitCamera(scanCoords, surfCoords);

        // Build legend
        buildLegend(minDist, maxDist);
    }

    function applyMode(mode) {
        currentMode = mode;
        if (!storedData) return;

        if (scanCloud) { scene.remove(scanCloud); scanCloud.geometry.dispose(); }
        if (surfCloud) { scene.remove(surfCloud); surfCloud.geometry.dispose(); }

        if (mode === 'heatmap') {
            scanCloud = createPointCloud(storedData.scanCoordsF32, storedData.scanHeatColors, currentPointSize);
            surfCloud = createPointCloud(storedData.surfCoordsF32, storedData.surfHeatColors, currentPointSize);
            if (legendEl) legendEl.style.display = '';
        } else {
            scanCloud = createPointCloud(storedData.scanCoordsF32, storedData.scanDualColors, currentPointSize);
            surfCloud = createPointCloud(storedData.surfCoordsF32, storedData.surfDualColors, currentPointSize);
            if (legendEl) legendEl.style.display = 'none';
        }

        scene.add(scanCloud);
        scene.add(surfCloud);
    }

    function toggleMode() {
        applyMode(currentMode === 'heatmap' ? 'dual' : 'heatmap');
        return currentMode;
    }

    function getMode() { return currentMode; }

    // ── Fit camera to bounding box ──────────────────
    function fitCamera(coords1, coords2) {
        let minX = Infinity, minY = Infinity, minZ = Infinity;
        let maxX = -Infinity, maxY = -Infinity, maxZ = -Infinity;

        const updateBounds = (coords) => {
            for (let i = 0; i < coords.length; i += 3) {
                minX = Math.min(minX, coords[i]);
                maxX = Math.max(maxX, coords[i]);
                minY = Math.min(minY, coords[i + 1]);
                maxY = Math.max(maxY, coords[i + 1]);
                minZ = Math.min(minZ, coords[i + 2]);
                maxZ = Math.max(maxZ, coords[i + 2]);
            }
        };

        updateBounds(coords1);
        updateBounds(coords2);

        const cx = (minX + maxX) / 2;
        const cy = (minY + maxY) / 2;
        const cz = (minZ + maxZ) / 2;
        const size = Math.max(maxX - minX, maxY - minY, maxZ - minZ);

        camera.position.set(cx, cy, cz + size * 1.5);
        controls.target.set(cx, cy, cz);
        controls.update();
    }

    // ── Color legend bar ────────────────────────────
    function buildLegend(minDist, maxDist) {
        // Remove existing
        if (legendEl) legendEl.remove();

        const container = renderer.domElement.parentElement;
        legendEl = document.createElement('div');
        legendEl.className = 'color-legend';
        const gradientCss = colormaps[currentColormap].css;
        legendEl.innerHTML = `
            <div class="legend-bar">
                <div class="legend-gradient" style="background: ${gradientCss}"></div>
            </div>
            <div class="legend-labels">
                <span>${minDist.toFixed(3)}</span>
                <span>${((minDist + maxDist) / 2).toFixed(3)}</span>
                <span>${maxDist.toFixed(3)}</span>
            </div>
            <div class="legend-title">Distance</div>
        `;
        container.appendChild(legendEl);
    }

    // ── Set colormap and recompute ──────────────────
    function setColormap(name) {
        if (!colormaps[name]) return;
        currentColormap = name;
        if (!storedData) return;

        recomputeHeatColors();

        // Refresh clouds if in heatmap mode
        if (currentMode === 'heatmap') {
            applyMode('heatmap');
        }

        // Update legend gradient
        buildLegend(storedData.minDist, storedData.maxDist);
    }

    function clear() {
        if (scanCloud) { scene.remove(scanCloud); scanCloud.geometry.dispose(); scanCloud = null; }
        if (surfCloud) { scene.remove(surfCloud); surfCloud.geometry.dispose(); surfCloud = null; }
        if (legendEl) { legendEl.remove(); legendEl = null; }
        storedData = null;
    }

    function setPointSize(size) {
        currentPointSize = size;
        if (scanCloud) scanCloud.material.size = size;
        if (surfCloud) surfCloud.material.size = size;
    }

    return { init, loadResults, toggleMode, getMode, setColormap, setPointSize, clear };
})();
