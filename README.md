# Quality Assurance 3D (QA3D) v1.1.2

![Build](https://img.shields.io/badge/build-passing-brightgreen)
![Julia](https://img.shields.io/badge/Julia-1.11-9558B2?logo=julia&logoColor=white)
![Electron](https://img.shields.io/badge/Electron-41-47848F?logo=electron&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-passing-brightgreen?logo=linux&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-passing-brightgreen?logo=windows&logoColor=white)
![Status](https://img.shields.io/badge/status-in%20development-yellow)

A desktop application for comparing scanned models against generated reference surfaces. QA3D reads 3D scan files (`.xyzrgb`, `.obj`, `.ply`, `.stl`), generates a rectangular prism surface from user-specified dimensions, and registers the scan to the surface using PCA alignment and ICP. Built with Electron + Julia.

**Key Features:**
- **Multi-Format Model Loading** — reads 3D scan data from `.xyzrgb`, `.obj`, `.ply` (ASCII + binary), and `.stl` (ASCII + binary) files
- **Surface Generation** — creates rectangular prism surfaces from X, Y, Z dimensions
- **Auto-Density Calculation** — automatically matches surface point density to the scan
- **PCA + ICP Registration** — point-to-point ICP with 8-axis reflection search (multithreaded, up to 8 threads)
- **3D Visualization** — interactive Three.js viewer with distance heatmap, dual-color modes, point cloud / mesh rendering toggle, and per-cloud visibility controls

## Architecture

```
┌─────────────────────────────────────────┐
│        Electron Window (Chromium)       │
│  HTML/CSS/JS + Three.js 3D viewer       │
└──────────────┬──────────────────────────┘
               │ ipcRenderer / ipcMain
┌──────────────┴──────────────────────────┐
│       Node.js Main Process (Electron)   │
│  IPC handlers, file I/O, sidecar mgmt   │
└──────────────┬──────────────────────────┘
               │ stdin/stdout JSON
┌──────────────┴──────────────────────────┐
│         Julia Sidecar (QA3D.jl)         │
│  XYZRGB parsing, surface gen, PCA+ICP   │
└─────────────────────────────────────────┘
```

- **Frontend**: Vanilla JS + Three.js in an Electron window
- **Electron (Node.js)**: Handles window management, file system access, and IPC
- **Julia sidecar**: Runs as a subprocess, communicating via JSON over stdin/stdout. Handles XYZRGB parsing, surface generation, PCA alignment, and ICP registration

## System Requirements

- **Julia**: 1.11+
- **Node.js**: 18+ with npm

---

## Development

### 1. Clone and install dependencies

```bash
git clone https://github.com/dpaa-gov/QA3D
cd QA3D

# Julia dependencies
julia --project=. -e "using Pkg; Pkg.instantiate()"

# Node/Electron dependencies
npm install
```

### 2. Run the app

```bash
npm run dev
```

## Building for Distribution

The build process has two steps: compile the Julia sidecar, then build the Electron app.

### Step 1: Compile the Julia Sidecar

```bash
julia build/build_sysimage.jl
```

This uses PackageCompiler to create a standalone Julia executable in `sidecar/`. Takes 5–15 minutes.

### Step 2: Build the Electron App

```bash
npm run build
```

**Output by platform:**

| Platform | Output |
|----------|--------|
| **Linux** | `dist/QA3D-1.1.2.AppImage` |
| **Windows** | `dist/QA3D Setup 1.1.2.exe` |

---

## Usage

1. Click **Browse** to select a 3D scan file (`.xyzrgb`, `.obj`, `.ply`, or `.stl`)
2. Dimensions default to **X**: 20, **Y**: 8.91, **Z**: 34.90 — adjust to match your gauge block
3. **D** (density) auto-calculates when a file is selected, based on the scan's point count and box surface area:
   ```
   d = sqrt( 2(XY + XZ + YZ) / n_scan_points )
   ```
   This generates a reference surface with similar point density to the scan. You can override D manually.
4. Click **Compare** to run PCA + ICP registration
5. Results appear in the left panel and the **3D viewer** shows both clouds overlapping

### Example Data

The `test/` directory contains the same gauge block scan (69,997 vertices) in all supported formats, with both ASCII and binary variants for PLY and STL:

| File | Format |
|------|--------|
| `gauge_block.xyzrgb` | XYZRGB point cloud (ASCII) |
| `gauge_block.obj` | Wavefront OBJ (ASCII) |
| `gauge_block_binary.ply` | PLY (binary) |
| `gauge_block_ascii.ply` | PLY (ASCII) |
| `gauge_block_binary.stl` | STL (binary) |
| `gauge_block_ascii.stl` | STL (ASCII) |

Use dimensions **20 × 8.91 × 34.90 mm** when comparing.

### 3D Viewer

After a comparison completes, the viewer displays both clouds registered together:

- **Heatmap mode** (default) — each point/face is colored green → yellow → red by its distance to the nearest point on the other cloud. The color legend shows the auto-scaled distance range.
- **Dual color mode** — scan shown in gold, reference surface in blue. Toggle between modes with the 🎨 button above the viewer.
- **Point Cloud / Mesh toggle** — switch between point cloud and solid mesh rendering. Mesh mode is available for PLY, OBJ, and STL files; the generated surface always supports mesh.
- **Visibility checkboxes** — show or hide the scan and surface independently.

Use mouse to **orbit** (left-drag), **zoom** (scroll), and **pan** (right-drag).

### Registration Algorithm

1. **PCA alignment** — centers both point clouds and rotates the scan via principal component analysis
2. **8-reflection search** — PCA can flip axes, so all 8 sign permutations (±X, ±Y, ±Z) are tested in parallel
3. **Point-to-point ICP** — for each reflection, SVD-based rigid body alignment iteratively refines the fit
4. **Bidirectional Hausdorff** — `(mean_A→B + mean_B→A) / 2` measures the final fit quality
5. The reflection with the lowest Hausdorff distance is selected as the best result

### Interpreting Results

- **Hausdorff (mean)** — average surface deviation; lower = better scanner accuracy
- **A → B** — mean distance from scan to surface (scanner noise)
- **B → A** — mean distance from surface to scan (coverage gaps)
- **SD** — standard deviation of per-point distances; lower = more uniform accuracy
- **RMSE** — root mean squared error; penalizes large deviations more than mean
- **TEM** — Technical Error of Measurement (Dahlberg formula); standard QA metric for repeated measurements
- **Max distance** — largest single-point deviation; identifies worst-case scanner error
- **Best reflection** — which axis permutation produced the best alignment

---

## Project Structure

```
QA3D/
├── src/
│   ├── QA3D.jl               # Module entry + sidecar command dispatcher
│   ├── mesh_reader.jl        # Multi-format parser (xyzrgb, obj, ply, stl)
│   ├── surface_generator.jl  # Box surface point generator
│   └── registration.jl       # PCA + point-to-point ICP
├── public/
│   ├── index.html             # Single-page UI
│   ├── css/styles.css         # Dark theme
│   └── js/
│       ├── app.js             # Frontend logic
│       ├── viewer.js          # Three.js 3D viewer
│       └── three.min.js       # Three.js library
├── build/
│   ├── build_sysimage.jl      # PackageCompiler build script
│   └── precompile_workload.jl # AOT precompilation workload
├── test/                      # Example scan data
│   ├── gauge_block.xyzrgb     # Gauge block scan (70K points)
│   ├── gauge_block.obj        # Same scan as OBJ
│   ├── gauge_block_binary.ply # Same scan as PLY (binary)
│   ├── gauge_block_ascii.ply  # Same scan as PLY (ASCII)
│   ├── gauge_block_binary.stl # Same scan as STL (binary)
│   └── gauge_block_ascii.stl  # Same scan as STL (ASCII)
├── main.js                    # Electron main process
├── preload.js                 # Electron IPC bridge
├── app.jl                     # Julia dev mode entry point
├── package.json               # npm + electron-builder config
└── Project.toml               # Julia dependencies
```

## Citation

Lynch, J.J. 2026 QA3D. Quality Assurance 3D. Version 1.1.2. Defense POW/MIA Accounting Agency, Offutt AFB, NE.

## Known Issues

| Issue | Status | Details |
|-------|--------|---------|
| Compiled app crashes on Julia 1.12 | **Open — upstream bug** | PackageCompiler `create_app` bundles built with Julia 1.12 crash on startup. **Workaround**: build with Julia 1.11.x. See [PackageCompiler.jl #989](https://github.com/JuliaLang/PackageCompiler.jl/issues/989). |

## License

GNU General Public License v2.0
