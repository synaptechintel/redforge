# RedForge

**Local-first native desktop application for authorized red team and adversary emulation operations.**

> **⚠️ CRITICAL LEGAL AND ETHICAL WARNING**
>
> RedForge is a tool designed **exclusively** for qualified security professionals, red teamers, and penetration testers conducting **authorized** engagements with explicit written permission from the system owners.
>
> - Unauthorized access to computer systems is a serious crime in virtually every jurisdiction.
> - You are solely responsible for ensuring all activities performed with this tool are legal, authorized, and within the documented Rules of Engagement (RoE) of your engagement.
> - The developers provide this software **as-is** with **no warranty** and accept **zero liability** for misuse, damage, or legal consequences arising from its use.
> - By using this software you acknowledge that you understand these restrictions and that you will only use it in lawful, authorized contexts.

## Repository

**https://github.com/synaptechintel/redforge**

```bash
git clone https://github.com/synaptechintel/redforge.git
cd redforge

# Easiest one-command start
./launch.sh          # Linux / macOS
# Windows: double-click RedForge.bat (or launch.ps1)
```

See the **One-click launch** and **How to Run** sections below.

## Quick Start

```bash
git clone https://github.com/synaptechintel/redforge.git
cd redforge

# Linux / macOS
./launch.sh

# Windows (double-click)
#   RedForge.bat     (or launch.ps1)
```

The launcher will:
- Use the release build if you've built it (`src-tauri/target/release/...`)
- Otherwise set up a Python venv for the sidecar and run `tauri dev`

**Ollama is required** for the Red Team Leader features (`ollama run llama3.1:8b` or similar).

## Current Status

**v0.5.0 — Complete functional red team co-pilot (recon → assets → execution → leader)**

The full loop is implemented and automatic:
- Robust recon parsing + auto asset/credential ingestion
- Real WinRM + full impacket PSExec (with output retrieval + pass-the-hash)
- Reactive live suggestions driven by discovered assets
- Structured kill chain plans importable to Chain Builder
- One-click launchers + Windows build + installer packaging support

Ready for local builds and authorized use / education.

**Real Practical Capabilities Added**
- **Real Local Execution** — Run commands locally with full output capture + auto-logging.
- **Remote Execution (WinRM + Full PSExec)** — 
  - **WinRM**: Fully working remote execution using native Windows Remote Management.
  - **PSExec**: Full working implementation using impacket (creates service on target, captures output via ADMIN$ share). Supports cleartext passwords and pass-the-hash (NTLM).
  - Both methods automatically log to the operation timeline with correct MITRE techniques (`T1021.006` / `T1021.002`).
- **Basic Recon Scanner** — Real TCP connect scans with automatic timeline logging.
- **Automatic Technique Suggestion** — As you type or paste commands, RedForge suggests relevant MITRE ATT&CK techniques in real time. 
  - Hover any suggestion to see **"Why this technique?"** — shows the exact matched keywords that triggered the recommendation.
  - Click to auto-fill the technique field. Works for both local and remote execution.
- **Red Team Leader Terminal** (new dedicated panel) — A terminal-style interface powered by your local LLM (Ollama). Acts as a semi-autonomous red team leader for beginners. Features:
  - **Guided Kill Chain mode** — LLM walks you phase-by-phase through the Cyber Kill Chain with one-click “Add to Chain” and “Load in Execution” actions.
  - **One-click Kill Chain Import** — When the Red Team Leader proposes a full kill chain (especially via "Generate Structured Plan"), a prominent **"Import this kill chain into Chain Builder"** button appears. It parses the plan and bulk-creates all steps with real discovered values already filled in.
  - Sees your real discovered hosts, services, ports, and accounts (now stored in a proper **Discovered Assets** tab).
  - Generates ready-to-run commands/scripts using **actual values** from your operation (no more manual placeholder editing).
  - Strong context from timeline + chains + assets.

  Recommended models for best reasoning: `llama3.1:8b+`, `qwen2.5:14b+`, or `command-r`.
