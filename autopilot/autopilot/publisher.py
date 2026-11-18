"""Publish engine. Guarantees: at most one successful publication per content id, safe retries, crash recovery.

State machine (content.status): ready → publishing → published | failed (retry later) | failed_permanent | skipped
Every network step is journaled in publish_attempts BEFORE the next step, so a crash at any point is recoverable:
- crash before a container exists         → nothing was created; retry is safe
- crash after container, before publish   → reconcile() asks Instagram whether it was published; if not, retry
"""
from __future__ import annotations

import hashlib
import json
import random
from datetime import timedelta
from pathlib import Path

from autopilot import logs, quality
from autopilot.db import DB, iso, parse, utcnow
from autopilot.notify import notify
from autopilot.publishing.base import AuthError, PermanentError, RateLimited, TemporaryError
from autopilot.publishing.instagram import InstagramPublisher
from autopilot.publishing.mediahost import get_host
from autopilot.publishing.simulated import SimulatedPublisher
from autopilot.publishing.youtube import YouTubeCommunityAssisted
from autopilot.secrets import SecretStore

log = logs.get("publisher")


def is_live(s, db: DB) -> bool:
    return s.mode == "live" and bool(db.kv_get("activated", False))


def build_publishers(s, db: DB, secrets=None, ig_client=None, host_factory=None) -> dict:
    secrets = secrets or SecretStore(s.data_dir)
    ig = InstagramPublisher(s, secrets, client=ig_client, media_host_factory=host_factory or (lambda: get_host(s)))
    yt = YouTubeCommunityAssisted(s, secrets)
    if is_live(s, db):
        return {"instagram": ig, "youtube": yt}
    return {"instagram": SimulatedPublisher(s, "instagram", ig), "youtube": yt}


def caption_full(c: dict) -> str:
    tags = json.loads(c.get("hashtags") or "[]")
    cap = (c.get("caption") or "").strip()
    if c["platform"] == "instagram" and tags:
        cap += "\n\n" + " ".join(tags)
    return cap


def assets_for(db: DB, cid: str) -> list[dict]:
    return [dict(r) for r in db.q("SELECT * FROM assets WHERE content_id=? ORDER BY ordinal", (cid,))]


def _validate_media(assets: list[dict]) -> list[str]:
    errs = []
    for a in assets:
        p = Path(a["path"])
        if not p.exists():
            errs.append(f"missing file {p.name}")
        elif a.get("sha256") and hashlib.sha256(p.read_bytes()).hexdigest() != a["sha256"]:
            errs.append(f"file changed since validation: {p.name}")
    return errs


def _backoff(s, attempt: int, retry_after: int | None) -> int:
    base = int(s.get("publishing.backoff_base_seconds", 60))
    return max(retry_after or 0, int(base * (2 ** (attempt - 1)) * random.uniform(0.8, 1.2)))


def _attempt_no(db, cid) -> int:
    return db.one("SELECT COUNT(*) FROM publish_attempts WHERE content_id=?", (cid,))[0] + 1


def _already_published(db, cid):
    return db.one("SELECT platform_post_id FROM publish_attempts WHERE content_id=? AND state IN ('published','reconciled') LIMIT 1", (cid,))


def mark_published(s, db: DB, c: dict, post_id: str, permalink: str | None, attempt_id: int | None, state="published", simulated=False):
    with db.tx() as t:
        t.execute("UPDATE content SET status='published', published_at=?, platform_post_id=?, permalink=?, updated_at=? WHERE id=?",
                  (iso(), post_id, permalink, iso(), c["id"]))
        if attempt_id:
            t.execute("UPDATE publish_attempts SET state=?, platform_post_id=?, finished_at=? WHERE id=?", (state, post_id, iso(), attempt_id))
    notify(s, db, "success", "published", f"{'[SIMULATED] ' if simulated else ''}Published {c['platform']} {c['format']}",
           f"{(c.get('hook') or '')[:120]}\n{permalink or post_id}", external=not simulated)


