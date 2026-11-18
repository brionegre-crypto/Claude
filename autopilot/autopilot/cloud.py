"""Cloud publishing (Mac side): keep a PRIVATE GitHub repo stocked with ready Instagram posts so GitHub Actions can
publish them on time while this computer is asleep or off. The Mac still researches, writes (Claude) and renders.

Setup uses the GitHub CLI (`gh`, free): it creates the private repo, stores the encryption key as an Actions secret,
and pushes the workflow. A free cron-job.org job triggers the workflow on time (GitHub's own timer runs hours late).
Cost: $0. A private repo gets 2,000 free Actions minutes/month; a 30-minute trigger uses roughly 900–1,300.
"""
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
from datetime import timedelta
from pathlib import Path

from cryptography.fernet import Fernet

from autopilot import logs
from autopilot.db import DB, iso, utcnow
from autopilot.notify import notify

log = logs.get("cloud")
ENGINE_FILES = ["__init__.py", "logs.py", "cloud_runner.py", "publishing/__init__.py", "publishing/base.py",
                "publishing/instagram.py", "publishing/mediahost.py"]

WORKFLOW = """name: Publish
on:
  workflow_dispatch:          # triggered on time by cron-job.org
  schedule:
    - cron: "17 */6 * * *"     # slow fallback in case the trigger service is down
concurrency:
  group: publish
  cancel-in-progress: false
permissions:
  contents: write
jobs:
  publish:
    runs-on: ubuntu-latest
    timeout-minutes: 25
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 1 }
      - name: Anything due?
        id: due
        run: |
          if PYTHONPATH=engine python3 -m autopilot.cloud_runner --check; then echo "go=true" >> "$GITHUB_OUTPUT"; fi
      - name: Install (free, open source)
        if: steps.due.outputs.go == 'true'
        run: |
          pip install --quiet httpx==0.28.1 cryptography
          curl -fsSL -o cf.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
          sudo dpkg -i cf.deb >/dev/null
      - name: Publish due posts
        if: steps.due.outputs.go == 'true'
        env:
          CLOUD_KEY: ${{ secrets.CLOUD_KEY }}
        run: |
          git config user.name "autopilot-publisher"
          git config user.email "autopilot-publisher@users.noreply.github.com"
          PYTHONPATH=engine python3 -m autopilot.cloud_runner
"""

README = """# Publishing queue (private)
Managed automatically by Social Autopilot on your Mac. Do not edit by hand.
- `queue/`: posts waiting to publish · `results/`: what happened · `state/`: attempt journal
- To stop publishing from anywhere: Actions tab → Publish → ••• → Disable workflow.
"""

SECTION = """
[cloud]
enabled = false                      # set by `autopilot cloud setup`
repo = ""                            # owner/name of the PRIVATE publishing repo
branch = "main"
export_days = 10
"""


def enabled(s) -> bool:
    return bool(s.get("cloud.enabled")) and bool(s.get("cloud.repo"))


def active(s, db: DB) -> bool:
    from autopilot.publisher import is_live
    return enabled(s) and is_live(s, db)


def repo_dir(s) -> Path:
    return s.data_dir / "cloud-repo"


def _run(cmd, cwd=None, input_=None, check=True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, input=input_, capture_output=True, text=True, check=check)


def _git(s, *args, check=True):
    return _run(["git", *args], cwd=repo_dir(s), check=check)


def ensure_section(path: Path) -> None:
    txt = path.read_text()
    if "[cloud]" not in txt:
        path.write_text(txt.rstrip() + "\n" + SECTION)


def key(s) -> str:
    from autopilot.secrets import SecretStore
    st = SecretStore(s.data_dir)
    k = st.get("cloud_key")
    if not k:
        k = Fernet.generate_key().decode()
        st.set("cloud_key", k)
    return k


