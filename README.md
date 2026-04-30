# Quality Assurance 3D (QA3D) v1.2.0

![Build](https://img.shields.io/badge/build-passing-brightgreen)
![Julia](https://img.shields.io/badge/Julia-1.11-9558B2?logo=julia&logoColor=white)
![Electron](https://img.shields.io/badge/Electron-41-47848F?logo=electron&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-passing-brightgreen?logo=linux&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-passing-brightgreen?logo=windows&logoColor=white)
![Status](https://img.shields.io/badge/status-in%20development-yellow)

A desktop application for comparing scanned models against generated reference surfaces. QA3D reads 3D scan files (`.xyzrgb`, `.obj`, `.ply`, `.stl`), generates a rectangular prism surface from user-specified dimensions, and registers the scan to the surface using PCA alignment and ICP. Includes automated face-pair dimensional analysis for per-axis accuracy, parallelism, and flatness metrics. Built with Electron + Julia.

**Key Features:**
- **Multi-Format Model Loading** — reads 3D scan data from `.xyzrgb`, `.obj`, `.ply` (ASCII + binary), and `.stl` (ASCII + binary) files
- **Surface Generation** — creates rectangular prism surfaces from X, Y, Z dimensions with per-vertex outward normals
- **Auto-Density Calculation** — automatically matches surface point density to the scan
- **PCA + ICP Registration** — point-to-point ICP with 8-axis reflection search (multithreaded, up to 8 threads)
- **Comprehensive QA Metrics** — Chamfer Distance, Signed Mean Bias, RMSE, SD, TEM, 95th Percentile Error, In-Tolerance Yield, and Max Distance
- **Dimensional Analysis** — automated face-pair plane fitting for per-axis measured dimension, dimensional error, parallelism angle, and face flatness (comparable to Geomagic Control X manual plane-distance workflow)
- **Report Export** — save timestamped QA reports as styled PDF files
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
│  Mesh parsing, surface gen, PCA+ICP, QA  │
└─────────────────────────────────────────┘
```

- **Frontend**: Vanilla JS + Three.js in an Electron window
- **Electron (Node.js)**: Handles window management, file system access, and IPC
- **Julia sidecar**: Runs as a subprocess, communicating via JSON over stdin/stdout. Handles mesh parsing, surface generation (with per-vertex normals), PCA alignment, ICP registration, and QA metric computation

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
| **Linux** | `dist/QA3D-1.2.0.AppImage` |
| **Windows** | `dist/QA3D Setup 1.2.0.exe` |

---

## Usage

1. Click **Browse** to select a 3D scan file (`.xyzrgb`, `.obj`, `.ply`, or `.stl`)
2. Dimensions default to **X**: 20, **Y**: 8.91, **Z**: 34.90 — adjust to match your gauge block
3. **D** (density) auto-calculates when a file is selected, based on the scan's point count and box surface area:
   ```
   d = sqrt( 2(XY + XZ + YZ) / n_scan_points )
   ```
   This generates a reference surface with similar point density to the scan. You can override D manually.
4. **Tol** (tolerance) defaults to **0.05 mm** — set this to your scanner's published accuracy for the In-Tolerance Yield metric
5. **Trim%** defaults to **10** — percentage of each face boundary to exclude from plane fitting (removes rounded edge/corner points). Set to 0 to disable trimming.
6. Click **Compare** to run PCA + ICP registration
7. Results appear in the left panel and the **3D viewer** shows both clouds overlapping
8. Click **📄 Save Report** to export a timestamped QA report as a PDF

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
4. **Bidirectional Mean Distance** — `(mean_A→B + mean_B→A) / 2` (Chamfer Distance) measures the final fit quality
5. The reflection with the lowest Chamfer Distance is selected as the best result

### Interpreting Results

#### Distance Metrics

These are global metrics computed from nearest-neighbor distances between the registered scan and the generated reference surface. For each scan point, the distance to the closest reference point is measured, and vice versa.

- **Chamfer Distance** — The average of the two directional mean distances: `(mean_S→R + mean_R→S) / 2`. This is the single best summary of overall scan quality. Lower = better. Typical good scanner values: < 0.05 mm.
- **Scan → Reference** — Mean distance from each scan point to its nearest reference surface point. Measures **scanner noise and distortion** — how much the scan deviates from the ideal shape.
- **Reference → Scan** — Mean distance from each reference point to its nearest scan point. Measures **coverage gaps** — areas of the block the scanner missed or undersampled.
- **Signed Mean** — Instead of absolute distance, each scan point's displacement is projected along the reference surface normal. Positive = the scan is consistently *outside* the ideal shape (bloating/oversizing), negative = consistently *inside* (shrinking/undersizing). Near zero means no systematic bias.
- **SD** — Standard deviation of all per-point distances. Measures **precision** — how uniform the deviations are. Low SD with high mean = consistent systematic error. High SD = noisy, variable accuracy.
- **RMSE** — Root Mean Squared Error. Like the mean, but squares each distance first, so large deviations are penalized more heavily. More sensitive to outliers than the mean.
- **TEM** — Technical Error of Measurement (Dahlberg formula): `sqrt(Σd² / 2n)`. A standard anthropometric precision metric — included for compatibility with bioanthropological reporting workflows.
- **Max Distance (S→R)** — The single worst scan point. Indicates worst-case scanner noise (often at edges, reflective spots, or dust particles).
- **Max Distance (R→S)** — The single worst reference gap. Indicates worst-case coverage blind spot (often on occluded faces or steep angles).

#### Percentile Metrics

Percentiles provide a robust alternative to maximum values that aren't skewed by single-point outliers.

- **95th Percentile (S→R)** — 95% of scan points fall within this distance of the reference. Upper boundary of typical scanner noise, ignoring the worst 5% (often edge artifacts or dust).
- **95th Percentile (R→S)** — 95% of reference points have a scan point within this distance. Upper boundary of coverage quality.
- **95th Percentile (Bidirectional)** — 95th percentile across all distances (both directions combined). A single robust "worst reasonable case" number.

#### Tolerance Analysis

- **In-Tolerance** — Percentage of scan points whose distance to the reference surface is ≤ the user-specified tolerance (default: 0.05 mm). A direct pass/fail metric: ≥95% (green), ≥80% (orange), <80% (red).

#### Registration

- **Best reflection** — PCA alignment can introduce axis flips. QA3D tests all 8 sign permutations (±X, ±Y, ±Z) and selects the one with the lowest Chamfer Distance. This reports which permutation won.

#### Dimensional Analysis

After ICP registration, the scan is segmented into 6 face clusters based on proximity to the known reference face planes. An independent least-squares plane is fitted to each face cluster using SVD, and per-axis metrics are computed from opposing face pairs.

**Edge trimming:** Before plane fitting, points within **Trim%** of the face boundary along each edge are excluded. This removes rounded corners and edge spray that would otherwise inflate flatness RMSE and bias the measured dimension inward. The default of 10% excludes the outer 10% on each side along both in-plane axes, retaining ~64% of each face's area (the central region). Set Trim% to 0 to disable.

- **Nominal** — The user-entered block dimension for this axis (e.g., 20.00 mm).
- **Measured** — Perpendicular distance between the two opposing fitted planes. This is computed by projecting the vector between the two plane centroids onto their average normal direction, giving the true perpendicular gap regardless of any lateral offset between face centers.
- **Error** — `Measured − Nominal`. Positive = the scan is larger than the known dimension (block appears "fatter" along this axis). Negative = smaller ("thinner"). A consistent error across all axes suggests a scale calibration issue; error on one axis suggests directional scanner bias.
- **Parallelism (∠ Para)** — Angle between the two opposing face normals. For a perfect rectangular prism, this is 0°. Any deviation means the faces are slightly tilted relative to each other (trapezoidal deformation). Computed as `acos(|dot(n₁, n₂)|)` where n₁ and n₂ are the fitted plane normals.
- **Flatness (Flat −/+)** — Planarity RMSE for each face in the pair. "−" is the face at the lower coordinate, "+" is at the higher coordinate. Each value is the root-mean-square of signed distances from the face's points to its fitted plane. Low values (< 0.01) mean the scanner captured a nearly perfect flat surface. High values indicate surface warping, noise, or edge contamination.

**How plane fitting works:** SVD (Singular Value Decomposition) of the centered face points finds three perpendicular directions of spread. The direction with the *least* spread is perpendicular to the face — that's the plane normal. The plane passes through the centroid (average position) of the face points.

### Report Export

Click **📄 Save Report** after a comparison to export a styled PDF report containing all input parameters, metrics, and results. Reports include color-coded indicators for signed bias direction and tolerance pass/fail status.

---

## Project Structure

```
QA3D/
├── src/
│   ├── QA3D.jl               # Module entry + sidecar command dispatcher
│   ├── mesh_reader.jl        # Multi-format parser (xyzrgb, obj, ply, stl)
│   ├── surface_generator.jl  # Box surface + normal generator
│   ├── registration.jl       # PCA + ICP + QA metrics
│   └── dimensional_analysis.jl # Face-pair plane fitting + dimensional metrics
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

Lynch, J.J. 2026 QA3D. Quality Assurance 3D. Version 1.2.0. Defense POW/MIA Accounting Agency, Offutt AFB, NE.

## Known Issues

| Issue | Status | Details |
|-------|--------|---------|
| Compiled app crashes on Julia 1.12 | **Open — upstream bug** | PackageCompiler `create_app` bundles built with Julia 1.12 crash on startup. **Workaround**: build with Julia 1.11.x. See [PackageCompiler.jl #989](https://github.com/JuliaLang/PackageCompiler.jl/issues/989). |
| Axis Mapping for Perfect Cubes | **Limitation** | The dimensional analysis maps PCA axes to user-input dimensions by sorting their lengths. If scanning a perfect cube (e.g., 20x20x20mm), the sorting cannot distinguish the axes, resulting in arbitrary X/Y/Z labels. **Workaround**: Always use an asymmetrical calibration artifact (like a 1-2-3 block) for scanner QA. |

## License

GNU General Public License v2.0
