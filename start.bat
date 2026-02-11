@echo off
REM QA3D Startup Script (development)

cd /d "%~dp0"

echo Starting QA3D...
echo.
echo   Web UI: http://127.0.0.1:8000
echo.

if exist "dist\qa3d_sysimage.dll" (
    julia --sysimage=dist\qa3d_sysimage.dll --project=. app.jl
) else (
    julia --project=. app.jl
)
