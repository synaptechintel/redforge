# RedForge Python Sidecar

This directory contains the Python worker process used by the RedForge desktop app for:

- ATT&CK data loading & querying
- Heavy reconnaissance (nmap wrappers, etc.)
- Professional report generation (PDF, HTML, Markdown)
- Future LLM proxying / analysis helpers

## Development

```bash
python -m venv .venv
source .venv/bin/activate   # or .venv\Scripts\activate on Windows
pip install -r requirements.txt

uvicorn engine:app --reload --port 18765
```

## Packaging for Windows (primary target)

```bash
pip install pyinstaller
pyinstaller redforge-sidecar.spec
```

The resulting `dist/redforge-sidecar/` folder (or single exe) will be bundled by Tauri.

## Safety Note

This process only ever talks to localhost. It never listens on external interfaces by default.
All sensitive operations (especially execution) are still driven and confirmed from the Rust desktop frontend.
