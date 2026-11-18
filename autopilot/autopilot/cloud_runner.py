"""Cloud publisher: runs inside GitHub Actions in your PRIVATE publishing repo, so posts go out while your Mac sleeps.

Repo layout (written by the Mac, see cloud.py):
  manifest.json            {"live": bool, "paused": bool, "window_minutes": int, "max_attempts": int, "api_version": str}
  secrets.enc              Fernet-encrypted {"token","user_id","host"}; key = GitHub Actions secret CLOUD_KEY
  queue/<id>/post.json     {"id","format","scheduled_at","caption_full","assets":[{"kind","ordinal","file","sha256"}]}
  queue/<id>/<media files>
  state/<id>.json          attempt journal (written and pushed BEFORE each network step)
  results/<id>.json        {"status": published|failed|skipped, "post_id", "permalink", "error", "at"}

Never-double-post rules (same as the Mac engine): one result per id; the attempt journal is pushed before
media_publish; any previously started attempt is reconciled against Instagram before anything is retried.

`python -m autopilot.cloud_runner --check` uses only the standard library and exits 0 when something is due.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path


def now_utc() -> datetime:
    return datetime.now(timezone.utc).replace(microsecond=0)


def load(p: Path, default=None):
    try:
        return json.loads(p.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def save(p: Path, data) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, indent=1, sort_keys=True))


def due_posts(root: Path, now: datetime) -> list[dict]:
    m = load(root / "manifest.json", {})
    if not m.get("live") or m.get("paused"):
        return []
    out = []
    for pj in sorted((root / "queue").glob("*/post.json")):
        post = load(pj)
        if not post or (root / "results" / f"{post['id']}.json").exists():
            continue
        if datetime.fromisoformat(post["scheduled_at"]) > now:
            continue
        st = load(root / "state" / f"{post['id']}.json", {})
        if st.get("next_retry_at") and datetime.fromisoformat(st["next_retry_at"]) > now:
            continue
        out.append(post)
    return sorted(out, key=lambda p: p["scheduled_at"])


class _Cfg:
    def __init__(self, d):
        self.d = d

    def get(self, k, default=None):
        return self.d.get(k, default)


class _Secrets:
    def __init__(self, d):
        self.d = d

    def get(self, k, default=None):
        return self.d.get(k, default)

    def set(self, k, v):
        self.d[k] = v

    def delete(self, k):
        self.d.pop(k, None)


class Git:
    def __init__(self, root: Path, enabled: bool = True):
        self.root, self.enabled = root, enabled

    def _run(self, *args, check=True):
        return subprocess.run(["git", *args], cwd=self.root, capture_output=True, text=True, check=check)

    def commit_push(self, msg: str) -> None:
        if not self.enabled:
            return
        self._run("add", "-A")
        if self._run("diff", "--cached", "--quiet", check=False).returncode == 0:
            return
        self._run("commit", "-q", "-m", msg)
        for i in range(5):
            if self._run("push", "-q", check=False).returncode == 0:
                return
            self._run("pull", "-q", "--rebase", check=False)
        raise RuntimeError("could not push the publishing journal; stopping so nothing is published twice")


def run(root: Path, now: datetime | None = None, client=None, host_factory=None, git: Git | None = None,
        key: str | None = None) -> dict:
    from cryptography.fernet import Fernet

    from autopilot.publishing.base import AuthError, PermanentError, TemporaryError
    from autopilot.publishing.instagram import InstagramPublisher, scrub
    from autopilot.publishing.mediahost import TunnelHost

    now = now or now_utc()
    git = git or Git(root)
    m = load(root / "manifest.json", {})
    if not m.get("live") or m.get("paused"):
        return {"halted": "paused or not live"}
    creds = json.loads(Fernet((key or os.environ["CLOUD_KEY"]).encode()).decrypt((root / "secrets.enc").read_bytes()))
    sec = _Secrets({"instagram_access_token": creds["token"], "instagram_user_id": creds["user_id"],
                    "instagram_api_host": creds["host"]})
    cfg = _Cfg({"publishing.instagram_api_host": creds["host"], "publishing.instagram_api_version": m.get("api_version", "v23.0")})
    ig = InstagramPublisher(cfg, sec, client=client, media_host_factory=host_factory or (lambda: TunnelHost(8766)))
    window = timedelta(minutes=int(m.get("window_minutes", 180)))
    max_attempts = int(m.get("max_attempts", 5))
    report = {}

    def finish(post, status, **kw):
        save(root / "results" / f"{post['id']}.json", {"status": status, "at": now.isoformat(), **kw})
        shutil.rmtree(root / "queue" / post["id"], ignore_errors=True)   # media no longer needed
        git.commit_push(f"{status}: {post['format']} {post['id'][:8]}")
        report[post["id"]] = status

    for post in due_posts(root, now):
        pid = post["id"]
        st_path = root / "state" / f"{pid}.json"
        st = load(st_path, {})
        content = {"id": pid, "format": post["format"], "scheduled_at": post["scheduled_at"], "caption_full": post["caption_full"]}
        if st.get("started_at"):
            try:
                rec = ig.reconcile(content, st.get("container_id"))
            except Exception as e:
                report[pid] = f"reconcile failed, will retry: {scrub(str(e))}"
                continue
            if rec:
                finish(post, "published", post_id=rec.post_id, permalink=rec.permalink, reconciled=True)
                continue
        if not st.get("started_at") and now - datetime.fromisoformat(post["scheduled_at"]) > window:
            finish(post, "skipped", error=f"more than {window} late (cloud trigger missed?)")
            continue
        assets = []
        bad = None
        for a in post["assets"]:
            f = root / "queue" / pid / a["file"]
            if not f.exists() or hashlib.sha256(f.read_bytes()).hexdigest() != a["sha256"]:
                bad = f"media missing or changed: {a['file']}"
            assets.append({"kind": a["kind"], "ordinal": a.get("ordinal", 0), "path": str(f), "sha256": a["sha256"]})
        if bad:
            finish(post, "failed", error=bad)
            continue
        st.update({"attempts": st.get("attempts", 0) + 1, "started_at": now.isoformat(), "container_id": None})
        save(st_path, st)
        git.commit_push(f"attempt {st['attempts']}: {post['format']} {pid[:8]}")   # journal BEFORE publishing

        def on_container(cid, st=st, st_path=st_path, pid=pid):
            st["container_id"] = cid
            save(st_path, st)
            git.commit_push(f"container: {pid[:8]}")

        try:
            res = ig.publish(content, assets, on_container)
            finish(post, "published", post_id=res.post_id, permalink=res.permalink)
        except AuthError as e:
            finish(post, "failed", error="Instagram authentication: " + scrub(str(e)), auth=True)
        except PermanentError as e:
            finish(post, "failed", error=scrub(str(e)))
        except Exception as e:   # temporary (network, rate limit, unknown): reconcile next run, then retry with backoff
            msg = scrub(f"{e.__class__.__name__}: {e}")
            if st["attempts"] >= max_attempts:
                try:
                    rec = ig.reconcile(content, st.get("container_id"))
                except Exception:
                    rec = None
                if rec:
                    finish(post, "published", post_id=rec.post_id, permalink=rec.permalink, reconciled=True)
                else:
                    finish(post, "failed", error=f"after {st['attempts']} attempts: {msg}")
                continue
            wait = max(getattr(e, "retry_after", 0) or 0, int(60 * 2 ** (st["attempts"] - 1) * random.uniform(0.8, 1.2)))
            st.update({"next_retry_at": (now + timedelta(seconds=wait)).isoformat(), "last_error": msg})
            save(st_path, st)
            git.commit_push(f"retry later: {pid[:8]}")
            report[pid] = f"retry at {st['next_retry_at']}: {msg}"
    return report


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--check", action="store_true", help="exit 0 if a post is due (stdlib only)")
    a = ap.parse_args(argv)
    root = Path(a.root).resolve()
    if a.check:
        d = due_posts(root, now_utc())
        print(f"{len(d)} post(s) due")
        sys.exit(0 if d else 1)
    print(json.dumps(run(root), indent=1))


if __name__ == "__main__":
    main()
