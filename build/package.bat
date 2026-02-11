@echo off
REM QA3D Windows Packaging Script
REM Creates a self-contained distributable bundle
REM
REM Usage: build\package.bat
REM
REM Prerequisites:
REM   - Julia installed and on PATH
REM   - Project dependencies installed (Pkg.instantiate)
REM
REM Output: dist\QA3D-v{VERSION}-windows-x86_64.zip

setlocal enabledelayedexpansion
cd /d "%~dp0\.."

REM Read version
if exist VERSION (
    set /p VERSION=<VERSION
) else (
    set VERSION=0.1.0
)

set ARCH=x86_64
set BUNDLE_NAME=QA3D-v%VERSION%-windows-%ARCH%
set DIST_DIR=%CD%\dist
set STAGE_DIR=%DIST_DIR%\%BUNDLE_NAME%

echo.
echo ============================================
echo      QA3D Windows Bundle Builder
echo ============================================
echo   Version:  %VERSION%
echo   Arch:     %ARCH%
echo   Output:   %BUNDLE_NAME%.zip
echo ============================================
echo.

REM Step 1: Build sysimage
echo 1. Building sysimage...
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"
julia --project=. build\build_sysimage.jl

REM Check sysimage exists
set SYSIMAGE=%DIST_DIR%\qa3d_sysimage.dll
if not exist "%SYSIMAGE%" (
    echo ERROR: Sysimage not found at %SYSIMAGE%
    pause
    exit /b 1
)

REM Clean staging directory
if exist "%STAGE_DIR%" rmdir /s /q "%STAGE_DIR%"
mkdir "%STAGE_DIR%"

echo 2. Copying application source...
for %%F in (app.jl routes.jl Project.toml VERSION README.md) do (
    if exist "%%F" copy "%%F" "%STAGE_DIR%\" >nul
)
for %%D in (lib views public data) do (
    if exist "%%D" xcopy /e /i /q "%%D" "%STAGE_DIR%\%%D" >nul
)

REM Generate Manifest.toml for the bundle
echo    Generating Manifest.toml...
julia --project="%STAGE_DIR%" -e "using Pkg; Pkg.instantiate()"

echo 3. Copying sysimage...
mkdir "%STAGE_DIR%\dist" 2>nul
copy "%SYSIMAGE%" "%STAGE_DIR%\dist\" >nul

echo 4. Copying launcher...
copy "%~dp0launcher.bat" "%STAGE_DIR%\launcher.bat" >nul
copy "%~dp0QA3D.vbs" "%STAGE_DIR%\QA3D.vbs" >nul

echo 5. Bundling Julia runtime...
for /f "delims=" %%i in ('julia -e "print(Sys.BINDIR)"') do set JULIA_HOME=%%i
for %%i in ("%JULIA_HOME%\..") do set JULIA_BASE=%%~fi

mkdir "%STAGE_DIR%\julia" 2>nul
xcopy /e /i /q "%JULIA_BASE%\bin" "%STAGE_DIR%\julia\bin" >nul
xcopy /e /i /q "%JULIA_BASE%\lib" "%STAGE_DIR%\julia\lib" >nul
xcopy /e /i /q "%JULIA_BASE%\share" "%STAGE_DIR%\julia\share" >nul
if exist "%JULIA_BASE%\include" xcopy /e /i /q "%JULIA_BASE%\include" "%STAGE_DIR%\julia\include" >nul

echo 6. Copying package depot (only required packages)...
for /f "delims=" %%i in ('julia -e "print(first(DEPOT_PATH))"') do set DEPOT=%%i

REM Get required package paths and copy them
mkdir "%STAGE_DIR%\.julia\packages" 2>nul
julia --project=. -e "using Pkg; deps = Pkg.dependencies(); for (uuid, info) in deps; if info.source !== nothing && isdir(info.source); println(info.source); end; end" > "%TEMP%\qa3d_pkgs.txt" 2>nul

for /f "delims=" %%P in (%TEMP%\qa3d_pkgs.txt) do (
    for %%H in ("%%P") do (
        for %%N in ("%%~dpH.") do (
            set PKG_HASH=%%~nxH
            set PKG_NAME=%%~nxN
            mkdir "%STAGE_DIR%\.julia\packages\!PKG_NAME!" 2>nul
            xcopy /e /i /q "%%P" "%STAGE_DIR%\.julia\packages\!PKG_NAME!\!PKG_HASH!" >nul
        )
    )
)

REM Copy artifacts
if exist "%DEPOT%\artifacts" (
    echo    Copying artifacts...
    xcopy /e /i /q "%DEPOT%\artifacts" "%STAGE_DIR%\.julia\artifacts" >nul
)

echo 7. Creating run script with DEPOT_PATH...
(
echo @echo off
echo REM QA3D - Click to Run
echo set "APP_DIR=%%~dp0"
echo set "JULIA_DEPOT_PATH=%%APP_DIR%%.julia"
echo call "%%APP_DIR%%launcher.bat"
) > "%STAGE_DIR%\qa3d.bat"

echo 8. Creating archive...
REM Use PowerShell to create zip (available on all modern Windows)
powershell -Command "Compress-Archive -Path '%STAGE_DIR%' -DestinationPath '%DIST_DIR%\%BUNDLE_NAME%.zip' -Force"

echo.
echo ============================================
echo   Bundle created successfully!
echo ============================================
echo   Archive: dist\%BUNDLE_NAME%.zip
echo ============================================
echo.
echo To distribute:
echo   1. Upload %BUNDLE_NAME%.zip
echo   2. Users extract and run: qa3d.bat

pause
