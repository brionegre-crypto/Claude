"""Interactive setup wizard. Safe by default: nothing is published to a real account unless you type an explicit
confirmation for that specific test, and autonomous publishing starts only via `autopilot activate`.

Never asks for account passwords. Instagram uses an OAuth access token you generate in Meta's own dashboard
(entered hidden, stored encrypted)."""
from __future__ import annotations

import getpass
import json
import os
import platform
import secrets as pysecrets
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from autopilot import config
from autopilot.config import PROJECT_ROOT

STEPS = ["system", "project", "network", "ai", "accounts", "formats", "notifications", "dashboard", "service", "e2e"]


def say(msg=""):
    print(msg)


def ask(q, default="") -> str:
    v = input(f"{q}{f' [{default}]' if default else ''}: ").strip()
    return v or default


def yes(q, default=False) -> bool:
    v = input(f"{q} [{'Y/n' if default else 'y/N'}]: ").strip().lower()
    return default if not v else v.startswith("y")


def hidden(q) -> str:
    return getpass.getpass(f"{q} (input hidden): ").strip()


def run(cmd, check=False) -> subprocess.CompletedProcess:
    say(f"  $ {' '.join(cmd)}")
    return subprocess.run(cmd, check=check)


def ctx():
    from autopilot import logs
    from autopilot.db import DB
    s = config.load()
    logs.setup(s.data_dir / "logs")
    return s, DB(s.db_path)


def mark(db, step, ok=True, detail=""):
    st = db.kv_get("wizard_steps", {}) or {}
    st[step] = {"ok": ok, "at": datetime.now(timezone.utc).isoformat(), "detail": detail}
    db.kv_set("wizard_steps", st)


# ---------------------------------------------------------------------------------------------------------------
def step_system(s, db):
    say("== 1. System inspection ==")
    say(f"OS: {platform.system()} {platform.release()} ({platform.machine()}) · Python {sys.version.split()[0]}")
    if sys.version_info < (3, 11):
        say("Python 3.11+ is required."); return False
    mac = platform.system() == "Darwin"
    missing = [b for b in ("ffmpeg", "cloudflared") if not shutil.which(b)]
    for b in ("ffmpeg", "cloudflared", "claude", "git"):
        say(f"  {b:12} {shutil.which(b) or 'MISSING'}")
    if missing:
        say("\nAll of these are free and open source. ffmpeg renders Reels; cloudflared exposes an image to Instagram for the")
        say("few seconds it takes to fetch it (Instagram only accepts images from a public URL).")
        if mac and shutil.which("brew") and yes(f"Install {', '.join(missing)} with Homebrew now?", True):
            run(["brew", "install", *missing])
        elif not mac and shutil.which("apt-get") and "ffmpeg" in missing and yes("Install ffmpeg with apt (sudo)?", True):
            run(["sudo", "apt-get", "install", "-y", "ffmpeg"])
        if "cloudflared" in missing and not shutil.which("cloudflared") and not mac:
            say("Install cloudflared: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/")
        if mac and not shutil.which("brew"):
            say("Homebrew not found. Install it from https://brew.sh (free), then re-run: autopilot wizard --step system")
    if not shutil.which("claude"):
        say("Claude Code CLI not found. Install: https://code.claude.com/docs (then run `claude` once and /login).")
    ok = bool(shutil.which("ffmpeg"))
    mark(db, "system", ok)
    return ok


TZ_ALIASES = {
    "central": "America/Chicago", "ct": "America/Chicago", "cst": "America/Chicago", "cdt": "America/Chicago",
    "eastern": "America/New_York", "et": "America/New_York", "est": "America/New_York", "edt": "America/New_York",
    "mountain": "America/Denver", "mt": "America/Denver", "mst": "America/Denver", "mdt": "America/Denver",
    "arizona": "America/Phoenix", "pacific": "America/Los_Angeles", "pt": "America/Los_Angeles",
    "pst": "America/Los_Angeles", "pdt": "America/Los_Angeles", "alaska": "America/Anchorage", "hawaii": "Pacific/Honolulu",
}


