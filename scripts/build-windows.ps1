# RedForge - Windows-Specific Build Script
# ========================================
#
# PURPOSE:
# Automates the full build process for the Windows version of RedForge.
# This produces a professional NSIS installer (.exe) ready for deployment
# on Windows machines (primary target for red team ops against Windows targets).
#
# USAGE (on Windows, in PowerShell):
#   1. Open PowerShell as Administrator (recommended for installs).
#   2. cd to the redforge project root (where package.json is).
#   3. .\scripts\build-windows.ps1
#
# PREREQUISITES (install these first on your Windows machine):
# - Rust (via rustup: https://rustup.rs/)
# - Node.js 20+ (https://nodejs.org/)
# - Python 3.12+ (https://python.org/) + pip
# - Visual Studio Build Tools (for Rust + native crates): 
#     winget install Microsoft.VisualStudio.2022.BuildTools
#     (Include "Desktop development with C++" workload)
# - (Optional but recommended) WiX Toolset for .msi: https://wixtoolset.org/
#
# WHAT IT DOES:
# - Installs npm deps.
# - Builds the Python sidecar (.exe) using PyInstaller (critical for remote exec).
# - Copies the sidecar to the correct location for Tauri bundling.
# - Runs `tauri build` which produces the Windows installer.
#
# OUTPUT:
# - src-tauri\target\release\bundle\nsis\RedForge_<version>_x64-setup.exe
# - (If WiX installed) also .msi
#
# IMPORTANT:
# - This is for AUTHORIZED, LEGAL red team / pen testing use ONLY.
# - The resulting installer still requires end-users to have Ollama running
#   locally for the Red Team Leader features.
# - After build, test on a clean VM before distribution.
# - Replace placeholder icons in src-tauri\icons\ with real ones for prod.
#
# For Linux/macOS cross-build notes, see README.md "Windows Version" section.
#
# Run this script at your own risk. See full disclaimers in README.

