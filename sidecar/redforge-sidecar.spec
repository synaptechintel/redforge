# -*- mode: python ; coding: utf-8 -*-
"""
RedForge Sidecar - PyInstaller Spec
====================================
Produces a single-file (or one-folder) executable that bundles the FastAPI
backend + all dependencies (impacket, pywinrm, ollama, stix2, etc.)
ready for Tauri to embed as an external binary.

Build with:
    cd sidecar
    pyinstaller redforge-sidecar.spec --clean --noconfirm

Output:
    dist/redforge-sidecar/redforge-sidecar(.exe)   # one-folder mode (faster startup, smaller per-file)

The build-windows.ps1 script copies the output to
    ../src-tauri/binaries/redforge-sidecar-x86_64-pc-windows-msvc.exe
"""

import sys
from pathlib import Path
from PyInstaller.utils.hooks import collect_submodules, collect_data_files

block_cipher = None
HERE = Path(SPECPATH).resolve()

# --- Hidden imports: impacket has tons of dynamically-loaded modules ---
hidden = []
hidden += collect_submodules("impacket")
hidden += collect_submodules("winrm")
hidden += collect_submodules("ntlm_auth")
hidden += collect_submodules("requests_ntlm")
hidden += collect_submodules("stix2")
hidden += collect_submodules("ollama")
hidden += collect_submodules("aiosqlite")
hidden += collect_submodules("fastapi")
hidden += collect_submodules("uvicorn")
hidden += collect_submodules("starlette")
hidden += collect_submodules("pydantic")
hidden += [
    "uvicorn.logging",
    "uvicorn.loops",
    "uvicorn.loops.auto",
    "uvicorn.protocols",
    "uvicorn.protocols.http",
    "uvicorn.protocols.http.auto",
    "uvicorn.protocols.websockets",
    "uvicorn.protocols.websockets.auto",
    "uvicorn.lifespan",
    "uvicorn.lifespan.on",
    "engine",
    "database",
    "attack_data",
]

# --- Data files: bundled ATT&CK data, certs, templates ---
datas = []
# Pull in the bundled ATT&CK json if present
attack_dir = HERE / "attack_data"
if attack_dir.exists():
    datas.append((str(attack_dir), "attack_data"))

# Pull in any CA certificates etc. used by requests/urllib3
try:
    import certifi
    datas.append((certifi.where(), "."))
except ImportError:
    pass


a = Analysis(
    ["engine.py"],
    pathex=[str(HERE)],
    binaries=[],
    datas=datas,
    hiddenimports=hidden,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        # Save space - we don't use these
        "tkinter",
        "matplotlib",
        "PIL",
        "numpy",
        "scipy",
        "IPython",
        "pytest",
        "test",
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

# One-folder mode: faster startup + smaller delta updates
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="redforge-sidecar",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,             # UPX often triggers AV false-positives - keep off
    console=True,          # Sidecar logs go to console; Tauri swallows it
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="redforge-sidecar",
)
