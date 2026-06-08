# ============================================================================
#  RedForge - PRODUCTION BUILD PIPELINE
# ============================================================================
#  Single-script "make me a shippable .exe" workflow.
#
#  What it does:
#    1. Sanity-checks the project path (no spaces/parens that break pip)
#    2. Verifies prerequisites (Node, Python, Rust, MSVC)
#    3. Generates icons (idempotent)
#    4. npm install + builds the frontend
#    5. Creates Python venv + installs sidecar deps + PyInstaller
#    6. Bundles the Python sidecar with PyInstaller
#    7. Stages the sidecar binary where Tauri expects it
#    8. Runs `tauri build` -> produces NSIS installer + portable exe
#    9. Reports output paths
#
#  Switches:
#    -SkipSidecar    : reuse existing sidecar exe (faster iterate)
#    -SkipNpmInstall : reuse existing node_modules
#    -SkipFrontend   : skip vite build (use existing dist/)
#    -DevSign        : self-sign the installer for local testing
# ============================================================================

param(
    [switch]$SkipSidecar,
    [switch]$SkipNpmInstall,
    [switch]$SkipFrontend,
    [switch]$DevSign
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

function Section($title) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host " $title" -ForegroundColor White
    Write-Host "============================================" -ForegroundColor Cyan
}

function OK($m)   { Write-Host "  [OK] " -ForegroundColor Green -NoNewline; Write-Host $m }
function Info($m) { Write-Host "  [..] " -ForegroundColor Cyan  -NoNewline; Write-Host $m }
function Warn($m) { Write-Host "  [~~] " -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Die($m)  { Write-Host "  [!!] " -ForegroundColor Red -NoNewline; Write-Host $m; exit 1 }

Section "RedForge - Production Build"
Write-Host "  Project: $ProjectRoot" -ForegroundColor Gray
Write-Host "  AUTHORIZED USE ONLY" -ForegroundColor Yellow

# ─── 1. Path sanity ──────────────────────────────────────────────────
# impacket's pip install breaks if the path contains spaces or parens
if ($ProjectRoot -match "[()\s]") {
    Warn "Project path contains spaces or parentheses:"
    Warn "  $ProjectRoot"
    Warn "This often breaks `pip install impacket`."
    Warn "Recommend moving the project to a clean path like C:\dev\redforge"
    Write-Host ""
    $confirm = Read-Host "Continue anyway? (y/N)"
    if ($confirm -ne "y") { exit 1 }
}

# ─── 2. Prerequisites ────────────────────────────────────────────────
Section "Prerequisites"

$missing = @()

if (Get-Command node -ErrorAction SilentlyContinue) {
    OK "Node.js $(node --version)"
} else { $missing += "Node.js (https://nodejs.org/)"; }

$pythonCmd = $null
if (Get-Command python -ErrorAction SilentlyContinue) {
    $pythonCmd = "python"; OK "$(python --version)"
} elseif (Get-Command py -ErrorAction SilentlyContinue) {
    $pythonCmd = "py -3"; OK "$(py -3 --version)"
} else { $missing += "Python 3.10+ (https://python.org/)"; }

if (Get-Command cargo -ErrorAction SilentlyContinue) {
    OK "$(rustc --version)"
} else { $missing += "Rust (https://rustup.rs/)"; }

# Check for MSVC linker (link.exe in MSVC tools, not system32)
$linkExe = (Get-Command link.exe -ErrorAction SilentlyContinue) | Where-Object { $_.Source -match "Microsoft Visual Studio|MSVC" } | Select-Object -First 1
if (-not $linkExe) {
    # Try vswhere
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsInstall = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($vsInstall) { OK "MSVC build tools found at: $vsInstall" }
        else { $missing += "Visual Studio Build Tools with C++ workload" }
    } else {
        $missing += "Visual Studio Build Tools (winget install Microsoft.VisualStudio.2022.BuildTools)"
    }
} else {
    OK "MSVC linker: $($linkExe.Source)"
}

