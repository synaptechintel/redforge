@echo off
REM RedForge - Universal One-Click Launcher (Windows)
REM Double-click this .bat file to launch RedForge with zero hassle.
REM 
REM It will:
REM   - Prefer the production build if you ran the build script.
REM   - Fall back to development mode if no build exists yet.
REM
REM For the smoothest experience (auto shortcuts + taskbar pin), first run scripts\build-windows.ps1
REM or double-click launch.ps1 (it will create Desktop + Start Menu shortcuts).
REM Then: right-click Start Menu "RedForge" -> "Pin to taskbar" for ultimate one-click.

setlocal
cd /d "%~dp0"

set "RELEASE_EXE=src-tauri\target\release\redforge.exe"

if exist "%RELEASE_EXE%" (
    echo Launching RedForge (release version)...
    start "" "%RELEASE_EXE%"
    goto :eof
)

echo No release build found.
echo Starting development mode (requires full dev setup)...
echo See README.md for prerequisites.

if exist "package.json" (
    npm run tauri dev
) else (
    echo ERROR: Not in the RedForge project root.
    pause
)
