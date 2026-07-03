#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

log() { printf '\033[1;36m%s\033[0m\n' "$*"; }
fail() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Missing required command '$1'. $2"; }

log "=== RedForge macOS Build ==="
log "Project root: $ROOT"
log "AUTHORIZED USE ONLY"

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS build must run on macOS. Use GitHub Actions macos-latest or a Mac."

log "[1/7] Checking build tools..."
need node "Install Node.js 20+."
need npm "Install Node.js 20+."
need python3 "Install Python 3.12+."
need rustc "Install Rust from https://rustup.rs/."
need cargo "Install Rust from https://rustup.rs/."
need sips "sips should be present on macOS."
need iconutil "iconutil should be present on macOS."

log "[2/7] Ensuring macOS icons exist..."
bash "$ROOT/scripts/ensure-macos-icons.sh"

log "[3/7] Installing frontend dependencies..."
if [[ -f package-lock.json ]]; then
  npm ci || npm install
else
  npm install
fi

log "[4/7] Building Python sidecar binary in local venv..."
pushd sidecar >/dev/null
VENV_DIR="$ROOT/sidecar/.venv-macos-build"
PYTHON_BIN="$VENV_DIR/bin/python"

if [[ ! -x "$PYTHON_BIN" ]]; then
  rm -rf "$VENV_DIR"
  python3 -m venv "$VENV_DIR"
fi

"$PYTHON_BIN" -m pip install --upgrade pip
"$PYTHON_BIN" -m pip install -r requirements.txt pyinstaller
rm -rf dist build
"$PYTHON_BIN" -m PyInstaller redforge-sidecar.spec --clean --noconfirm
[[ -x "dist/redforge-sidecar/redforge-sidecar" ]] || fail "Expected sidecar binary missing: sidecar/dist/redforge-sidecar/redforge-sidecar"
popd >/dev/null

log "[5/7] Staging sidecar for current macOS target..."
mkdir -p src-tauri/binaries
ARCH="$(uname -m)"
case "$ARCH" in
  arm64) TARGET_TRIPLE="aarch64-apple-darwin" ;;
  x86_64) TARGET_TRIPLE="x86_64-apple-darwin" ;;
  *) fail "Unsupported macOS architecture: $ARCH" ;;
esac
cp sidecar/dist/redforge-sidecar/redforge-sidecar "src-tauri/binaries/redforge-sidecar-$TARGET_TRIPLE"
chmod +x "src-tauri/binaries/redforge-sidecar-$TARGET_TRIPLE"
log "Staged sidecar: src-tauri/binaries/redforge-sidecar-$TARGET_TRIPLE"

log "[6/7] Building frontend..."
npm run build

log "[7/7] Building Tauri macOS app/dmg..."
npm run tauri build -- --bundles app,dmg

APP_PATH="src-tauri/target/release/bundle/macos/RedForge.app"
DMG_DIR="src-tauri/target/release/bundle/dmg"
[[ -d "$APP_PATH" ]] || fail "App bundle missing: $APP_PATH"
DMG_FILE="$(find "$DMG_DIR" -maxdepth 1 -name '*.dmg' -print -quit 2>/dev/null || true)"
[[ -n "$DMG_FILE" ]] || fail "DMG missing in $DMG_DIR"

log "BUILD SUCCESSFUL"
log "App bundle: $ROOT/$APP_PATH"
log "DMG:        $ROOT/$DMG_FILE"
log "Note: this build is unsigned unless Apple Developer signing variables are configured."