def resolve_timezone(answer: str) -> str | None:
    from zoneinfo import ZoneInfo
    a = answer.strip()
    a = TZ_ALIASES.get(a.lower().replace(" time", "").replace(" ", ""), a)
    try:
        ZoneInfo(a)
        return a
    except Exception:
        return None


def ask_timezone(default: str) -> str:
    while True:
        tz = resolve_timezone(ask("Your posting time zone (press Enter to keep it, or type e.g. Central, Eastern, America/Chicago)", default))
        if tz:
            say(f"  using {tz}")
            return tz
        say("  I don't recognise that time zone. Try Central, Eastern, Mountain, Pacific, or a name like America/Chicago.")


def step_project(s, db):
    say("== 2. Project, database and storage ==")
    target = Path(os.environ.get("AUTOPILOT_CONFIG") or PROJECT_ROOT / "config" / "settings.toml")
    if not target.exists():
        shutil.copy(PROJECT_ROOT / "config" / "settings.example.toml", target)
        say(f"Created {target}")
    s = config.load()
    tz = ask_timezone(s.get("general.timezone", "America/Chicago"))
    config.set_value(target, "general.timezone", tz)
    say("(The first posting date is chosen later, at activation, once everything is set up.)")
    s = config.load()
    probe = s.data_dir / ".write-test"
    probe.write_text("ok"); probe.unlink()
    free = shutil.disk_usage(s.data_dir).free / 1e9
    say(f"Storage: {s.data_dir} writable, {free:.1f} GB free")
    from autopilot import research, scheduler
    from autopilot.db import DB
    db = DB(s.db_path)
    say(f"Database: {s.db_path} (integrity {db.integrity_check()})")
    say(f"Evergreen topics seeded: {research.seed_evergreen(s, db)} · plan: {scheduler.plan(s, db)}")
    mark(db, "project", True)
    return True


def step_network(s, db):
    say("== 3. Network ==")
    import httpx
    ok = True
    for u in ("https://graph.instagram.com", "https://news.google.com", "https://ntfy.sh", "https://www.googleapis.com"):
        try:
            httpx.head(u, timeout=10); say(f"  ✓ {u}")
        except Exception as e:
            ok = False; say(f"  ✗ {u}: {e}")
    mark(db, "network", ok)
    return ok


def step_ai(s, db):
    say("== 4. Claude Code (your subscription) ==")
    say("Content is written by the official Claude Code CLI in headless mode (`claude -p`), signed in with YOUR plan.")
    say("Facts you should know (from Anthropic's docs):")
    say("  • It draws from the same usage limits as claude.ai and interactive Claude Code (5-hour + weekly windows).")
    say("    The autopilot caps itself (ai.max_calls_per_day) and keeps a multi-day content buffer, so hitting a limit")
    say("    pauses writing, not publishing.")
    say("  • For unattended runs, `claude setup-token` creates a 1-year token meant for scripts; or rely on your /login.")
    say("  • If ANTHROPIC_API_KEY is set, `claude -p` bills the API instead. The autopilot refuses to run in that case.")
    if os.environ.get("ANTHROPIC_API_KEY"):
        say("\n!! ANTHROPIC_API_KEY is set in this shell. Remove it from your shell profile before continuing.")
    from autopilot.ai.provider import ClaudeCLIProvider
    from autopilot.secrets import SecretStore
    p = ClaudeCLIProvider(s, db)
    if not p.binary():
        say("claude CLI not found."); mark(db, "ai", False, "cli missing"); return False
    if yes("Store a `claude setup-token` token for the background service? (recommended; run `claude setup-token` in another terminal first)"):
        from autopilot.publishing.instagram import clean_token
        tok = clean_token(hidden("Paste the token"))
        if tok:
            SecretStore(s.data_dir).set("claude_code_oauth_token", tok); say("Saved (encrypted).")
    if yes("Make ONE tiny test call to Claude now to prove headless generation works? (uses a sliver of your usage)", True):
        ok, msg = p.check()
        say(("  ✓ " if ok else "  ✗ ") + msg)
        mark(db, "ai", ok, msg)
        return ok
    mark(db, "ai", False, "not tested")
    return False


