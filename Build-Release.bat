@echo off
REM ============================================================================
REM  RedForge - PRODUCTION BUILD (one-click)
REM  Double-click this to build a shippable Windows installer.
REM
REM  Output: src-tauri\target\release\bundle\nsis\RedForge_*_x64-setup.exe
REM          src-tauri\target\release\redforge.exe  (portable .exe)
REM
REM  First build takes 10-20 minutes (Rust + sidecar PyInstaller).
REM  Subsequent builds are much faster.
REM ============================================================================
setlocal
cd /d "%~dp0"

title RedForge - Production Build

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\productize.ps1" %*
if %ERRORLEVEL% neq 0 (
    echo.
    echo Build failed - see errors above.
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ============================================
echo  Build complete!
echo  Installer + portable exe in:
echo    src-tauri\target\release\bundle\nsis\
echo    src-tauri\target\release\redforge.exe
echo ============================================
pause
