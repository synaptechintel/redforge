"""
RedForge Sidecar Entrypoint
---------------------------
PyInstaller builds this file into redforge-sidecar.exe.
The Tauri desktop app starts that executable and talks to the FastAPI app over localhost.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import uvicorn


def _runtime_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def main() -> None:
    runtime_dir = _runtime_dir()
    os.chdir(runtime_dir)

    port_raw = os.getenv("REDFORGE_SIDECAR_PORT", "18765")
    try:
        port = int(port_raw)
    except ValueError:
        port = 18765

    uvicorn.run(
        "engine:app",
        host="127.0.0.1",
        port=port,
        log_level=os.getenv("REDFORGE_LOG_LEVEL", "info"),
        reload=False,
        access_log=False,
    )


if __name__ == "__main__":
    main()
