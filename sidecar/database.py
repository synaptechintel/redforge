"""
RedForge Sidecar - Database Layer

Owns the local SQLite database for operations, evidence, timeline, etc.
Uses aiosqlite for clean async access.
"""

from __future__ import annotations

import json
import os
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import aiosqlite
from pydantic import BaseModel, Field

# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #

DEFAULT_DB_FILENAME = "redforge.db"


def get_data_dir() -> Path:
    """Resolve the data directory for RedForge.

    Priority:
    1. REDFORGE_DATA_DIR environment variable
    2. Platform-specific app data directory (best effort)
    3. ~/.redforge
    """
    env = os.getenv("REDFORGE_DATA_DIR")
    if env:
        return Path(env).expanduser().resolve()

    # Try platformdirs if available (optional nice-to-have)
    try:
        import platformdirs  # type: ignore

        return Path(platformdirs.user_data_dir("RedForge", "RedForge"))
    except Exception:
        pass

    # Fallback
    return Path.home() / ".redforge"


def get_db_path() -> Path:
    data_dir = get_data_dir()
    data_dir.mkdir(parents=True, exist_ok=True)
    return data_dir / DEFAULT_DB_FILENAME


# --------------------------------------------------------------------------- #
# Pydantic Models (shared with API)
# --------------------------------------------------------------------------- #

class OperationCreate(BaseModel):
    name: str
    description: str | None = None
    scope: str | None = None
    roe_notes: str | None = None


class OperationUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    scope: str | None = None
    roe_notes: str | None = None
    status: str | None = None


class TimelineEventCreate(BaseModel):
    operation_id: str
    type: str = "manual"
    technique_id: str | None = None
    command: str | None = None
    output: str | None = None
    result: str | None = None
    notes: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)
    # New fields for remote execution
    target_host: str | None = None
    execution_method: str | None = None   # local | winrm | psexec | smb
    remote_user: str | None = None


class TimelineEvent(BaseModel):
    id: str
    operation_id: str
    timestamp: str
    type: str
    technique_id: str | None = None
    command: str | None = None
    output: str | None = None
    result: str | None = None
    notes: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


# Attack Chain models
class ChainCreate(BaseModel):
    operation_id: str
    name: str
    description: str | None = None


class Chain(BaseModel):
    id: str
    operation_id: str
    name: str
    description: str | None = None
    created_at: str
    updated_at: str


class ChainStep(BaseModel):
    id: str
    chain_id: str
    position: int
    technique_id: str
    status: str = "planned"
    notes: str | None = None


class ChainWithSteps(Chain):
    steps: list[ChainStep] = Field(default_factory=list)


# Discovered Assets & Credentials
class Asset(BaseModel):
    id: str
    operation_id: str
    host: str
    port: int | None = None
    service: str | None = None
    protocol: str | None = None
    status: str | None = None
    notes: str | None = None
    first_seen: str
    last_seen: str
    metadata: dict[str, Any] = Field(default_factory=dict)


class Credential(BaseModel):
    id: str
    operation_id: str
    host: str | None = None
    username: str | None = None
    password: str | None = None
    hash: str | None = None
    type: str | None = None
    source: str | None = None
    first_seen: str
    metadata: dict[str, Any] = Field(default_factory=dict)


class Operation(BaseModel):
    id: str
    name: str
    description: str | None = None
    scope: str | None = None
    roe_notes: str | None = None
    status: str = "planning"
    created_at: str
    updated_at: str
    metadata: dict[str, Any] = Field(default_factory=dict)


# --------------------------------------------------------------------------- #
# Database Manager
# --------------------------------------------------------------------------- #