if ($missing.Count -gt 0) {
    Write-Host ""
    Die "Missing prerequisites:`n    $($missing -join "`n    ")"
}

# ─── 3. Icons ────────────────────────────────────────────────────────
Section "Icons"

$iconDir = Join-Path $ProjectRoot "src-tauri\icons"
$iconIco = Join-Path $iconDir "icon.ico"

if (-not (Test-Path $iconIco)) {
    Info "Generating icons via scripts/generate-icons.py..."
    & $pythonCmd.Split()[0] "scripts\generate-icons.py"
    if ($LASTEXITCODE -ne 0) { Die "Icon generation failed" }
} else {
    OK "Icons already present"
}

# ─── 4. Frontend (npm install + vite build) ──────────────────────────
Section "Frontend"

if (-not $SkipNpmInstall) {
    Info "Running npm install..."
    & npm install
    if ($LASTEXITCODE -ne 0) { Die "npm install failed" }
    OK "Node dependencies installed"
} else {
    OK "Skipping npm install (--SkipNpmInstall)"
}

if (-not $SkipFrontend) {
    Info "Building React frontend (vite + tsc)..."
    & npm run build
    if ($LASTEXITCODE -ne 0) { Die "Frontend build failed" }
    OK "Frontend built to dist/"
} else {
    OK "Skipping frontend build (--SkipFrontend)"
}

# ─── 5. Python sidecar venv + dependencies ───────────────────────────
Section "Python Sidecar"

$venvPath = Join-Path $ProjectRoot "sidecar\.venv"

if (-not (Test-Path $venvPath)) {
    Info "Creating Python venv..."
    if ($pythonCmd -eq "py -3") {
        & py -3 -m venv $venvPath
    } else {
        & python -m venv $venvPath
    }
    if ($LASTEXITCODE -ne 0) { Die "venv creation failed" }
    OK "venv created"
}

$activate = Join-Path $venvPath "Scripts\Activate.ps1"
if (-not (Test-Path $activate)) { Die "venv activate script not found at $activate" }
. $activate

if (-not $SkipSidecar) {
    Info "Upgrading pip + installing sidecar dependencies..."
    & python -m pip install --upgrade pip --quiet
    & python -m pip install -r sidecar\requirements.txt
    if ($LASTEXITCODE -ne 0) { Die "sidecar pip install failed" }
    OK "Sidecar deps installed"

    Info "Installing PyInstaller..."
    & python -m pip install --quiet "pyinstaller>=6.0.0"
    if ($LASTEXITCODE -ne 0) { Die "PyInstaller install failed" }
    OK "PyInstaller ready"

    # ─── 6. Bundle sidecar with PyInstaller ────────────────────────
    Section "Bundling sidecar exe (PyInstaller)"

    Push-Location sidecar
    try {
        # Clean previous build
        if (Test-Path "dist")  { Remove-Item -Recurse -Force "dist"  -ErrorAction SilentlyContinue }
        if (Test-Path "build") { Remove-Item -Recurse -Force "build" -ErrorAction SilentlyContinue }

        Info "Running PyInstaller (this takes 1-3 min)..."
        & python -m PyInstaller redforge-sidecar.spec --clean --noconfirm
        if ($LASTEXITCODE -ne 0) { Die "PyInstaller failed" }

        $sidecarExe = Join-Path (Get-Location) "dist\redforge-sidecar\redforge-sidecar.exe"
        if (-not (Test-Path $sidecarExe)) {
            Die "Expected sidecar binary not found at $sidecarExe"
        }
        OK "Sidecar bundled: $((Get-Item $sidecarExe).Length / 1MB) MB"

        # ─── 7. Stage for Tauri ────────────────────────────────────
        Section "Staging sidecar for Tauri"

        $binDir = Join-Path $ProjectRoot "src-tauri\binaries"
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null

        # The whole one-folder bundle (deps + exe) needs to be available at runtime.
        # We embed the launcher exe as the externalBin, and we ship the
        # supporting files alongside it via a tauri resource folder.
        #
        # For simplicity we copy the exe directly and rely on PyInstaller
        # one-folder mode placing all DLLs next to it. We then zip the rest
        # into resources/sidecar/ which Tauri will deploy alongside the binary.

        $stagedExe = Join-Path $binDir "redforge-sidecar-x86_64-pc-windows-msvc.exe"
        Copy-Item $sidecarExe $stagedExe -Force
        OK "Staged: $stagedExe"

        # Copy supporting one-folder contents into src-tauri/resources/sidecar/
        $resourceDir = Join-Path $ProjectRoot "src-tauri\resources\sidecar"
        if (Test-Path $resourceDir) { Remove-Item -Recurse -Force $resourceDir }
        New-Item -ItemType Directory -Force -Path $resourceDir | Out-Null

        $sidecarFolder = Join-Path (Get-Location) "dist\redforge-sidecar"
        Copy-Item "$sidecarFolder\*" $resourceDir -Recurse -Force
        OK "Sidecar support files staged at src-tauri\resources\sidecar"
    } finally {
        Pop-Location
    }
} else {
    OK "Skipping sidecar build (--SkipSidecar)"
}

# ─── 8. Tauri build ──────────────────────────────────────────────────
Section "Tauri build (Rust compile + NSIS installer)"

Info "Running npm run tauri build... (first run takes 5-15 min for Rust)"
Info "All subsequent runs are much faster (incremental compilation)"
Write-Host ""

& npm run tauri build
if ($LASTEXITCODE -ne 0) { Die "tauri build failed" }

# ─── 9. Report outputs ──────────────────────────────────────────────
Section "Build Complete"

$bundleDir = Join-Path $ProjectRoot "src-tauri\target\release\bundle"
$portableExe = Join-Path $ProjectRoot "src-tauri\target\release\redforge.exe"

Write-Host ""
Write-Host "  Outputs:" -ForegroundColor Green

if (Test-Path $portableExe) {
    $sz = "{0:N1}" -f ((Get-Item $portableExe).Length / 1MB)
    OK "Portable EXE  ($sz MB):  $portableExe"
}

$nsisDir = Join-Path $bundleDir "nsis"
if (Test-Path $nsisDir) {
    Get-ChildItem $nsisDir -Filter "*.exe" | ForEach-Object {
        $sz = "{0:N1}" -f ($_.Length / 1MB)
        OK "NSIS Installer ($sz MB):  $($_.FullName)"
    }
}

$msiDir = Join-Path $bundleDir "msi"
if (Test-Path $msiDir) {
    Get-ChildItem $msiDir -Filter "*.msi" | ForEach-Object {
        $sz = "{0:N1}" -f ($_.Length / 1MB)
        OK "MSI Installer  ($sz MB):  $($_.FullName)"
    }
}

# Create RedForge.bat in project root that prefers release
$launcher = Join-Path $ProjectRoot "RedForge.bat"
# (Already maintained separately - just ensure it exists)
if (Test-Path $launcher) { OK "Launcher present: RedForge.bat" }

# Desktop + Start Menu shortcuts
if (Test-Path $portableExe) {
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $desktop = [Environment]::GetFolderPath('Desktop')
        $startMenu = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
        if (-not (Test-Path $startMenu)) { New-Item -ItemType Directory -Force -Path $startMenu | Out-Null }

        foreach ($lnkPath in @("$desktop\RedForge.lnk", "$startMenu\RedForge.lnk")) {
            $sc = $WshShell.CreateShortcut($lnkPath)
            $sc.TargetPath = $portableExe
            $sc.WorkingDirectory = Split-Path $portableExe -Parent
            $sc.IconLocation = "$portableExe,0"
            $sc.Description = "RedForge - Authorized Red Team Operations"
            $sc.Save()
            OK "Shortcut: $(Split-Path $lnkPath -Leaf)"
        }
    } catch {
        Warn "Shortcut creation skipped: $_"
    }
}

Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "    - Test the installer on a clean Windows VM"
Write-Host "    - Sign the installer for production distribution"
Write-Host "      (see Tauri code signing docs)"
Write-Host "    - Ship!"
Write-Host ""