def publish_one(s, db: DB, c: dict, pubs: dict) -> str:
    cid = c["id"]
    if db.kv_get("emergency_stop") or db.kv_get("paused"):
        return "halted"
    # lease: only one worker can move ready/failed → publishing
    with db.tx() as t:
        n = t.execute("UPDATE content SET status='publishing', updated_at=? WHERE id=? AND status IN ('ready','failed')", (iso(), cid)).rowcount
    if not n:
        return "not_claimed"
    prev = _already_published(db, cid)
    if prev:
        db.x("UPDATE content SET status='published', platform_post_id=? WHERE id=?", (prev[0], cid))
        return "already_published"
    pub = pubs[c["platform"]]
    simulated = isinstance(pub, SimulatedPublisher)
    if not pub.autonomous(c["format"]):
        db.x("UPDATE content SET status='manual_due', updated_at=? WHERE id=?", (iso(), cid))
        notify(s, db, "warning", "manual_due", f"Time to post on YouTube ({c['format'].replace('_', ' ')})",
               f"Open the dashboard → Overview → 'Ready for you to post'.\n\n{caption_full(c)[:800]}")
        return "manual_due"
    assets = assets_for(db, cid)
    media_errs = _validate_media(assets)
    rep = quality.check(s, db, {**c, "body": c["body"]}, assets=[{**a, "license": a["license"]} for a in assets])
    problems = media_errs + [b for b in rep["blocks"] if not b.startswith(("exact duplicate", "near-duplicate"))]
    if problems:
        db.x("UPDATE content SET status='blocked', block_reason=?, updated_at=? WHERE id=?", ("; ".join(problems), iso(), cid))
        notify(s, db, "error", "blocked", f"Blocked at publish time: {c['platform']} {c['format']}", "; ".join(problems))
        return "blocked"
    attempt = _attempt_no(db, cid)
    key = f"{cid}:{c['platform']}"
    aid = db.x("INSERT INTO publish_attempts(content_id,idempotency_key,attempt,state,request_summary,started_at) VALUES(?,?,?,?,?,?)",
               (cid, key, attempt, "started", json.dumps({"format": c["format"], "assets": len(assets), "simulated": simulated}), iso()))

    def on_container(container_id):
        db.x("UPDATE publish_attempts SET state='container_created', container_id=? WHERE id=?", (container_id, aid))

    payload = {**c, "caption_full": caption_full(c), "thumb_offset_ms": (json.loads(c.get("body") or "{}") or {}).get("thumb_offset_ms", 0)}
    try:
        if db.kv_get("emergency_stop"):
            raise TemporaryError("emergency stop engaged")
        res = pub.publish(payload, assets, on_container)
    except AuthError as e:
        _fail(s, db, c, aid, attempt, str(e), permanent=False, retry_after=3600)
        db.kv_set(f"auth_problem:{c['platform']}", str(e)[:300])
        notify(s, db, "error", "auth", f"{c['platform'].title()} authentication problem", f"{e}\nReconnect in the setup wizard: autopilot wizard --step accounts")
        return "auth_error"
    except (TemporaryError, RateLimited) as e:
        # we may not know whether publish happened (e.g. timeout after media_publish): reconcile first
        rec = None
        try:
            container = db.one("SELECT container_id FROM publish_attempts WHERE id=?", (aid,))[0]
            rec = pub.reconcile(payload, container) if container else None
        except Exception:
            pass
        if rec:
            mark_published(s, db, c, rec.post_id, rec.permalink, aid, state="reconciled", simulated=simulated)
            return "published"
        return _fail(s, db, c, aid, attempt, str(e), permanent=False, retry_after=getattr(e, "retry_after", None))
    except PermanentError as e:
        return _fail(s, db, c, aid, attempt, str(e), permanent=True)
    except Exception as e:  # unknown → treat as temporary but bounded by max_attempts
        log.exception("unexpected publish error")
        return _fail(s, db, c, aid, attempt, f"{e.__class__.__name__}: {e}", permanent=False)
    db.x("UPDATE publish_attempts SET response=? WHERE id=?", (json.dumps(res.raw)[:2000], aid))
    mark_published(s, db, c, res.post_id, res.permalink, aid, simulated=simulated)
    db.kv_set(f"auth_problem:{c['platform']}", None)
    return "published"


def _fail(s, db, c, aid, attempt, err, permanent, retry_after=None) -> str:
    maxa = int(s.get("publishing.max_attempts", 5))
    final = permanent or attempt >= maxa
    nxt = None if final else utcnow() + timedelta(seconds=_backoff(s, attempt, retry_after))
    with db.tx() as t:
        t.execute("UPDATE publish_attempts SET state=?, error=?, finished_at=?, next_retry_at=? WHERE id=?",
                  ("failed_permanent" if final else "failed_temporary", err[:1000], iso(), iso(nxt) if nxt else None, aid))
        t.execute("UPDATE content SET status=?, block_reason=?, updated_at=? WHERE id=?",
                  ("failed_permanent" if final else "failed", err[:500], iso(), c["id"]))
    if final:
        notify(s, db, "error", "publish_failed", f"Publishing failed: {c['platform']} {c['format']}", f"After {attempt} attempt(s): {err[:500]}")
        return "failed_permanent"
    log.warning("temporary publish failure for %s (attempt %s): %s; retry at %s", c["id"], attempt, err, nxt)
    return "retry_scheduled"


