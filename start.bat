@echo off
rem QA3D Startup Script (Windows)

cd /d "%~dp0"

echo Starting QA3D...
echo.
echo   Web UI: http://127.0.0.1:8000
echo.

julia --project=. app.jl
