#!/bin/bash
# QA3D launcher — sets thread count and launches the compiled binary
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export JULIA_NUM_THREADS=8
exec "$SCRIPT_DIR/bin/qa3d" "$@"