IG_GUIDE = """
Instagram setup (free, done in YOUR browser; I never see your password):
 1. Instagram app → Settings → Account type and tools → Professional account → Business (needed for Stories).
 2. developers.facebook.com → My Apps → your app → Use cases → Instagram API → "API setup with Unified login"
    (Meta's name for it in newer apps; older apps say "API setup with Instagram login").
 3. App roles → Roles → add @{handle} as an Instagram Tester, and accept the invite in Instagram
    (Settings → Website permissions → Apps and websites → Tester invites).
 4. Back on the API setup page: "2. Generate access tokens" → Add account → log in as @{handle} → approve →
    Generate token → copy it.
 Either token type works: Instagram-login tokens (IGAA…) are renewed automatically every 60 days;
 Facebook/Unified-login system-user tokens (EAA…) never expire. Paste it below (hidden), never in a chat.
"""


def step_accounts(s, db):
    say("== 5. Accounts ==")
    from autopilot.publishing.instagram import InstagramPublisher
    from autopilot.secrets import SecretStore
    sec = SecretStore(s.data_dir)
    say(IG_GUIDE.format(handle=s.get("brand.handle_instagram")))
    if yes("Connect Instagram now?", True):
        from autopilot.publishing.instagram import clean_token, scrub
        tok = clean_token(hidden("Paste the Instagram access token"))
        if tok:
            say(f"  (received {len(tok)} characters, starting {tok[:3]}…)")
        if tok:
            from autopilot.publishing.instagram import detect_account
            choose = lambda found: found[int(ask(
                "Several Instagram accounts found: " + ", ".join(f"{i}=@{f.get('username')}" for i, f in enumerate(found)) + ". Which one?", "0"))]
            try:
                acct = detect_account(s, tok, choose=choose)
            except Exception as e:
                msg = scrub(str(e), tok)
                say(f"  ✗ couldn't find the Instagram account automatically: {msg}")
                say("    On Meta's API setup page, under '2. Generate access tokens', the connected account usually shows")
                say("    its Instagram account ID (a long number, often starting 178…).")
                manual = ask("Instagram account ID (leave empty to stop)").strip()
                acct = None
                if manual:
                    try:
                        acct = detect_account(s, tok, choose=choose, manual_id=manual)
                    except Exception as e2:
                        say(f"  ✗ {scrub(str(e2), tok)}")
                if not acct:
                    mark(db, "accounts", False, msg)
                    return False
            sec.set("instagram_access_token", tok)
            sec.set("instagram_api_host", acct["host"])
            sec.set("instagram_user_id", acct["user_id"])
            ig = InstagramPublisher(s, sec)
            kind = "Instagram login" if ig.flavor == "instagram" else "Facebook/Unified login"
            say(f"  ✓ connected @{acct['username']} ({acct['account_type']}) via {kind}")
            if acct["account_type"] not in ("BUSINESS", "MEDIA_CREATOR", "CREATOR") and ig.flavor == "instagram":
                say("  ! Not a professional account: publishing will fail until you switch.")
            if ig.flavor == "instagram":
                sec.delete("instagram_token_expires_at")
                try:
                    exp = ig.refresh_token(); say(f"  ✓ 60-day token, auto-renewed; currently valid until {exp[:10]}")
                except Exception:
                    if yes("Is this a SHORT-lived token (1 hour) that needs exchanging?", False):
                        app_secret = hidden("Instagram app secret (App dashboard → App settings → Basic → app secret)")
                        try:
                            d = ig.exchange_long_lived(tok, app_secret)
                            sec.set("instagram_access_token", d["access_token"])
                            sec.set("instagram_token_expires_at", (datetime.now(timezone.utc) + timedelta(seconds=int(d.get("expires_in", 5184000)))).isoformat())
                            say("  ✓ exchanged for a 60-day token")
                        except Exception as e:
                            say(f"  (exchange failed: {e})")
                    if not sec.get("instagram_token_expires_at"):
                        sec.set("instagram_token_expires_at", (datetime.now(timezone.utc) + timedelta(days=59)).isoformat())
            else:
                sec.delete("instagram_token_expires_at")
                exp = acct.get("expires_at")
                if exp:
                    left = datetime.fromtimestamp(exp, timezone.utc) - datetime.now(timezone.utc)
                    say(f"  ! This token expires in {left.days} days {left.seconds // 3600} hours.")
                    if left < timedelta(days=3) and yes("Exchange it for a 60-day token? (needs App ID + App secret from App settings → Basic)", True):
                        from autopilot.publishing.instagram import exchange_facebook_long_lived
                        try:
                            d = exchange_facebook_long_lived(s, tok, ask("App ID"), clean_token(hidden("App secret")))
                            tok = d["access_token"]
                            sec.set("instagram_access_token", tok)
                            exp = int(datetime.now(timezone.utc).timestamp()) + int(d.get("expires_in", 5184000))
                            say("  ✓ exchanged for a ~60-day token. You'll be alerted a week before it expires.")
                        except Exception as e:
                            say(f"  ✗ {scrub(str(e), tok)}")
                    sec.set("instagram_token_expires_at", datetime.fromtimestamp(exp, timezone.utc).isoformat())
                else:
                    say("  ✓ This token does not expire; the autopilot still checks it every 6 hours.")
                need = {"instagram_basic", "instagram_content_publish"}
                missing = sorted(need - set(acct.get("scopes") or need))
                if missing:
                    say(f"  ✗ Token is missing permission(s): {', '.join(missing)}. Add them in the app's Permissions list, then regenerate.")
                if acct.get("scopes") and "instagram_manage_insights" not in acct["scopes"]:
                    say("  ! No instagram_manage_insights permission: publishing works, but analytics will be empty.")
            # permission validation
            try:
                lim = ig._call("GET", f"{sec.get('instagram_user_id')}/content_publishing_limit", fields="quota_usage,config")
                say(f"  ✓ content publishing permission OK (quota: {json.dumps(lim.get('data', [{}])[0])})")
            except Exception as e:
                say(f"  ✗ content publishing permission missing: {e}")
            try:
                ig._call("GET", f"{sec.get('instagram_user_id')}/media", fields="id", limit=1)
                say("  ✓ media read OK (insights are checked on your first post)")
            except Exception as e:
                say(f"  ✗ media read failed: {e}")
    say("""
YouTube Community posts: there is NO official API to create them, and YouTube's Terms forbid automating the website.
The autopilot therefore writes and designs each Community post (text, image, poll, quiz) and, at the scheduled time,
alerts you and shows it on the dashboard with a Copy button and a link to YouTube Studio (one tap to post; Studio
can also schedule a week of posts at once). Optional and free: a YouTube Data API key lets the autopilot track your
subscriber count. Create one at https://console.cloud.google.com → APIs & Services → enable "YouTube Data API v3" →
Credentials → API key (restrict it to that API). No billing account is needed for this key.""")
    if yes("Add a YouTube Data API key + channel id for stats?"):
        k = hidden("YouTube API key")
        ch = ask("Your channel id (starts with UC…; YouTube Studio → Settings → Channel → Advanced)")
        if k and ch:
            sec.set("youtube_api_key", k); sec.set("youtube_channel_id", ch)
            from autopilot.publishing.youtube import YouTubeCommunityAssisted
            ok, msg = YouTubeCommunityAssisted(s, sec).check_auth(); say(("  ✓ " if ok else "  ✗ ") + msg)
    ok = bool(sec.get("instagram_access_token"))
    mark(db, "accounts", ok)
    return ok


