import sqlite3
import threading
import time
from pathlib import Path


class Store:
    """SQLite log + dedup. One row per comment we've seen."""

    def __init__(self, path: str):
        if path != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(path, check_same_thread=False)
        self._lock = threading.Lock()
        self._db.executescript(
            """
            CREATE TABLE IF NOT EXISTS interactions (
                platform TEXT NOT NULL,
                comment_id TEXT NOT NULL,
                author_id TEXT,
                text TEXT,
                reply TEXT,
                status TEXT NOT NULL,
                detail TEXT,
                created_at REAL NOT NULL,
                PRIMARY KEY (platform, comment_id)
            );
            CREATE TABLE IF NOT EXISTS authors (
                platform TEXT NOT NULL,
                author_id TEXT NOT NULL,
                PRIMARY KEY (platform, author_id)
            );
            """
        )

    def reset_pending(self) -> None:
        """A restart drops in-flight replies; free them so polling/redelivery retries."""
        with self._lock:
            self._db.execute("DELETE FROM interactions WHERE status = 'pending'")
            self._db.commit()

    def claim(self, platform: str, comment_id: str, author_id: str, text: str) -> bool:
        with self._lock:
            cur = self._db.execute(
                "INSERT OR IGNORE INTO interactions "
                "(platform, comment_id, author_id, text, status, created_at) "
                "VALUES (?, ?, ?, ?, 'pending', ?)",
                (platform, comment_id, author_id, text, time.time()),
            )
            self._db.commit()
            return cur.rowcount == 1

    def finish(self, platform: str, comment_id: str, status: str, reply: str = "", detail: str = "") -> None:
        with self._lock:
            self._db.execute(
                "UPDATE interactions SET status = ?, reply = ?, detail = ? "
                "WHERE platform = ? AND comment_id = ?",
                (status, reply, detail, platform, comment_id),
            )
            self._db.commit()

    def sent_today(self) -> int:
        since = time.time() - 24 * 3600
        with self._lock:
            row = self._db.execute(
                "SELECT COUNT(*) FROM interactions WHERE status = 'sent' AND created_at > ?",
                (since,),
            ).fetchone()
        return row[0]

    def first_time_author(self, platform: str, author_id: str) -> bool:
        """True exactly once per author."""
        with self._lock:
            cur = self._db.execute(
                "INSERT OR IGNORE INTO authors (platform, author_id) VALUES (?, ?)",
                (platform, author_id),
            )
            self._db.commit()
            return cur.rowcount == 1

    def recent(self, limit: int = 50) -> list[dict]:
        with self._lock:
            rows = self._db.execute(
                "SELECT platform, comment_id, author_id, text, reply, status, detail, created_at "
                "FROM interactions ORDER BY created_at DESC LIMIT ?",
                (limit,),
            ).fetchall()
        keys = ["platform", "comment_id", "author_id", "text", "reply", "status", "detail", "created_at"]
        return [dict(zip(keys, r)) for r in rows]
