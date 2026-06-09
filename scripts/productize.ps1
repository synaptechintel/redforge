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
#    -AssumeYes      : answer 'yes' to all prompts (for CI / non-interactive)
# ============================================================================

param(
    [switch]$SkipSidecar,
    [switch]$SkipNpmInstall,
    [switch]$SkipFrontend,
    [switch]$DevSign,
    [switch]$AssumeYes
)

# Prompt helper that auto-continues when -AssumeYes or non-interactive
function Confirm-Continue($message) {
    if ($AssumeYes -or -not [Environment]::UserInteractive) {
        Write-Host "  $message -> auto-yes (-AssumeYes / non-interactive)" -ForegroundColor DarkGray
        return $true
    }
    $answer = Read-Host $message
    return ($answer -eq "y")
}

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
    if (-not (Confirm-Continue "Continue anyway? (y/N)")) { exit 1 }
}

# ─── 1b. Windows Defender exclusion (CRITICAL for impacket) ───────────
# impacket is a credential-dumping toolkit. Windows Defender quarantines
# its files (__init__.py, GetNPUsers.py, etc.) IN REAL TIME as pip writes
# them, which makes `pip install impacket` fail on a fresh machine.
# We try to add a Defender exclusion for the project folder. This needs
# admin; if we don't have it, we print clear manual instructions.
if ($IsWindows -or $env:OS -eq "Windows_NT") {
    $alreadyExcluded = $false
    try {
        $excl = (Get-MpPreference -ErrorAction Stop).ExclusionPath
        if ($excl -and ($excl -contains $ProjectRoot)) { $alreadyExcluded = $true }
    } catch { }

    if ($alreadyExcluded) {
        OK "Windows Defender exclusion already present for project folder"
    } else {
        try {
            Add-MpPreference -ExclusionPath $ProjectRoot -ErrorAction Stop
            OK "Added Windows Defender exclusion for project folder (impacket-safe)"
        } catch {
            Warn "Could not add a Windows Defender exclusion (not running as admin)."
            Warn "impacket may be quarantined during install, causing 'pip install' to fail with:"
            Warn "  OSError: [Errno 22] Invalid argument: '...\impacket\__init__.py'"
            Write-Host ""
            Write-Host "  RECOMMENDED ONE-TIME FIX (pick one):" -ForegroundColor Yellow
            Write-Host "    A) Run this build from an ADMIN PowerShell once - it will auto-add the exclusion." -ForegroundColor Gray
            Write-Host "    B) Manually add an exclusion: Windows Security > Virus & threat protection >" -ForegroundColor Gray
            Write-Host "       Manage settings > Exclusions > Add a folder > $ProjectRoot" -ForegroundColor Gray
            Write-Host "    C) Or download the prebuilt installer instead (no build needed):" -ForegroundColor Gray
            Write-Host "       https://github.com/synaptechintel/redforge/releases/latest" -ForegroundColor Gray
            Write-Host ""
            if (-not (Confirm-Continue "Continue and attempt the build anyway? (y/N)")) { exit 1 }
        }
    }
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

# ─── 3b. MITRE ATT&CK data ───────────────────────────────────────────
Section "MITRE ATT&CK Data"

$attackJson = Join-Path $ProjectRoot "sidecar\attack_data\enterprise-attack.json"
if (-not (Test-Path $attackJson)) {
    Info "Downloading MITRE ATT&CK Enterprise STIX bundle (~45 MB)..."
    & $pythonCmd.Split()[0] "scripts\download-attack-data.py"
    if ($LASTEXITCODE -ne 0) { Die "ATT&CK download failed" }
} else {
    $sz = "{0:N1}" -f ((Get-Item $attackJson).Length / 1MB)
    OK "ATT&CK data already present ($sz MB)"
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

    # impacket ships CLI script wrappers (GetNPUsers.py, etc.) that Windows
    # Defender briefly QUARANTINES during install - causing pip to fail with
    # "[Errno 22] Invalid argument: '...\GetNPUsers.py'" even though the actual
    # LIBRARY installed fine. We retry a few times (Defender releases the lock),
    # then verify by importing the critical modules rather than trusting pip's
    # exit code. See CONTEXT.md gotcha #4.
    $maxAttempts = 3
    $installed = $false
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Info "pip install attempt $attempt/$maxAttempts..."
        & python -m pip install -r sidecar\requirements.txt 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { $installed = $true; break }

        # pip failed - check if it was just the script-wrapper lock by trying
        # to import the real libraries. If they import, we're actually fine.
        Info "pip returned non-zero - verifying whether libraries actually imported..."
        & python -c "import impacket, winrm, fastapi, uvicorn, ollama, stix2, aiosqlite, structlog, reportlab" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Warn "pip reported an error (likely Defender locking impacket CLI scripts) but all libraries import correctly. Continuing."
            $installed = $true
            break
        }

        if ($attempt -lt $maxAttempts) {
            Warn "Libraries not yet importable. Waiting 5s for Defender to release locks, then retrying..."
            Start-Sleep -Seconds 5
        }
    }
    if (-not $installed) {
        Die "sidecar pip install failed after $maxAttempts attempts AND libraries do not import.`n`n  If this is the impacket/GetNPUsers.py Defender lock: add an exclusion for this folder in Windows Security, or run the build again (Defender usually releases the lock after the first scan)."
    }
    OK "Sidecar deps installed (verified by import)"

    Info "Installing PyInstaller..."
    & python -m pip install --quiet "pyinstaller>=6.0.0"
    if ($LASTEXITCODE -ne 0) {
        # PyInstaller has no AV-sensitive scripts, but verify import to be safe
        & python -c "import PyInstaller" 2>$null
        if ($LASTEXITCODE -ne 0) { Die "PyInstaller install failed" }
    }
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

        # PyInstaller one-file mode produces a single self-contained exe
        # directly at dist\redforge-sidecar.exe (no subfolder, no _internal/).
        # See sidecar/redforge-sidecar.spec - we use EXE() with binaries+datas
        # baked in, not COLLECT().
        $sidecarExe = Join-Path (Get-Location) "dist\redforge-sidecar.exe"
        if (-not (Test-Path $sidecarExe)) {
            Die "Expected sidecar binary not found at $sidecarExe`n`n  Likely cause: PyInstaller spec is in one-folder mode but our pipeline expects one-file. Check sidecar/redforge-sidecar.spec - the bottom should be a single EXE() block with a.binaries / a.zipfiles / a.datas inside, NOT a COLLECT() block."
        }
        $sizeMB = "{0:N1}" -f ((Get-Item $sidecarExe).Length / 1MB)
        OK "Sidecar bundled (one-file): $sizeMB MB"

        # ─── 7. Stage for Tauri ────────────────────────────────────
        Section "Staging sidecar for Tauri"

        $binDir = Join-Path $ProjectRoot "src-tauri\binaries"
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null

        # The one-file exe is fully self-contained (Python runtime + all deps
        # + ATT&CK data). Tauri externalBin just copies this one file.
        $stagedExe = Join-Path $binDir "redforge-sidecar-x86_64-pc-windows-msvc.exe"
        Copy-Item $sidecarExe $stagedExe -Force
        OK "Staged: $stagedExe"

        # ─── 6b. Smoke test the bundled sidecar BEFORE running tauri build ──
        Section "Smoke testing bundled sidecar"
        Info "Running 13-test integration suite..."
        & powershell -ExecutionPolicy Bypass -NoProfile -File (Join-Path $ProjectRoot "scripts\smoke-test.ps1") -ExePath $sidecarExe
        if ($LASTEXITCODE -ne 0) {
            Die "Smoke test failed - aborting build before tauri compile."
        }
        OK "Smoke test passed - sidecar is shippable"
    } finally {
        Pop-Location
    }
} else {
    OK "Skipping sidecar build (--SkipSidecar)"
}