def step_formats(s, db):
    say("== 6. Test each publishing format ==")
    from autopilot import generation, publisher
    from autopilot.ai.provider import MockProvider
    from autopilot.assets import render
    import uuid
    from autopilot.db import iso, utcnow
    say("Rendering one sample of every format (simulation)…")
    os.environ["AUTOPILOT_WIZARD"] = "1"
    sim_ok = True
    for plat, fmt in (("instagram", "image"), ("instagram", "carousel"), ("instagram", "reel"), ("instagram", "story"),
                      ("youtube", "community_text"), ("youtube", "community_image"), ("youtube", "community_poll"), ("youtube", "community_quiz")):
        cid = "wizard-" + uuid.uuid4().hex[:8]
        db.x("INSERT INTO content(id,platform,format,status,scheduled_at,slot_key,created_at,updated_at) VALUES(?,?,?,'planned',?,?,?,?)",
             (cid, plat, fmt, iso(utcnow() + timedelta(days=400)), f"wizard|{cid}", iso(), iso()))
        try:
            res = generation.generate_one(s, db, MockProvider(s, db), dict(db.one("SELECT * FROM content WHERE id=?", (cid,))))
            c = dict(db.one("SELECT * FROM content WHERE id=?", (cid,)))
            pub = publisher.build_publishers(s, db)[plat]
            if pub.autonomous(fmt) and res["status"] == "ready":
                from autopilot.publishing.simulated import SimulatedPublisher
                r = SimulatedPublisher(s, plat).publish({**c, "caption_full": publisher.caption_full(c)}, publisher.assets_for(db, cid), lambda x: None)
                say(f"  ✓ {plat:9} {fmt:16} rendered + simulated publish → {r.raw['outbox']}")
            else:
                say(f"  {'✓' if res['status']=='ready' else '✗'} {plat:9} {fmt:16} {res['status']} ({'assisted' if not pub.autonomous(fmt) else ''})")
            sim_ok &= res["status"] == "ready"
        finally:
            db.x("UPDATE content SET status='cancelled' WHERE id=?", (cid,))
    from autopilot.secrets import SecretStore
    sec = SecretStore(s.data_dir)
    real = db.kv_get("real_tests", {}) or {}
    if sec.get("instagram_access_token"):
        say("\nREAL tests publish to your actual Instagram account. Each one needs you to type the format name to confirm.")
        say("Suggested: start with 'story' (disappears after 24h). You can delete test feed posts in the app afterwards.")
        for fmt in ("story", "image", "carousel", "reel"):
            if not yes(f"Publish a REAL test {fmt} to @{s.get('brand.handle_instagram')} now?"):
                continue
            if ask(f"Type '{fmt}' to confirm") != fmt:
                say("  not confirmed, skipped"); continue
            res = real_test(s, db, fmt)
            real[fmt] = res
            say(("  ✓ " if res["ok"] else "  ✗ ") + res["detail"])
        db.kv_set("real_tests", real)
    mark(db, "formats", sim_ok, json.dumps(real))
    return sim_ok


