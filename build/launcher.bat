@echo off
REM QA3D Launcher for Windows
REM Starts the Genie web app and opens in browser app mode.
REM This script is meant for the standalone distribution bundle.

cd /d "%~dp0"

echo.
echo   ========================================
echo        QA3D - Quality Assurance 3D
echo   ========================================
echo.

REM Detect Julia: bundled or system
if exist "%~dp0julia\bin\julia.exe" (
    set "JULIA=%~dp0julia\bin\julia.exe"
) else (
    where julia >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Julia not found. Please install Julia or use the full QA3D bundle.
        pause
        exit /b 1
    )
    set "JULIA=julia"
)

REM Detect sysimage
set "SYSIMAGE=%~dp0dist\qa3d_sysimage.dll"
if exist "%SYSIMAGE%" (
    set "JULIA_FLAGS=--project=%~dp0. -J%SYSIMAGE%"
    echo Using precompiled sysimage (fast startup)
) else (
    set "JULIA_FLAGS=--project=%~dp0."
    echo No sysimage found — using JIT compilation (slower startup)
)

REM --- Start Genie app and capture its PID ---
echo Starting QA3D on port 8000...
set "GENIE_PID="
for /f %%a in ('powershell -NoProfile -Command "(Start-Process \"%JULIA%\" -ArgumentList '%JULIA_FLAGS% \"%~dp0app.jl\"' -WindowStyle Minimized -PassThru).Id"') do set "GENIE_PID=%%a"
if not defined GENIE_PID (
    echo WARNING: Could not capture Genie app PID
) else (
    echo   Genie PID: %GENIE_PID%
)

REM Wait for Genie
echo Waiting for web app...
set WAITED=0
set MAX_WAIT=120

:genie_wait
if %WAITED% GEQ %MAX_WAIT% goto genie_timeout
curl -s http://127.0.0.1:8000/ >nul 2>&1
if %ERRORLEVEL% EQU 0 goto genie_ready
timeout /t 2 /nobreak >nul
set /a WAITED=%WAITED%+2
echo   ...waiting (%WAITED% seconds)
goto genie_wait

:genie_timeout
echo ERROR: QA3D failed to start within %MAX_WAIT% seconds
if defined GENIE_PID taskkill /PID %GENIE_PID% /F >nul 2>&1
pause
exit /b 1

:genie_ready
set "URL=http://127.0.0.1:8000"

REM Open in browser app mode — try Edge (pre-installed), then Chrome
echo.
echo Opening QA3D in browser...
where msedge >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    start "" msedge --app="%URL%" --new-window
    goto browser_done
)
if exist "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" (
    start "" "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" --app="%URL%" --new-window
    goto browser_done
)
if exist "C:\Program Files\Google\Chrome\Application\chrome.exe" (
    start "" "C:\Program Files\Google\Chrome\Application\chrome.exe" --app="%URL%" --new-window
    goto browser_done
)
REM Fallback: open in default browser
start "" "%URL%"

:browser_done
echo.
echo QA3D is running!
echo   Web UI: %URL%
echo.
echo Press Ctrl+C to stop manually.

REM --- Monitor: check if Genie PID is still alive ---
:monitor_loop
timeout /t 5 /nobreak >nul
if defined GENIE_PID (
    tasklist /FI "PID eq %GENIE_PID%" 2>nul | findstr /I "julia.exe" >nul
    if errorlevel 1 (
        echo.
        echo QA3D exited.
        goto :eof
    )
)
goto monitor_loop
