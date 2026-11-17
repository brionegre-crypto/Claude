"""Backups: consistent SQLite snapshot (online backup API) + encrypted secrets + settings, zipped. Restore verifies
integrity before swapping files in, and keeps the replaced database as a safety copy."""
from __future__ import annotations

import shutil
import sqlite3
import zipfile
from datetime import datetime
from pathlib import Path

from autopilot.db import DB


def backup_dir(s) -> Path:
    d = s.data_dir / "backups"
    d.mkdir(exist_ok=True)
    return d


def create(s, db: DB, include_assets: bool = False) -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    tmp = backup_dir(s) / f".snap-{stamp}.db"
    dst = sqlite3.connect(tmp)
    db.conn.backup(dst)
    dst.close()
    out = backup_dir(s) / f"autopilot-{stamp}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(tmp, "autopilot.db")
        for extra, name in ((s.data_dir / "secrets.enc", "secrets.enc"), (s.path, "settings.toml")):
            if Path(extra).exists():
                z.write(extra, name)
        if include_assets:
            for f in s.assets_dir.rglob("*"):
                if f.is_file():
                    z.write(f, "assets/" + str(f.relative_to(s.assets_dir)))
    tmp.unlink()
    prune(s)
    return out


def prune(s) -> None:
    keep = int(s.get("backup.keep", 14))
    files = sorted(backup_dir(s).glob("autopilot-*.zip"))
    for f in files[:-keep] if len(files) > keep else []:
        f.unlink()


def restore(s, archive: Path) -> dict:
    lock = s.data_dir / "worker.lock"
    if lock.exists():
        try:
            import fcntl
            with open(lock, "a") as fh:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                fcntl.flock(fh, fcntl.LOCK_UN)
        except BlockingIOError:
            raise RuntimeError("Autopilot is running. Stop it first (scripts/stop.sh).")
        except ImportError:
            pass
    staging = s.data_dir / "restore-staging"
    shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir()
    with zipfile.ZipFile(archive) as z:
        z.extractall(staging)
    c = sqlite3.connect(staging / "autopilot.db")
    ok = c.execute("PRAGMA integrity_check").fetchone()[0]
    rows = c.execute("SELECT COUNT(*) FROM content").fetchone()[0]
    c.close()
    if ok != "ok":
        raise RuntimeError(f"backup database failed integrity check: {ok}")
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    if s.db_path.exists():
        shutil.copy(s.db_path, s.data_dir / f"pre-restore-{stamp}.db")
    for suffix in ("-wal", "-shm"):
        Path(str(s.db_path) + suffix).unlink(missing_ok=True)
    shutil.copy(staging / "autopilot.db", s.db_path)
    if (staging / "secrets.enc").exists():
        shutil.copy(staging / "secrets.enc", s.data_dir / "secrets.enc")
    if (staging / "assets").exists():
        shutil.copytree(staging / "assets", s.assets_dir, dirs_exist_ok=True)
    shutil.rmtree(staging)
    return {"restored_content_rows": rows, "safety_copy": f"pre-restore-{stamp}.db"}
