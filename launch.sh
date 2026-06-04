#!/bin/bash
# RedForge - One Click Launcher (Linux/macOS)
# ==========================================
# Run with: ./launch.sh
# Or double-click if your file manager supports it (chmod +x launch.sh first)
#
# Behavior:
# - If a release build exists, launches the production app.
# - Otherwise, starts development mode.
#
# Auto-sets up sidecar venv on first dev run.
#
# SAFETY: Authorized use only.

set -e

echo "RedForge Launcher"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RELEASE_EXE="src-tauri/target/release/redforge"

if [ -f "$RELEASE_EXE" ]; then
    echo "Found release build. Launching..."
    "$RELEASE_EXE"
    exit 0
fi

echo "No release build. Starting dev mode..."
echo "Setting up Python sidecar venv if needed..."

if [ ! -d ".venv" ]; then
    python3 -m venv .venv
    echo "Created .venv"
fi

source .venv/bin/activate
pip install -r sidecar/requirements.txt

npm run tauri dev
