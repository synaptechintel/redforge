"""
RedForge - ATT&CK Data Downloader
==================================
Downloads MITRE ATT&CK Enterprise STIX 2.1 bundle from the official
MITRE/cti GitHub repository to sidecar/attack_data/enterprise-attack.json

This is required for the ATT&CK Browser, technique search, and the
Red Team Leader AI to function. Without it, attack_data_loaded=False.

The file is ~32 MB. It's gitignored (too big for git) but must exist
at build time so PyInstaller can bundle it into the sidecar exe.

Usage:
    python scripts/download-attack-data.py [--force]
"""

from __future__ import annotations
import sys
import os
import argparse
from pathlib import Path
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError

# Pin to a known-good MITRE ATT&CK release. Update periodically.
# Using the master branch is fine for now - MITRE updates it carefully.
ATTACK_URL = (
    "https://raw.githubusercontent.com/mitre/cti/master/"
    "enterprise-attack/enterprise-attack.json"
)

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "sidecar" / "attack_data"
OUT_FILE = OUT_DIR / "enterprise-attack.json"


def download(force: bool = False) -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    if OUT_FILE.exists() and not force:
        size_mb = OUT_FILE.stat().st_size / 1024 / 1024
        print(f"[attack-data] Already present: {OUT_FILE} ({size_mb:.1f} MB)")
        print(f"             Use --force to re-download.")
        return 0

    print(f"[attack-data] Downloading from MITRE/cti...")
    print(f"  URL: {ATTACK_URL}")
    print(f"  Out: {OUT_FILE}")

    try:
        req = Request(ATTACK_URL, headers={"User-Agent": "RedForge-Build/0.5.0"})
        with urlopen(req, timeout=60) as resp:
            total = int(resp.headers.get("Content-Length", 0))
            downloaded = 0
            with open(OUT_FILE, "wb") as f:
                while True:
                    chunk = resp.read(64 * 1024)
                    if not chunk:
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total:
                        pct = (downloaded / total) * 100
                        sys.stdout.write(
                            f"\r  Downloading: {downloaded/1024/1024:.1f} / "
                            f"{total/1024/1024:.1f} MB ({pct:.0f}%)"
                        )
                        sys.stdout.flush()
            sys.stdout.write("\n")
    except HTTPError as e:
        print(f"[attack-data] HTTP error {e.code}: {e.reason}")
        return 1
    except URLError as e:
        print(f"[attack-data] Network error: {e.reason}")
        return 1
    except Exception as e:
        print(f"[attack-data] Error: {e}")
        return 1

    size_mb = OUT_FILE.stat().st_size / 1024 / 1024
    print(f"[attack-data] Done: {OUT_FILE} ({size_mb:.1f} MB)")
    return 0


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--force", action="store_true", help="Re-download even if present")
    args = p.parse_args()
    return download(force=args.force)


if __name__ == "__main__":
    sys.exit(main())