def write_engine(s) -> None:
    src = Path(__file__).parent
    dst = repo_dir(s) / "engine" / "autopilot"
    for f in ENGINE_FILES:
        (dst / f).parent.mkdir(parents=True, exist_ok=True)
        if not (dst / f).exists() or (dst / f).read_bytes() != (src / f).read_bytes():
            shutil.copy(src / f, dst / f)
    wf = repo_dir(s) / ".github" / "workflows" / "publish.yml"
    wf.parent.mkdir(parents=True, exist_ok=True)
    if not wf.exists() or wf.read_text() != WORKFLOW:
        wf.write_text(WORKFLOW)
    rd = repo_dir(s) / "README.md"
    if not rd.exists():
        rd.write_text(README)
    gi = repo_dir(s) / ".gitignore"
    if not gi.exists():
        gi.write_text("__pycache__/\n*.pyc\n")


def write_secrets(s) -> bool:
    """Encrypt the Instagram credentials for the cloud. Rewritten only when they change."""
    from autopilot.secrets import SecretStore
    sec = SecretStore(s.data_dir)
    creds = {"token": sec.get("instagram_access_token"), "user_id": sec.get("instagram_user_id"),
             "host": sec.get("instagram_api_host") or s.get("publishing.instagram_api_host")}
    if not creds["token"]:
        return False
    digest = hashlib.sha256(json.dumps(creds, sort_keys=True).encode()).hexdigest()
    marker = s.data_dir / ".cloud_secrets_digest"
    target = repo_dir(s) / "secrets.enc"
    if target.exists() and marker.exists() and marker.read_text() == digest:
        return False
    target.write_bytes(Fernet(key(s).encode()).encrypt(json.dumps(creds).encode()))
    marker.write_text(digest)
    return True


def export_posts(s, db: DB) -> dict:
    from autopilot.publisher import assets_for, caption_full, is_live
    root = repo_dir(s)
    live = is_live(s, db)
    horizon = utcnow() + timedelta(days=int(s.get("cloud.export_days", 10)))
    rows = db.q("SELECT * FROM content WHERE platform='instagram' AND status='ready' AND scheduled_at <= ? ORDER BY scheduled_at",
                (iso(horizon),)) if live else []
    wanted = set()
    exported = 0
    for r in rows:
        c = dict(r)
        if (root / "results" / f"{c['id']}.json").exists():
            continue
        wanted.add(c["id"])
        d = root / "queue" / c["id"]
        d.mkdir(parents=True, exist_ok=True)
        assets = []
        for a in assets_for(db, c["id"]):
            src = Path(a["path"])
            if not src.exists():
                continue
            name = f"{a['kind']}-{a['ordinal']:02d}{src.suffix}"
            if not (d / name).exists() or hashlib.sha256((d / name).read_bytes()).hexdigest() != a["sha256"]:
                shutil.copy(src, d / name)
            assets.append({"kind": a["kind"], "ordinal": a["ordinal"], "file": name, "sha256": a["sha256"]})
        post = {"id": c["id"], "format": c["format"], "scheduled_at": c["scheduled_at"],
                "caption_full": caption_full(c), "assets": assets,
                "thumb_offset_ms": (json.loads(c.get("body") or "{}") or {}).get("thumb_offset_ms", 0)}
        pj = d / "post.json"
        new = json.dumps(post, indent=1, sort_keys=True)
        if not pj.exists() or pj.read_text() != new:
            pj.write_text(new)
            exported += 1
        for f in d.iterdir():   # drop media that no longer belongs to the post (e.g. after Replace)
            if f.name != "post.json" and f.name not in {a["file"] for a in assets}:
                f.unlink()
    removed = 0
    for d in (root / "queue").glob("*") if (root / "queue").exists() else []:
        # cancelled, rescheduled beyond the horizon, edited into 'blocked', or not live anymore: withdraw it,
        # unless the cloud has already started publishing it (then let it finish or reconcile)
        if d.name not in wanted and not (root / "state" / f"{d.name}.json").exists():
            shutil.rmtree(d)
            removed += 1
    return {"exported_or_updated": exported, "queued": len(wanted), "withdrawn": removed}