def real_test(s, db, fmt) -> dict:
    """Publish one explicit, user-confirmed test post through the full live code path."""
    import uuid
    from autopilot import publisher
    from autopilot.assets import render
    from autopilot.db import iso, utcnow
    from autopilot.publishing.instagram import InstagramPublisher
    from autopilot.publishing.mediahost import get_host
    from autopilot.secrets import SecretStore
    db.x("UPDATE content SET status='cancelled' WHERE id LIKE 'realtest-%' AND status NOT IN ('published','cancelled')")
    cid = "realtest-" + uuid.uuid4().hex[:8]
    body = {"slides": [{"title": "System check", "text": "Testing the publishing pipeline. Break the cycle. Build the system."},
                       {"title": "Slide two", "text": "If you see this, carousels work."}],
            "script": [{"text": "System check.", "seconds": 3}, {"text": "Reels work.", "seconds": 3}],
            "frames": [{"text": "System check: Stories work."}]}
    if fmt == "image":
        body["slides"] = body["slides"][:1]
    cap = f"System check ({fmt}) · {datetime.now().strftime('%b %d %H:%M')}"
    db.x("""INSERT INTO content(id,platform,format,status,scheduled_at,slot_key,caption,hook,body,hashtags,created_at,updated_at,generated_by)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)""",
         (cid, "instagram", fmt, "ready", iso(), f"realtest|{cid}", cap, "System check", json.dumps(body), "[]", iso(), iso(), "wizard"))
    c = dict(db.one("SELECT * FROM content WHERE id=?", (cid,)))
    render.produce(s, db, c)
    ig = InstagramPublisher(s, SecretStore(s.data_dir), media_host_factory=lambda: get_host(s))
    try:
        r = publisher.publish_one(s, db, c, {"instagram": ig, "youtube": None})
    except Exception as e:
        return {"ok": False, "detail": str(e), "at": iso()}
    row = db.one("SELECT status, permalink, block_reason FROM content WHERE id=?", (cid,))
    ok = row["status"] == "published"
    if not ok:  # a failed test must not be retried later by the background worker
        db.x("UPDATE content SET status='cancelled' WHERE id=?", (cid,))
    return {"ok": ok, "detail": (row["permalink"] or "published") if ok else f"{r}: {row['block_reason']}", "at": iso()}