- **Strong Automation from Recon → Execution**:
  - After running a scan in the Recon tab, one button can automatically:
    - Log all discovered services to the Assets system
    - Ask the Red Team Leader to analyze the results
    - Pre-load the best next command into the Execution console
  - "What's my next best move?" button in Execution combines timeline analysis + LLM reasoning to suggest the most logical next command(s) using real discovered values.
  - Marking a chain step "executed" automatically triggers the Red Team Leader to suggest the next move.
- **Real Ollama Integration** — The Assistant can use a local Ollama model (llama3.1, qwen2.5, etc.) for high-quality, contextual advice instead of the old stub.
- **Output → Next Command / Script Generator** — Paste results from any command or script (especially useful after port scans). RedForge can:
  - Detect IPs, open ports, and other entities from the output
  - Let you choose a scenario: **Credential Access**, **Lateral Movement Prep**, **Privilege Escalation**, **Defense Evasion**, **Port Scan Follow-up**
  - Suggest specific tools based on discovered services (e.g. CrackMapExec when 445 is open)
  - Let you **edit the discovered values** before generation
  - Generate either a single command **or** a multi-line script (PowerShell/Bash)
  - **Save the generated script directly to the operation’s timeline as an artifact**
  - Automatically copy the result to clipboard

  **Vision**: A semi-autonomous red team leader / educational assistant designed for beginner cybersecurity students performing authorized penetration tests.
- Quick procedure templates (whoami, systeminfo, net user, ipconfig, tasklist, id, etc.)
- Full Attack Chain Builder with execution tracking
- Structured timeline that now contains real command output
- Markdown report generation

This is now a tool you can actually use during authorized engagements for logging real actions and performing basic recon/execution.
- React 19 + TypeScript + Tailwind
- Python sidecar (FastAPI + aiosqlite) for heavy logic and data
- 100% local / air-gapped capable

All actions stay on your machine. Use only for authorized testing.

**Implemented (foundational):**
- Professional dark tactical desktop UI shell (Tauri v2 + React 19 + Tailwind)
- Sidebar navigation + status bar
- Strong authorization messaging baked into the interface
- Project structure ready for full feature implementation

**Planned (see IMPLEMENTATION_PLAN.md or the approved design for details):**
- Full MITRE ATT&CK Enterprise browser with local embedded data
- Visual attack chain builder with logging
- Reconnaissance module (host discovery, safe port scanning)
- Execution console with procedure runner + full immutable audit trail
- AI operator co-pilot + dedicated LLM red teaming lab (Ollama-first)
- Professional report generation (PDF, Markdown, HTML, evidence bundles)
- Python sidecar for heavy lifting (recon, reporting, ATT&CK queries)

## Tech Stack

- **Desktop**: Tauri v2 (Rust) + React 19 + TypeScript + Tailwind + shadcn/ui patterns
- **Data**: SQLite (local, portable)
- **Heavy logic**: Python sidecar (PyInstaller on Windows)
- **ATT&CK**: Bundled STIX 2.1 enterprise data (offline)
- **AI**: Local-first via Ollama (optional remote model support)

## Getting Started (Development)

See the **Quick Start** section near the top for the easiest way to launch.

### Prerequisites (for building / modifying)
- Rust (stable)
- Node 20+
- Python 3.12+ (for sidecar)

The root launchers (`launch.sh`, `RedForge.bat`, `launch.ps1`) are the recommended way to run during development — they handle the Python sidecar venv automatically on first run.

The first `tauri dev` (or first run of the launcher in dev mode) will take a while because it compiles the Rust Tauri shell.

## Safety & OPSEC Features (Planned & Partial)

- Prominent "AUTHORIZED USE ONLY" banners and first-run wizard
- Per-operation explicit authorization confirmation
- All actions logged with timestamps and context (immutable timeline)
- No cloud, no telemetry, fully local/air-gapped capable
- Clear distinction between simulated vs real execution paths

