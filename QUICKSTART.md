# RedForge - Idiot-Proof Setup Guide

**Zero experience needed. Follow the steps exactly. Don't skip anything.**

---

## STEP 0: What is RedForge?

RedForge is a desktop app for **authorized** red team / penetration testing operations. It helps you:

- Scan targets for open ports
- Track what you've done (timeline)
- Execute commands locally or on remote Windows machines
- Get AI-powered kill chain suggestions (via Ollama)
- Build MITRE ATT&CK chains visually
- Generate reports

**It runs 100% on YOUR machine. No cloud. No accounts. No telemetry.**

---

## STEP 1: Install the Prerequisites (one time only)

You need 4 things installed. Here's how to get each one on **Windows**:

### 1a. Node.js (the JavaScript engine)

1. Go to **https://nodejs.org/**
2. Click the big green **"Download LTS"** button
3. Run the installer
4. **CHECK the box** that says "Automatically install necessary tools"
5. Click Next through everything, finish

**Verify it worked:** Open a new Command Prompt and type:
```
node --version
```
You should see something like `v20.x.x` or `v24.x.x`. If you get "not recognized", restart your computer and try again.

### 1b. Python (for the backend sidecar)

1. Go to **https://www.python.org/downloads/**
2. Click the big yellow **"Download Python 3.x.x"** button
3. Run the installer
4. **IMPORTANT: CHECK THE BOX** at the bottom that says **"Add Python to PATH"** (this is the #1 mistake people make)
5. Click "Install Now"

**Verify it worked:**
```
python --version
```
Should show `Python 3.12.x` or higher.

### 1c. Rust (compiles the desktop shell)

1. Go to **https://rustup.rs/**
2. Click **"rustup-init.exe (64-bit)"**
3. Run it
4. When it asks, just press **Enter** to accept defaults (option 1)
5. Wait for it to finish
6. **Close and reopen your terminal** (this is required)

**Verify it worked:**
```
rustc --version
cargo --version
```

### 1d. Visual Studio Build Tools (Rust needs this on Windows)

1. Run this in PowerShell:
   ```
   winget install Microsoft.VisualStudio.2022.BuildTools
   ```
2. When the Visual Studio Installer opens, check **"Desktop development with C++"**
3. Click Install
4. This takes a while (several GB download). Go get coffee.

**OR** if you already have Visual Studio 2022 installed with C++ tools, skip this step.

### 1e. Ollama (OPTIONAL - for AI features)

1. Go to **https://ollama.com/**
2. Download and install for Windows
3. Open a terminal and run:
   ```
   ollama pull llama3.1:8b
   ```
4. Wait for the model to download (~4.7 GB)

**This is optional.** RedForge works without it, but the "Red Team Leader" AI assistant won't function.

### 1f. Git (you probably already have this)

```
winget install Git.Git
```

Or download from **https://git-scm.com/download/win**

---

## STEP 2: Get RedForge

Open a terminal (Command Prompt or PowerShell) and run:

```
git clone https://github.com/synaptechintel/redforge.git
cd redforge
```

That's it. You now have RedForge on your machine.

---

## STEP 3: Launch RedForge (ONE CLICK)

### Option A: Double-click (easiest)

1. Open the `redforge` folder in File Explorer
2. **Double-click `RedForge.bat`**
3. A terminal window opens and does everything automatically:
   - Checks all prerequisites
   - Installs Node.js dependencies (`npm install`)
   - Creates Python virtual environment
   - Installs Python sidecar dependencies
   - Launches the app

**First time takes 5-10 minutes** (Rust compilation). Just wait. Don't close the window.

**Every time after that: ~5 seconds.**

### Option B: PowerShell (same thing, prettier output)

```powershell
cd redforge
.\launch.ps1
```

### Option C: One-liner install from anywhere (no git clone needed)

```powershell
irm https://raw.githubusercontent.com/synaptechintel/redforge/main/install.ps1 | iex
```

This clones, sets up, creates desktop shortcuts, and launches. One command.

---

## STEP 4: Using RedForge

When the app opens, you'll see a dark tactical interface with a sidebar on the left.

### 4a. Create an Operation (do this first!)

1. Click **"Operations"** in the sidebar (it's the first item)
2. Click the red **"+ New"** button
3. Fill in:
   - **Name**: e.g. "Lab Practice - June 2026"
   - **Description**: e.g. "Practice engagement against home lab"
   - **Scope**: e.g. "192.168.1.0/24"
4. Click **"Create Operation"**
5. Click **"Set as Active"** on the operation you just created

**Everything you do from now on gets logged to this operation.**

### 4b. Run a Recon Scan

1. Click **"Recon"** in the sidebar
2. Type a target IP in the **Target** box (e.g. `192.168.1.100`)
3. Pick ports or use a preset (click "Common Red Team" for a good default)
4. Click **"Scan [target] (python)"**
5. Results appear showing open ports
6. Click **"Recon Complete -> Ask Red Team Leader"** to get AI guidance on next steps

### 4c. Execute Commands

1. Click **"Execution"** in the sidebar
2. Type a command (e.g. `whoami`, `ipconfig`, `systeminfo`)
3. The app will **auto-suggest MITRE ATT&CK techniques** as you type
4. Click a suggestion to auto-fill the technique field
5. Click **"Execute"** to run it (output appears below)
6. Everything is logged to your operation timeline

### 4d. Remote Execution (WinRM / PSExec)

1. In the Execution view, switch mode from **"Local"** to **"WinRM"** or **"PSExec"**
2. Fill in: Host, Username, Password (or NTLM hash for pass-the-hash)
3. Click **"Test Connection"** first to verify access
4. Then type commands and execute remotely
5. All output is captured and logged

### 4e. Build Attack Chains

1. Click **"Chain Builder"** in the sidebar
2. Click **"+ New"** to create a chain (e.g. "Initial Access to Domain Admin")
3. Search for MITRE ATT&CK techniques and add them as steps
4. Mark steps as "planned" -> "in progress" -> "executed" as you go
5. When you mark a step "executed", the Red Team Leader auto-suggests the next move

### 4f. Talk to the Red Team Leader (AI)

1. Click **"Red Team Leader"** in the sidebar
2. This is a terminal-style chat powered by your local Ollama LLM
3. It sees your real discovered hosts, ports, and credentials
4. Try the quick buttons:
   - **"Start Kill Chain"** - walks you through a full engagement step by step
   - **"Best Next Move"** - tells you exactly what command to run next
   - **"Generate Structured Plan"** - creates a full kill chain you can import into Chain Builder
5. Commands it suggests use **your real discovered data** (no placeholders)

### 4g. Browse ATT&CK Techniques

1. Click **"ATT&CK Browser"** in the sidebar
2. Search by name, ID, tactic, or platform
3. Click any technique to see its details, detection guidance, and MITRE link
4. Click **"Log to Active Operation Timeline"** to note that you considered it

### 4h. View Discovered Assets

1. Click **"Discovered Assets"** in the sidebar
2. See all hosts, ports, services, and credentials discovered during your operation
3. These are auto-populated from recon scans and command output
4. The Red Team Leader and auto-suggestions use these to give you real commands

### 4i. Generate Reports

1. Click **"Reports"** in the sidebar
2. Click **"Generate Report"**
3. A Markdown report is generated with your full timeline, chains, and findings
4. Click **"Download Markdown"** to save it

---

## Common Problems

### "npm is not recognized"
You need to restart your terminal after installing Node.js. If that doesn't work, reinstall Node.js and make sure "Add to PATH" is checked.

### "python is not recognized"
Reinstall Python. **Check "Add Python to PATH"** at the very bottom of the installer. This is the single most common mistake.

### "cargo is not recognized"
Close ALL terminal windows and open a fresh one. Rust modifies PATH but existing terminals don't see it.

### "tauri dev failed" / Rust compilation errors
You probably need Visual Studio Build Tools with C++ workload. Run:
```
winget install Microsoft.VisualStudio.2022.BuildTools
```
Then in the installer, check "Desktop development with C++" and install.

### First launch is really slow
Normal! The first `tauri dev` compiles the entire Rust backend (~3-5 minutes). Every launch after that is fast (~5 seconds).

### "Sidecar: down" in the app header
The Python backend didn't start. Click the "Restart" button next to "Sidecar: down" in the top bar. If it keeps failing, check that your Python venv exists (`sidecar\.venv` folder) and has the dependencies installed.

### Red Team Leader says "Error reaching the assistant backend"
Ollama isn't running. Open a terminal and run:
```
ollama serve
```
Leave it running. Then in another terminal:
```
ollama pull llama3.1:8b
```

### I want to start fresh
Delete the `.redforge-setup-done` file in the project root, then double-click `RedForge.bat` again. It will redo all setup.

### Where is my data stored?
Your operations database is at `%LOCALAPPDATA%\com.redforge.desktop\redforge.db` (or `~/.redforge/redforge.db` on Linux). It's a SQLite file.

---

## Quick Reference

| What | How |
|---|---|
| Launch the app | Double-click `RedForge.bat` |
| Force re-setup | Delete `.redforge-setup-done`, then launch |
| Build release version | `.\scripts\build-windows.ps1` (faster native .exe, no dev tools needed to run) |
| Update to latest | `git pull` then launch normally |
| Change Ollama model | Edit `model='llama3.1:8b'` in `sidecar/engine.py` (search for "ollama.chat") |
| View sidecar API docs | Open `http://127.0.0.1:18765/docs` while app is running |

---

## The 30-Second Version

```
git clone https://github.com/synaptechintel/redforge.git
cd redforge
RedForge.bat
```

Wait. Done.

---

**REMEMBER: Only use on systems you own or have explicit written authorization to test.**