def step_notifications(s, db):
    say("== 7. Notifications ==")
    say("Free options: ntfy.sh push to your phone (install the free ntfy app), a Discord/Slack webhook, or email through")
    say("your own mailbox's SMTP (e.g. a Gmail *app password*, stored encrypted). The dashboard + log always work.")
    target = s.path
    if yes("Set up ntfy push notifications?", True):
        import re as _re
        default = "autopilot-" + pysecrets.token_urlsafe(12).replace("_", "").replace("-", "").lower()
        topic = ask("ntfy topic (press Enter to use this private random one)", default).strip()
        if not _re.fullmatch(r"[A-Za-z0-9_-]{12,64}", topic):
            say("  That doesn't look like a topic name (letters, numbers, - and _ only); using the random one instead.")
            topic = default
        config.set_value(target, "notifications.ntfy_topic", topic)
        say(f"  In the ntfy app, subscribe to topic: {topic}")
    if yes("Add a Discord/Slack webhook?"):
        config.set_value(target, "notifications.webhook_url", ask("Webhook URL"))
    if yes("Set up email?"):
        for k, q in (("notifications.email_to", "Send summaries to"), ("notifications.smtp_host", "SMTP host (smtp.gmail.com)"),
                     ("notifications.smtp_user", "SMTP username (your email)")):
            config.set_value(target, k, ask(q))
        from autopilot.secrets import SecretStore
        SecretStore(s.data_dir).set("smtp_password", hidden("SMTP app password (NOT your normal password)"))
    s = config.load()
    from autopilot.notify import send_external
    res = send_external(s, "Autopilot test notification", "If you can read this, notifications work.")
    say(f"  test: {res or 'no external channels configured (dashboard only)'}")
    mark(db, "notifications", all(v == "ok" for v in res.values()), json.dumps(res))
    return True


def step_dashboard(s, db):
    say("== 8. Dashboard ==")
    from autopilot.web.auth import ensure_token
    tok = ensure_token(s)
    say(f"URL:   http://127.0.0.1:{s.get('dashboard.port')}  (local only)")
    say(f"Token: {tok}   (show again: ./scripts/autopilot dashboard-token)")
    mark(db, "dashboard", True)
    return True


