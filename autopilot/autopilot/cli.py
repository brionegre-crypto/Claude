"""Command line interface: `python -m autopilot <command>` (or scripts/autopilot)."""
from __future__ import annotations

import argparse
import getpass
import json
import os
import shutil
import sys
import threading
from pathlib import Path

from autopilot import config, logs
from autopilot.config import PROJECT_ROOT


def ctx(strict=True):
    s = config.load(strict=strict)
    logs.setup(s.data_dir / "logs")
    from autopilot.db import DB
    return s, DB(s.db_path)


def cmd_init(a):
    target = Path(os.environ.get("AUTOPILOT_CONFIG") or PROJECT_ROOT / "config" / "settings.toml")
    if not target.exists():
        shutil.copy(PROJECT_ROOT / "config" / "settings.example.toml", target)
        print(f"created {target}")
    s, db = ctx()
    from autopilot import research, scheduler
    from autopilot.web.auth import ensure_token
    print("evergreen topics added:", research.seed_evergreen(s, db))
    print("plan:", scheduler.plan(s, db))
    print("dashboard login token stored in data/.dashboard_token (show it with: autopilot dashboard-token)")
    ensure_token(s)


def cmd_run(a):
    s, db = ctx()
    from autopilot.worker import Worker, acquire_lock
    lock = acquire_lock(s)  # noqa: F841 (held for process lifetime)
    w = Worker(s, db)
    t = threading.Thread(target=w.run_forever, kwargs={"interval": a.interval}, daemon=True)
    t.start()
    if a.no_dashboard:
        try:
            t.join()
        except KeyboardInterrupt:
            w.stop_event.set()
        return
    import uvicorn
    from autopilot.web.app import create_app
    try:
        uvicorn.run(create_app(s, db), host=s.get("dashboard.host", "127.0.0.1"), port=int(s.get("dashboard.port", 8765)), log_level="warning")
    finally:
        w.stop_event.set()


def cmd_dashboard(a):
    s, db = ctx()
    import uvicorn
    from autopilot.web.app import create_app
    uvicorn.run(create_app(s, db), host=s.get("dashboard.host", "127.0.0.1"), port=int(s.get("dashboard.port", 8765)), log_level="warning")


def _provider(s, db):
    from autopilot.ai.provider import get_provider
    return get_provider(s, db)


def cmd_research(a):
    s, db = ctx()
    from autopilot import research, scheduler
    res = research.run(s, db, _provider(s, db))
    res["trends"] = scheduler.apply_trends(s, db)
    print(json.dumps(res, indent=2))


def cmd_generate(a):
    s, db = ctx()
    from autopilot import generation
    print(json.dumps(generation.generate_due(s, db, _provider(s, db), limit=a.limit), indent=2))


def cmd_plan(a):
    s, db = ctx()
    from autopilot import scheduler
    print(json.dumps(scheduler.rebuild(s, db) if a.rebuild else scheduler.plan(s, db), indent=2))


def cmd_publish_due(a):
    s, db = ctx()
    from autopilot import publisher
    print(json.dumps(publisher.run_due(s, db), indent=2))


def cmd_analytics(a):
    s, db = ctx()
    from autopilot import analytics, publisher
    print(json.dumps(analytics.collect(s, db, publisher.build_publishers(s, db)), indent=2, default=str))
    print(json.dumps(analytics.optimize(s, db, _provider(s, db) if a.ai else None), indent=2, default=str))


def cmd_report(a):
    s, db = ctx()
    from autopilot import analytics
    print(analytics.report(s, db, a.kind))


def cmd_flag(a):
    s, db = ctx()
    from autopilot.notify import notify
    if a.cmd == "pause":
        db.kv_set("paused", True); notify(s, db, "warning", "control", "Automation paused", "via CLI")
    elif a.cmd == "resume":
        db.kv_set("paused", False); notify(s, db, "info", "control", "Automation resumed", "via CLI")
    elif a.cmd == "stop":
        db.kv_set("emergency_stop", True); notify(s, db, "error", "control", "EMERGENCY STOP engaged", "Nothing will publish until cleared.")
    elif a.cmd == "clear-stop":
        db.kv_set("emergency_stop", False); notify(s, db, "warning", "control", "Emergency stop cleared", "via CLI")
    print(a.cmd, "ok")


def cmd_backup(a):
    s, db = ctx()
    from autopilot import backup
    print(backup.create(s, db, include_assets=a.assets))


def cmd_restore(a):
    s = config.load()
    from autopilot import backup
    print(json.dumps(backup.restore(s, Path(a.file)), indent=2))


def cmd_secrets(a):
    s = config.load()
    from autopilot.secrets import SecretStore
    st = SecretStore(s.data_dir)
    if a.action == "list":
        print("\n".join(st.names()) or "(none)")
    elif a.action == "set":
        v = getpass.getpass(f"Value for {a.name} (input hidden): ").strip()
        if v:
            st.set(a.name, v); print("saved (encrypted)")
    elif a.action == "delete":
        st.delete(a.name); print("deleted")


def cmd_status(a):
    s, db = ctx(strict=False)
    from autopilot import diagnostics
    rep = diagnostics.run(s, db, live_ai=a.live_ai, network=not a.offline)
    for item in rep:
        print(f"[{'OK ' if item['ok'] else ('WARN' if item.get('warn') else 'FAIL')}] {item['name']}: {item['detail']}")
    sys.exit(0 if all(i["ok"] or i.get("warn") for i in rep) else 1)


