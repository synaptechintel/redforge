#!/bin/bash
set -e

echo "==> RedForge Codespaces post-create setup"

# Install root npm deps
if [ -f package.json ]; then
  echo "Installing npm dependencies..."
  npm install
fi

# Set up Python sidecar venv (mirrors what launch.sh does)
if [ -d sidecar ]; then
  echo "Setting up sidecar Python environment..."
  cd sidecar
  python3 -m venv .venv || true
  source .venv/bin/activate
  pip install --upgrade pip
  if [ -f requirements.txt ]; then
    pip install -r requirements.txt
  fi
  cd ..
fi

# Make launch scripts executable
chmod +x launch.sh RedForge.bat 2>/dev/null || true
chmod +x scripts/*.ps1 2>/dev/null || true

echo ""
echo "==> Setup complete."
echo "To run the app (note: full GUI Tauri app won't display in Codespaces cloud):"
echo "  ./launch.sh"
echo ""
echo "For code editing: open src/, sidecar/, src-tauri/ in the editor."
echo "Useful ports are forwarded: 1420 (Vite), 8000 (sidecar if started)."