## Project Structure

```
redforge/
├── src/                  # React frontend (views, components, state)
├── src-tauri/            # Rust Tauri application core
│   └── src/main.rs
├── sidecar/              # Python worker (recon, reports, ATT&CK processing)
├── data/                 # User operations (SQLite + evidence) — gitignored
└── package.json
```

## Building for Release / Deployment

RedForge is a Tauri + Python sidecar application. To create distributable binaries you must build **both** the Rust/Tauri app **and** the Python sidecar.

### 1. Build the Python Sidecar (Critical Step)

The sidecar must be compiled to a standalone binary using PyInstaller.

```bash
cd sidecar

# Install build tools
pip install pyinstaller

# Build the sidecar
pyinstaller redforge-sidecar.spec

# Result will be in dist/redforge-sidecar/
#   - On Windows: redforge-sidecar/redforge-sidecar.exe
#   - On Linux:   redforge-sidecar/redforge-sidecar
```

**Important hidden imports** are already configured in `redforge-sidecar.spec` (impacket, pywinrm, stix2, etc.).

Copy the resulting `redforge-sidecar` (or `.exe`) into the appropriate location for Tauri bundling (see below).

### 2. Prepare Icons (Required for Installers)

Create the directory `src-tauri/icons/` and place properly sized icons:

- 32x32.png, 128x128.png, 128x128@2x.png
- icon.icns (macOS)
- icon.ico (Windows)

You can use tools like `iconutil` (macOS) or online converters. Without icons, `tauri build` will fail or produce incomplete bundles.

### Windows Version (Primary Target for Red Team Use)

RedForge is designed with Windows as the main deployment target for operators (remote execution against Windows targets via WinRM/PSExec).

To build the Windows version (recommended way):

1. **On a Windows machine** (strongly recommended for correct sidecar .exe + testing):
   - Install prerequisites (Rust via rustup, Node 20+, Python 3.12+, Visual Studio Build Tools with C++ workload).
   - Open PowerShell (as Administrator) in the `redforge` project root.
   - Run the dedicated script:
     ```
     .\scripts\build-windows.ps1
     ```
   - This script:
     - Runs `npm install`
     - Builds the Python sidecar with PyInstaller
     - Stages the .exe correctly for Tauri
     - Runs `tauri build`
   - Output: NSIS installer (`.exe`) + optional `.msi` (if WiX installed) in `src-tauri\target\release\bundle\`

2. **Cross-build from Linux/macOS** (advanced, not fully supported for sidecar):
   - `rustup target add x86_64-pc-windows-msvc`
   - Prepare cross toolchain (complex, see Tauri docs).
   - Manually build sidecar on a real Windows box and place the .exe in `src-tauri/binaries/redforge-sidecar-x86_64-pc-windows-msvc.exe` (we ship a placeholder stub).
   - `npm run tauri build -- --target x86_64-pc-windows-msvc`

The `tauri.conf.json` already enables both NSIS (recommended, user-friendly installer) and WiX/MSI.

See the script itself (`scripts/build-windows.ps1`) for detailed comments, parameters (`-SkipSidecar`, `-SkipNpmInstall`), and safety reminders.

### 3. Install Linux build dependencies (for Tauri native crates)

On Debian/Ubuntu (this env and many CI):

```bash
sudo apt-get update
sudo apt-get install -y \
  pkg-config \
  libssl-dev \
  libglib2.0-dev libgobject-2.0-dev libgio-2.0-dev \
  libgtk-3-dev libwebkit2gtk-4.1-dev \
  libgdk-pixbuf-2.0-dev libpango1.0-dev libcairo2-dev \
  libatk1.0-dev libatk-bridge2.0-dev \
  build-essential curl wget file libxdo-dev \
  libayatana-appindicator3-dev librsvg2-dev
