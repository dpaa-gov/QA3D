@echo off
setlocal enabledelayedexpansion
REM QA3D Windows Packaging Script
REM Creates a standalone compiled application bundle
REM
REM Usage: build\package.bat
REM
REM Output: dist\QA3D-v{VERSION}-windows-x86_64.zip

cd /d "%~dp0\.."
set "PROJECT_DIR=%cd%"
set "SCRIPT_DIR=%PROJECT_DIR%\build"

REM Version
if exist "%PROJECT_DIR%\VERSION" (
    set /p VERSION=<"%PROJECT_DIR%\VERSION"
) else (
    set "VERSION=0.1.0"
)

set "ARCH=x86_64"
set "BUNDLE_NAME=QA3D-v%VERSION%-windows-%ARCH%"
set "DIST_DIR=%PROJECT_DIR%\dist"
set "COMPILED_DIR=%DIST_DIR%\QA3D-compiled"
set "STAGE_DIR=%DIST_DIR%\%BUNDLE_NAME%"

echo.
echo ==========================================
echo      QA3D Windows Bundle Builder
echo ==========================================
echo   Version:  %VERSION%
echo   Arch:     %ARCH%
echo   Output:   %BUNDLE_NAME%.zip
echo ==========================================
echo.

REM Step 1: Build compiled app
echo 1. Building compiled application...
echo    This may take 5-15 minutes...
julia "%SCRIPT_DIR%\build_sysimage.jl"

if not exist "%COMPILED_DIR%\bin\qa3d.exe" (
    echo ERROR: Compiled app not found at %COMPILED_DIR%\bin\qa3d.exe
    pause
    exit /b 1
)

REM Step 2: Stage the bundle
echo 2. Staging bundle...
if exist "%STAGE_DIR%" rmdir /s /q "%STAGE_DIR%"
xcopy /e /i /q "%COMPILED_DIR%" "%STAGE_DIR%" >nul

REM Step 3: Copy runtime assets
echo 3. Copying runtime assets...
xcopy /e /i /q "%PROJECT_DIR%\public" "%STAGE_DIR%\public" >nul
xcopy /e /i /q "%PROJECT_DIR%\views" "%STAGE_DIR%\views" >nul
copy "%PROJECT_DIR%\Manifest.toml" "%STAGE_DIR%\share\julia\" >nul

REM Step 4: Archive
echo 4. Creating archive...
cd "%DIST_DIR%"
powershell -NoProfile -Command "Compress-Archive -Path '%BUNDLE_NAME%' -DestinationPath '%BUNDLE_NAME%.zip' -Force"

echo.
echo ==========================================
echo   Bundle created successfully!
echo ==========================================
echo   Archive: dist\%BUNDLE_NAME%.zip
echo   Run:     bin\qa3d.exe
echo.
pause