# ─── 8. Tauri build ──────────────────────────────────────────────────
Section "Tauri build (Rust compile + NSIS installer)"

# tauri.conf.json has `createUpdaterArtifacts: true` so official releases get
# signed auto-update artifacts. That REQUIRES the signing private key. Two cases:
#   1. The signing key exists locally (~/.tauri/redforge-updater.key) - use it,
#      producing signed .sig files the in-app updater will accept.
#   2. No key (typical contributor build) - we override createUpdaterArtifacts
#      to false so the build still succeeds and produces a working installer
#      (just without auto-update signing). The installer itself is identical.
$signingKey = Join-Path $env:USERPROFILE ".tauri\redforge-updater.key"
$tauriArgs = @("run", "tauri", "build")

if (Test-Path $signingKey) {
    OK "Updater signing key found - building signed updater artifacts"
    $env:TAURI_SIGNING_PRIVATE_KEY = (Get-Content $signingKey -Raw)
    if (-not $env:TAURI_SIGNING_PRIVATE_KEY_PASSWORD) {
        # Default dev password (CHANGE for production - see CONTEXT.md)
        $env:TAURI_SIGNING_PRIVATE_KEY_PASSWORD = "redforge-updater-dev-password"
    }
} else {
    Warn "No updater signing key at $signingKey"
    Warn "Building WITHOUT signed updater artifacts (installer still works fully)."
    Warn "Auto-update will be unavailable in this build. To enable it, generate a key:"
    Warn "  npx @tauri-apps/cli signer generate -w `"$signingKey`" -p `"<password>`""
    # Override createUpdaterArtifacts to false so the build doesn't demand a key.
    $tauriArgs += @("--", "--config", '{"bundle":{"createUpdaterArtifacts":false}}')
}

Info "Running npm $($tauriArgs -join ' ')... (first run takes 5-15 min for Rust)"
Info "All subsequent runs are much faster (incremental compilation)"
Write-Host ""

& npm @tauriArgs
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
