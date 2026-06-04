"""
RedForge Sidecar - ATT&CK Data Loader (Phase 1)

Loads the enterprise-attack STIX JSON once at startup and builds
fast in-memory indexes for the browser and other features.

This is intentionally simple for v1. We can add SQLite FTS, 
vector search, or incremental updates later.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

# --------------------------------------------------------------------------- #
# Paths
# --------------------------------------------------------------------------- #

ATTACK_DATA_DIR = Path(__file__).parent / "attack_data"
ENTERPRISE_JSON = ATTACK_DATA_DIR / "enterprise-attack.json"


# --------------------------------------------------------------------------- #
# In-memory indexes (populated at startup)
# --------------------------------------------------------------------------- #

class AttackDataStore:
    def __init__(self):
        self.loaded: bool = False
        self.version: str | None = None
        self.total_objects: int = 0

        # Core indexes
        self.techniques: list[dict[str, Any]] = []           # simplified technique dicts
        self.techniques_by_id: dict[str, dict[str, Any]] = {}  # external_id (Txxxx) -> technique
        self.techniques_by_stix: dict[str, dict[str, Any]] = {}  # STIX id -> technique

        self.tactics: list[dict[str, Any]] = []
        self.tactics_by_id: dict[str, dict[str, Any]] = {}

        self.platforms: set[str] = set()
        self.tactic_order: list[str] = []  # canonical order from the matrix

    def is_ready(self) -> bool:
        return self.loaded and len(self.techniques) > 0


STORE = AttackDataStore()


def _simplify_technique(obj: dict[str, Any]) -> dict[str, Any] | None:
    """Turn a raw STIX attack-pattern into a compact dict we actually need."""
    if obj.get("type") != "attack-pattern":
        return None
    if obj.get("x_mitre_deprecated") or obj.get("revoked"):
        return None

    ext_refs = obj.get("external_references", [])
    external_id = None
    for ref in ext_refs:
        if ref.get("source_name") == "mitre-attack":
            external_id = ref.get("external_id")
            break
    if not external_id:
        return None

    # Tactics come from kill_chain_phases or x_mitre_tactics
    tactics: list[str] = []
    for phase in obj.get("kill_chain_phases", []):
        if phase.get("kill_chain_name") in ("mitre-attack", "mitre-ics-attack"):
            if phase.get("phase_name"):
                tactics.append(phase["phase_name"])

    # Some objects use x_mitre_tactics instead
    if not tactics:
        tactics = obj.get("x_mitre_tactics", []) or []

    platforms = obj.get("x_mitre_platforms", []) or []
    for p in platforms:
        STORE.platforms.add(p)

    return {
        "id": obj.get("id"),                    # STIX id
        "external_id": external_id,             # T1055.001 etc.
        "name": obj.get("name", ""),
        "description": obj.get("description", ""),
        "tactics": tactics,
        "platforms": platforms,
        "permissions_required": obj.get("x_mitre_permissions_required", []),
        "data_sources": obj.get("x_mitre_data_sources", []),
        "detection": obj.get("x_mitre_detection", ""),
        "url": f"https://attack.mitre.org/techniques/{external_id.replace('.', '/')}",
        "is_subtechnique": obj.get("x_mitre_is_subtechnique", False),
    }


def _simplify_tactic(obj: dict[str, Any]) -> dict[str, Any] | None:
    if obj.get("type") != "x-mitre-tactic":
        return None
    if obj.get("x_mitre_deprecated") or obj.get("revoked"):
        return None

    ext_refs = obj.get("external_references", [])
    external_id = None
    for ref in ext_refs:
        if ref.get("source_name") == "mitre-attack":
            external_id = ref.get("external_id")
            break
    if not external_id:
        return None

    return {
        "id": obj.get("id"),
        "external_id": external_id,
        "name": obj.get("name", ""),
        "description": obj.get("description", ""),
        "short_name": obj.get("x_mitre_short_name", ""),
        "url": f"https://attack.mitre.org/tactics/{external_id}",
    }


def load_attack_data() -> None:
    """Load and index the ATT&CK data. Safe to call multiple times (idempotent)."""
    global STORE

    if STORE.loaded:
        return

    if not ENTERPRISE_JSON.exists():
        print(f"[ATT&CK] enterprise-attack.json not found at {ENTERPRISE_JSON}")
        return

    print(f"[ATT&CK] Loading {ENTERPRISE_JSON} (this may take a few seconds on first run)...")
    try:
        with open(ENTERPRISE_JSON, encoding="utf-8") as f:
            bundle = json.load(f)

        objects = bundle.get("objects", [])
        STORE.total_objects = len(objects)

        techniques: list[dict[str, Any]] = []
        tactics: list[dict[str, Any]] = []

        for obj in objects:
            if obj.get("type") == "attack-pattern":
                t = _simplify_technique(obj)
                if t:
                    techniques.append(t)
            elif obj.get("type") == "x-mitre-tactic":
                tac = _simplify_tactic(obj)
                if tac:
                    tactics.append(tac)

        # Build lookup indexes
        for t in techniques:
            STORE.techniques_by_id[t["external_id"]] = t
            STORE.techniques_by_stix[t["id"]] = t

        for tac in tactics:
            STORE.tactics_by_id[tac["external_id"]] = tac

        # Sort techniques by external_id for stable listing
        techniques.sort(key=lambda x: x["external_id"])

        STORE.techniques = techniques
        STORE.tactics = sorted(tactics, key=lambda x: x["external_id"])

        # Try to get a reasonable tactic order from the matrix (best effort)
        for obj in objects:
            if obj.get("type") == "x-mitre-matrix" and "enterprise" in (obj.get("name") or "").lower():
                tactics_order = obj.get("tactic_refs", [])
                ordered = []
                for ref in tactics_order:
                    for t in tactics:
                        if t["id"] == ref:
                            ordered.append(t["external_id"])
                            break
                if ordered:
                    STORE.tactic_order = ordered
                break

        if not STORE.tactic_order:
            STORE.tactic_order = [t["external_id"] for t in STORE.tactics]

        STORE.loaded = True
        print(f"[ATT&CK] Loaded {len(techniques)} techniques and {len(tactics)} tactics.")

    except Exception as e:
        print(f"[ATT&CK] Failed to load ATT&CK data: {e}")
        STORE.loaded = False


def get_stats() -> dict[str, Any]:
    return {
        "loaded": STORE.is_ready(),
        "total_techniques": len(STORE.techniques),
        "total_tactics": len(STORE.tactics),
        "total_objects_in_bundle": STORE.total_objects,
        "platforms": sorted(STORE.platforms),
    }


def search_techniques(
    query: str | None = None,
    tactic: str | None = None,
    platform: str | None = None,
    limit: int = 200,
) -> list[dict[str, Any]]:
    """Very basic search for Phase 1. Returns list of simplified techniques."""
    results = STORE.techniques

    if tactic:
        t = tactic.lower()
        results = [r for r in results if any(t in tac.lower() for tac in r.get("tactics", []))]

    if platform:
        p = platform.lower()
        results = [r for r in results if any(p in plat.lower() for plat in r.get("platforms", []))]

    if query:
        q = query.lower()
        results = [
            r for r in results
            if q in r.get("name", "").lower()
            or q in r.get("description", "").lower()
            or q in r.get("external_id", "").lower()
        ]

    return results[:limit]


def get_technique(external_id: str) -> dict[str, Any] | None:
    return STORE.techniques_by_id.get(external_id)


def get_all_tactics() -> list[dict[str, Any]]:
    # Return in canonical order when possible
    if STORE.tactic_order:
        ordered = []
        for ext_id in STORE.tactic_order:
            if ext_id in STORE.tactics_by_id:
                ordered.append(STORE.tactics_by_id[ext_id])
        if ordered:
            return ordered
    return STORE.tactics
