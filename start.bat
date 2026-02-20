@echo off
REM QA3D Development Startup
cd /d "%~dp0"
julia --threads=8 --project=. -e "using QA3D; QA3D.APP_ROOT[] = pwd(); QA3D.start_server()"
pause