def apply_results(s, db: DB) -> dict:
    from autopilot.publisher import mark_published
    out = {"published": 0, "failed": 0, "skipped": 0}
    for f in sorted((repo_dir(s) / "results").glob("*.json")) if (repo_dir(s) / "results").exists() else []:
        cid = f.stem
        r = json.loads(f.read_text())
        row = db.one("SELECT * FROM content WHERE id=?", (cid,))
        if not row or row["status"] in ("published", "failed_permanent", "skipped", "cancelled"):
            continue
        c = dict(row)
        if r["status"] == "published":
            aid = db.x("INSERT INTO publish_attempts(content_id,idempotency_key,attempt,state,request_summary,started_at) VALUES(?,?,?,?,?,?)",
                       (cid, f"{cid}:instagram", 1, "started", '{"cloud": true}', r.get("at") or iso()))
            mark_published(s, db, c, r["post_id"], r.get("permalink"), aid, state="reconciled" if r.get("reconciled") else "published")
            out["published"] += 1
        elif r["status"] == "failed":
            db.x("UPDATE content SET status='failed_permanent', block_reason=?, updated_at=? WHERE id=?", (r.get("error", "")[:500], iso(), cid))
            notify(s, db, "error", "auth" if r.get("auth") else "publish_failed", f"Cloud publishing failed: {c['format']}", r.get("error", ""))
            out["failed"] += 1
        elif r["status"] == "skipped":
            db.x("UPDATE content SET status='skipped', block_reason=?, updated_at=? WHERE id=?", (r.get("error", "")[:500], iso(), cid))
            notify(s, db, "warning", "skipped", f"Cloud skipped a late post: {c['format']}", r.get("error", ""))
            out["skipped"] += 1
    return out


def write_manifest(s, db: DB) -> None:
    from autopilot.publisher import is_live
    m = {"live": is_live(s, db), "paused": bool(db.kv_get("paused") or db.kv_get("emergency_stop")),
         "window_minutes": int(s.get("publishing.publish_window_minutes", 180)),
         "max_attempts": int(s.get("publishing.max_attempts", 5)),
         "api_version": s.get("publishing.instagram_api_version", "v23.0")}
    p = repo_dir(s) / "manifest.json"
    new = json.dumps(m, indent=1, sort_keys=True)
    if not p.exists() or json.loads(p.read_text()) != m:
        p.write_text(new)


def sync(s, db: DB) -> dict:
    if not enabled(s):
        return {"cloud": "disabled"}
    if not repo_dir(s).exists():
        raise RuntimeError("cloud repo not cloned; run: ./scripts/autopilot cloud setup")
    _git(s, "pull", "-q", "--rebase", "--autostash", check=False)
    res = {"results": apply_results(s, db)}
    write_engine(s)
    write_manifest(s, db)
    res["secrets_updated"] = write_secrets(s)
    res.update(export_posts(s, db))
    _git(s, "add", "-A")
    if _git(s, "diff", "--cached", "--quiet", check=False).returncode != 0:
        _git(s, "commit", "-q", "-m", f"sync from Mac: {res.get('queued', 0)} queued")
        pushed = False
        for _ in range(3):
            if _git(s, "push", "-q", check=False).returncode == 0:
                pushed = True
                break
            _git(s, "pull", "-q", "--rebase", check=False)
        if not pushed:
            raise RuntimeError("could not push to the publishing repo (check `gh auth status`)")
        res["pushed"] = True
    db.kv_set("cloud_last_sync", {"at": iso(), **res})
    return res


def status(s, db: DB) -> dict:
    root = repo_dir(s)
    q = [load_json(p) for p in sorted((root / "queue").glob("*/post.json"))] if (root / "queue").exists() else []
    return {"enabled": enabled(s), "repo": s.get("cloud.repo"), "queued": len(q),
            "next": min((p["scheduled_at"] for p in q if p), default=None), "last_sync": db.kv_get("cloud_last_sync")}


