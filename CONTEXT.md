# RedForge — Living Project Context

> **This is a working notepad for active developers (and AI assistants) on this project.**
> Read it before starting work; update it as you finish meaningful tasks.
> Keeps the cost of context-switching low and the cost of repeating past mistakes near zero.

**Last updated:** 2026-06-09 (v0.5.3 in active development)

---

## TL;DR — what is this thing

A Windows desktop app (Tauri 2 + React + Python sidecar) for authorized red team operations.
- `RedForge.exe` (12 MB) — Tauri shell with WebView2 UI
- `redforge-sidecar.exe` (34 MB) — FastAPI sidecar, PyInstaller-bundled, includes 697 MITRE ATT&CK techniques + impacket + pywinrm + Ollama integration
- SQLite at `%APPDATA%\com.redforge.desktop\redforge.db`

Build one-click: `Build-Release.bat` → installer + portable in `src-tauri\target\release\bundle\`

---

## Current state

**Latest published release:** [v0.5.2](https://github.com/synaptechintel/redforge/releases/tag/v0.5.2) — first release where everything actually works end-to-end.

**In development:** v0.5.3 — launch polish (first-run wizard, per-user install, smarter loading UX, CI/CD workflows, README rewrite).

**Working locally:** `C:\Users\waspf\rftest\redforge` (main work dir). Also a fresh clone at `C:\Users\waspf\dev\redforge` (less used). User's deployed copy: `C:\Users\waspf\Downloads\RedForge_0.5.0_x64-portable\` (folder name says 0.5.0, files inside get hot-swapped during testing).

---

## Stack

| Layer | Tech |
|---|---|
| Desktop shell | Tauri 2.x (Rust) |
| UI | React 19 + TypeScript + Tailwind + Radix + Zustand |
| Sidecar | Python 3.11+ FastAPI + uvicorn |
| Sidecar bundling | PyInstaller (one-file mode — important, see gotchas) |
| Persistence | SQLite via aiosqlite |
| LLM | Ollama (local, optional) |
| ATT&CK data | MITRE STIX 2.1 Enterprise bundle (45 MB, baked into sidecar exe at build time) |
| Bundled tools | impacket, pywinrm, structlog, stix2, reportlab |

---

## Hard-won bug landmines (don't relearn these)

Each of these cost real time. Document them HERE when you find new ones.

### 1. PyInstaller mode for Tauri externalBin

**Symptom:** App launches but sidecar fails silently, "redforge-sidecar.exe missing _internal directory" error.

**Cause:** PyInstaller `--onedir` (COLLECT) mode produces an exe + a sibling `_internal/` folder of support files. Tauri's `externalBin` only copies the EXE alone. The exe can't find its deps and crashes immediately.

**Fix:** Use `--onefile` (EXE only, no COLLECT block) so the exe is truly self-contained. See `sidecar/redforge-sidecar.spec` — there's no `coll = COLLECT(...)` block, just `exe = EXE(... a.binaries, a.zipfiles, a.datas ...)`.

### 2. CORS for Tauri 2 WebView2 on Windows

**Symptom:** GET requests from UI work, but POST requests show "Error reaching the assistant backend" or "Failed to..." in the UI. No POST appears in the sidecar log.

**Cause:** Tauri 2's WebView2 on Windows uses origin `http://tauri.localhost` (HTTP, not HTTPS as the docs imply). Earlier versions of our CORS regex required `https://tauri.localhost` so the preflight returned 400.

**Fix:** In `sidecar/engine.py` the regex must be `https?://tauri\.localhost` to accept both. Already fixed; just don't tighten it.

**Other valid origins to keep matching:** `tauri://localhost` (macOS/Linux), `http://localhost:1420` (dev mode), `http://127.0.0.1:*`.

### 3. ollama-python 0.5+ Model object

**Symptom:** `/api/ollama/status` returns empty `available_models` array even though `ollama list` shows installed models. Assistant always falls back to rule-based replies.

**Cause:** ollama-python 0.5 changed the Model object from `{"name": ...}` dict to a `Model` class with `.model` attribute (not `.name`).

