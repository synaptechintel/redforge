# ============================================================================
#  RedForge - TRUE One-Click Launcher (PowerShell / Windows)
#  ============================================================================
#  Right-click -> "Run with PowerShell", or double-click if policy allows.
#
#  Does everything automatically:
#    1. Prerequisite detection (Node, Python, Rust, Ollama)
#    2. npm install (if needed)
#    3. Python venv + sidecar deps (if needed)
#    4. Desktop + Start Menu shortcuts (one-time)
#    5. Launches release build or tauri dev
#
#  Subsequent runs skip setup (~2 seconds to launch).
#  Delete .redforge-setup-done to force re-setup.
#
#  AUTHORIZED USE ONLY - See README.md
# ============================================================================

$ErrorActionPreference = "Continue"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

function Write-Step($icon, $msg, $color) {
    Write-Host "  [$icon] " -NoNewline -ForegroundColor $color
    Write-Host $msg
}

function Write-OK($msg)   { Write-Step "OK"   $msg Green }
function Write-FAIL($msg) { Write-Step "!!"   $msg Red }
function Write-WARN($msg) { Write-Step "~~"   $msg Yellow }
function Write-INFO($msg) { Write-Step ".."   $msg Cyan }

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Red
Write-Host "   REDFORGE - One Click Launcher" -ForegroundColor White
Write-Host "  ============================================" -ForegroundColor Red
Write-Host "   AUTHORIZED USE ONLY" -ForegroundColor Yellow
Write-Host "  ============================================" -ForegroundColor Red
Write-Host ""

# ─── FAST PATH: Release build ─────────────────────────────────────────
$releaseExe = Join-Path $projectRoot "src-tauri\target\release\redforge.exe"

if (Test-Path $releaseExe) {
    Write-OK "Release build found. Launching RedForge..."

    # One-time shortcut creation
    $desktopLnk = "$env:USERPROFILE\Desktop\RedForge.lnk"
    $startMenuLnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\RedForge.lnk"

    if (-not (Test-Path $desktopLnk) -or -not (Test-Path $startMenuLnk)) {
        try {
            $WshShell = New-Object -ComObject WScript.Shell
            foreach ($lnkPath in @($desktopLnk, $startMenuLnk)) {
                if (-not (Test-Path $lnkPath)) {
                    $parent = Split-Path $lnkPath -Parent
                    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
                    $sc = $WshShell.CreateShortcut($lnkPath)
                    $sc.TargetPath = $releaseExe
                    $sc.WorkingDirectory = Split-Path $releaseExe -Parent
                    $sc.IconLocation = "$releaseExe,0"
                    $sc.Description = "RedForge Red Team Operations Platform"
                    $sc.Save()
                    Write-OK "Created shortcut: $(Split-Path $lnkPath -Leaf)"
                }
            }
        } catch {
            Write-WARN "Could not auto-create shortcuts (create manually if needed)"
        }
    }

    Start-Process -FilePath $releaseExe -WorkingDirectory (Split-Path $releaseExe -Parent)
    exit 0
}

# ─── DEV MODE: Full auto-setup + launch ──────────────────────────────
Write-INFO "No release build. Running in development mode."
Write-Host ""

# --- Prerequisites ---
$missing = @()

# Node.js
if (Get-Command node -ErrorAction SilentlyContinue) {
    $nodeVer = & node --version 2>$null
    Write-OK "Node.js $nodeVer"
} else {
    Write-FAIL "Node.js not found - install from https://nodejs.org/"
    $missing += "Node.js"
}

# Python
$pythonCmd = $null
if (Get-Command python -ErrorAction SilentlyContinue) {
    $pythonCmd = "python"
    $pyVer = & python --version 2>$null
    Write-OK "$pyVer"
} elseif (Get-Command py -ErrorAction SilentlyContinue) {
    $pythonCmd = "py"
    $pyVer = & py -3 --version 2>$null
    Write-OK "$pyVer"
} else {
    Write-FAIL "Python not found - install from https://python.org/ (check 'Add to PATH')"
    $missing += "Python"
}