def service_files(s) -> dict:
    py = sys.executable
    root = str(PROJECT_ROOT)
    plist = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.socialautopilot</string>
  <key>ProgramArguments</key><array><string>{py}</string><string>-m</string><string>autopilot</string><string>run</string></array>
  <key>WorkingDirectory</key><string>{root}</string>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>{os.environ.get('PATH', '/usr/bin:/bin')}</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>StandardOutPath</key><string>{s.data_dir}/logs/service.out.log</string>
  <key>StandardErrorPath</key><string>{s.data_dir}/logs/service.err.log</string>
</dict></plist>
"""
    unit = f"""[Unit]
Description=Social Autopilot
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory={root}
ExecStart={py} -m autopilot run
Restart=on-failure
RestartSec=30
Environment=PATH={os.environ.get('PATH', '/usr/bin:/bin')}

[Install]
WantedBy=default.target
"""
    return {"plist": plist, "unit": unit}


def step_service(s, db):
    say("== 9. Background service ==")
    say("The autopilot runs on THIS computer. It publishes only while the computer is on, awake and online.")
    say("Missed slots beyond the publish window (default 3h) are skipped and reported, never dumped late.")
    f = service_files(s)
    if platform.system() == "Darwin":
        dst = Path.home() / "Library/LaunchAgents/com.socialautopilot.plist"
        if yes(f"Install launchd agent at {dst} (starts at login, restarts on crash)?", True):
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(f["plist"])
            run(["launchctl", "unload", str(dst)])
            run(["launchctl", "load", "-w", str(dst)])
            say("Tip: System Settings → Battery/Energy → prevent automatic sleeping when the display is off (or use `caffeinate`).")
            mark(db, "service", True, "launchd"); return True
    elif shutil.which("systemctl"):
        dst = Path.home() / ".config/systemd/user/socialautopilot.service"
        if yes(f"Install systemd user service at {dst}?", True):
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(f["unit"])
            run(["systemctl", "--user", "daemon-reload"])
            run(["systemctl", "--user", "enable", "--now", "socialautopilot.service"])
            say("For it to run while logged out: sudo loginctl enable-linger $USER")
            mark(db, "service", True, "systemd"); return True
    say("Manual start instead: ./scripts/start.sh  (stop: ./scripts/stop.sh)")
    mark(db, "service", False, "manual")
    return False


def step_e2e(s, db):
    say("== 10. End-to-end test (simulation, real Claude) ==")
    from autopilot import generation, publisher, research, scheduler
    from autopilot.ai.provider import get_provider
    from autopilot.db import iso, utcnow
    prov = get_provider(s, db)
    say(f"research: {json.dumps(research.run(s, db, prov))[:400]}")
    scheduler.plan(s, db)
    res = generation.generate_due(s, db, prov, limit=1)
    say(f"generate: {res}")
    row = db.one("SELECT * FROM content WHERE status='ready' ORDER BY scheduled_at LIMIT 1")
    ok = False
    if row:
        from autopilot.publishing.simulated import SimulatedPublisher
        c = dict(row)
        r = SimulatedPublisher(s, c["platform"]).publish({**c, "caption_full": publisher.caption_full(c)}, publisher.assets_for(db, c["id"]), lambda x: None)
        say(f"simulated publish of the next real post → {r.raw['outbox']}")
        say("\n" + publisher.caption_full(c)[:800])
        ok = res["ready"] >= 1 or bool(row)
    mark(db, "e2e", ok)
    return ok


def main(step: str | None = None):
    s, db = ctx()
    say("Social Autopilot setup wizard. Nothing is published to real accounts without your typed confirmation.\n")
    steps = [step] if step else STEPS
    for st in steps:
        if st not in STEPS:
            say(f"unknown step {st}; choose from {STEPS}"); return
        s, db = ctx() if st != "project" else (s, db)
        try:
            globals()[f"step_{st}"](config.load(), db)
        except KeyboardInterrupt:
            say("\ninterrupted"); return
        say("")
    done = db.kv_get("wizard_steps", {})
    say("Summary: " + ", ".join(f"{k}={'ok' if v['ok'] else 'todo'}" for k, v in done.items()))
    say("When everything you need is ok, run: ./scripts/autopilot activate")


def choose_start_date(s):
    """Asked at activation (not during setup): the first day real posts go out."""
    from datetime import date
    today = datetime.now(s.tz).date()
    default = today + timedelta(days=1)
    say("\nChoose the FIRST POSTING DATE. Tip: if other tools (e.g. Sprout) still have posts scheduled, pick a date")
    say("after they end so the two schedules don't overlap.")
    for _ in range(3):
        v = ask("First posting date (YYYY-MM-DD)", default.isoformat())
        try:
            d = date.fromisoformat(v)
        except ValueError:
            say("  please use YYYY-MM-DD"); continue
        if d < today:
            say("  that date is in the past"); continue
        return d
    return None


def activate():
    s, db = ctx()
    from autopilot import backup, diagnostics
    from autopilot.secrets import SecretStore
    steps = db.kv_get("wizard_steps", {}) or {}
    real = db.kv_get("real_tests", {}) or {}
    sec = SecretStore(s.data_dir)
    say("== Activation checklist ==")
    checks = [
        ("Instagram connected", bool(sec.get("instagram_access_token"))),
        ("Claude Code headless call verified", steps.get("ai", {}).get("ok", False)),
        ("At least one REAL Instagram test publish succeeded", any(v.get("ok") for v in real.values())),
        ("All formats render + simulate", steps.get("formats", {}).get("ok", False)),
        ("Background service installed", steps.get("service", {}).get("ok", False)),
        ("Notifications tested (or dashboard-only accepted)", "notifications" in steps),
        ("Database integrity ok", db.integrity_check() == "ok"),
    ]
    for name, ok in checks:
        say(f"  [{'x' if ok else ' '}] {name}")
    tested = [k for k, v in real.items() if v.get("ok")]
    untested = [f for f in ("image", "carousel", "reel", "story") if f not in tested]
    if untested:
        say(f"\nInstagram formats NOT yet proven with a real test: {', '.join(untested)}.")
        say("They will still publish autonomously after activation; failures are retried, reported and never duplicated.")
    hard_fail = [n for n, ok in checks[:3] if not ok]
    if hard_fail:
        say(f"\nCannot activate: {', '.join(hard_fail)}. Run ./scripts/autopilot wizard"); return
    from autopilot import scheduler
    start = choose_start_date(s)
    if not start:
        say("Not activated."); return
    first = scheduler.planned_slots(s, db, start, 7)
    first = [t for t in first if t["platform"] == "instagram"][:3]
    say(f"\nFirst posting date: {start:%A %B %d, %Y}. First Instagram posts:")
    for t in first:
        say(f"  • {t['utc'].astimezone(s.tz):%a %b %d %I:%M %p} {t['format']}")
    say("\nAfter activation the autopilot publishes to your real Instagram account on schedule WITHOUT per-post approval.")
    say("You can pause or emergency-stop at any time from the dashboard or with ./scripts/autopilot stop")
    if input("Type ACTIVATE to go live: ").strip() != "ACTIVATE":
        say("Not activated."); return
    print("backup:", backup.create(s, db))
    config.set_value(s.path, "calendar.start_date", start.isoformat())
    s = config.load(s.path)
    say(f"queue: {scheduler.go_live_reset(s, db, start)}")
    config.set_value(s.path, "general.mode", "live")
    db.kv_set("activated", True)
    db.kv_set("activated_at", datetime.now(timezone.utc).isoformat())
    db.kv_set("paused", False)
    from autopilot.notify import notify
    notify(config.load(), db, "success", "control", "Autopilot activated", "Autonomous publishing is now live.")
    say("✓ Live. Restart the service so it picks up live mode: ./scripts/restart.sh")
