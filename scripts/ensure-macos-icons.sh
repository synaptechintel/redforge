#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_DIR="$ROOT/src-tauri/icons"
ICONSET="$ICON_DIR/icon.iconset"
mkdir -p "$ICON_DIR"

REDFORGE_ICON_DIR="$ICON_DIR" python3 - <<'PY'
from __future__ import annotations

import os
import struct
import zlib
from pathlib import Path

icon_dir = Path(os.environ['REDFORGE_ICON_DIR']).resolve()
icon_dir.mkdir(parents=True, exist_ok=True)

def write_png(path: Path, size: int) -> None:
    # Always rewrite generated placeholders so a previously bad/partial run is repaired.
    rows = []
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            cx = (x + 0.5) / size
            cy = (y + 0.5) / size
            dx = cx - 0.5
            dy = cy - 0.5
            in_circle = dx * dx + dy * dy <= 0.34 * 0.34
            if in_circle:
                r, g, b, a = 220, 38, 38, 255
            else:
                r, g, b, a = 24, 24, 27, 255

            # simple white block-R approximation
            rx = int(cx * 100)
            ry = int(cy * 100)
            in_r = (
                (28 <= rx <= 39 and 24 <= ry <= 76) or
                (39 <= rx <= 65 and 24 <= ry <= 34) or
                (39 <= rx <= 69 and 43 <= ry <= 53) or
                (65 <= rx <= 76 and 32 <= ry <= 45) or
                (53 <= rx <= 74 and 52 <= ry <= 76 and (rx - 53) >= (ry - 52) * 0.45)
            )
            if in_circle and in_r:
                r, g, b, a = 245, 245, 245, 255
            row.extend([r, g, b, a])
        rows.append(bytes(row))

    raw = b''.join(rows)
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 9))
    png += chunk(b'IEND', b'')
    path.write_bytes(png)

for size, name in [(32, '32x32.png'), (128, '128x128.png'), (256, '128x128@2x.png'), (1024, 'icon_1024.png')]:
    write_png(icon_dir / name, size)
PY

if [[ ! -f "$ICON_DIR/icon_1024.png" ]]; then
  echo "Failed to generate $ICON_DIR/icon_1024.png" >&2
  exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

cp "$ICON_DIR/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
sips -z 16 16 "$ICON_DIR/icon_1024.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_DIR/icon_1024.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_DIR/icon_1024.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_DIR/icon_1024.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_DIR/icon_1024.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_DIR/icon_1024.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_DIR/icon_1024.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_DIR/icon_1024.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_DIR/icon_1024.png" --out "$ICONSET/icon_512x512.png" >/dev/null

iconutil -c icns "$ICONSET" -o "$ICON_DIR/icon.icns"
rm -rf "$ICONSET"

# Tauri config also references icon.ico for Windows. On macOS builds this file only needs to exist.
if [[ ! -f "$ICON_DIR/icon.ico" ]]; then
  cp "$ICON_DIR/32x32.png" "$ICON_DIR/icon.ico"
fi

echo "RedForge macOS icons ready in $ICON_DIR"
