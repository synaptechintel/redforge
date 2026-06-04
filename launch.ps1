# RedForge - One Click Launcher (Windows)
# =======================================
# Double-click this file in Windows Explorer (or run from PowerShell)
# to launch RedForge with zero typing.
#
# Behavior:
# - If a release build exists (from build-windows.ps1 or `npm run tauri build`),
#   it launches the production app immediately.
# - Otherwise, it falls back to development mode (`npm run tauri dev`).
#   This requires the full development prerequisites (see README).
#
# This makes running the app as easy as double-clicking a shortcut.
#
# For production users: after installing the NSIS .exe produced by the build,
# you can also just use the Start Menu / Desktop shortcut created by the installer.
#
# After running the build script or this launcher with a release build:
#   - Right-click "RedForge" in Start Menu -> "Pin to taskbar" for the easiest access.
#
# SAFETY: Only use on authorized targets. See README for warnings.

$ErrorActionPreference = "Continue"

Write-Host "RedForge Launcher" -ForegroundColor Cyan

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

$releaseExe = Join-Path $projectRoot "src-tauri\target\release\redforge.exe"

if (Test-Path $releaseExe) {
    Write-Host "Found release build. Launching RedForge..." -ForegroundColor Green

    # One-time setup: create desktop + Start Menu shortcuts if they don't exist
    # (then user can right-click Start Menu entry -> Pin to taskbar)
    $desktopLnk = "$env:USERPROFILE\Desktop\RedForge.lnk"
    $startMenuDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    $startMenuLnk = "$startMenuDir\RedForge.lnk"

    if (-not (Test-Path $desktopLnk) -or -not (Test-Path $startMenuLnk)) {
        try {
            $WshShell = New-Object -ComObject WScript.Shell
            if (-not (Test-Path $desktopLnk)) {
                $Shortcut = $WshShell.CreateShortcut($desktopLnk)
                $Shortcut.TargetPath = $releaseExe
                $Shortcut.WorkingDirectory = Split-Path $releaseExe -Parent
                $Shortcut.IconLocation = "$releaseExe,0"
                $Shortcut.Description = "RedForge Red Team Operations Platform"
                $Shortcut.Save()
                Write-Host "  • Created Desktop shortcut: $desktopLnk" -ForegroundColor Green
            }
            if (-not (Test-Path $startMenuLnk)) {
                New-Item -ItemType Directory -Force -Path $startMenuDir | Out-Null
                $Shortcut = $WshShell.CreateShortcut($startMenuLnk)
                $Shortcut.TargetPath = $releaseExe
                $Shortcut.WorkingDirectory = Split-Path $releaseExe -Parent
                $Shortcut.IconLocation = "$releaseExe,0"
                $Shortcut.Description = "RedForge Red Team Operations Platform"
                $Shortcut.Save()
                Write-Host "  • Created Start Menu shortcut: $startMenuLnk" -ForegroundColor Green
            }
        } catch {
            Write-Host "  (Could not auto-create shortcuts this time - you can create them manually)" -ForegroundColor Yellow
        }
    }

    # Launch the app (it will bundle its own sidecar)
    Start-Process -FilePath $releaseExe -WorkingDirectory (Split-Path $releaseExe -Parent)
    exit 0
}

# No release build - try dev mode
Write-Host "No release build found. Starting development mode..." -ForegroundColor Yellow
Write-Host "This requires Rust, Node.js, Python, etc. See README.md for setup." -ForegroundColor Yellow

if (Get-Command npm -ErrorAction SilentlyContinue) {
    npm run tauri dev
} else {
    Write-Error "npm not found. Please install Node.js and run this from a proper environment."
    Read-Host "Press Enter to exit"
    exit 1
}
