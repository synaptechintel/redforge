# ============================================================================
#  RedForge - One-Click Install & Run for Windows
# ============================================================================
#  Run from anywhere:
#    irm https://raw.githubusercontent.com/synaptechintel/redforge/main/install.ps1 | iex
#
#  Or save and run:
#    .\install.ps1
#
#  What this does:
#    1. Checks prerequisites (git, Node.js, Python, Rust)
#    2. Clones or updates RedForge to %LOCALAPPDATA%\RedForge
#    3. Runs npm install
#    4. Creates Python sidecar venv + installs dependencies
#    5. Creates Desktop + Start Menu shortcuts
#    6. Launches the app immediately
#
#  After this, just double-click the Desktop shortcut to launch.
#
#  For native release builds (fastest, no dev deps needed at runtime):
#    cd $env:LOCALAPPDATA\RedForge
#    .\scripts\build-windows.ps1
#
#  AUTHORIZED USE ONLY - See README.md
# ============================================================================

$ErrorActionPreference = 'Stop'

$RepoUrl    = 'https://github.com/synaptechintel/redforge.git'
$InstallDir = "$env:LOCALAPPDATA\RedForge"
$AppName    = 'RedForge'

function Write-Step($icon, $msg, $color) {
    Write-Host "  [$icon] " -NoNewline -ForegroundColor $color
    Write-Host $msg
}

function Write-OK($msg)   { Write-Step "OK" $msg Green }
function Write-FAIL($msg) { Write-Step "!!" $msg Red }
function Write-WARN($msg) { Write-Step "~~" $msg Yellow }
function Write-INFO($msg) { Write-Step ".." $msg Cyan }

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Red
Write-Host "   REDFORGE - One-Click Windows Installer" -ForegroundColor White
Write-Host "  ============================================" -ForegroundColor Red
Write-Host "   AUTHORIZED USE ONLY" -ForegroundColor Yellow
Write-Host "  ============================================" -ForegroundColor Red
Write-Host ""
Write-Host "  Installing to: $InstallDir" -ForegroundColor Gray
Write-Host ""

# ─── 1. Prerequisites ────────────────────────────────────────────────
$missing = @()

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-FAIL "Git not found - install from https://git-scm.com/download/win"
    $missing += "Git"
} else {
    Write-OK "Git found"
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-FAIL "Node.js not found - install from https://nodejs.org/"
    $missing += "Node.js"
} else {
    Write-OK "Node.js $(node --version)"
}

$pythonCmd = $null
if (Get-Command python -ErrorAction SilentlyContinue) {
    $pythonCmd = "python"
    Write-OK "$(python --version)"
} elseif (Get-Command py -ErrorAction SilentlyContinue) {
    $pythonCmd = "py"
    Write-OK "$(py -3 --version)"
} else {
    Write-FAIL "Python not found - install from https://python.org/ (check 'Add to PATH')"
    $missing += "Python"
}

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-WARN "Rust not found - needed for 'tauri dev'. Install from https://rustup.rs/"
    Write-Host "         (Not blocking install - you can install it later)" -ForegroundColor DarkYellow
} else {
    Write-OK "$(rustc --version)"
}

if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
    Write-WARN "Ollama not found. Red Team Leader features need it."
    Write-Host "         Install: https://ollama.com/  then: ollama pull llama3.1:8b" -ForegroundColor DarkYellow
} else {
    Write-OK "Ollama found"
}

Write-Host ""

