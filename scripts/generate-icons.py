"""
RedForge - Icon Generator
=========================
Generates all icons required by Tauri's bundler for Windows, macOS, and Linux:

  src-tauri/icons/32x32.png
  src-tauri/icons/128x128.png
  src-tauri/icons/128x128@2x.png   (256x256)
  src-tauri/icons/icon.ico         (Windows installer + .exe icon)
  src-tauri/icons/icon.icns        (macOS .app icon)
  src-tauri/icons/icon.png         (512x512 master)
  src-tauri/icons/Square*Logo.png  (extra sizes for installer banner)

Usage:
  python scripts/generate-icons.py

Auto-installs Pillow on first run if missing.
"""

from __future__ import annotations
import os
import sys
import subprocess
from pathlib import Path

# --- Auto-install Pillow if missing ---
try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("[icons] Installing Pillow...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--quiet", "Pillow>=10.0.0"])
    from PIL import Image, ImageDraw, ImageFont

# --- Paths ---
ROOT = Path(__file__).resolve().parent.parent
ICON_DIR = ROOT / "src-tauri" / "icons"
ICON_DIR.mkdir(parents=True, exist_ok=True)

# --- Color palette (RedForge tactical) ---
BG_TOP = (60, 10, 10)        # dark red top
BG_BOTTOM = (120, 20, 20)    # blood red bottom
ACCENT = (255, 60, 60)       # red highlight
TEXT = (255, 255, 255)       # white
BORDER = (180, 30, 30)       # outer border red


def make_master(size: int = 1024) -> Image.Image:
    """Create the master high-resolution icon."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Background: rounded square with vertical gradient
    radius = int(size * 0.18)
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg)

    # Vertical gradient
    for y in range(size):
        t = y / size
        r = int(BG_TOP[0] * (1 - t) + BG_BOTTOM[0] * t)
        g = int(BG_TOP[1] * (1 - t) + BG_BOTTOM[1] * t)
        b = int(BG_TOP[2] * (1 - t) + BG_BOTTOM[2] * t)
        bg_draw.line([(0, y), (size, y)], fill=(r, g, b, 255))

    # Apply rounded-rect mask
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    img.paste(bg, (0, 0), mask)

    # Outer border
    border_w = max(4, size // 80)
    draw.rounded_rectangle(
        (border_w // 2, border_w // 2, size - border_w // 2, size - border_w // 2),
        radius=radius - border_w // 2,
        outline=BORDER,
        width=border_w,
    )

    # Draw stylized "RF" monogram
    # Try a few common bold fonts; fall back to default
    font_paths = [
        "C:/Windows/Fonts/arialbd.ttf",
        "C:/Windows/Fonts/segoeuib.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ]
    font = None
    font_size = int(size * 0.48)
    for fp in font_paths:
        if Path(fp).exists():
            try:
                font = ImageFont.truetype(fp, font_size)
                break
            except Exception:
                continue
    if font is None:
        font = ImageFont.load_default()

    text = "RF"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (size - tw) // 2 - bbox[0]
    ty = (size - th) // 2 - bbox[1] - int(size * 0.02)

    # Subtle shadow
    shadow_off = max(2, size // 200)
    draw.text((tx + shadow_off, ty + shadow_off), text, fill=(0, 0, 0, 180), font=font)
    # Main text
    draw.text((tx, ty), text, fill=TEXT, font=font)

    # Accent slash bottom-right (forge spark)
    spark_w = int(size * 0.08)
    spark_y = int(size * 0.78)
    spark_x = int(size * 0.18)
    draw.rectangle(
        (spark_x, spark_y, size - spark_x, spark_y + spark_w),
        fill=ACCENT,
    )

    return img


def save_all(master: Image.Image) -> None:
    """Save all required icon variants."""
    # PNGs
    sizes = {
        "32x32.png": 32,
        "128x128.png": 128,
        "128x128@2x.png": 256,
        "icon.png": 512,
        # Windows installer banner sizes
        "Square30x30Logo.png": 30,
        "Square44x44Logo.png": 44,
        "Square71x71Logo.png": 71,
        "Square89x89Logo.png": 89,
        "Square107x107Logo.png": 107,
        "Square142x142Logo.png": 142,
        "Square150x150Logo.png": 150,
        "Square284x284Logo.png": 284,
        "Square310x310Logo.png": 310,
        "StoreLogo.png": 50,
    }

    for name, size in sizes.items():
        out = ICON_DIR / name
        master.resize((size, size), Image.LANCZOS).save(out, "PNG")
        print(f"  [+] {out.relative_to(ROOT)}")

    # Windows .ico (multi-resolution)
    ico_path = ICON_DIR / "icon.ico"
    ico_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    master.save(ico_path, format="ICO", sizes=ico_sizes)
    print(f"  [+] {ico_path.relative_to(ROOT)}")

    # macOS .icns - Pillow supports it natively (size requirements are strict)
    icns_path = ICON_DIR / "icon.icns"
    try:
        # icns requires specific sizes: 16, 32, 64, 128, 256, 512, 1024
        master.save(icns_path, format="ICNS")
        print(f"  [+] {icns_path.relative_to(ROOT)}")
    except Exception as e:
        # Fallback: write a 512x512 PNG with .icns extension as placeholder
        # (Tauri will skip if not bundling for macOS)
        print(f"  [~] icns save failed ({e}), writing placeholder")
        master.resize((512, 512), Image.LANCZOS).save(icns_path, format="PNG")


def main() -> int:
    print("[icons] Generating RedForge icons...")
    master = make_master(1024)
    save_all(master)
    print(f"[icons] Done. Output: {ICON_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
