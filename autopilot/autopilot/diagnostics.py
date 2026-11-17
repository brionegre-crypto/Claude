"""System diagnostics used by `autopilot status`, the wizard and the dashboard."""
from __future__ import annotations

import os
import platform
import shutil
import sys
from datetime import timedelta

import httpx

from autopilot.db import DB, parse, utcnow


def run(s, db: DB, live_ai=False, network=True) -> list[dict]:
    out = []

    def add(name, ok, detail, warn=False):
        out.append({"name": name, "ok": bool(ok), "detail": detail, "warn": warn and not ok})

    add("os", True, f"{platform.system()} {platform.release()} · Python {sys.version.split()[0]}")
    add("python>=3.11", sys.version_info >= (3, 11), sys.version.split()[0])
    add("config", not s.errors, "; ".join(s.errors) or f"{s.path.name} valid")
    add("database", db.integrity_check() == "ok", f"integrity {db.integrity_check()} · {s.db_path}")
    free = shutil.disk_usage(s.data_dir).free / 1e9
    add("disk", free > 2, f"{free:.1f} GB free", warn=True)
    add("ffmpeg", shutil.which("ffmpeg"), shutil.which("ffmpeg") or "missing: needed for Reels")
    cf = shutil.which("cloudflared")
    need_cf = s.get("publishing.media_host") == "tunnel"
    add("cloudflared", cf or not need_cf, cf or "missing: needed to publish Instagram images (free)", warn=True)
    add("no ANTHROPIC_API_KEY", not os.environ.get("ANTHROPIC_API_KEY"), "set! `claude -p` would bill the API, not your subscription"
        if os.environ.get("ANTHROPIC_API_KEY") else "subscription auth will be used")
    from autopilot.ai.provider import ClaudeCLIProvider, get_provider
    prov = get_provider(s, db)
    if s.get("ai.provider") == "claude_cli":
        b = ClaudeCLIProvider(s, db).binary()
        add("claude CLI", b, b or "not found on PATH")
        if live_ai and b:
            ok, msg = ClaudeCLIProvider(s, db).check()
            add("claude headless call", ok, msg)
    st = prov.status()
    add("AI budget", st["calls_today"] < int(st["budget"]), f"{st['provider']}: {st['calls_today']}/{st['budget']} calls today", warn=True)
    hb = db.kv_get("heartbeat")
    alive = hb and utcnow() - parse(hb) < timedelta(minutes=3)
    add("worker heartbeat", alive, f"last {hb}" if hb else "worker has not run yet", warn=True)
    add("mode", True, f"{s.mode}; activated={bool(db.kv_get('activated'))}; paused={bool(db.kv_get('paused'))}; "
                      f"emergency_stop={bool(db.kv_get('emergency_stop'))}")
    if network:
        for host in ("https://graph.instagram.com", "https://news.google.com"):
            try:
                httpx.head(host, timeout=10)
                add(f"network {host}", True, "reachable")
            except Exception as e:
                add(f"network {host}", False, str(e)[:120], warn=True)
    from autopilot.secrets import SecretStore
    sec = SecretStore(s.data_dir)
    if sec.get("instagram_access_token") and network:
        from autopilot.publishing.instagram import InstagramPublisher
        ok, detail = InstagramPublisher(s, sec).check_auth()
        add("instagram auth", ok, detail)
    else:
        add("instagram auth", False, "not connected yet (wizard step 'accounts')", warn=True)
    from autopilot import scheduler
    h = scheduler.queue_health(s, db)
    add("queue", h["state"] == "healthy", f"{h['state']}: {h['days_fully_ready']} days ready, {h['ready_next_7d']}/{h['slots_next_7d']} slots ready in 7d", warn=True)
    return out