if ($missing.Count -gt 0) {
    Write-FAIL "Missing required prerequisites: $($missing -join ', ')"
    Write-Host "  Install the tools listed above and re-run this installer." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# ─── 2. Clone or update ─────────────────────────────────────────────
if (Test-Path (Join-Path $InstallDir '.git')) {
    Write-INFO "Updating existing installation..."
    Push-Location $InstallDir
    try {
        git fetch --all --quiet 2>$null
        git pull --ff-only --quiet 2>$null
        Write-OK "Repository updated."
    } catch {
        Write-WARN "Git pull failed - continuing with existing version."
    }
    Pop-Location
} else {
    if (Test-Path $InstallDir) {
        Write-WARN "Directory exists but is not a git repo. Removing and re-cloning..."
        Remove-Item $InstallDir -Recurse -Force -Confirm:$false
    }
    Write-INFO "Cloning RedForge..."
    git clone --depth 1 $RepoUrl $InstallDir --quiet 2>$null
    Write-OK "Repository cloned."
}

Set-Location $InstallDir

# ─── 3. npm install ──────────────────────────────────────────────────
if (-not (Test-Path (Join-Path $InstallDir 'node_modules'))) {
    Write-INFO "Installing Node.js dependencies (may take a minute)..."
    & npm install --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-WARN "npm install had issues - some features may not work."
    } else {
        Write-OK "Node dependencies installed."
    }
} else {
    Write-OK "Node dependencies already installed."
}

# ─── 4. Python sidecar ──────────────────────────────────────────────
$venvPath = Join-Path $InstallDir 'sidecar\.venv'

if (-not (Test-Path $venvPath)) {
    Write-INFO "Creating Python virtual environment..."
    if ($pythonCmd -eq "py") {
        & py -3 -m venv $venvPath
    } else {
        & python -m venv $venvPath
    }
    Write-OK "Virtual environment created."
}

$activateScript = Join-Path $venvPath 'Scripts\Activate.ps1'
if (Test-Path $activateScript) {
    Write-INFO "Installing Python sidecar dependencies..."
    . $activateScript
    & python -m pip install --upgrade pip --quiet 2>$null
    if (Test-Path 'sidecar\requirements.txt') {
        & python -m pip install -r sidecar\requirements.txt --quiet 2>$null
    }
    Write-OK "Sidecar dependencies installed."
}

# Mark setup done
"Setup completed on $(Get-Date)" | Out-File -FilePath ".redforge-setup-done" -Encoding utf8

# ─── 5. Create shortcuts ────────────────────────────────────────────
Write-INFO "Creating Desktop and Start Menu shortcuts..."

try {
    $WshShell = New-Object -ComObject WScript.Shell
    $launcher = Join-Path $InstallDir 'RedForge.bat'

    # Desktop shortcut
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    $desktopLnk  = $WshShell.CreateShortcut("$desktopPath\$AppName.lnk")
    $desktopLnk.TargetPath       = $launcher
    $desktopLnk.WorkingDirectory = $InstallDir
    $desktopLnk.Description      = 'RedForge - Authorized Red Team Operations'
    $desktopLnk.Save()
    Write-OK "Desktop shortcut created"

    # Start Menu shortcut
    $startMenu = [Environment]::GetFolderPath('StartMenu')
    $programs   = Join-Path $startMenu 'Programs'
    if (-not (Test-Path $programs)) { New-Item -ItemType Directory -Force -Path $programs | Out-Null }
    $startLnk   = $WshShell.CreateShortcut("$programs\$AppName.lnk")
    $startLnk.TargetPath       = $launcher
    $startLnk.WorkingDirectory = $InstallDir
    $startLnk.Description      = 'RedForge - Authorized Red Team Operations'
    $startLnk.Save()
    Write-OK "Start Menu shortcut created"
} catch {
    Write-WARN "Could not create shortcuts automatically."
}

# ─── 6. Launch ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "   Installation complete!" -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Installed to:  $InstallDir" -ForegroundColor Gray
Write-Host "  Shortcuts:     Desktop + Start Menu -> $AppName" -ForegroundColor Gray
Write-Host ""
Write-Host "  Launching RedForge now..." -ForegroundColor Cyan
Write-Host "  (First launch compiles Rust - may take 3-5 minutes)" -ForegroundColor DarkGray
Write-Host ""

Start-Process -FilePath $launcher -WorkingDirectory $InstallDir -WindowStyle Normal

Write-Host "  Launch it anytime from the Desktop shortcut or Start Menu." -ForegroundColor Gray
Write-Host "  For native builds: cd $InstallDir; .\scripts\build-windows.ps1" -ForegroundColor Gray
Write-Host ""
