# QA3D 0.1.0

![Build](https://img.shields.io/badge/build-passing-brightgreen)
![Julia](https://img.shields.io/badge/Julia-1.10+-blue)
![Linux](https://img.shields.io/badge/Linux-supported-informational?logo=linux&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-supported-informational?logo=windows&logoColor=white)
![Status](https://img.shields.io/badge/status-in%20development-yellow)

Quality Assurance 3D application for comparing scanned models against generated reference surfaces. QA3D reads `.xyzrgb` scan files, generates a rectangular prism surface from user-specified dimensions, and registers the scan to the surface using PCA alignment and ICP.

**Key Features:**
- **XYZRGB Model Loading** — reads 3D scan data from `.xyzrgb` files
- **Surface Generation** — creates rectangular prism point clouds from X, Y, Z dimensions
- **Auto-Density Calculation** — automatically matches surface point density to the scan
- **PCA + ICP Registration** — point-to-point ICP with 8-axis reflection search
- **3D Visualization** — interactive Three.js viewer with distance heatmap and dual-color modes
- Cross-platform (Linux/Windows) with sysimage packaging

## Architecture

| Layer | Technology |
|-------|-----------|
| Backend | Julia + Genie |
| Frontend | HTML/CSS/JS |
| Visualization | Three.js + OrbitControls |
| Packaging | PackageCompiler sysimage |

## Project Structure

```
QA3D/
├── app.jl                     # Genie server entry point
├── routes.jl                  # API routes
├── lib/
│   ├── xyzrgb_reader.jl       # .xyzrgb file parser
│   ├── surface_generator.jl   # Box surface point generator
│   └── registration.jl        # PCA + point-to-point ICP
├── views/index.html           # Single-page UI
├── public/
│   ├── css/styles.css         # Dark theme
│   ├── js/app.js              # Frontend logic
│   ├── js/viewer.js           # Three.js 3D viewer
│   └── favicon.svg            # App icon
├── build/                     # Sysimage build scripts
├── start.sh                   # Linux startup
└── start.bat                  # Windows startup
```

## Installation

### Prerequisites
- Julia 1.10+

### Development Setup

```bash
git clone https://github.com/dpaa-gov/QA3D
cd QA3D
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

### Running

```bash
# Linux
chmod +x start.sh
./start.sh

# Windows
start.bat
```

App will be available at http://127.0.0.1:8000

## Usage

1. Click **Browse** to select a `.xyzrgb` scan file
2. Dimensions default to **X**: 20, **Y**: 8.91, **Z**: 34.90 — adjust to match your gauge block
3. **D** (density) auto-calculates when a file is selected, based on the scan's point count and box surface area:
   ```
   d = sqrt( 2(XY + XZ + YZ) / n_scan_points )
   ```
   This generates a reference surface with similar point density to the scan. You can override D manually.
4. Click **Compare** to run PCA + ICP registration
5. Results appear in the left panel and the **3D viewer** shows both clouds overlapping

### 3D Viewer

After a comparison completes, the viewer displays both point clouds registered together:

- **Heatmap mode** (default) — each point is colored green → yellow → red by its distance to the nearest point on the other cloud. The color legend shows the auto-scaled distance range.
- **Dual color mode** — scan points shown in gold, reference surface in blue, for visual separation. Toggle between modes with the 🎨 button above the viewer.

Use mouse to **orbit** (left-drag), **zoom** (scroll), and **pan** (right-drag).

### Registration Algorithm

1. **PCA alignment** — centers both point clouds and rotates the scan via principal component analysis
2. **8-reflection search** — PCA can flip axes, so all 8 sign permutations (±X, ±Y, ±Z) are tested
3. **Point-to-point ICP** — for each reflection, SVD-based rigid body alignment iteratively refines the fit
4. **Bidirectional Hausdorff** — `(mean_A→B + mean_B→A) / 2` measures the final fit quality
5. The reflection with the lowest Hausdorff distance is selected as the best result

### Interpreting Results

- **Hausdorff (mean)** — average surface deviation; lower = better scanner accuracy
- **A → B** — mean distance from scan to surface (scanner noise)
- **B → A** — mean distance from surface to scan (coverage gaps)
- **Best reflection** — which axis permutation produced the best alignment

## Building Distribution

```bash
chmod +x build/package.sh
./build/package.sh
```

Creates a self-contained distribution in `dist/` with a precompiled sysimage for fast startup.

## Acknowledgments

- **Jeff Lynch** — concept and development
- Built with [Genie.jl](https://genieframework.com/)

## Citation

Lynch, J.J. 2026 QA3D. Quality Assurance 3D. Version 0.1.0. Defense POW/MIA Accounting Agency, Offutt AFB, NE.

## License

GNU General Public License v2.0 — see [LICENSE](LICENSE) for details.