class Database:
    def __init__(self, db_path: Path | None = None):
        self.db_path = db_path or get_db_path()
        self._conn: aiosqlite.Connection | None = None

    async def connect(self) -> None:
        if self._conn is not None:
            return
        self._conn = await aiosqlite.connect(self.db_path)
        self._conn.row_factory = aiosqlite.Row
        await self._ensure_schema()

    async def close(self) -> None:
        if self._conn:
            await self._conn.close()
            self._conn = None

    async def _ensure_schema(self) -> None:
        assert self._conn is not None

        # Simple schema versioning table
        await self._conn.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
            """
        )

        # Operations table
        await self._conn.execute(
            """
            CREATE TABLE IF NOT EXISTS operations (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT,
                scope TEXT,
                roe_notes TEXT,
                status TEXT NOT NULL DEFAULT 'planning',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                metadata TEXT NOT NULL DEFAULT '{}'
            )
            """
        )

        # Timeline / Action Log
        await self._conn.execute(
            """
            CREATE TABLE IF NOT EXISTS timeline_events (
                id TEXT PRIMARY KEY,
                operation_id TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                type TEXT NOT NULL DEFAULT 'manual',
                technique_id TEXT,
                command TEXT,
                output TEXT,
                result TEXT,
                notes TEXT,
                metadata TEXT NOT NULL DEFAULT '{}',
                FOREIGN KEY(operation_id) REFERENCES operations(id) ON DELETE CASCADE
            )
            """
        )

        # Attack Chains (core feature)
        await self._conn.execute(
            """
            CREATE TABLE IF NOT EXISTS attack_chains (
                id TEXT PRIMARY KEY,
                operation_id TEXT NOT NULL,
                name TEXT NOT NULL,
                description TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(operation_id) REFERENCES operations(id) ON DELETE CASCADE
            )
            """
        )

        await self._conn.execute(
            """
            CREATE TABLE IF NOT EXISTS chain_steps (
                id TEXT PRIMARY KEY,
                chain_id TEXT NOT NULL,
                position INTEGER NOT NULL,
                technique_id TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'planned',  -- planned | in_progress | executed | failed | skipped
                notes TEXT,
                FOREIGN KEY(chain_id) REFERENCES attack_chains(id) ON DELETE CASCADE
            )
            """
        )

        # Discovered Assets (hosts, services, etc.) - for LLM context and kill chain planning
        await self._conn.execute(
            """
            CREATE TABLE IF NOT EXISTS assets (
                id TEXT PRIMARY KEY,
                operation_id TEXT NOT NULL,
                host TEXT NOT NULL,
                port INTEGER,
                service TEXT,
                protocol TEXT,
                status TEXT,
                notes TEXT,
                first_seen TEXT NOT NULL,
                last_seen TEXT NOT NULL,
                metadata TEXT NOT NULL DEFAULT '{}',
                FOREIGN KEY(operation_id) REFERENCES operations(id) ON DELETE CASCADE
            )
            """
        )

        # Credentials / Accounts discovered
        await self._conn.execute(
            """
            CREATE TABLE IF NOT EXISTS credentials (
                id TEXT PRIMARY KEY,
                operation_id TEXT NOT NULL,
                host TEXT,
                username TEXT,
                password TEXT,
                hash TEXT,
                type TEXT,
                source TEXT,
                first_seen TEXT NOT NULL,
                metadata TEXT NOT NULL DEFAULT '{}',
                FOREIGN KEY(operation_id) REFERENCES operations(id) ON DELETE CASCADE
            )
            """
        )

        await self._conn.execute(
            "INSERT OR IGNORE INTO schema_meta (key, value) VALUES ('schema_version', '1')"
        )
        await self._conn.commit()

    # ----------------------------------------------------------------------- #
    # Operations CRUD
    # ----------------------------------------------------------------------- #

    async def list_operations(self) -> list[Operation]:
        assert self._conn is not None
        cursor = await self._conn.execute(
            """
            SELECT id, name, description, scope, roe_notes, status,
                   created_at, updated_at, metadata
            FROM operations
            ORDER BY updated_at DESC
            """
        )
        rows = await cursor.fetchall()
        return [self._row_to_operation(row) for row in rows]

    async def get_operation(self, op_id: str) -> Operation | None:
        assert self._conn is not None
        cursor = await self._conn.execute(
            """
            SELECT id, name, description, scope, roe_notes, status,
                   created_at, updated_at, metadata
            FROM operations
            WHERE id = ?
            """,
            (op_id,),
        )
        row = await cursor.fetchone()
        return self._row_to_operation(row) if row else None

    async def create_operation(self, data: OperationCreate) -> Operation:
        assert self._conn is not None

        now = datetime.now(timezone.utc).isoformat()
        op_id = str(uuid.uuid4())

        await self._conn.execute(
            """
            INSERT INTO operations (id, name, description, scope, roe_notes, status, created_at, updated_at, metadata)
            VALUES (?, ?, ?, ?, ?, 'planning', ?, ?, '{}')
            """,
            (op_id, data.name, data.description, data.scope, data.roe_notes, now, now),
        )
        await self._conn.commit()

        return Operation(
            id=op_id,
            name=data.name,
            description=data.description,
            scope=data.scope,
            roe_notes=data.roe_notes,
            status="planning",
            created_at=now,
            updated_at=now,
        )

    async def update_operation(self, op_id: str, data: OperationUpdate) -> Operation | None:
        assert self._conn is not None

        # Build dynamic update
        fields: list[str] = []
        values: list[Any] = []

        if data.name is not None:
            fields.append("name = ?")
            values.append(data.name)
        if data.description is not None:
            fields.append("description = ?")
            values.append(data.description)
        if data.scope is not None:
            fields.append("scope = ?")
            values.append(data.scope)
        if data.roe_notes is not None:
            fields.append("roe_notes = ?")
            values.append(data.roe_notes)
        if data.status is not None:
            fields.append("status = ?")
            values.append(data.status)

        if not fields:
            return await self.get_operation(op_id)

        fields.append("updated_at = ?")
        values.append(datetime.now(timezone.utc).isoformat())
        values.append(op_id)

        sql = f"UPDATE operations SET {', '.join(fields)} WHERE id = ?"
        await self._conn.execute(sql, values)
        await self._conn.commit()

        return await self.get_operation(op_id)

    async def delete_operation(self, op_id: str) -> bool:
        assert self._conn is not None
        cursor = await self._conn.execute("DELETE FROM operations WHERE id = ?", (op_id,))
        await self._conn.commit()
        return cursor.rowcount > 0

    # ----------------------------------------------------------------------- #
    # Timeline / Action Log
    # ----------------------------------------------------------------------- #

    async def log_timeline_event(self, data: TimelineEventCreate) -> TimelineEvent:
        assert self._conn is not None
        event_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc).isoformat()

        await self._conn.execute(
            """
            INSERT INTO timeline_events
            (id, operation_id, timestamp, type, technique_id, command, output, result, notes, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                event_id,
                data.operation_id,
                now,
                data.type,
                data.technique_id,
                data.command,
                data.output,
                data.result,
                data.notes,
                json.dumps({
                    **data.metadata,
                    "target_host": data.target_host,
                    "execution_method": data.execution_method,
                    "remote_user": data.remote_user,
                }),
            ),
        )
        await self._conn.commit()

        return TimelineEvent(
            id=event_id,
            operation_id=data.operation_id,
            timestamp=now,
            type=data.type,
            technique_id=data.technique_id,
            command=data.command,
            output=data.output,
            result=data.result,
            notes=data.notes,
            metadata=data.metadata,
        )

    async def get_timeline_for_operation(self, op_id: str) -> list[TimelineEvent]:
        assert self._conn is not None
        cursor = await self._conn.execute(
            """
            SELECT id, operation_id, timestamp, type, technique_id, command, output, result, notes, metadata
            FROM timeline_events
            WHERE operation_id = ?
            ORDER BY timestamp DESC
            """,
            (op_id,),
        )
        rows = await cursor.fetchall()
        events: list[TimelineEvent] = []
        for row in rows:
            events.append(
                TimelineEvent(
                    id=row["id"],
                    operation_id=row["operation_id"],
                    timestamp=row["timestamp"],
                    type=row["type"],
                    technique_id=row["technique_id"],
                    command=row["command"],
                    output=row["output"],
                    result=row["result"],
                    notes=row["notes"],
                    metadata=json.loads(row["metadata"]) if row["metadata"] else {},
                )
            )
        return events

    # ----------------------------------------------------------------------- #
    # Attack Chains
    # ----------------------------------------------------------------------- #

    async def create_chain(self, data: ChainCreate) -> Chain:
        assert self._conn is not None
        chain_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc).isoformat()

        await self._conn.execute(
            """
            INSERT INTO attack_chains (id, operation_id, name, description, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (chain_id, data.operation_id, data.name, data.description, now, now),
        )
        await self._conn.commit()

        return Chain(
            id=chain_id,
            operation_id=data.operation_id,
            name=data.name,
            description=data.description,
            created_at=now,
            updated_at=now,
        )

    async def get_chains_for_operation(self, op_id: str) -> list[Chain]:
        assert self._conn is not None
        cursor = await self._conn.execute(
            "SELECT * FROM attack_chains WHERE operation_id = ? ORDER BY updated_at DESC",
            (op_id,),
        )
        rows = await cursor.fetchall()
        return [
            Chain(
                id=r["id"],
                operation_id=r["operation_id"],
                name=r["name"],
                description=r["description"],
                created_at=r["created_at"],
                updated_at=r["updated_at"],
            )
            for r in rows
        ]

    async def get_chain_with_steps(self, chain_id: str) -> ChainWithSteps | None:
        assert self._conn is not None
        cursor = await self._conn.execute("SELECT * FROM attack_chains WHERE id = ?", (chain_id,))
        chain_row = await cursor.fetchone()
        if not chain_row:
            return None

        cursor = await self._conn.execute(
            "SELECT * FROM chain_steps WHERE chain_id = ? ORDER BY position ASC",
            (chain_id,),
        )
        step_rows = await cursor.fetchall()

        steps = [
            ChainStep(
                id=r["id"],
                chain_id=r["chain_id"],
                position=r["position"],
                technique_id=r["technique_id"],
                status=r["status"],
                notes=r["notes"],
            )
            for r in step_rows
        ]

        return ChainWithSteps(
            id=chain_row["id"],
            operation_id=chain_row["operation_id"],
            name=chain_row["name"],
            description=chain_row["description"],
            created_at=chain_row["created_at"],
            updated_at=chain_row["updated_at"],
            steps=steps,
        )

    async def add_step_to_chain(self, chain_id: str, technique_id: str) -> ChainStep:
        assert self._conn is not None
        # Get current max position
        cursor = await self._conn.execute(
            "SELECT COALESCE(MAX(position), -1) + 1 as next_pos FROM chain_steps WHERE chain_id = ?",
            (chain_id,),
        )
        next_pos = (await cursor.fetchone())["next_pos"]

        step_id = str(uuid.uuid4())

        await self._conn.execute(
            """
            INSERT INTO chain_steps (id, chain_id, position, technique_id, status)
            VALUES (?, ?, ?, ?, 'planned')
            """,
            (step_id, chain_id, next_pos, technique_id),
        )
        await self._conn.commit()

        return ChainStep(
            id=step_id,
            chain_id=chain_id,
            position=next_pos,
            technique_id=technique_id,
            status="planned",
        )

    async def update_step_status(self, step_id: str, status: str, notes: str | None = None) -> None:
        assert self._conn is not None
        await self._conn.execute(
            "UPDATE chain_steps SET status = ?, notes = ? WHERE id = ?",
            (status, notes, step_id),
        )
        await self._conn.commit()

    async def delete_chain(self, chain_id: str) -> bool:
        assert self._conn is not None
        cursor = await self._conn.execute("DELETE FROM attack_chains WHERE id = ?", (chain_id,))
        await self._conn.commit()
        return cursor.rowcount > 0

    # ----------------------------------------------------------------------- #
    # Discovered Assets & Credentials
    # ----------------------------------------------------------------------- #

    async def upsert_asset(self, operation_id: str, host: str, port: int | None = None,
                           service: str | None = None, protocol: str | None = None,
                           status: str | None = None, notes: str | None = None,
                           metadata: dict | None = None) -> Asset:
        assert self._conn is not None
        now = datetime.now(timezone.utc).isoformat()
        asset_id = f"{operation_id}:{host}:{port or 0}"

        # Check if exists
        cursor = await self._conn.execute(
            "SELECT * FROM assets WHERE id = ?", (asset_id,)
        )
        existing = await cursor.fetchone()

        if existing:
            await self._conn.execute(
                """
                UPDATE assets SET
                    last_seen = ?,
                    service = COALESCE(?, service),
                    protocol = COALESCE(?, protocol),
                    status = COALESCE(?, status),
                    notes = COALESCE(?, notes),
                    metadata = ?
                WHERE id = ?
                """,
                (now, service, protocol, status, notes, json.dumps(metadata or {}), asset_id)
            )
        else:
            await self._conn.execute(
                """
                INSERT INTO assets (id, operation_id, host, port, service, protocol, status, notes, first_seen, last_seen, metadata)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (asset_id, operation_id, host, port, service, protocol, status, notes, now, now, json.dumps(metadata or {}))
            )
        await self._conn.commit()

        return await self.get_asset(asset_id)

    async def get_asset(self, asset_id: str) -> Asset | None:
        assert self._conn is not None
        cursor = await self._conn.execute("SELECT * FROM assets WHERE id = ?", (asset_id,))
        row = await cursor.fetchone()
        if not row:
            return None
        return Asset(
            id=row["id"],
            operation_id=row["operation_id"],
            host=row["host"],
            port=row["port"],
            service=row["service"],
            protocol=row["protocol"],
            status=row["status"],
            notes=row["notes"],
            first_seen=row["first_seen"],
            last_seen=row["last_seen"],
            metadata=json.loads(row["metadata"]) if row["metadata"] else {}
        )

    async def list_assets(self, operation_id: str) -> list[Asset]:
        assert self._conn is not None
        cursor = await self._conn.execute(
            "SELECT * FROM assets WHERE operation_id = ? ORDER BY last_seen DESC",
            (operation_id,)
        )
        rows = await cursor.fetchall()
        return [
            Asset(
                id=r["id"], operation_id=r["operation_id"], host=r["host"],
                port=r["port"], service=r["service"], protocol=r["protocol"],
                status=r["status"], notes=r["notes"],
                first_seen=r["first_seen"], last_seen=r["last_seen"],
                metadata=json.loads(r["metadata"]) if r["metadata"] else {}
            ) for r in rows
        ]

    async def log_credential(self, operation_id: str, username: str | None = None,
                             password: str | None = None, hash: str | None = None,
                             host: str | None = None, type: str | None = None,
                             source: str | None = None, metadata: dict | None = None) -> Credential:
        assert self._conn is not None
        cred_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc).isoformat()

        await self._conn.execute(
            """
            INSERT INTO credentials (id, operation_id, host, username, password, hash, type, source, first_seen, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (cred_id, operation_id, host, username, password, hash, type, source, now, json.dumps(metadata or {}))
        )
        await self._conn.commit()

        return Credential(
            id=cred_id, operation_id=operation_id, host=host,
            username=username, password=password, hash=hash,
            type=type, source=source, first_seen=now,
            metadata=metadata or {}
        )

    async def list_credentials(self, operation_id: str) -> list[Credential]:
        assert self._conn is not None
        cursor = await self._conn.execute(
            "SELECT * FROM credentials WHERE operation_id = ? ORDER BY first_seen DESC",
            (operation_id,)
        )
        rows = await cursor.fetchall()
        return [
            Credential(
                id=r["id"], operation_id=r["operation_id"], host=r["host"],
                username=r["username"], password=r["password"], hash=r["hash"],
                type=r["type"], source=r["source"], first_seen=r["first_seen"],
                metadata=json.loads(r["metadata"]) if r["metadata"] else {}
            ) for r in rows
        ]

    # ----------------------------------------------------------------------- #
    # Helpers
    # ----------------------------------------------------------------------- #

    def _row_to_operation(self, row: aiosqlite.Row) -> Operation:
        meta = json.loads(row["metadata"]) if row["metadata"] else {}
        return Operation(
            id=row["id"],
            name=row["name"],
            description=row["description"],
            scope=row["scope"],
            roe_notes=row["roe_notes"],
            status=row["status"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            metadata=meta,
        )


# Global singleton for the sidecar process
_db: Database | None = None


async def get_db() -> Database:
    global _db
    if _db is None:
        _db = Database()
        await _db.connect()
    return _db


async def close_db() -> None:
    global _db
    if _db:
        await _db.close()
        _db = None
