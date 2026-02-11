#!/bin/bash
# Build QA3D distribution with sysimage

cd "$(dirname "$0")/.."

echo "Building QA3D sysimage..."
mkdir -p dist

julia --project=. build/build_sysimage.jl

# Copy app files to dist
cp -r app.jl routes.jl lib views public dist/
cp start.sh start.bat dist/
cp Project.toml VERSION dist/

echo ""
echo "Build complete! Distribution in dist/"
echo "Run with: julia --sysimage=dist/qa3d_sysimage.so --project=dist dist/app.jl"
