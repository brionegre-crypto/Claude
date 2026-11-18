"""Local web dashboard (FastAPI + Jinja). Bound to 127.0.0.1 only."""
from __future__ import annotations

import calendar as pycal
import hmac
import json
import re
from datetime import date, datetime, timedelta
from pathlib import Path

from fastapi import Depends, FastAPI, Form, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, PlainTextResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from autopilot import analytics, backup, generation, publisher, research, scheduler
from autopilot.ai.provider import get_provider
from autopilot.db import DB, iso, parse, utcnow
from autopilot.notify import notify, send_external
from autopilot.secrets import SecretStore
from autopilot.web.auth import ensure_token, make_session, read_session

HERE = Path(__file__).parent
ALLOWED_HOSTS = {"127.0.0.1", "localhost", "[::1]"}
SECRET_NAMES = ["instagram_access_token", "instagram_user_id", "instagram_app_secret", "claude_code_oauth_token",
                "youtube_api_key", "smtp_password"]


def youtube_pack_text(c: dict) -> str:
    """Exactly what to paste into YouTube Studio for one Community post."""
    body = json.loads(c.get("body") or "{}")
    out = [(c.get("caption") or "").strip()]
    if body.get("poll"):
        out += ["", "POLL OPTIONS:"] + [f"  • {o}" for o in body["poll"].get("options", [])]
    if body.get("quiz"):
        q = body["quiz"]
        opts = q.get("options", [])
        out += ["", f"QUIZ: {q.get('question', '')}"] + [f"  {i + 1}. {o}" for i, o in enumerate(opts)]
        if isinstance(q.get("answer_index"), int) and 0 <= q["answer_index"] < len(opts):
            out += [f"  Correct answer: {opts[q['answer_index']]}", f"  Explanation: {q.get('explanation', '')}"]
    return "\n".join(out).strip()