def load_json(p: Path):
    try:
        return json.loads(p.read_text())
    except Exception:
        return None


def trigger_instructions(s) -> str:
    repo = s.get("cloud.repo")
    branch = s.get("cloud.branch", "main")
    return f"""
=== cron-job.org (free) — makes posts go out on time ===
A. Create a GitHub key that can ONLY start this workflow:
   github.com → your photo → Settings → Developer settings → Personal access tokens → Fine-grained tokens →
   Generate new token. Name: autopilot-trigger · Expiration: 1 year · Repository access: Only select
   repositories → {repo} · Permissions → Repository permissions → Actions: Read and write. Generate, copy it.
B. cron-job.org → sign up (free) → Create cronjob:
   Title:     BTM publish
   URL:       https://api.github.com/repos/{repo}/actions/workflows/publish.yml/dispatches
   Schedule:  Custom → every 30 minutes, hours 8–23 (time zone: {s.get('general.timezone')})
   Advanced → Request method: POST
   Headers:   Accept: application/vnd.github+json
              Authorization: Bearer <paste the key from step A>
              X-GitHub-Api-Version: 2022-11-28
              Content-Type: application/json
   Request body: {{"ref":"{branch}"}}
   Save, then use "Test run": it should return status 204.
Posts then go out within 30 minutes after their slot time (e.g. a 12:15 Story at 12:30).
Free-minute budget: about 30 triggers/day ≈ 900–1,300 of the 2,000 free minutes per month.
"""


def setup(s, db: DB, repo_name: str, ask=input, say=print) -> bool:
    if not shutil.which("gh"):
        say("The GitHub CLI is needed (free):  brew install gh   then:  gh auth login")
        return False
    if _run(["gh", "auth", "status"], check=False).returncode != 0:
        say("Sign in to GitHub first:  gh auth login   (choose GitHub.com → HTTPS → Login with a web browser)")
        return False
    owner = _run(["gh", "api", "user", "--jq", ".login"]).stdout.strip()
    full = repo_name if "/" in repo_name else f"{owner}/{repo_name}"
    view = _run(["gh", "repo", "view", full, "--json", "visibility", "--jq", ".visibility"], check=False)
    if view.returncode != 0:
        say(f"Creating PRIVATE repo {full} …")
        _run(["gh", "repo", "create", full, "--private", "--description", "Social Autopilot publishing queue (private)"])
    elif view.stdout.strip().upper() != "PRIVATE":
        say(f"✗ {full} exists but is {view.stdout.strip()}. Use a private repo (posts would be visible before publishing).")
        return False
    d = repo_dir(s)
    if not d.exists():
        _run(["gh", "repo", "clone", full, str(d)])
    _run(["git", "checkout", "-q", "-B", s.get("cloud.branch", "main")], cwd=d, check=False)
    _run(["gh", "secret", "set", "CLOUD_KEY", "--repo", full], input_=key(s))   # key never printed or typed
    say("✓ encryption key stored as GitHub Actions secret CLOUD_KEY")
    from autopilot import config
    ensure_section(s.path)
    config.set_value(s.path, "cloud.repo", full)
    config.set_value(s.path, "cloud.enabled", "true")
    s.raw = config.load(s.path).raw
    write_engine(s)
    write_manifest(s, db)
    write_secrets(s)
    _git(s, "add", "-A")
    _git(s, "commit", "-q", "-m", "Set up publishing queue", check=False)
    _git(s, "push", "-q", "-u", "origin", s.get("cloud.branch", "main"))
    say(f"✓ private publishing repo ready: https://github.com/{full}")
    say(trigger_instructions(s))
    notify(s, db, "info", "cloud", "Cloud publishing set up", f"Queue repo: {full}", external=False)
    return True
