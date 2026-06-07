#!/usr/bin/env bash
# ============================================================================
#  RedForge - TRUE One-Click Launcher (Linux / macOS)
# ============================================================================
#  Run: ./launch.sh   (chmod +x launch.sh if needed)
#
#  Does everything automatically:
#    1. Prerequisite detection (Node, Python, Rust, Ollama)
#    2. npm install (if needed)
#    3. Python venv + sidecar deps (if needed)
#    4. Launches release build or tauri dev
#
#  Subsequent runs skip setup (~2 seconds to launch).
#  Delete .redforge-setup-done to force re-setup.
#
#  AUTHORIZED USE ONLY - See README.md
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

ok()   { echo -e "  [${GREEN}OK${NC}] $1"; }
fail() { echo -e "  [${RED}!!${NC}] $1"; }
warn() { echo -e "  [${YELLOW}~~${NC}] $1"; }
info() { echo -e "  [${CYAN}..${NC}] $1"; }

echo ""
echo -e "  ${RED}============================================${NC}"
echo -e "   REDFORGE - One Click Launcher"
echo -e "  ${RED}============================================${NC}"
echo -e "   ${YELLOW}AUTHORIZED USE ONLY${NC}"
echo -e "  ${RED}============================================${NC}"
echo ""

# ─── FAST PATH: Release build ─────────────────────────────────────────
RELEASE_EXE="src-tauri/target/release/redforge"

if [ -f "$RELEASE_EXE" ]; then
    ok "Release build found. Launching RedForge..."
    "$RELEASE_EXE"
    exit 0
fi

# ─── DEV MODE: Full auto-setup + launch ──────────────────────────────
info "No release build. Running in development mode."
echo ""

MISSING=()

# Node.js
if command -v node &>/dev/null; then
    ok "Node.js $(node --version)"
else
    fail "Node.js not found - install from https://nodejs.org/"
    MISSING+=("Node.js")
fi

# Python
PYTHON_CMD=""
if command -v python3 &>/dev/null; then
    PYTHON_CMD="python3"
    ok "$(python3 --version)"
elif command -v python &>/dev/null; then
    PYTHON_CMD="python"
    ok "$(python --version)"
else
    fail "Python not found - install Python 3.12+"
    MISSING+=("Python")
fi

# Rust
if command -v cargo &>/dev/null; then
    ok "$(rustc --version)"
else
    fail "Rust not found - install from https://rustup.rs/"
    MISSING+=("Rust")
fi

# Ollama (non-blocking)
if command -v ollama &>/dev/null; then
    ok "Ollama found"
else
    warn "Ollama not found. Red Team Leader features need it."
    echo "         Install: https://ollama.com/  then: ollama pull llama3.1:8b"
fi

echo ""

if [ ${#MISSING[@]} -gt 0 ]; then
    fail "Missing prerequisites: ${MISSING[*]}"
    echo "  Install the missing tools above and re-run."
    exit 1
fi

# ─── SETUP: Skip if already done ─────────────────────────────────────
NEEDS_SETUP=false

if [ ! -f ".redforge-setup-done" ]; then NEEDS_SETUP=true; fi
if [ ! -d "node_modules" ]; then NEEDS_SETUP=true; fi
if [ ! -d "sidecar/.venv" ]; then NEEDS_SETUP=true; fi

if [ "$NEEDS_SETUP" = true ]; then
    echo -e "  ${CYAN}First-time setup (this only happens once)...${NC}"
    echo ""

    # npm install
    if [ ! -d "node_modules" ]; then
        info "Installing Node.js dependencies (may take a minute)..."
        npm install
        ok "Node dependencies installed."
    else
        ok "node_modules exists, skipping npm install."
    fi

    # Python venv
    if [ ! -d "sidecar/.venv" ]; then
        info "Creating Python virtual environment for sidecar..."
        $PYTHON_CMD -m venv sidecar/.venv
        ok "Virtual environment created."
    fi

    # Install sidecar deps
    info "Installing Python sidecar dependencies..."
    source sidecar/.venv/bin/activate
    pip install --upgrade pip --quiet 2>/dev/null
    pip install -r sidecar/requirements.txt --quiet
    ok "Python sidecar dependencies installed."

    # Linux-specific: Check for Tauri system deps
    if [ "$(uname)" = "Linux" ]; then
        if ! pkg-config --exists webkit2gtk-4.1 2>/dev/null; then
            warn "Missing Linux system libraries for Tauri."
            echo "         Run: sudo apt-get install -y pkg-config libssl-dev libgtk-3-dev libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev"
            echo ""
        fi
    fi

    # Mark done
    echo "Setup completed on $(date)" > .redforge-setup-done
    echo ""
else
    ok "Setup already completed. Skipping installs."
fi

# ─── LAUNCH ──────────────────────────────────────────────────────────
echo ""
echo -e "  ${CYAN}============================================${NC}"
echo -e "   Launching RedForge (development mode)..."
echo -e "   First launch compiles Rust - may take 3-5 min."
echo -e "   Subsequent launches are fast."
echo -e "  ${CYAN}============================================${NC}"
echo ""

# Activate venv
if [ -f "sidecar/.venv/bin/activate" ]; then
    source sidecar/.venv/bin/activate
fi

npx tauri dev
