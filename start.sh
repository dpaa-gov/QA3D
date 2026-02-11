#!/bin/bash
# QA3D Startup Script (development)

cd "$(dirname "$0")"

echo "Starting QA3D..."
echo ""
echo "  Web UI: http://127.0.0.1:8000"
echo ""

if [ -f dist/qa3d_sysimage.so ]; then
    julia --sysimage=dist/qa3d_sysimage.so --project=. app.jl
elif [ -f dist/qa3d_sysimage.dylib ]; then
    julia --sysimage=dist/qa3d_sysimage.dylib --project=. app.jl
else
    julia --project=. app.jl
fi
