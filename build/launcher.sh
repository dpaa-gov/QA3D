#!/bin/bash
## QA3D Launcher
## Starts the Genie web app and opens in browser app mode.
## This script is meant for the standalone distribution bundle.

set -e

# Resolve app directory (where this script lives)
APP_DIR="$(cd "$(dirname "$0")" && pwd)"

# Use bundled Julia if available, otherwise fall back to system Julia
if [ -x "$APP_DIR/julia/bin/julia" ]; then
    JULIA="$APP_DIR/julia/bin/julia"
else
    JULIA="$(command -v julia 2>/dev/null || true)"
    if [ -z "$JULIA" ]; then
        echo "ERROR: Julia not found. Please install Julia or use the full QA3D bundle."
        exit 1
    fi
fi

# Use sysimage if available
SYSIMAGE="$APP_DIR/dist/qa3d_sysimage.so"
if [ -f "$SYSIMAGE" ]; then
    JULIA_FLAGS="--project=$APP_DIR -J$SYSIMAGE"
    echo "Using precompiled sysimage (fast startup)"
else
    JULIA_FLAGS="--project=$APP_DIR"
    echo "No sysimage found — using JIT compilation (slower startup)"
fi

echo ""
echo "  ╔═══════════════════════════════════════╗"
echo "  ║     QA3D - Quality Assurance 3D       ║"
echo "  ╚═══════════════════════════════════════╝"
echo ""

# Open browser after a delay (in background) while Julia starts
(
    # Wait for the web server to accept connections
    for i in $(seq 1 30); do
        if curl -s http://127.0.0.1:8000/ >/dev/null 2>&1; then
            # Open in browser app mode — try Chrome, Edge, Chromium, then default
            if command -v google-chrome &>/dev/null; then
                google-chrome --app="http://127.0.0.1:8000" --new-window 2>/dev/null &
            elif command -v google-chrome-stable &>/dev/null; then
                google-chrome-stable --app="http://127.0.0.1:8000" --new-window 2>/dev/null &
            elif command -v chromium-browser &>/dev/null; then
                chromium-browser --app="http://127.0.0.1:8000" --new-window 2>/dev/null &
            elif command -v chromium &>/dev/null; then
                chromium --app="http://127.0.0.1:8000" --new-window 2>/dev/null &
            elif command -v microsoft-edge &>/dev/null; then
                microsoft-edge --app="http://127.0.0.1:8000" --new-window 2>/dev/null &
            else
                xdg-open "http://127.0.0.1:8000" 2>/dev/null &
            fi
            break
        fi
        sleep 2
    done
) &

echo "Starting QA3D on port 8000..."
echo "  Web UI: http://127.0.0.1:8000"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Run Julia in foreground — process stays alive, output visible, Ctrl+C works
exec $JULIA $JULIA_FLAGS "$APP_DIR/app.jl"
