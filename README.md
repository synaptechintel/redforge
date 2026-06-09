# RedForge

**A local-first native desktop app for authorized red team and adversary emulation operations.**

[![Latest Release](https://img.shields.io/github/v/release/synaptechintel/redforge?label=Download&color=red)](https://github.com/synaptechintel/redforge/releases/latest)
[![License](https://img.shields.io/badge/license-Proprietary-orange)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)](#)

---

> ## ⚠ AUTHORIZED USE ONLY
> RedForge bundles real offensive tooling (impacket, WinRM, recon, credential collection).
> Using it against systems you don't own or have **explicit written authorization** to test
> is a felony in most jurisdictions (CFAA in the US, Computer Misuse Act in the UK, equivalents elsewhere).
> The authors accept no liability for unauthorized use.

---

## Install (one-click)

**1.** Go to the [latest release](https://github.com/synaptechintel/redforge/releases/latest)
**2.** Download `RedForge_X.X.X_x64-setup.exe`
**3.** Run it. Done.

No Python, Node, or Rust required. Everything is bundled.

> The installer is currently unsigned, so Windows SmartScreen will warn. Click **More info → Run anyway**.
> Code signing is on the roadmap.

### Optional: AI features
For the **Red Team Leader** chat assistant, install [Ollama](https://ollama.com/) and pull a model:

```
ollama pull llama3.1:8b
```

RedForge auto-detects whatever model you have installed (llama3, qwen2.5, mistral, gemma, etc.).
Override with the `REDFORGE_OLLAMA_MODEL` env var if you want a specific one.

---

## What's inside

| Feature | What it does |
|---|---|
| **Operations** | Per-engagement workspace with scope + RoE tracking |
| **Recon** | Live TCP scans + paste-and-parse (nmap / masscan / rustscan) → auto-saves to assets |
| **Execution Console** | Local + remote (WinRM / PSExec) command execution with full output capture, live MITRE technique suggestions, paste-output-and-generate-next-command |
| **Auto-Suggest Techniques** | Real-time MITRE ATT&CK suggestions as you type |
| **Discovered Assets** | Persisted hosts, services, credentials with auto-extraction from command output |
| **Chain Builder** | Visual MITRE ATT&CK kill chain editor with execution tracking |
| **Red Team Leader** | Local LLM (Ollama) acting as a semi-autonomous mentor with full context awareness |
| **Reports** | Markdown engagement reports |
| **100% local** | No cloud. No accounts. No telemetry. Air-gapped capable. |

**697 MITRE ATT&CK Enterprise techniques + 15 tactics bundled** (no download needed).

---

## Where your data lives

Everything stays on your machine. The installer creates:

```
%APPDATA%\com.redforge.desktop\
├── redforge.db                # SQLite: operations, timeline, assets, creds
└── logs\
    └── sidecar.log            # Rotating log file (5 MB × 3 backups)
```

To export an engagement, copy `redforge.db` somewhere else. To wipe everything, delete the folder.

---

## Quick troubleshooting

| Symptom | Fix |
|---|---|
| SmartScreen blocks the installer | Click **More info → Run anyway** |
| Antivirus quarantines `redforge-sidecar.exe` | Add it as an exclusion (impacket is a known credential-dumping tool, AV will flag it) |
| "Red Team Leader" stuck on "thinking..." | First reply takes 30-60s while the model loads from disk. Pre-warm with `ollama run llama3.1:8b` |
| Sidecar shows "down" in the header | Click **Restart** in the header. If it persists, check `sidecar.log` |
| Want to see what the sidecar is doing | Open `http://127.0.0.1:18765/docs` (full OpenAPI) or `/api/ollama/status` (model diagnostics) |

---

## Build from source

For developers and contributors. End users should use the installer above.

### Prerequisites
- **Node.js** 20+ ([nodejs.org](https://nodejs.org/))
- **Python** 3.11+ ([python.org](https://www.python.org/downloads/) — check "Add to PATH")
- **Rust** ([rustup.rs](https://rustup.rs/))
- **Visual Studio 2022 Build Tools** with "Desktop development with C++"

### Build
```
git clone https://github.com/synaptechintel/redforge.git
cd redforge
Build-Release.bat        # produces installer in src-tauri\target\release\bundle\
```

First build: ~15-20 minutes. Output:
- `src-tauri\target\release\bundle\nsis\RedForge_*_x64-setup.exe` — installer
- `src-tauri\target\release\redforge.exe` — portable

### Dev mode (hot reload)
```
RedForge.bat
```
or
```
.\launch.ps1
```

See [QUICKSTART.md](QUICKSTART.md) for a step-by-step walkthrough including each prerequisite install.

---

## Architecture

```
┌──────────────────────────────────────────────┐
│  RedForge.exe (Tauri / Rust + React)         │
│  ┌──────────────┐  ┌──────────────────────┐  │
│  │  WebView2    │  │  Sidecar manager     │  │
│  │  (React UI)  │←→│  (Rust)              │  │
│  └──────────────┘  └────────┬─────────────┘  │
└──────────────────────────────│───────────────┘
                               │ spawns
                  ┌────────────▼─────────────┐
                  │  redforge-sidecar.exe    │
                  │  (Python / FastAPI)      │
                  │  - 697 ATT&CK techniques │
                  │  - impacket + pywinrm    │
                  │  - SQLite                │
                  │  - Ollama integration    │
                  └────────────┬─────────────┘
                               │ optional
                  ┌────────────▼─────────────┐
                  │  Ollama (your install)   │
                  │  llama3.1 / gemma / etc. │
                  └──────────────────────────┘
```

Both `RedForge.exe` and `redforge-sidecar.exe` only bind to `127.0.0.1`. Nothing listens on a public interface.

---

## Contributing

PRs welcome. Run the smoke suite before submitting:

```
.\scripts\smoke-test.ps1
```

13 integration tests against the bundled sidecar — must all pass.

---

## License

Proprietary. See [LICENSE](LICENSE).

---

**REMEMBER:** With great power comes great responsibility — and potential felony charges. Only use on systems you own or have explicit written authorization to test.