```

(These are needed for the Rust sys crates like glib-sys, openssl-sys, gobject-sys, gio-sys, gdk-sys, pango-sys, cairo-sys-rs, atk-sys, gdk-pixbuf-sys that Tauri depends on for Linux desktop integration. The exact list can grow; install what the build error tells you.)

After the packages are installed and `cargo` is in your PATH (`source "$HOME/.cargo/env"`), `npm run tauri build` will succeed and emit the platform-specific bundles (AppImage, NSIS installer, dmg, etc.) in `src-tauri/target/release/bundle/`.

**One-click launch (the easiest way to run RedForge):**
- **Double-click `RedForge.bat`** (in the project root) — works before or after build. Prefers the fast release version if you built it.
- **Double-click `launch.ps1`** (same folder) — PowerShell version with the same logic + auto-creates shortcuts on first use.
- The `scripts\build-windows.ps1` script automatically creates:
  - `RedForge.bat` (root, for instant launch)
  - Desktop shortcut (`RedForge.lnk`)
  - Start Menu entry ("RedForge")
- **Pin to taskbar for the ultimate one-click:** Right-click the Start Menu "RedForge" -> "Pin to taskbar".
- After running the produced NSIS installer, you get normal Start Menu + optional Desktop shortcuts too.

No typing commands needed after the first build. Just double-click and go.

### 4. Build the Desktop Application

```bash
# From project root
npm install

# Production build (creates installers in src-tauri/target/release/bundle/)
npm run tauri build
```

**Platform notes:**
- **Windows**: Produces `.exe` installer (NSIS) + `.msi` (if wix is installed).
- **Linux**: Produces `.AppImage` (recommended for distribution).
- **macOS**: Produces `.dmg` and `.app` (you will need to sign/notarize for distribution outside your organization).

### 4. External Binary Placement (for Tauri)

For the sidecar to be bundled correctly, place the compiled binary in:

`src-tauri/binaries/redforge-sidecar-<target-triple>`

Example filenames Tauri expects:
- `redforge-sidecar-x86_64-pc-windows-msvc.exe`  (we have a stub in the repo; replace with real PyInstaller .exe)
- `redforge-sidecar-x86_64-unknown-linux-gnu`
- `redforge-sidecar-aarch64-apple-darwin`

Tauri will automatically rename and include it when `externalBin` is declared in `tauri.conf.json`.

### Recommended Release Checklist

- [ ] On Windows (primary): Run `.\scripts\build-windows.ps1` (see dedicated section above)
- [ ] On other OSes: Build sidecar with PyInstaller on the target OS
- [ ] Place binary in `src-tauri/binaries/` with correct triple (our Windows stub is already there as a placeholder)
- [ ] Add proper icons (we provide placeholders; replace `icon.ico` etc. for production)
- [ ] Run `npm run tauri build` (or the platform script)
- [ ] Test the resulting installer on a clean machine / VM
- [ ] Verify the sidecar starts and `/health` responds
- [ ] Document that end-users still need Ollama running locally (e.g. `ollama run llama3.1:8b`)
- [ ] Include strong legal/authorized-use warning in any distribution package or docs
- [ ] For Windows: sign the installer if distributing broadly (see Tauri code signing docs)

### Runtime Requirements for End Users

- Windows 10/11, modern Linux, or macOS 11+
- Ollama installed and running with at least one model (for Red Team Leader features)
- For full remote execution features on Windows targets: appropriate credentials and network access (445 for PSExec, 5985/5986 for WinRM)

Ollama is **not** bundled. This is intentional for air-gapped and model choice flexibility.

## License & Usage

Licensed under the [MIT License](LICENSE).

**This software is provided for authorized security professionals, red team operators, and students performing legal, permitted penetration testing and adversary emulation only.**

All red team tools carry inherent risk. Use responsibly and only on systems you own or have explicit written authorization to test.

---

**Remember: With great power comes great responsibility — and potential felony charges.**
