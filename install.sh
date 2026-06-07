#!/usr/bin/env bash
# ============================================================================
#  RedForge - One-Click Install & Run (Linux / macOS)
# ============================================================================
#  Run from anywhere:
#    curl -fsSL https://raw.githubusercontent.com/synaptechintel/redforge/main/install.sh | bash
#
#  Or save and run:
#    chmod +x install.sh && ./install.sh
#
#  Installs to ~/.local/share/RedForge, creates a launcher alias,
#  then launches the app.
#
#  AUTHORIZED USE ONLY - See README.md
# ============================================================================

set -e

REPO_URL="https://github.com/synaptechintel/redforge.git"
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/RedForge"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  [${GREEN}OK${NC}] $1"; }
fail() { echo -e "  [${RED}!!${NC}] $1"; }
warn() { echo -e "  [${YELLOW}~~${NC}] $1"; }
info() { echo -e "  [${CYAN}..${NC}] $1"; }

echo ""
echo -e "  ${RED}============================================${NC}"
echo -e "   REDFORGE - One-Click Installer"
echo -e "  ${RED}============================================${NC}"
echo -e "   ${YELLOW}AUTHORIZED USE ONLY${NC}"
echo -e "  ${RED}============================================${NC}"
echo ""
echo "  Installing to: $INSTALL_DIR"
echo ""

# ─── Prerequisites ───────────────────────────────────────────────────
MISSING=()

command -v git    &>/dev/null && ok "Git found"       || { fail "Git not found"; MISSING+=("git"); }
command -v node   &>/dev/null && ok "Node.js $(node --version)" || { fail "Node.js not found"; MISSING+=("node"); }
command -v cargo  &>/dev/null && ok "$(rustc --version)" || { warn "Rust not found - install from https://rustup.rs/"; }

PYTHON_CMD=""
if command -v python3 &>/dev/null; then PYTHON_CMD="python3"; ok "$(python3 --version)";
elif command -v python &>/dev/null; then PYTHON_CMD="python"; ok "$(python --version)";
else fail "Python not found"; MISSING+=("python3");
fi

if command -v ollama &>/dev/null; then ok "Ollama found"
else warn "Ollama not found. Install from https://ollama.com/ for Red Team Leader features."; fi

echo ""

if [ ${#MISSING[@]} -gt 0 ]; then
    fail "Missing required tools: ${MISSING[*]}"
    echo "  Install them and re-run this script."
    exit 1
fi

# ─── Clone or update ────────────────────────────────────────────────
if [ -d "$INSTALL_DIR/.git" ]; then
    info "Updating existing installation..."
    cd "$INSTALL_DIR"
    git fetch --all --quiet 2>/dev/null
    git pull --ff-only --quiet 2>/dev/null || true
    ok "Repository updated."
else
    if [ -d "$INSTALL_DIR" ]; then
        warn "Directory exists but is not a git repo. Removing..."
        rm -rf "$INSTALL_DIR"
    fi
    info "Cloning RedForge..."
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" --quiet
    ok "Repository cloned."
fi

cd "$INSTALL_DIR"

# ─── Setup (delegates to launch.sh) ─────────────────────────────────
chmod +x launch.sh

# ─── Shell alias ─────────────────────────────────────────────────────
SHELL_RC=""
if [ -f "$HOME/.zshrc" ]; then SHELL_RC="$HOME/.zshrc";
elif [ -f "$HOME/.bashrc" ]; then SHELL_RC="$HOME/.bashrc";
fi

if [ -n "$SHELL_RC" ]; then
    if ! grep -q "alias redforge=" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "# RedForge launcher" >> "$SHELL_RC"
        echo "alias redforge='$INSTALL_DIR/launch.sh'" >> "$SHELL_RC"
        ok "Added 'redforge' alias to $SHELL_RC"
        echo "  (Run: source $SHELL_RC  or open a new terminal to use it)"
    else
        ok "Shell alias already exists."
    fi
fi

# ─── Launch ──────────────────────────────────────────────────────────
echo ""
echo -e "  ${GREEN}============================================${NC}"
echo -e "   ${GREEN}Installation complete!${NC}"
echo -e "  ${GREEN}============================================${NC}"
echo ""
echo "  Installed to: $INSTALL_DIR"
echo "  Launch with:  redforge  (or $INSTALL_DIR/launch.sh)"
echo ""
echo "  Launching RedForge now..."
echo ""

exec "$INSTALL_DIR/launch.sh"