def recover(s, db: DB, pubs: dict) -> list[str]:
    """Run at startup: resolve rows left in 'publishing' by a crash/restart."""
    out = []
    for r in db.q("SELECT * FROM content WHERE status='publishing'"):
        c = dict(r)
        att = db.one("SELECT * FROM publish_attempts WHERE content_id=? ORDER BY id DESC LIMIT 1", (c["id"],))
        prev = _already_published(db, c["id"])
        if prev:
            db.x("UPDATE content SET status='published' WHERE id=?", (c["id"],))
            out.append(f"{c['id']}: already published")
            continue
        rec = None
        if att and att["state"] == "container_created":
            try:
                rec = pubs[c["platform"]].reconcile({**c, "caption_full": caption_full(c)}, att["container_id"])
            except Exception as e:
                # cannot tell: keep it out of the queue rather than risk a duplicate
                db.x("UPDATE content SET status='failed', block_reason=? WHERE id=?", (f"recovery check failed: {e}", c["id"]))
                db.x("UPDATE publish_attempts SET state='failed_temporary', error=?, next_retry_at=? WHERE id=?",
                     (f"recovery check failed: {e}", iso(utcnow() + timedelta(minutes=15)), att["id"]))
                out.append(f"{c['id']}: recovery check failed, retry in 15m")
                continue
        if rec:
            mark_published(s, db, c, rec.post_id, rec.permalink, att["id"], state="reconciled")
            out.append(f"{c['id']}: reconciled as published")
        else:
            db.x("UPDATE content SET status='ready' WHERE id=?", (c["id"],))
            if att:
                db.x("UPDATE publish_attempts SET state='failed_temporary', error='interrupted (restart)', finished_at=? WHERE id=? AND state IN ('started','container_created')",
                     (iso(), att["id"]))
            out.append(f"{c['id']}: returned to queue")
    return out


def run_due(s, db: DB, pubs: dict | None = None) -> dict:
    if db.kv_get("emergency_stop") or db.kv_get("paused"):
        return {"halted": True}
    pubs = pubs or build_publishers(s, db)
    now = utcnow()
    window = timedelta(minutes=int(s.get("publishing.publish_window_minutes", 180)))
    results = {}
    due = db.q("SELECT * FROM content WHERE status='ready' AND scheduled_at <= ? ORDER BY scheduled_at", (iso(now),))
    retry = db.q("""SELECT c.* FROM content c JOIN publish_attempts a ON a.content_id=c.id
                    WHERE c.status='failed' AND a.id=(SELECT MAX(id) FROM publish_attempts WHERE content_id=c.id)
                    AND a.next_retry_at <= ?""", (iso(now),))
    from autopilot import cloud
    cloud_on = cloud.active(s, db)
    for r in list(due) + list(retry):
        c = dict(r)
        if cloud_on and c["platform"] == "instagram":
            continue   # the private GitHub repo publishes these; results come back through cloud.sync()
        if c["status"] == "ready" and now - parse(c["scheduled_at"]) > window:
            db.x("UPDATE content SET status='skipped', block_reason=?, updated_at=? WHERE id=?",
                 (f"missed publish window ({window}); computer off or automation paused?", iso(), c["id"]))
            notify(s, db, "warning", "skipped", f"Skipped late post ({c['platform']} {c['format']})",
                   f"Scheduled {c['scheduled_at']} UTC; more than {window} late, so it was not published.")
            results[c["id"]] = "skipped"
            continue
        results[c["id"]] = publish_one(s, db, c, pubs)
    # YouTube posts you scheduled yourself in YouTube Studio count as published once their time passes
    db.x("""UPDATE content SET status='published', published_at=scheduled_at, platform_post_id=COALESCE(platform_post_id,'studio_scheduled'),
            updated_at=? WHERE status='scheduled_external' AND scheduled_at <= ?""", (iso(), iso(now)))
    # unfinished blocked/planned posts whose time has passed
    stale = db.q("SELECT id FROM content WHERE status IN ('planned','generating','draft','blocked') AND scheduled_at < ?", (iso(now - window),))
    for r in stale:
        db.x("UPDATE content SET status='skipped', block_reason=COALESCE(block_reason,'no publishable content by slot time'), updated_at=? WHERE id=?",
             (iso(), r[0]))
    return results
