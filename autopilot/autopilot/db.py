"""SQLite access, migrations, integrity checks. WAL mode for crash safety."""
from __future__ import annotations

import json
import sqlite3
import threading
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

MIGRATIONS = Path(__file__).parent / "migrations"
_lock = threading.RLock()


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(microsecond=0)


def iso(dt: datetime | None = None) -> str:
    return (dt or utcnow()).astimezone(timezone.utc).isoformat()


def parse(s: str | None) -> datetime | None:
    return datetime.fromisoformat(s) if s else None


class DB:
    def __init__(self, path: Path | str):
        self.path = str(path)
        self.conn = sqlite3.connect(self.path, check_same_thread=False, timeout=30, isolation_level=None)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA journal_mode=WAL")
        self.conn.execute("PRAGMA foreign_keys=ON")
        self.conn.execute("PRAGMA busy_timeout=30000")
        self.migrate()

    def migrate(self) -> list[str]:
        with _lock:
            self.conn.execute("CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at TEXT)")
            done = {r[0] for r in self.conn.execute("SELECT name FROM schema_migrations")}
            applied = []
            for f in sorted(MIGRATIONS.glob("*.sql")):
                if f.name in done:
                    continue
                self.conn.execute("BEGIN")
                try:
                    for stmt in f.read_text().split(";\n"):
                        if stmt.strip():
                            self.conn.execute(stmt)
                    self.conn.execute("INSERT INTO schema_migrations VALUES (?, ?)", (f.name, iso()))
                    self.conn.execute("COMMIT")
                except Exception:
                    self.conn.execute("ROLLBACK")
                    raise
                applied.append(f.name)
            return applied

    @contextmanager
    def tx(self):
        """Serialized write transaction (BEGIN IMMEDIATE)."""
        with _lock:
            self.conn.execute("BEGIN IMMEDIATE")
            try:
                yield self.conn
                self.conn.execute("COMMIT")
            except Exception:
                self.conn.execute("ROLLBACK")
                raise

    def q(self, sql: str, args=()) -> list[sqlite3.Row]:
        with _lock:
            return self.conn.execute(sql, args).fetchall()

    def one(self, sql: str, args=()):
        with _lock:
            return self.conn.execute(sql, args).fetchone()

    def x(self, sql: str, args=()) -> int:
        with _lock:
            cur = self.conn.execute(sql, args)
            return cur.lastrowid

    # key/value store for runtime flags (paused, emergency stop, activation)
    def kv_get(self, key: str, default=None):
        r = self.one("SELECT value FROM kv WHERE key=?", (key,))
        return json.loads(r[0]) if r else default

    def kv_set(self, key: str, value) -> None:
        self.x("INSERT INTO kv(key,value,updated_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at",
               (key, json.dumps(value), iso()))

    def integrity_check(self) -> str:
        return self.one("PRAGMA integrity_check")[0]

    def close(self):
        self.conn.close()
