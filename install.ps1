# RedForge One-Click Install & Run for Windows
#
# Recommended usage (from anywhere):
#   irm https://raw.githubusercontent.com/synaptechintel/redforge/main/install.ps1 | iex
#
# What this does:
# - Clones or updates RedForge into %LOCALAPPDATA%\RedForge
# - Creates and populates the Python sidecar virtualenv (pip installs requirements)
# - Creates a Desktop shortcut and a Start Menu shortcut
# - Launches the app immediately
#
# After this, you can always launch RedForge from the Start Menu or Desktop.
# The included launchers (RedForge.bat / launch.ps1) will automatically prefer a
# pre-built native binary if you later run the full build.
#
# For the absolute best experience (native .exe + installer, no dev dependencies at runtime):
#   After first run, cd into the install dir and run:  scripts\build-windows.ps1
#   (this requires Rust, Node.js, Python, and Visual Studio Build Tools)

$ErrorActionPreference = 'Stop'

$RepoUrl      = 'https://github.com/synaptechintel/redforge.git'
$InstallDir   = "$env:LOCALAPPDATA\RedForge"
$AppName      = 'RedForge'

Write-Host "==> RedForge One-Click Windows Installer" -ForegroundColor Cyan
Write-Host "Installing / updating to: $InstallDir" -ForegroundColor Gray
Write-Host ""

# 1. Make sure git is available
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git is required." -ForegroundColor Red
    Write-Host "Please install Git for Windows: https://git-scm.com/download/win" -ForegroundColor Yellow
    Write-Host "Then re-run this command." -ForegroundColor Yellow
    exit 1
}

# 2. Clone or update the repository
if (Test-Path (Join-Path $InstallDir '.git')) {
    Write-Host "Updating existing installation..." -ForegroundColor Yellow
    Push-Location $InstallDir
    git fetch --all --quiet
    git reset --hard origin/main --quiet
    git pull --ff-only --quiet
    Pop-Location
} else {
    if (Test-Path $InstallDir) {
        Write-Host "Directory exists but is not a git repo. Removing and re-cloning..." -ForegroundColor Yellow
        Remove-Item $InstallDir -Recurse -Force
    }
    Write-Host "Cloning RedForge..." -ForegroundColor Green
    git clone --depth 1 $RepoUrl $InstallDir --quiet
}

Set-Location $InstallDir

# 3. Set up Python sidecar (the part that can be fully automated)
$venvPath = Join-Path $InstallDir 'sidecar\.venv'
$pythonCmd = $null
if (Get-Command python -ErrorAction SilentlyContinue) { $pythonCmd = 'python' }
elseif (Get-Command py -ErrorAction SilentlyContinue) { $pythonCmd = 'py -3' }

if ($pythonCmd) {
    Write-Host "Setting up Python sidecar virtual environment..." -ForegroundColor Green

    if (-not (Test-Path $venvPath)) {
        & $pythonCmd -m venv sidecar\.venv | Out-Null
    }

    $activateScript = Join-Path $venvPath 'Scripts\Activate.ps1'
    if (Test-Path $activateScript) {
        . $activateScript
        python -m pip install --upgrade pip --quiet
        if (Test-Path 'sidecar\requirements.txt') {
            python -m pip install -r sidecar\requirements.txt --quiet
        }
        Write-Host "  Sidecar ready." -ForegroundColor Green
    }
} else {
    Write-Host "Python not found in PATH." -ForegroundColor Yellow
    Write-Host "The sidecar (recon, remote execution, LLM) needs Python 3.12+." -ForegroundColor Yellow
    Write-Host "Install it from https://www.python.org/downloads/ (tick 'Add to PATH')." -ForegroundColor Yellow
}

# 4. Create nice shortcuts
Write-Host "Creating Desktop and Start Menu shortcuts..." -ForegroundColor Green

$WshShell = New-Object -ComObject WScript.Shell

$launcher = Join-Path $InstallDir 'RedForge.bat'
if (-not (Test-Path $launcher)) {
    $launcher = Join-Path $InstallDir 'launch.ps1'
}

# Desktop
$desktopPath = [Environment]::GetFolderPath('Desktop')
$desktopLnk  = $WshShell.CreateShortcut("$desktopPath\$AppName.lnk")
$desktopLnk.TargetPath       = $launcher
$desktopLnk.WorkingDirectory = $InstallDir
$desktopLnk.Description      = 'RedForge - Authorized Red Team Operations'
$desktopLnk.Save()

# Start Menu
$startMenu    = [Environment]::GetFolderPath('StartMenu')
$programs     = Join-Path $startMenu 'Programs'
$startLnk     = $WshShell.CreateShortcut("$programs\$AppName.lnk")
$startLnk.TargetPath       = $launcher
$startLnk.WorkingDirectory = $InstallDir
$startLnk.Description      = 'RedForge - Authorized Red Team Operations'
$startLnk.Save()

Write-Host ""
Write-Host "✅ Installation complete!" -ForegroundColor Green
Write-Host "   Installed to: $InstallDir"
Write-Host "   Shortcuts: Desktop and Start Menu → $AppName"
Write-Host ""

# 5. Launch immediately
Write-Host "Starting RedForge now..." -ForegroundColor Cyan
Start-Process -FilePath $launcher -WorkingDirectory $InstallDir -WindowStyle Normal

Write-Host ""
Write-Host "You can launch it later from the Start Menu or Desktop shortcut." -ForegroundColor Gray
Write-Host "For a fully native build (recommended for daily use), see scripts\build-windows.ps1 in the installed folder." -ForegroundColor Gray