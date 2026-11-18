"""Background worker: one loop, DB-driven, safe to kill at any moment (all state is in SQLite)."""
from __future__ import annotations

import json
import threading
import time
from datetime import datetime, timedelta

from autopilot import analytics, backup, generation, logs, publisher, research, scheduler
from autopilot.ai.provider import ProviderUnavailable, get_provider
from autopilot.db import DB, iso, parse, utcnow
from autopilot.notify import notify
from autopilot.secrets import SecretStore

log = logs.get("worker")

JOBS = {  # name: interval in minutes (None = handled by schedule logic)
    "publish": 1, "plan": 60, "generate": 30, "research": None, "analytics": None, "auth": 360,
    "backup": None, "integrity": 1440, "inbox": 15, "health": 60, "daily_summary": None, "reports": None, "optimize": 1440,
}


class Worker:
    def __init__(self, s, db: DB):
        self.s, self.db = s, db
        self.stop_event = threading.Event()
        self.provider = get_provider(s, db)
        self.recovered = False

    # --- helpers ------------------------------------------------------------------------------------------
    def last_run(self, job):
        r = self.db.one("SELECT started_at FROM job_runs WHERE job=? AND ok=1 ORDER BY id DESC LIMIT 1", (job,))
        return parse(r[0]) if r else None

    def due(self, job, minutes) -> bool:
        lr = self.last_run(job)
        return lr is None or utcnow() - lr >= timedelta(minutes=minutes)

    def run_job(self, job, fn):
        rid = self.db.x("INSERT INTO job_runs(job,started_at) VALUES(?,?)", (job, iso()))
        try:
            res = fn()
            self.db.x("UPDATE job_runs SET finished_at=?, ok=1, detail=? WHERE id=?", (iso(), json.dumps(res, default=str)[:4000], rid))
            return res
        except ProviderUnavailable as e:
            self.db.x("UPDATE job_runs SET finished_at=?, ok=1, detail=? WHERE id=?", (iso(), json.dumps({"ai_unavailable": str(e)}), rid))
            self._alert_once(f"ai:{str(e)[:40]}", "warning", "ai", "Claude Code is unavailable for now", f"{e}\nPublishing continues from the queue buffer.")
        except Exception as e:
            log.exception("job %s failed", job)
            self.db.x("UPDATE job_runs SET finished_at=?, ok=0, detail=? WHERE id=?", (iso(), str(e)[:2000], rid))
            self._alert_once(f"job:{job}:{str(e)[:60]}", "error", "system", f"Background job '{job}' failed", str(e)[:1000])

    def _alert_once(self, key, level, cat, title, body, hours=6):
        k = f"alerted:{key}"
        last = self.db.kv_get(k)
        if last and utcnow() - parse(last) < timedelta(hours=hours):
            return
        self.db.kv_set(k, iso())
        notify(self.s, self.db, level, cat, title, body)

    def local_now(self) -> datetime:
        return utcnow().astimezone(self.s.tz)

    def at_local_time(self, job, hhmm, weekday=None, monthday=None) -> bool:
        now = self.local_now()
        if weekday is not None and now.weekday() != weekday:
            return False
        if monthday is not None and now.day != monthday:
            return False
        h, m = map(int, hhmm.split(":"))
        if (now.hour, now.minute) < (h, m):
            return False
        lr = self.last_run(job)
        return lr is None or lr.astimezone(self.s.tz).date() < now.date()

    # --- jobs ---------------------------------------------------------------------------------------------
    def job_auth(self):
        secrets = SecretStore(self.s.data_dir)
        out = {}
        if secrets.get("instagram_access_token"):
            from autopilot.publishing.instagram import InstagramPublisher
            ig = InstagramPublisher(self.s, secrets)
            exp = secrets.get("instagram_token_expires_at")
            days = (parse(exp) - utcnow()).days if exp else None
            if days is not None and days < 15:
                try:
                    out["refreshed_until"] = ig.refresh_token()
                    days = 60
                except Exception as e:
                    out["refresh_error"] = str(e)
            ok, detail = ig.check_auth()
            out["instagram"] = detail
            self.db.kv_set("auth:instagram", {"ok": ok, "detail": detail, "checked": iso()})
            if not ok:
                self._alert_once("auth:ig", "error", "auth", "Instagram connection failed", detail + "\nRun: autopilot wizard --step accounts", 12)
            elif days is not None and days < 7:
                self._alert_once("auth:ig:exp", "warning", "auth", f"Instagram token expires in {days} days",
                                 "Automatic refresh failed. Reconnect with: autopilot wizard --step accounts", 24)
        if self.s.get("ai.provider") == "claude_cli":
            from autopilot.ai.provider import ClaudeCLIProvider
            out["claude_cli_found"] = bool(ClaudeCLIProvider(self.s, self.db).binary())
        return out

    def job_health(self):
        h = scheduler.queue_health(self.s, self.db)
        if h["state"] != "healthy" and not self.db.kv_get("paused"):
            self._alert_once("queue", "warning", "queue", f"Content queue is {h['state']}",
                             f"Only {h['days_fully_ready']} day(s) of Instagram posts are ready. Check AI availability/budget.", 24)
        return h

    def job_daily_summary(self):
        since = iso(utcnow() - timedelta(days=1))
        pub = self.db.q("SELECT platform, format, hook, permalink FROM content WHERE status='published' AND published_at >= ?", (since,))
        bad = self.db.q("SELECT platform, format, status, block_reason FROM content WHERE status IN ('failed_permanent','blocked','skipped') AND updated_at >= ?", (since,))
        manual = self.db.q("SELECT format, scheduled_at FROM content WHERE status='manual_due'")
        up = self.db.q("SELECT platform, format, scheduled_at FROM content WHERE status IN ('ready','manual_due','planned') AND scheduled_at BETWEEN ? AND ? ORDER BY scheduled_at",
                       (iso(), iso(utcnow() + timedelta(days=1))))
        h = scheduler.queue_health(self.s, self.db)
        lines = [f"Mode: {self.s.mode}{' (activated)' if self.db.kv_get('activated') else ''}", f"Published (24h): {len(pub)}"]
        lines += [f"  • {r['platform']} {r['format']}: {(r['hook'] or '')[:70]} {r['permalink'] or ''}" for r in pub]
        lines += [f"Problems (24h): {len(bad)}"] + [f"  • {r['platform']} {r['format']} {r['status']}: {(r['block_reason'] or '')[:100]}" for r in bad]
        lines += [f"YouTube posts waiting for you: {len(manual)}", f"Next 24h: {len(up)} posts",
                  f"Queue: {h['state']} ({h['days_fully_ready']} days ready)"]
        notify(self.s, self.db, "info", "report", "Daily summary", "\n".join(lines), external=True)
        return {"published": len(pub)}

    def job_youtube_pack(self):
        start = utcnow()
        rows = self.db.q("""SELECT format, scheduled_at FROM content WHERE platform='youtube' AND status IN ('ready','blocked','planned')
                            AND scheduled_at BETWEEN ? AND ? ORDER BY scheduled_at""", (iso(start), iso(start + timedelta(days=8))))
        if rows:
            lines = [f"• {parse(r['scheduled_at']).astimezone(self.s.tz):%a %I:%M %p} — {r['format'].replace('community_', '')}" for r in rows]
            notify(self.s, self.db, "info", "youtube_pack", f"Your YouTube posts for next week are ready ({len(rows)})",
                   "Load them into YouTube Studio's scheduler in one sitting:\n" + "\n".join(lines) +
                   "\nDashboard → YouTube → Copy / Download, then click 'Scheduled in Studio ✓'.", external=True)
        return {"posts": len(rows)}

    def tick(self):
        s, db = self.s, self.db
        db.kv_set("heartbeat", iso())
        from autopilot import cloud
        if cloud.enabled(s) and self.due("cloud_sync", 10):
            # runs even when paused / emergency-stopped, so the stop reaches the cloud publisher too
            self.run_job("cloud_sync", lambda: cloud.sync(s, db))
        if db.kv_get("emergency_stop"):
            return
        pubs = publisher.build_publishers(s, db)
        if not self.recovered:
            self.run_job("recover", lambda: publisher.recover(s, db, pubs))
            self.recovered = True
        paused = db.kv_get("paused", False)
        if not paused:
            self.run_job("publish", lambda: publisher.run_due(s, db, pubs)) if self._has_due() else None
        if self.due("plan", JOBS["plan"]):
            self.run_job("plan", lambda: scheduler.plan(s, db))
        if not paused and self.due("research", int(float(s.get("research.interval_hours", 12)) * 60)):
            self.run_job("research", lambda: {**research.run(s, db, self.provider),
                                              "trends": scheduler.apply_trends(s, db, lambda *a: notify(s, db, *a))})
        if not paused and s.get("ai.provider") == "inbox" and self.due("inbox", JOBS["inbox"]):
            self.run_job("inbox", lambda: generation.import_inbox(s, db))
        if not paused and self.due("generate", JOBS["generate"]):
            self.run_job("generate", lambda: generation.generate_due(s, db, self.provider))
        if self.due("analytics", int(float(s.get("analytics.interval_hours", 6)) * 60)):
            self.run_job("analytics", lambda: analytics.collect(s, db, pubs))
        if self.due("optimize", JOBS["optimize"]):
            self.run_job("optimize", lambda: analytics.optimize(s, db, self.provider if publisher.is_live(s, db) else None))
        if self.due("auth", JOBS["auth"]):
            self.run_job("auth", self.job_auth)
        if self.due("health", JOBS["health"]):
            self.run_job("health", self.job_health)
        if self.due("backup", int(float(s.get("backup.interval_hours", 24)) * 60)):
            self.run_job("backup", lambda: {"file": str(backup.create(s, db))})
        if self.due("integrity", JOBS["integrity"]):
            self.run_job("integrity", lambda: self._integrity())
        if self.at_local_time("daily_summary", s.get("notifications.daily_summary_time", "08:00")):
            self.run_job("daily_summary", self.job_daily_summary)
        if self.at_local_time("youtube_pack", s.get("notifications.youtube_pack_time", "17:00"), weekday=6):
            self.run_job("youtube_pack", self.job_youtube_pack)
        if self.at_local_time("weekly_report", "08:30", weekday=0):
            self.run_job("weekly_report", lambda: {"chars": len(analytics.report(s, db, "weekly"))})
        if self.at_local_time("monthly_report", "08:45", monthday=1):
            self.run_job("monthly_report", lambda: {"chars": len(analytics.report(s, db, "monthly"))})

    def _has_due(self):
        return bool(self.db.one("SELECT 1 FROM content WHERE (status='ready' AND scheduled_at<=?) OR status='failed' LIMIT 1", (iso(),)))

    def _integrity(self):
        r = self.db.integrity_check()
        if r != "ok":
            notify(self.s, self.db, "error", "system", "Database integrity check failed", f"{r}\nRestore the latest backup: scripts/restore.sh")
        return {"integrity": r}

    def run_forever(self, interval: int = 30):
        log.info("worker started (mode=%s, provider=%s)", self.s.mode, self.provider.name)
        while not self.stop_event.is_set():
            try:
                self.tick()
            except Exception:
                log.exception("tick failed")
            self.stop_event.wait(interval)
        log.info("worker stopped")


def acquire_lock(s):
    import fcntl
    fh = open(s.data_dir / "worker.lock", "a+")
    try:
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit("Another autopilot worker is already running (data/worker.lock).")
    fh.seek(0)
    fh.truncate()
    import os
    fh.write(str(os.getpid()))
    fh.flush()
    return fh