param(
    [switch]$SkipSidecar,   # Use existing sidecar stub/binary
    [switch]$SkipNpmInstall # Assume deps already installed
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

Write-Host "=== RedForge Windows Build Script ===" -ForegroundColor Cyan
Write-Host "Project root: $ProjectRoot" -ForegroundColor Gray
Write-Host ""
Write-Host "⚠️  CRITICAL: AUTHORIZED USE ONLY. Unauthorized use is illegal." -ForegroundColor Red
Write-Host "    See README.md for full legal/ethical warnings." -ForegroundColor Red
Write-Host ""

# Helper to check if command exists
function Test-Command($cmd) {
    $oldPref = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try { if (Get-Command $cmd) { return $true } } catch {}
    $ErrorActionPreference = $oldPref
    return $false
}

# 1. Prerequisites checks (non-fatal warnings)
Write-Host "[1/5] Checking prerequisites..." -ForegroundColor Yellow
$missing = @()
if (-not (Test-Command "rustc")) { $missing += "Rust (rustc)" }
if (-not (Test-Command "node")) { $missing += "Node.js" }
if (-not (Test-Command "python")) { $missing += "Python" }
if ($missing.Count -gt 0) {
    Write-Warning "Missing or not in PATH: $($missing -join ', ')"
    Write-Host "Install them and ensure they are in your PATH, then re-run." -ForegroundColor Yellow
    # Continue anyway; user may have them via winget etc.
}

# 2. Frontend dependencies
if (-not $SkipNpmInstall) {
    Write-Host "[2/5] Installing/updating npm dependencies..." -ForegroundColor Yellow
    npm install
    if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
} else {
    Write-Host "[2/5] Skipping npm install (as requested)." -ForegroundColor Gray
}

# 3. Python sidecar (the heart of remote execution features)
if (-not $SkipSidecar) {
    Write-Host "[3/5] Building Python sidecar with PyInstaller (Windows .exe)..." -ForegroundColor Yellow
    Push-Location sidecar
    try {
        python -m pip install --upgrade pip
        python -m pip install -r requirements.txt pyinstaller
        if ($LASTEXITCODE -ne 0) { throw "pip install failed" }

        # Clean previous build
        if (Test-Path "dist") { Remove-Item -Recurse -Force "dist" }
        if (Test-Path "build") { Remove-Item -Recurse -Force "build" }

        pyinstaller redforge-sidecar.spec --clean --noconfirm
        if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed" }

        $exePath = "dist\redforge-sidecar\redforge-sidecar.exe"
        if (-not (Test-Path $exePath)) {
            throw "Expected sidecar not found at $exePath after build."
        }
        Write-Host "Sidecar built successfully at $exePath" -ForegroundColor Green
    } finally {
        Pop-Location
    }

    # 4. Stage the sidecar for Tauri
    Write-Host "[4/5] Staging sidecar for Tauri bundler..." -ForegroundColor Yellow
    $srcExe = "sidecar\dist\redforge-sidecar\redforge-sidecar.exe"
    $dstDir = "src-tauri\binaries"
    $dstExe = "$dstDir\redforge-sidecar-x86_64-pc-windows-msvc.exe"

    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    Copy-Item $srcExe $dstExe -Force
    Write-Host "Copied to $dstExe" -ForegroundColor Green
} else {
    Write-Host "[3/5] Skipping sidecar build (using existing binary/stub)." -ForegroundColor Gray
    Write-Host "[4/5] Skipping sidecar staging." -ForegroundColor Gray
}

# 5. Tauri build for Windows
Write-Host "[5/5] Running Tauri build (this will produce the NSIS installer)..." -ForegroundColor Yellow
Write-Host "This may take several minutes on first build (Rust compilation)." -ForegroundColor Gray

npm run tauri build
if ($LASTEXITCODE -ne 0) { throw "tauri build failed" }

# Find and report the output
$bundleDir = "src-tauri\target\release\bundle\nsis"
if (Test-Path $bundleDir) {
    Write-Host ""
    Write-Host "✅ BUILD SUCCESSFUL!" -ForegroundColor Green
    Write-Host "Windows installer(s) located at:" -ForegroundColor Green
    Get-ChildItem $bundleDir -Filter "*.exe" | ForEach-Object {
        Write-Host "  $($_.FullName)" -ForegroundColor Cyan
    }
    Get-ChildItem $bundleDir -Filter "*.msi" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  $($_.FullName) (MSI - requires WiX)" -ForegroundColor Cyan
    }
} else {
    Write-Host "Build completed, but bundle dir not found at expected location. Check src-tauri\target\release\bundle\" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  - Test the installer on a clean Windows VM (never on production systems)." -ForegroundColor Yellow
Write-Host "  - On the target machine, user must also have Ollama installed and a model pulled (e.g. `ollama run llama3.1:8b`)." -ForegroundColor Yellow
Write-Host "  - Distribute only to authorized personnel with proper RoE documentation." -ForegroundColor Yellow
# 6. One-click launch helpers (RedForge.bat + Desktop shortcut for true one-click experience)
Write-Host "[6/6] Creating one-click launch helpers..." -ForegroundColor Yellow

$releaseExe = "src-tauri\target\release\redforge.exe"
$launcherBat = "RedForge.bat"

if (Test-Path $releaseExe) {
    # Simple double-clickable .bat in the project root (portable launch)
    @"
@echo off
REM RedForge - One Click Launcher (auto-generated)
start "" "%~dp0$releaseExe"
"@ | Out-File -FilePath $launcherBat -Encoding ASCII -Force

    Write-Host "  • Created $launcherBat (double-click anywhere for instant launch)" -ForegroundColor Green

    # Desktop shortcut - the ultimate one-click launch
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\RedForge.lnk")
        $Shortcut.TargetPath = (Resolve-Path $releaseExe).Path
        $Shortcut.WorkingDirectory = Split-Path (Resolve-Path $releaseExe).Path -Parent
        $Shortcut.IconLocation = (Resolve-Path $releaseExe).Path + ",0"
        $Shortcut.Description = "RedForge Red Team Operations Platform - One Click Launch"
        $Shortcut.Save()
        Write-Host "  • Desktop shortcut created: RedForge.lnk" -ForegroundColor Green
    } catch {
        Write-Warning "Could not create desktop shortcut automatically (you can make one manually pointing to the redforge.exe)."
    }

    # Start Menu shortcut (appears in Start Menu for easy one-click launch)
    try {
        $startMenuDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
        New-Item -ItemType Directory -Force -Path $startMenuDir | Out-Null
        $startMenuShortcut = "$startMenuDir\RedForge.lnk"
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($startMenuShortcut)
        $Shortcut.TargetPath = (Resolve-Path $releaseExe).Path
        $Shortcut.WorkingDirectory = Split-Path (Resolve-Path $releaseExe).Path -Parent
        $Shortcut.IconLocation = (Resolve-Path $releaseExe).Path + ",0"
        $Shortcut.Description = "RedForge Red Team Operations Platform"
        $Shortcut.Save()
        Write-Host "  • Start Menu shortcut created: $startMenuShortcut" -ForegroundColor Green
        Write-Host "    (Will appear in Start Menu -> RedForge. Right-click -> Pin to taskbar if desired.)" -ForegroundColor Green
    } catch {
        Write-Warning "Could not create Start Menu shortcut automatically."
    }
} else {
    Write-Host "  • No release exe found yet - one-click launchers skipped. Re-run this script after a successful tauri build." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "One-click launch options:" -ForegroundColor Yellow
Write-Host "  • Double-click RedForge.bat (in project root) for instant launch." -ForegroundColor Cyan
Write-Host "  • Desktop shortcut and Start Menu (RedForge) created above." -ForegroundColor Cyan
Write-Host "    (In Start Menu: right-click RedForge -> 'Pin to taskbar' for super easy access.)" -ForegroundColor Cyan
Write-Host "  • After running the NSIS .exe installer, you'll get additional Start Menu/Desktop entries." -ForegroundColor Cyan

Write-Host ""
Write-Host "See README.md for full deployment checklist, runtime requirements, and legal warnings." -ForegroundColor Gray