def cmd_capabilities(a):
    s, db = ctx()
    from autopilot import publisher
    for p in publisher.build_publishers(s, db).values():
        for c in p.capabilities():
            print(f"{c.platform:10} {c.format:16} {'AUTONOMOUS' if c.autonomous else 'ASSISTED  '} {c.method} — {c.notes}")


def cmd_token(a):
    s = config.load()
    from autopilot.web.auth import ensure_token
    print(ensure_token(s, reset=a.reset))


def cmd_tunnel_test(a):
    s = config.load()
    from autopilot.publishing.mediahost import tunnel_test
    for line in tunnel_test(int(s.get("publishing.local_media_port", 8766))):
        print(line)


def cmd_cloud(a):
    s, db = ctx()
    from autopilot import cloud
    if a.action == "setup":
        name = a.repo or input("Name for the new PRIVATE publishing repo [btm-publisher]: ").strip() or "btm-publisher"
        cloud.setup(s, db, name)
    elif a.action == "sync":
        print(json.dumps(cloud.sync(s, db), indent=2))
    elif a.action == "status":
        print(json.dumps(cloud.status(s, db), indent=2, default=str))
    elif a.action == "trigger-info":
        print(cloud.trigger_instructions(s))
    elif a.action == "disable":
        from autopilot import config
        config.set_value(s.path, "cloud.enabled", "false")
        print("Cloud publishing disabled: this Mac publishes Instagram posts again. Queued cloud posts are withdrawn on the next sync")
        print("only if you re-enable; to be safe also disable the workflow on GitHub (Actions → Publish → Disable workflow).")


def cmd_refresh(a):
    s, db = ctx()
    from autopilot import generation
    prov = _provider(s, db)
    print(f"Refreshing scheduled posts ({'rewrite + re-render' if a.rewrite else 're-render only'}). "
          "Each rewrite is one Claude call (~30 s). You can keep using your Mac; Ctrl+C is safe.")
    res = generation.refresh_queue(s, db, prov, rewrite=a.rewrite, max_n=a.max)
    print(json.dumps({k: v for k, v in res.items() if k != "cloud"}, indent=2))


def cmd_wizard(a):
    from autopilot import wizard
    wizard.main(step=a.step)


def cmd_activate(a):
    from autopilot import wizard
    wizard.activate()


def main(argv=None):
    p = argparse.ArgumentParser(prog="autopilot", description="Social Autopilot")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("init").set_defaults(fn=cmd_init)
    r = sub.add_parser("run", help="worker + dashboard (use this for the background service)")
    r.add_argument("--interval", type=int, default=30); r.add_argument("--no-dashboard", action="store_true"); r.set_defaults(fn=cmd_run)
    sub.add_parser("dashboard").set_defaults(fn=cmd_dashboard)
    sub.add_parser("research").set_defaults(fn=cmd_research)
    g = sub.add_parser("generate"); g.add_argument("--limit", type=int, default=6); g.set_defaults(fn=cmd_generate)
    pl = sub.add_parser("plan"); pl.add_argument("--rebuild", action="store_true"); pl.set_defaults(fn=cmd_plan)
    sub.add_parser("publish-due").set_defaults(fn=cmd_publish_due)
    an = sub.add_parser("analytics"); an.add_argument("--ai", action="store_true"); an.set_defaults(fn=cmd_analytics)
    rp = sub.add_parser("report"); rp.add_argument("kind", choices=["weekly", "monthly"]); rp.set_defaults(fn=cmd_report)
    for f in ("pause", "resume", "stop", "clear-stop"):
        sub.add_parser(f).set_defaults(fn=cmd_flag)
    b = sub.add_parser("backup"); b.add_argument("--assets", action="store_true"); b.set_defaults(fn=cmd_backup)
    rs = sub.add_parser("restore"); rs.add_argument("file"); rs.set_defaults(fn=cmd_restore)
    se = sub.add_parser("secrets"); se.add_argument("action", choices=["list", "set", "delete"]); se.add_argument("name", nargs="?"); se.set_defaults(fn=cmd_secrets)
    st = sub.add_parser("status", aliases=["doctor"]); st.add_argument("--live-ai", action="store_true", help="make one tiny Claude call")
    st.add_argument("--offline", action="store_true"); st.set_defaults(fn=cmd_status)
    sub.add_parser("capabilities").set_defaults(fn=cmd_capabilities)
    t = sub.add_parser("dashboard-token"); t.add_argument("--reset", action="store_true"); t.set_defaults(fn=cmd_token)
    w = sub.add_parser("wizard"); w.add_argument("--step", default=None); w.set_defaults(fn=cmd_wizard)
    sub.add_parser("activate").set_defaults(fn=cmd_activate)
    rq = sub.add_parser("refresh-queue", help="redo already-scheduled posts with the current design/prompts")
    rq.add_argument("--rewrite", action="store_true", help="rewrite text with Claude too (not just re-render)")
    rq.add_argument("--max", type=int, default=None); rq.set_defaults(fn=cmd_refresh)
    cl = sub.add_parser("cloud", help="publish from a private GitHub repo so the Mac can sleep")
    cl.add_argument("action", choices=["setup", "sync", "status", "trigger-info", "disable"]); cl.add_argument("--repo")
    cl.set_defaults(fn=cmd_cloud)
    sub.add_parser("tunnel-test", help="diagnose the Instagram image hand-off (Cloudflare quick tunnel)").set_defaults(fn=cmd_tunnel_test)
    a = p.parse_args(argv)
    a.fn(a)
