@echo off
REM ============================================================================
REM  RedForge - TRUE One-Click Launcher (Windows)
REM  Double-click this file. That's it. No typing, no setup, nothing.
REM
REM  On first run it will:
REM    1. Check for Node.js, Python, Rust
REM    2. Run npm install (if needed)
REM    3. Create Python venv + install sidecar deps (if needed)
REM    4. Check for Ollama (warn if missing, don't block)
REM    5. Launch the app (release build if available, otherwise tauri dev)
REM
REM  Subsequent runs skip all setup (takes ~2 seconds to launch).
REM  Delete .redforge-setup-done to force re-setup.
REM
REM  AUTHORIZED USE ONLY - See README.md
REM ============================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"

title RedForge Launcher

echo.
echo  ============================================
echo   REDFORGE - One Click Launcher
echo  ============================================
echo   AUTHORIZED USE ONLY
echo  ============================================
echo.

REM --- Detect problematic project path (spaces/parens break pip install impacket) ---
echo %CD%| findstr /R /C:"[ (]" >nul
if %ERRORLEVEL% equ 0 (
    echo [WARN] Project path contains spaces or parentheses:
    echo        %CD%
    echo        This will likely break the Python sidecar install ^(impacket^).
    echo        Move the project to a clean path like C:\dev\redforge and re-run.
    echo.
    set /p CONTINUE="Continue anyway? (y/N): "
    if /i not "!CONTINUE!"=="y" exit /b 1
)

REM === FAST PATH: Try release build first ===
set "RELEASE_EXE=src-tauri\target\release\redforge.exe"
if exist "%RELEASE_EXE%" (
    echo [OK] Release build found. Launching RedForge...
    start "" "%RELEASE_EXE%"
    goto :eof
)

REM === DEV MODE: Full auto-setup + launch ===
echo [..] No release build found. Running in development mode.
echo [..] Checking prerequisites...
echo.

REM --- Check Node.js ---
where node >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [FAIL] Node.js not found in PATH.
    echo        Install from: https://nodejs.org/ ^(LTS recommended^)
    echo        Make sure to check "Add to PATH" during install.
    echo.
    pause
    exit /b 1
)
for /f "tokens=*" %%v in ('node --version 2^>nul') do echo [OK] Node.js %%v

REM --- Check npm ---
where npm >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [FAIL] npm not found. It should come with Node.js.
    pause
    exit /b 1
)

REM --- Check Python ---
set "PYTHON_CMD="
where python >nul 2>nul && set "PYTHON_CMD=python"
if "%PYTHON_CMD%"=="" (
    where py >nul 2>nul && set "PYTHON_CMD=py -3"
)
if "%PYTHON_CMD%"=="" (
    echo [FAIL] Python not found in PATH.
    echo        Install from: https://python.org/ ^(3.12+ recommended^)
    echo        IMPORTANT: Check "Add Python to PATH" during install.
    echo.
    pause
    exit /b 1
)
for /f "tokens=*" %%v in ('%PYTHON_CMD% --version 2^>nul') do echo [OK] %%v

REM --- Check Rust (cargo) ---
where cargo >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [FAIL] Rust/Cargo not found in PATH.
    echo        Install from: https://rustup.rs/
    echo        After install, restart this terminal and try again.
    echo.
    pause
    exit /b 1
)
for /f "tokens=*" %%v in ('rustc --version 2^>nul') do echo [OK] %%v

REM --- Check Ollama (non-blocking) ---
where ollama >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [WARN] Ollama not found. Red Team Leader features need it.
    echo        Install from: https://ollama.com/
    echo        Then run: ollama pull llama3.1:8b
    echo        ^(RedForge will still work without it^)
    echo.
) else (
    echo [OK] Ollama found
)

echo.

REM === SETUP: Only run heavy installs if not done before ===
if exist ".redforge-setup-done" (
    if exist "node_modules" (
        if exist "sidecar\.venv" (
            echo [OK] Setup already completed. Skipping installs.
            goto :launch
        )
    )
)

echo [..] First-time setup ^(this only happens once^)...
echo.

REM --- npm install ---
if not exist "node_modules" (
    echo [..] Installing Node.js dependencies... ^(this may take a minute^)
    call npm install
    if %ERRORLEVEL% neq 0 (
        echo [FAIL] npm install failed. Check errors above.
        pause
        exit /b 1
    )
    echo [OK] Node dependencies installed.
) else (
    echo [OK] node_modules exists, skipping npm install.
)

REM --- Python venv + sidecar deps ---
if not exist "sidecar\.venv" (
    echo [..] Creating Python virtual environment for sidecar...
    %PYTHON_CMD% -m venv sidecar\.venv
    if %ERRORLEVEL% neq 0 (
        echo [FAIL] Could not create Python venv.
        pause
        exit /b 1
    )
    echo [OK] Virtual environment created.
)

echo [..] Installing Python sidecar dependencies...
call sidecar\.venv\Scripts\activate.bat
python -m pip install --upgrade pip --quiet 2>nul
python -m pip install -r sidecar\requirements.txt --quiet
if %ERRORLEVEL% neq 0 (
    echo [WARN] Some Python dependencies may have failed.
    echo        The app may still work for basic features.
    echo.
) else (
    echo [OK] Python sidecar dependencies installed.
)

REM --- Mark setup as done ---
echo Setup completed on %date% %time% > .redforge-setup-done
echo.

:launch
echo ============================================
echo  Launching RedForge ^(development mode^)...
echo  First launch compiles Rust - may take 3-5 min.
echo  Subsequent launches are fast.
echo ============================================
echo.

REM Activate venv so the sidecar can find its dependencies
if exist "sidecar\.venv\Scripts\activate.bat" (
    call sidecar\.venv\Scripts\activate.bat
)

call npx tauri dev
if %ERRORLEVEL% neq 0 (
    echo.
    echo [FAIL] tauri dev failed. Common fixes:
    echo   - Install Visual Studio Build Tools with C++ workload
    echo   - Run: winget install Microsoft.VisualStudio.2022.BuildTools
    echo   - Make sure Rust is up to date: rustup update
    echo.
    pause
)