def create_app(s, db: DB) -> FastAPI:
    async def csrf_guard(request: Request):
        if request.method == "POST" and request.url.path != "/login":
            form = await request.form()   # cached on this Request, so Form(...) params still work
            token = form.get("csrf") or request.headers.get("x-csrf")
            if not token or not request.state.csrf or not hmac.compare_digest(str(token), request.state.csrf):
                raise HTTPException(403, "CSRF check failed")

    app = FastAPI(title="Social Autopilot", docs_url=None, redoc_url=None, openapi_url=None, dependencies=[Depends(csrf_guard)])
    tpl = Jinja2Templates(directory=str(HERE / "templates"))
    tz = s.tz

    def local(v, fmt="%a %b %d · %I:%M %p"):
        if not v:
            return ""
        d = parse(v) if isinstance(v, str) else v
        return d.astimezone(tz).strftime(fmt).replace(" 0", " ")

    tpl.env.filters["local"] = local
    tpl.env.filters["fromjson"] = lambda v: json.loads(v) if v else None

    @app.middleware("http")
    async def guard(request: Request, call_next):
        host = (request.headers.get("host") or "").rsplit(":", 1)[0]
        if host not in ALLOWED_HOSTS:
            return PlainTextResponse("forbidden host", status_code=403)  # DNS-rebinding protection
        request.state.csrf = read_session(s, request.cookies.get("ap_session"))
        if request.url.path not in ("/login", "/static/style.css") and not request.state.csrf:
            return RedirectResponse("/login", status_code=303)
        resp = await call_next(request)
        resp.headers["X-Frame-Options"] = "DENY"
        resp.headers["Content-Security-Policy"] = "default-src 'self'; img-src 'self' data:; media-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'"
        resp.headers["Referrer-Policy"] = "no-referrer"
        return resp

    def render(request, name, **kw):
        unread = db.one("SELECT COUNT(*) FROM notifications WHERE read=0 AND level IN ('warning','error')")[0]
        return tpl.TemplateResponse(request, name, {"s": s, "csrf": request.state.csrf, "unread": unread,
                                                    "mode": s.mode, "activated": db.kv_get("activated", False),
                                                    "paused": db.kv_get("paused", False), "estop": db.kv_get("emergency_stop", False), **kw})

    # ---- auth -------------------------------------------------------------------------------------------
    @app.get("/login", response_class=HTMLResponse)
    def login_page(request: Request):
        return tpl.TemplateResponse(request, "login.html", {"error": None})

    @app.post("/login")
    def login(request: Request, token: str = Form(...)):
        if not hmac.compare_digest(token.strip(), ensure_token(s)):
            return tpl.TemplateResponse(request, "login.html", {"error": "Wrong token"}, status_code=401)
        r = RedirectResponse("/", status_code=303)
        r.set_cookie("ap_session", make_session(s), httponly=True, samesite="strict", max_age=7 * 86400)
        return r

    @app.post("/logout")
    def logout():
        r = RedirectResponse("/login", status_code=303)
        r.delete_cookie("ap_session")
        return r

    @app.get("/static/style.css")
    def css():
        return FileResponse(HERE / "static" / "style.css", media_type="text/css")

    # ---- overview ---------------------------------------------------------------------------------------
    @app.get("/", response_class=HTMLResponse)
    def overview(request: Request):
        now = iso()
        upcoming = db.q("SELECT * FROM content WHERE scheduled_at > ? AND status NOT IN ('cancelled','skipped') ORDER BY scheduled_at LIMIT 12", (now,))
        recent = db.q("SELECT * FROM content WHERE status='published' ORDER BY published_at DESC LIMIT 8")
        failed = db.q("SELECT * FROM content WHERE status IN ('failed','failed_permanent','blocked') ORDER BY updated_at DESC LIMIT 10")
        manual = db.q("SELECT * FROM content WHERE status='manual_due' ORDER BY scheduled_at")
        jobs = {r["job"]: dict(r) for r in db.q("SELECT job, MAX(started_at) started_at, ok, detail FROM job_runs GROUP BY job")}
        secrets = SecretStore(s.data_dir)
        accounts = {
            "instagram": {"connected": bool(secrets.get("instagram_access_token")), "auth": db.kv_get("auth:instagram"),
                          "problem": db.kv_get("auth_problem:instagram")},
            "youtube": {"connected": bool(secrets.get("youtube_api_key")), "note": "Community posts: assisted (no API)"},
        }
        from autopilot import cloud
        accounts["cloud"] = cloud.status(s, db) if cloud.enabled(s) else None
        return render(request, "overview.html", upcoming=upcoming, recent=recent, failed=failed, manual=manual,
                      health=scheduler.queue_health(s, db), heartbeat=db.kv_get("heartbeat"), jobs=jobs, accounts=accounts,
                      ai=get_provider(s, db).status())

    # ---- calendar ---------------------------------------------------------------------------------------
    @app.get("/calendar", response_class=HTMLResponse)
    def cal(request: Request, month: str | None = None, platform: str = "", fmt: str = ""):
        today = utcnow().astimezone(tz).date()
        y, m = (map(int, month.split("-")) if month else (today.year, today.month))
        first = date(y, m, 1)
        weeks = pycal.Calendar(firstweekday=0).monthdatescalendar(y, m)
        start, end = weeks[0][0], weeks[-1][-1] + timedelta(days=1)
        q = "SELECT * FROM content WHERE scheduled_at >= ? AND scheduled_at < ? AND status!='cancelled'"
        args = [iso(datetime.combine(start, datetime.min.time(), tz)), iso(datetime.combine(end, datetime.min.time(), tz))]
        if platform:
            q += " AND platform=?"; args.append(platform)
        if fmt:
            q += " AND format=?"; args.append(fmt)
        by_day: dict = {}
        for r in db.q(q + " ORDER BY scheduled_at", args):
            by_day.setdefault(parse(r["scheduled_at"]).astimezone(tz).date(), []).append(r)
        prev_m = (first - timedelta(days=1)).strftime("%Y-%m")
        next_m = (first + timedelta(days=32)).replace(day=1).strftime("%Y-%m")
        return render(request, "calendar.html", weeks=weeks, by_day=by_day, first=first, today=today, prev_m=prev_m,
                      next_m=next_m, platform=platform, fmt=fmt)

    # ---- library / content ------------------------------------------------------------------------------
    @app.get("/library", response_class=HTMLResponse)
    def library(request: Request, status: str = "", platform: str = "", q: str = ""):
        sql, args = "SELECT * FROM content WHERE status!='planned'", []
        if status:
            sql += " AND status=?"; args.append(status)
        if platform:
            sql += " AND platform=?"; args.append(platform)
        if q:
            sql += " AND (hook LIKE ? OR caption LIKE ? OR topic LIKE ?)"; args += [f"%{q}%"] * 3
        rows = db.q(sql + " ORDER BY scheduled_at DESC LIMIT 200", args)
        return render(request, "library.html", rows=rows, status=status, platform=platform, q=q)

    def get_content(cid):
        r = db.one("SELECT * FROM content WHERE id=?", (cid,))
        if not r:
            raise HTTPException(404)
        return r

    @app.get("/content/{cid}", response_class=HTMLResponse)
    def content_detail(request: Request, cid: str):
        c = get_content(cid)
        assets = db.q("SELECT * FROM assets WHERE content_id=? ORDER BY ordinal", (cid,))
        attempts = db.q("SELECT * FROM publish_attempts WHERE content_id=? ORDER BY id", (cid,))
        metrics = db.q("SELECT metric, value, collected_at FROM metrics WHERE id IN (SELECT MAX(id) FROM metrics WHERE content_id=? GROUP BY metric)", (cid,))
        return render(request, "content.html", c=c, assets=assets, attempts=attempts, metrics=metrics,
                      caption_full=publisher.caption_full(dict(c)),
                      local_input=parse(c["scheduled_at"]).astimezone(tz).strftime("%Y-%m-%dT%H:%M") if c["scheduled_at"] else "")

    @app.get("/asset/{aid}")
    def asset(aid: int):
        a = db.one("SELECT path FROM assets WHERE id=?", (aid,))
        if not a:
            raise HTTPException(404)
        p = Path(a[0]).resolve()
        if not str(p).startswith(str(s.assets_dir.resolve())) or not p.exists():
            raise HTTPException(404)
        return FileResponse(p)

    @app.post("/content/{cid}/edit")
    def edit(request: Request, cid: str, hook: str = Form(""), caption: str = Form(""), hashtags: str = Form("")):
        c = dict(get_content(cid))
        if c["status"] in ("published", "publishing"):
            raise HTTPException(409, "already published")
        tags = [t if t.startswith("#") else "#" + t for t in hashtags.replace(",", " ").split() if t]
        from autopilot import quality
        rec = {**c, "hook": hook, "caption": caption, "hashtags": tags}
        rep = quality.check(s, db, rec, assets=[dict(a) for a in db.q("SELECT * FROM assets WHERE content_id=?", (cid,))])
        st = "ready" if rep["ok"] else "blocked"
        db.x("UPDATE content SET hook=?, caption=?, hashtags=?, quality_report=?, block_reason=?, fingerprint=?, status=?, updated_at=? WHERE id=?",
             (hook, caption, json.dumps(rep["hashtags"]), json.dumps(rep), "; ".join(rep["blocks"]) or None, rep["fingerprint"], st, iso(), cid))
        return RedirectResponse(f"/content/{cid}", status_code=303)

    @app.post("/content/{cid}/reschedule")
    def resched(cid: str, when: str = Form(...)):
        dt = datetime.strptime(when, "%Y-%m-%dT%H:%M").replace(tzinfo=tz)
        if dt <= utcnow():
            raise HTTPException(400, "time must be in the future")
        scheduler.reschedule(db, cid, dt)
        return RedirectResponse(f"/content/{cid}", status_code=303)

    @app.post("/content/{cid}/delete")
    def delete(cid: str):
        db.x("UPDATE content SET status='cancelled', updated_at=? WHERE id=? AND status NOT IN ('published','publishing')", (iso(), cid))
        return RedirectResponse("/library", status_code=303)

    @app.post("/content/{cid}/replace")
    def replace(cid: str):
        """Discard the current draft and regenerate this slot with a fresh topic."""
        db.x("UPDATE content SET status='planned', research_ids=NULL, block_reason=NULL, updated_at=? WHERE id=? AND status NOT IN ('published','publishing')", (iso(), cid))
        try:
            generation.generate_one(s, db, get_provider(s, db), dict(get_content(cid)))
        except Exception as e:
            notify(s, db, "warning", "generation", "Regeneration deferred", str(e), external=False)
        return RedirectResponse(f"/content/{cid}", status_code=303)

    @app.post("/content/{cid}/approve-block")
    def approve_block(cid: str):
        """Human override for a blocked post (only after you have reviewed it)."""
        db.x("UPDATE content SET status='ready', block_reason=NULL, updated_at=? WHERE id=? AND status='blocked'", (iso(), cid))
        notify(s, db, "info", "control", "Blocked post released by you", cid, external=False)
        return RedirectResponse(f"/content/{cid}", status_code=303)

    @app.post("/content/{cid}/mark-posted")
    def mark_posted(cid: str, url: str = Form("")):
        c = dict(get_content(cid))
        if c["status"] in ("manual_due", "ready"):
            aid = db.x("INSERT INTO publish_attempts(content_id,idempotency_key,attempt,state,request_summary,started_at) VALUES(?,?,?,?,?,?)",
                       (cid, f"{cid}:{c['platform']}", 1, "started", '{"manual": true}', iso()))
            publisher.mark_published(s, db, c, url or f"manual_{cid[:8]}", url or None, aid, simulated=False)
        return RedirectResponse("/", status_code=303)

    # ---- competitive research ---------------------------------------------------------------------------
    @app.get("/competitors", response_class=HTMLResponse)
    def competitors_page(request: Request):
        from autopilot import competitive
        comp = competitive.comparison(s, db)
        rows = [r for r in [comp["you"]] + comp["competitors"] if r]
        return render(request, "competitors.html", comp=comp, rows=rows, handles=competitive.handles(db),
                      last_run=db.one("SELECT started_at, ok, detail FROM job_runs WHERE job='competitive' ORDER BY id DESC LIMIT 1"))

    @app.post("/competitors/add")
    def competitors_add(handle: str = Form(...)):
        from autopilot import competitive
        for h in re.split(r"[\s,]+", handle):
            if h:
                competitive.add(db, h)
        return RedirectResponse("/competitors", status_code=303)

    @app.post("/competitors/remove")
    def competitors_remove(handle: str = Form(...)):
        from autopilot import competitive
        competitive.remove(db, handle)
        return RedirectResponse("/competitors", status_code=303)

    @app.post("/competitors/run")
    def competitors_run():
        from autopilot import competitive
        from autopilot.publishing.instagram import InstagramPublisher
        res = competitive.collect(s, db, competitive.research_client(s, SecretStore(s.data_dir)))
        msg = f"Collected: {', '.join(res['collected']) or 'none'}" + (f" · errors: {json.dumps(res['errors'])[:800]}" if res["errors"] else "")
        try:
            if competitive.handles(db):
                competitive.ai_insights(s, db, get_provider(s, db))
        except Exception as e:
            msg += f" · insights skipped: {e}"
        notify(s, db, "info", "competitive", "Competitive research updated", msg, external=False)
        return RedirectResponse("/competitors", status_code=303)

    # ---- YouTube weekly pack ----------------------------------------------------------------------------
    def yt_week(offset: int):
        today = utcnow().astimezone(tz).date()
        monday = today - timedelta(days=today.weekday()) + timedelta(weeks=offset)
        start = datetime.combine(monday, datetime.min.time(), tz)
        end = start + timedelta(days=7)
        rows = db.q("""SELECT * FROM content WHERE platform='youtube' AND scheduled_at >= ? AND scheduled_at < ?
                       AND status NOT IN ('cancelled','skipped') ORDER BY scheduled_at""", (iso(start), iso(end)))
        posts = []
        for r in rows:
            c = dict(r)
            c["assets"] = [dict(a) for a in db.q("SELECT id, kind, path FROM assets WHERE content_id=? ORDER BY ordinal", (c["id"],))]
            c["pack_text"] = youtube_pack_text(c)
            posts.append(c)
        return monday, posts

    @app.get("/youtube", response_class=HTMLResponse)
    def youtube_pack(request: Request, week: int | None = None):
        if week is None:   # on Sundays show the coming week; otherwise this week
            week = 1 if utcnow().astimezone(tz).weekday() == 6 else 0
        monday, posts = yt_week(week)
        return render(request, "youtube.html", posts=posts, monday=monday, week=week)

    @app.get("/youtube/pack.zip")
    def youtube_pack_zip(week: int = 0):
        import io
        import zipfile
        from fastapi.responses import Response
        monday, posts = yt_week(week)
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
            lines = [f"YouTube Community posts — week of {monday:%b %d, %Y}", ""]
            for i, c in enumerate(posts, 1):
                when = parse(c["scheduled_at"]).astimezone(tz).strftime("%a %b %d, %I:%M %p")
                lines += [f"=== {i}. {when} · {c['format'].replace('community_', '')} ===", c["pack_text"], ""]
                for a in c["assets"]:
                    pth = Path(a["path"])
                    if pth.exists() and a["kind"] == "image":
                        z.write(pth, f"{i:02d}-{parse(c['scheduled_at']).astimezone(tz):%a-%H%M}{pth.suffix}")
            z.writestr("POSTS.txt", "\n".join(lines))
        return Response(buf.getvalue(), media_type="application/zip",
                        headers={"Content-Disposition": f'attachment; filename="youtube-week-{monday:%Y-%m-%d}.zip"'})

    @app.post("/content/{cid}/scheduled-in-studio")
    def scheduled_in_studio(cid: str, week: str = Form("1")):
        db.x("UPDATE content SET status='scheduled_external', updated_at=? WHERE id=? AND platform='youtube' AND status IN ('ready','manual_due','blocked')",
             (iso(), cid))
        return RedirectResponse(f"/youtube?week={int(week)}", status_code=303)

    @app.post("/content/{cid}/unschedule-studio")
    def unschedule_studio(cid: str, week: str = Form("1")):
        db.x("UPDATE content SET status='ready', updated_at=? WHERE id=? AND status='scheduled_external'", (iso(), cid))
        return RedirectResponse(f"/youtube?week={int(week)}", status_code=303)

    # ---- research ---------------------------------------------------------------------------------------
    @app.get("/research", response_class=HTMLResponse)
    def research_page(request: Request):
        rows = db.q("SELECT * FROM research_items ORDER BY researched_at DESC, relevance DESC LIMIT 200")
        return render(request, "research.html", rows=rows)

    # ---- analytics --------------------------------------------------------------------------------------
    @app.get("/analytics", response_class=HTMLResponse)
    def analytics_page(request: Request):
        posts = analytics.latest_post_metrics(db, utcnow() - timedelta(days=90))
        agg = analytics.aggregate(s, posts)
        growth = {f"{p} {m}": db.q("SELECT collected_at, value FROM account_metrics WHERE platform=? AND metric=? ORDER BY collected_at", (p, m))
                  for p, m in (("instagram", "followers_count"), ("youtube", "subscriber_count"))}
        reports = db.q("SELECT * FROM reports ORDER BY created_at DESC LIMIT 6")
        return render(request, "analytics.html", posts=posts, agg=agg, growth=growth, reports=reports, opt=db.kv_get("optimizer_last"))

    # ---- controls ---------------------------------------------------------------------------------------
    @app.get("/controls", response_class=HTMLResponse)
    def controls(request: Request):
        diag = db.kv_get("last_diagnostics")
        runs = db.q("SELECT * FROM job_runs ORDER BY id DESC LIMIT 30")
        return render(request, "controls.html", diag=diag, runs=runs)

    @app.post("/controls/{action}")
    def control(action: str):
        msg = ""
        if action == "pause":
            db.kv_set("paused", True); notify(s, db, "warning", "control", "Automation paused", "from dashboard")
        elif action == "resume":
            db.kv_set("paused", False); notify(s, db, "info", "control", "Automation resumed", "from dashboard")
        elif action == "emergency-stop":
            db.kv_set("emergency_stop", True); notify(s, db, "error", "control", "EMERGENCY STOP engaged", "Nothing will publish until cleared.")
        elif action == "clear-stop":
            db.kv_set("emergency_stop", False); notify(s, db, "warning", "control", "Emergency stop cleared", "from dashboard")
        elif action == "research":
            msg = json.dumps(research.run(s, db, get_provider(s, db)))
        elif action == "generate":
            msg = json.dumps(generation.generate_due(s, db, get_provider(s, db), limit=4))
        elif action == "rebuild":
            msg = json.dumps(scheduler.rebuild(s, db))
        elif action == "diagnostics":
            from autopilot import diagnostics
            db.kv_set("last_diagnostics", {"at": iso(), "items": diagnostics.run(s, db)})
        elif action == "backup":
            msg = str(backup.create(s, db))
        elif action == "test-notification":
            msg = json.dumps(send_external(s, "Autopilot test notification", "If you can read this, notifications work."))
        else:
            raise HTTPException(404)
        if msg:
            notify(s, db, "info", "control", f"Ran '{action}'", msg[:2000], external=False)
        return RedirectResponse("/controls", status_code=303)

    # ---- notifications / settings -----------------------------------------------------------------------
    @app.get("/notifications", response_class=HTMLResponse)
    def notifications(request: Request):
        rows = db.q("SELECT * FROM notifications ORDER BY id DESC LIMIT 200")
        db.x("UPDATE notifications SET read=1 WHERE read=0")
        return render(request, "notifications.html", rows=rows)

    @app.get("/settings", response_class=HTMLResponse)
    def settings_page(request: Request):
        sec = SecretStore(s.data_dir)
        return render(request, "settings.html", secrets={n: bool(sec.get(n)) for n in SECRET_NAMES},
                      slots=s.get("calendar.slots", []), overrides=db.kv_get("slot_overrides", {}),
                      config_path=str(s.path))

    @app.post("/settings")
    def save_settings(timezone: str = Form(...), research_hours: str = Form(...), max_calls: str = Form(...),
                      ntfy_topic: str = Form(""), webhook_url: str = Form(""), email_to: str = Form(""),
                      daily_summary_time: str = Form("08:00"), backup_keep: str = Form("14")):
        from autopilot import config as cfg
        from zoneinfo import ZoneInfo
        ZoneInfo(timezone)
        p = s.path
        if p.name == "settings.example.toml":
            raise HTTPException(400, "run `autopilot init` first to create config/settings.toml")
        for k, v in (("general.timezone", timezone), ("research.interval_hours", research_hours), ("ai.max_calls_per_day", max_calls),
                     ("notifications.ntfy_topic", ntfy_topic), ("notifications.webhook_url", webhook_url),
                     ("notifications.email_to", email_to), ("notifications.daily_summary_time", daily_summary_time),
                     ("backup.keep", backup_keep)):
            cfg.set_value(p, k, v)
        new = cfg.load(p)
        s.raw = new.raw
        return RedirectResponse("/settings?saved=1", status_code=303)

    @app.get("/api/health")
    def health():
        hb = db.kv_get("heartbeat")
        return JSONResponse({"heartbeat": hb, "queue": scheduler.queue_health(s, db), "mode": s.mode,
                             "activated": db.kv_get("activated", False), "paused": db.kv_get("paused", False),
                             "emergency_stop": db.kv_get("emergency_stop", False)})

    return app