**Fix:** Check both forms when parsing `ollama.list()`:
```python
name = (m.get("model") or m.get("name")) if isinstance(m, dict) else (getattr(m, "model", None) or getattr(m, "name", None))
```

### 4. impacket gets AV-quarantined during pip install

**Symptom:** `pip install impacket` fails with `[Errno 22] Invalid argument: '...\GetNPUsers.py'` or PyInstaller fails with `FileNotFoundError: ...\impacket\__init__.py`.

**Cause:** Windows Defender quarantines impacket files (it's a credential-dumping toolkit). The library MAY install successfully and just the CLI scripts get blocked — but sometimes `__init__.py` gets quarantined too.

**Fix:** Retry the install. If `__init__.py` is missing after install, run `pip install --force-reinstall --no-deps impacket`. If that also fails partway, the lib files might still install (PyInstaller will work) even if script wrappers don't. Verify with `python -c "import impacket"`.

**Prevention:** Add `redforge-sidecar.exe` + the source folder to Defender exclusions during development.

### 5. Tauri 2 API changes

**Symptom:** `cargo check` errors like `no method named on_window_event found for struct AppHandle` or `borrow of moved value: app_data`.

**Cause:** Tauri v2 moved some methods. `on_window_event` is on the WebviewWindow, not AppHandle. And `Command::env()` consumes its argument — use `&` to borrow.

**Fix:** See `src-tauri/src/main.rs` and `src-tauri/src/sidecar.rs` — already correct. Look at those files for examples.

### 6. Tauri externalBin path resolution

**Symptom:** In production builds, sidecar fails to start. App can't find `redforge-sidecar.exe` even though it's right next to the main exe.

**Cause:** Tauri places the externalBin as a SIBLING of the main exe, not in `resource_dir()`. Our `sidecar.rs` candidates list checked resource_dir first which doesn't include sibling exes.

**Fix:** Added `exe_dir` (parent of `current_exe()`) as the FIRST candidate. See `src-tauri/src/sidecar.rs`.

### 7. NSIS installer schema is strict

**Symptom:** `npm run tauri build` fails with `"tauri.conf.json" error on bundle > windows > nsis: ... is not valid under any of the schemas listed`.

**Cause:** Adding extra fields like `allowToChangeInstallationDirectory: false` to nsis config — Tauri's schema only accepts specific fields per `installMode`. The schema is anyOf-style strict.

**Fix:** Only use documented fields. For `installMode: "currentUser"`, that's basically just `installMode` and `template`. Check the [Tauri docs](https://v2.tauri.app/distribute/nsis/) for the current schema before adding anything new.

---

## Build pipeline

### Full release build (from scratch, ~15-20 min first time)

```powershell
cd C:\Users\waspf\rftest\redforge
Build-Release.bat
```

Produces:
- `src-tauri\target\release\bundle\nsis\RedForge_*_x64-setup.exe` (the installer)
- `src-tauri\target\release\bundle\msi\RedForge_*_x64_en-US.msi`
- `src-tauri\target\release\redforge.exe` (portable, needs sibling sidecar)

### Faster: rebuild only the sidecar

```powershell
cd C:\Users\waspf\rftest\redforge\sidecar
.\.venv\Scripts\python.exe -m PyInstaller redforge-sidecar.spec --clean --noconfirm
```

Output: `sidecar\dist\redforge-sidecar.exe` (~34 MB)

### Faster: rebuild only Tauri (after sidecar exists)

```powershell
# Stage the sidecar
Copy-Item sidecar\dist\redforge-sidecar.exe src-tauri\binaries\redforge-sidecar-x86_64-pc-windows-msvc.exe -Force
# Build
npm run tauri build
```

### Hot-swap (fastest, for testing fixes against existing install)

```powershell
Get-Process redforge* -ErrorAction SilentlyContinue | Stop-Process -Force
Copy-Item sidecar\dist\redforge-sidecar.exe C:\Users\waspf\Downloads\RedForge_0.5.0_x64-portable\redforge-sidecar.exe -Force
Start-Process C:\Users\waspf\Downloads\RedForge_0.5.0_x64-portable\RedForge.exe
```

### Smoke test (must pass before release)

```powershell
.\scripts\smoke-test.ps1
```

13 tests against the bundled sidecar. Hits: health, ATT&CK browse, search, detail, create op, log timeline event, suggest techniques, recon scan, parse, generate followup, chain builder, list+timeline, DB persistence. Returns non-zero on failure (productize.ps1 gates on it).

---

## Release process

```powershell
# 1. Bump version in 3 places (must all match):
#    - package.json
#    - src-tauri/tauri.conf.json
#    - src-tauri/Cargo.toml
#    - scripts/package-portable.ps1 (the staging path + README)

# 2. Build
Build-Release.bat

# 3. Package portable
.\scripts\package-portable.ps1

# 4. Commit + tag + push
git add -A
git commit -m "..."
git tag -a v0.5.X -m "..."
git push origin main v0.5.X

# 5. Publish release with assets
gh release create v0.5.X --title "RedForge v0.5.X - ..." --notes-file .release-notes-v0.5.X.md `
  "src-tauri\target\release\bundle\nsis\RedForge_0.5.X_x64-setup.exe" `
  "src-tauri\target\release\bundle\msi\RedForge_0.5.X_x64_en-US.msi" `
  "RedForge_0.5.X_x64-portable.zip"
```

**Or:** with v0.5.3+, just push a `v*` tag and GitHub Actions does steps 2-5 automatically (see `.github/workflows/release.yml`).

---

## File map (where things live)

| Path | What it is |
|---|---|
| `RedForge.bat` / `launch.ps1` | Dev mode launcher (one-click setup + tauri dev) |
| `Build-Release.bat` | Production build entrypoint |
| `scripts/productize.ps1` | Full build pipeline (icons, ATT&CK data, sidecar, smoke test, Tauri) |
| `scripts/smoke-test.ps1` | 13-test integration suite |
| `scripts/package-portable.ps1` | Builds the portable .zip release asset |
| `scripts/download-attack-data.py` | Downloads MITRE ATT&CK STIX bundle (45 MB) |
| `scripts/generate-icons.py` | Generates all 17 Tauri icon formats |
| `src/App.tsx` | ALL React UI (3000+ lines, big monolith — has all views inline) |
| `src/lib/sidecar.ts` | All HTTP client wrappers for the sidecar API |
| `src/lib/store.ts` | Zustand global store (active operation, etc.) |
| `sidecar/engine.py` | FastAPI app — all routes, models, business logic (2000+ lines) |
| `sidecar/database.py` | SQLite layer + pydantic models |
| `sidecar/attack_data.py` | MITRE STIX bundle loader |
| `sidecar/redforge-sidecar.spec` | PyInstaller spec (one-file mode!) |
| `src-tauri/src/main.rs` | Tauri entry, window setup |
| `src-tauri/src/sidecar.rs` | Sidecar process manager (spawns, restart, status) |
| `src-tauri/tauri.conf.json` | Tauri config (versions, bundle settings, NSIS) |
| `src-tauri/binaries/redforge-sidecar-x86_64-pc-windows-msvc.exe` | **Stub file (580 bytes)**. Real sidecar is staged here at build time. Stub stays committed; real exe is .gitignored. |
| `%APPDATA%\com.redforge.desktop\` | User data: redforge.db + logs/sidecar.log |

---

## Backend API surface

`http://127.0.0.1:18765/...` (only binds to 127.0.0.1). Full OpenAPI at `/docs`.

Critical endpoints:
- `GET /health` — sidecar status (used by Rust polling)
- `GET /api/ollama/status` — Ollama detection + model selection diagnostics
- `GET|POST /api/operations[/{id}/...]` — CRUD ops + timeline + assets + creds + chains
- `GET /api/attack/{stats,tactics,techniques[/{id}]}` — MITRE ATT&CK browse
- `POST /api/execute` — local command execution
- `POST /api/remote/{test,execute}` — WinRM/PSExec remote
- `POST /api/recon/{scan,execute,parse}` — recon flows
- `POST /api/suggest_techniques?command=...` — auto-suggest as you type
- `POST /api/generate_followup` — paste output, get next command
- `POST /api/assistant` — Red Team Leader chat (uses Ollama, falls back to rules)
- `POST /api/assistant/plan_kill_chain` — structured kill chain (JSON output)

---

## Logging & debugging

**Sidecar log:** `%APPDATA%\com.redforge.desktop\logs\sidecar.log` (rotating, 5 MB × 3).
Captures uvicorn access logs, our own info/warn, and httpx Ollama call traces.

**Tauri logs:** stdout — only visible when running from terminal (`npm run tauri dev`). In production they're swallowed.

**Live debug:**
```powershell
# Watch sidecar log live
Get-Content "$env:APPDATA\com.redforge.desktop\logs\sidecar.log" -Wait -Tail 30

# Direct API hit
Invoke-RestMethod "http://127.0.0.1:18765/health"

# Check Ollama detection
Invoke-RestMethod "http://127.0.0.1:18765/api/ollama/status"
```

**DevTools in the UI:** F12 enabled via `tauri = { features = ["devtools"] }` in Cargo.toml.

---

## Active TODOs / Roadmap

**Immediate (v0.5.3):**
- [x] Per-user NSIS install (no UAC)
- [x] WebView2 bootstrapper bundled
- [x] First-run wizard (auth checkbox + Ollama detection)
- [x] Smarter "thinking..." loading UX with cold-start explanation
- [x] GitHub Actions CI (smoke test + release workflow)
- [x] README rewrite for end users
- [ ] Build & ship v0.5.3 release

**Tier 1 (blocking real launch):**
- [ ] **Code signing** ($150-500/yr) — eliminates SmartScreen warning. Major install-rate blocker.
- [ ] **Antivirus whitelisting** — submit `redforge-sidecar.exe` to Microsoft for clean-binary review

**Tier 2 (polish):**
- [ ] **Auto-updater** — Tauri 2 built-in. Needs signing key + update manifest server (can be GitHub Releases).
- [ ] **Single-instance lock** — `tauri-plugin-single-instance` so double-clicking doesn't spawn 2 apps.
- [ ] **Dynamic sidecar port** — pick free port instead of hardcoded 18765. Currently silently fails if port is taken.
- [ ] **Settings view** — currently a stub. Should have Ollama model picker, log location, "factory reset", "show first-run wizard again".

**Tier 3 (CI/CD + portability):**
- [ ] **Linux/macOS builds** — AppImage + .dmg. Tauri supports both natively but they're untested here.
- [ ] **Telemetry audit** — confirm + document zero telemetry (Ollama is local, ATT&CK is bundled, no other network calls).

---

## Gotchas to remember

1. **Don't commit `redforge-sidecar.exe` to git.** The repo has a 580-byte stub. Always `git checkout HEAD -- src-tauri/binaries/redforge-sidecar-x86_64-pc-windows-msvc.exe` before committing if you've staged a real one.

2. **The portable folder is named "RedForge_0.5.0_x64-portable"** but contains hot-swapped current files. Don't trust the folder name — check `(Get-FileHash X.exe).Hash` to verify which version.

3. **Tauri's "stage sidecar to binaries/" step is racy.** If Tauri's mid-build during a copy, you might grab a stale exe. Verify hashes match between source and destination after staging.

4. **Ollama model auto-detection caches for 60 sec.** If you `ollama pull` a new model and want RedForge to see it immediately, restart the sidecar.

5. **PyInstaller builds fail intermittently on Windows due to Defender locking files.** Build twice if the first one fails — usually works the second time once Defender is done scanning.

6. **PowerShell heredocs in Bash tool break on inline double-quotes** in commit messages. Use temp file approach: `Write` the message to `.commit-msg.tmp` then `git commit -F`.

---

## How to update this doc

After finishing a meaningful task, edit `CONTEXT.md`:
- Bump "Last updated" date
- Cross off completed items in "Active TODOs"
- Add any new bugs you hit to "Hard-won bug landmines"
- Update "Current state" if version changed

Keep it terse — this is reference, not prose.