# Rust
if (Get-Command cargo -ErrorAction SilentlyContinue) {
    $rustVer = & rustc --version 2>$null
    Write-OK "$rustVer"
} else {
    Write-FAIL "Rust not found - install from https://rustup.rs/"
    $missing += "Rust"
}

# Ollama (non-blocking)
if (Get-Command ollama -ErrorAction SilentlyContinue) {
    Write-OK "Ollama found"
} else {
    Write-WARN "Ollama not found. Red Team Leader features need it."
    Write-Host "         Install: https://ollama.com/  then: ollama pull llama3.1:8b" -ForegroundColor DarkYellow
}

Write-Host ""

if ($missing.Count -gt 0) {
    Write-FAIL "Missing prerequisites: $($missing -join ', ')"
    Write-Host "  Install the missing tools above and re-run this launcher." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# ─── SETUP: Skip if already done ─────────────────────────────────────
$setupDone = Join-Path $projectRoot ".redforge-setup-done"
$needsSetup = $false

if (-not (Test-Path $setupDone)) { $needsSetup = $true }
elseif (-not (Test-Path (Join-Path $projectRoot "node_modules"))) { $needsSetup = $true }
elseif (-not (Test-Path (Join-Path $projectRoot "sidecar\.venv"))) { $needsSetup = $true }

if ($needsSetup) {
    Write-Host "  First-time setup (this only happens once)..." -ForegroundColor Cyan
    Write-Host ""

    # npm install
    if (-not (Test-Path (Join-Path $projectRoot "node_modules"))) {
        Write-INFO "Installing Node.js dependencies (may take a minute)..."
        & npm install
        if ($LASTEXITCODE -ne 0) {
            Write-FAIL "npm install failed. Check errors above."
            Read-Host "Press Enter to exit"
            exit 1
        }
        Write-OK "Node dependencies installed."
    } else {
        Write-OK "node_modules exists, skipping npm install."
    }

    # Python venv
    $venvPath = Join-Path $projectRoot "sidecar\.venv"
    if (-not (Test-Path $venvPath)) {
        Write-INFO "Creating Python virtual environment for sidecar..."
        if ($pythonCmd -eq "py") {
            & py -3 -m venv $venvPath
        } else {
            & python -m venv $venvPath
        }
        if ($LASTEXITCODE -ne 0) {
            Write-FAIL "Could not create Python venv."
            Read-Host "Press Enter to exit"
            exit 1
        }
        Write-OK "Virtual environment created."
    }

    # Install sidecar deps
    $activateScript = Join-Path $venvPath "Scripts\Activate.ps1"
    if (Test-Path $activateScript) {
        Write-INFO "Installing Python sidecar dependencies..."
        . $activateScript
        & python -m pip install --upgrade pip --quiet 2>$null
        & python -m pip install -r sidecar\requirements.txt --quiet
        if ($LASTEXITCODE -ne 0) {
            Write-WARN "Some Python dependencies may have failed (app may still work)."
        } else {
            Write-OK "Python sidecar dependencies installed."
        }
    }

    # Mark done
    "Setup completed on $(Get-Date)" | Out-File -FilePath $setupDone -Encoding utf8
    Write-Host ""

} else {
    Write-OK "Setup already completed. Skipping installs."
}

# ─── LAUNCH ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "   Launching RedForge (development mode)..." -ForegroundColor White
Write-Host "   First launch compiles Rust - may take 3-5 min." -ForegroundColor DarkGray
Write-Host "   Subsequent launches are fast." -ForegroundColor DarkGray
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

# Activate venv so sidecar can find its deps
$activateScript = Join-Path $projectRoot "sidecar\.venv\Scripts\Activate.ps1"
if (Test-Path $activateScript) {
    . $activateScript
}

& npx tauri dev
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-FAIL "tauri dev failed. Common fixes:"
    Write-Host "    - Install Visual Studio Build Tools with C++ workload" -ForegroundColor Yellow
    Write-Host "    - Run: winget install Microsoft.VisualStudio.2022.BuildTools" -ForegroundColor Yellow
    Write-Host "    - Update Rust: rustup update" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
}
