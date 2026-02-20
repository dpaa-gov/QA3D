#!/bin/bash
# QA3D Development Startup
# Starts the Genie web app and opens browser in app mode

cd "$(dirname "$0")"

PORT=8001

# Start Julia server in background with threads for parallel ICP reflections
THREADS=8
echo "Starting QA3D on port $PORT (threads=$THREADS)..."
julia --threads=$THREADS --project=. -e "using QA3D; QA3D.APP_ROOT[] = pwd(); QA3D.start_server(open=false)" &
JULIA_PID=$!

# Auto-open browser in app mode when server is ready
(
    for i in $(seq 1 60); do
        if curl -s http://127.0.0.1:$PORT/ >/dev/null 2>&1; then
            if command -v google-chrome &>/dev/null; then
                google-chrome --app="http://127.0.0.1:$PORT" --new-window 2>/dev/null &
            elif command -v google-chrome-stable &>/dev/null; then
                google-chrome-stable --app="http://127.0.0.1:$PORT" --new-window 2>/dev/null &
            elif command -v chromium-browser &>/dev/null; then
                chromium-browser --app="http://127.0.0.1:$PORT" --new-window 2>/dev/null &
            elif command -v chromium &>/dev/null; then
                chromium --app="http://127.0.0.1:$PORT" --new-window 2>/dev/null &
            elif command -v microsoft-edge &>/dev/null; then
                microsoft-edge --app="http://127.0.0.1:$PORT" --new-window 2>/dev/null &
            else
                xdg-open "http://127.0.0.1:$PORT" 2>/dev/null &
            fi
            break
        fi
        sleep 2
    done
) &

echo ""
echo "QA3D is running!"
echo "  - Web UI: http://127.0.0.1:$PORT"
echo ""
echo "Press Ctrl+C to stop"

# Cleanup function
cleanup() {
    echo "Stopping QA3D..."
    kill $JULIA_PID 2>/dev/null
    wait $JULIA_PID 2>/dev/null
    echo "Stopped."
    exit 0
}

# Handle Ctrl+C
trap cleanup SIGINT SIGTERM

# Wait for process to exit
wait $JULIA_PID
