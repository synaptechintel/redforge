# RedForge - Windows EXE/Installer Build Script
# ============================================
# Produces a normal Windows app exe plus NSIS setup exe.

param(
    [switch]$SkipSidecar,
    [switch]$SkipNpmInstall
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

function Test-Command($cmd) {
    $oldPref = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
    } finally {
        $ErrorActionPreference = $oldPref
    }
}

function Assert-Command($cmd, $installHint) {
    if (-not (Test-Command $cmd)) {
        throw "Missing required command '$cmd'. $installHint"
    }
}

Write-Host "=== RedForge Windows EXE Build ===" -ForegroundColor Cyan
Write-Host "Project root: $ProjectRoot" -ForegroundColor Gray
Write-Host "AUTHORIZED USE ONLY" -ForegroundColor Yellow
Write-Host ""

Write-Host "[1/7] Checking required build tools..." -ForegroundColor Yellow
Assert-Command "node" "Install Node.js 20+ from https://nodejs.org/"
Assert-Command "npm" "Install Node.js 20+ from https://nodejs.org/"
Assert-Command "python" "Install Python 3.12+ from https://python.org/ and add it to PATH."
Assert-Command "rustc" "Install Rust from https://rustup.rs/"
Assert-Command "cargo" "Install Rust from https://rustup.rs/"
Write-Host "Tools OK" -ForegroundColor Green

Write-Host "[2/7] Ensuring Windows icons exist..." -ForegroundColor Yellow
& "$PSScriptRoot\ensure-windows-icons.ps1"
if (-not $?) { throw "Icon generation failed" }
$global:LASTEXITCODE = 0

if (-not $SkipNpmInstall) {
    Write-Host "[3/7] Installing/updating frontend dependencies..." -ForegroundColor Yellow
    npm install
    if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
} else {
    Write-Host "[3/7] Skipping npm install." -ForegroundColor Gray
}

if (-not $SkipSidecar) {
    Write-Host "[4/7] Building Python sidecar executable..." -ForegroundColor Yellow
    Push-Location sidecar
    try {
        python -m pip install --upgrade pip
        if ($LASTEXITCODE -ne 0) { throw "pip upgrade failed" }
        python -m pip install -r requirements.txt pyinstaller
        if ($LASTEXITCODE -ne 0) { throw "pip install failed" }

        if (Test-Path "dist") { Remove-Item -Recurse -Force "dist" }
        if (Test-Path "build") { Remove-Item -Recurse -Force "build" }

        pyinstaller redforge-sidecar.spec --clean --noconfirm
        if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed" }

        $exePath = "dist\redforge-sidecar\redforge-sidecar.exe"
        if (-not (Test-Path $exePath)) {
            throw "Expected sidecar not found at $exePath after build."
        }
        Write-Host "Sidecar built: $exePath" -ForegroundColor Green
    } finally {
        Pop-Location
    }

    Write-Host "[5/7] Staging sidecar for Tauri bundler..." -ForegroundColor Yellow
    $srcExe = "sidecar\dist\redforge-sidecar\redforge-sidecar.exe"
    $dstDir = "src-tauri\binaries"
    $dstExe = "$dstDir\redforge-sidecar-x86_64-pc-windows-msvc.exe"
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    Copy-Item $srcExe $dstExe -Force
    if (-not (Test-Path $dstExe)) { throw "Failed to stage sidecar at $dstExe" }
    Write-Host "Staged sidecar: $dstExe" -ForegroundColor Green
} else {
    Write-Host "[4/7] Skipping sidecar build." -ForegroundColor Gray
    Write-Host "[5/7] Verifying existing staged sidecar..." -ForegroundColor Yellow
    $dstExe = "src-tauri\binaries\redforge-sidecar-x86_64-pc-windows-msvc.exe"
    if (-not (Test-Path $dstExe)) { throw "SkipSidecar was used, but $dstExe does not exist." }
}

Write-Host "[6/7] Building frontend and Tauri Windows NSIS installer..." -ForegroundColor Yellow
npm run build
if ($LASTEXITCODE -ne 0) { throw "frontend build failed" }

npm run tauri build -- --bundles nsis
if ($LASTEXITCODE -ne 0) { throw "tauri build failed" }

Write-Host "[7/7] Verifying output files..." -ForegroundColor Yellow
$releaseExe = "src-tauri\target\release\redforge.exe"
$bundleDir = "src-tauri\target\release\bundle\nsis"
$installer = Get-ChildItem $bundleDir -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not (Test-Path $releaseExe)) { throw "Release app exe missing: $releaseExe" }
if (-not $installer) { throw "NSIS installer exe missing in $bundleDir" }

$launcherBat = "RedForge.bat"
@"
@echo off
start "" "%~dp0$releaseExe"
"@ | Out-File -FilePath $launcherBat -Encoding ASCII -Force

try {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\RedForge.lnk")
    $Shortcut.TargetPath = (Resolve-Path $releaseExe).Path
    $Shortcut.WorkingDirectory = Split-Path (Resolve-Path $releaseExe).Path -Parent
    $Shortcut.IconLocation = (Resolve-Path $releaseExe).Path + ",0"
    $Shortcut.Description = "RedForge"
    $Shortcut.Save()
} catch {
    Write-Warning "Could not create desktop shortcut automatically."
}

Write-Host ""
Write-Host "BUILD SUCCESSFUL" -ForegroundColor Green
Write-Host "App EXE:       $(Resolve-Path $releaseExe)" -ForegroundColor Cyan
Write-Host "Installer EXE: $($installer.FullName)" -ForegroundColor Cyan
Write-Host "Launcher BAT:  $(Resolve-Path $launcherBat)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Test the installer on a clean Windows VM before distributing." -ForegroundColor Yellow
