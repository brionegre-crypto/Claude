import json
import re
from datetime import timedelta

from fastapi.testclient import TestClient

from autopilot import backup, generation, scheduler
from autopilot.db import DB, iso, utcnow
from conftest import make_ready


def test_generation_end_to_end_with_assets(env):
    s, db = env
    from autopilot import research
    from autopilot.ai.provider import MockProvider
    research.seed_evergreen(s, db)
    scheduler.plan(s, db)
    res = generation.generate_due(s, db, MockProvider(s, db), limit=8)
    assert res["generated"] == 8 and res["blocked"] == 0, res
    reel = db.one("SELECT id FROM content WHERE format='reel' AND status='ready'")
    if reel:
        kinds = {r[0] for r in db.q("SELECT kind FROM assets WHERE content_id=?", (reel[0],))}
        assert {"video", "cover"} <= kinds


def test_backup_and_restore_roundtrip(env):
    s, db = env
    cid = make_ready(s, db, "image")
    z = backup.create(s, db)
    db.x("DELETE FROM assets"); db.x("DELETE FROM content")
    db.close()
    info = backup.restore(s, z)
    assert info["restored_content_rows"] >= 1
    db2 = DB(s.db_path)
    assert db2.one("SELECT id FROM content WHERE id=?", (cid,))


def test_worker_tick_full_cycle(env):
    s, db = env
    from autopilot.worker import Worker
    w = Worker(s, db)
    w.tick()
    assert db.kv_get("heartbeat")
    assert db.one("SELECT COUNT(*) FROM content WHERE status='ready'")[0] > 0
    # make the first ready post due, tick again → published in simulation exactly once
    cid = db.one("SELECT id FROM content WHERE status='ready' AND platform='instagram' ORDER BY scheduled_at")[0]
    db.x("UPDATE content SET scheduled_at=? WHERE id=?", (iso(utcnow() - timedelta(minutes=1)), cid))
    w2 = Worker(s, db)      # simulates a restart
    w2.tick(); w2.tick()
    assert db.one("SELECT status FROM content WHERE id=?", (cid,))[0] == "published"
    assert db.one("SELECT COUNT(*) FROM publish_attempts WHERE content_id=? AND state='published'", (cid,))[0] == 1


def test_worker_respects_emergency_stop(env):
    s, db = env
    from autopilot.worker import Worker
    db.kv_set("emergency_stop", True)
    Worker(s, db).tick()
    assert db.one("SELECT COUNT(*) FROM content")[0] == 0


def _client(s, db):
    from autopilot.web.app import create_app
    from autopilot.web.auth import ensure_token
    c = TestClient(create_app(s, db), base_url="http://127.0.0.1")
    return c, ensure_token(s)


def _login(c, tok):
    r = c.post("/login", data={"token": tok}, follow_redirects=False)
    assert r.status_code == 303
    page = c.get("/controls").text
    return re.search(r'name="csrf" value="([^"]+)"', page).group(1)


def test_dashboard_requires_login(env):
    s, db = env
    c, tok = _client(s, db)
    assert c.get("/", follow_redirects=False).status_code == 303
    assert c.post("/login", data={"token": "wrong"}).status_code == 401


def test_dashboard_blocks_foreign_host(env):
    s, db = env
    c, tok = _client(s, db)
    assert c.get("/login", headers={"host": "evil.example"}).status_code == 403


def test_dashboard_pages_and_csrf(env):
    s, db = env
    make_ready(s, db, "carousel")
    c, tok = _client(s, db)
    csrf = _login(c, tok)
    for path in ("/", "/calendar", "/library", "/research", "/analytics", "/controls", "/notifications", "/settings", "/api/health"):
        assert c.get(path).status_code == 200, path
    cid = db.one("SELECT id FROM content")[0]
    assert c.get(f"/content/{cid}").status_code == 200
    assert c.post("/controls/pause", data={}).status_code == 403          # no CSRF token
    assert c.post("/controls/pause", data={"csrf": csrf}, follow_redirects=False).status_code == 303
    assert db.kv_get("paused") is True
    c.post("/controls/emergency-stop", data={"csrf": csrf})
    assert db.kv_get("emergency_stop") is True


def test_dashboard_never_shows_secret_values(env):
    s, db = env
    from autopilot.secrets import SecretStore
    SecretStore(s.data_dir).set("instagram_access_token", "IGverysecret999")
    c, tok = _client(s, db)
    _login(c, tok)
    for path in ("/settings", "/", "/api/health"):
        assert "IGverysecret999" not in c.get(path).text


def test_dashboard_edit_and_reschedule(env):
    s, db = env
    cid = make_ready(s, db, "image")
    db.x("UPDATE content SET scheduled_at=? WHERE id=?", (iso(utcnow() + timedelta(days=2)), cid))
    c, tok = _client(s, db)
    csrf = _login(c, tok)
    c.post(f"/content/{cid}/edit", data={"csrf": csrf, "hook": "New hook", "caption": "A fresh caption about the weekly scorecard habit.", "hashtags": "#bethemansystem #dadlife"})
    row = db.one("SELECT hook, status FROM content WHERE id=?", (cid,))
    assert row[0] == "New hook" and row[1] == "ready"
    when = (utcnow() + timedelta(days=3)).astimezone(s.tz).strftime("%Y-%m-%dT%H:%M")
    c.post(f"/content/{cid}/reschedule", data={"csrf": csrf, "when": when})
    assert db.one("SELECT scheduled_at FROM content WHERE id=?", (cid,))[0] > iso(utcnow() + timedelta(days=2, hours=12))


def test_media_server_serves_only_registered_files(tmp_path):
    """The tunnel's local server exposes only the files of the post being published, under random paths."""
    import http.server
    import threading
    import httpx
    from autopilot.publishing.mediahost import _Handler
    secret = tmp_path / "secrets.enc"; secret.write_text("nope")
    img = tmp_path / "post.jpg"; img.write_bytes(b"\xff\xd8jpeg")
    files = {"/m/randomtoken/post.jpg": img}
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), type("H", (_Handler,), {"files": files}))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{srv.server_port}"
    try:
        r = httpx.get(base + "/m/randomtoken/post.jpg")
        assert r.status_code == 200 and r.headers["content-type"] == "image/jpeg"
        for bad in ("/secrets.enc", "/m/randomtoken/../secrets.enc", "/m/other/post.jpg", "/"):
            assert httpx.get(base + bad).status_code == 404
    finally:
        srv.shutdown()


def test_activation_requires_real_test(env, monkeypatch, capsys):
    s, db = env
    from autopilot import wizard
    from autopilot.secrets import SecretStore
    SecretStore(s.data_dir).set("instagram_access_token", "IGx")
    db.kv_set("wizard_steps", {"ai": {"ok": True}})
    monkeypatch.setattr(wizard, "ctx", lambda: (s, db))
    monkeypatch.setattr("builtins.input", lambda *a: "ACTIVATE")
    wizard.activate()
    assert not db.kv_get("activated") and "REAL Instagram test" in capsys.readouterr().out


def test_inbox_import_fills_slot_and_validates(env):
    s, db = env
    from autopilot import generation
    scheduler.plan(s, db)
    inbox = s.resolve(s.get("ai.inbox_dir"))
    s.raw["ai"]["inbox_dir"] = str(s.data_dir / "inbox")
    inbox = s.data_dir / "inbox"; inbox.mkdir()
    (inbox / "week.json").write_text(json.dumps([
        {"platform": "instagram", "format": "carousel", "topic": "Weekly scorecard", "pillar": "Discipline systems",
         "hook": "Score the week before it scores you", "caption": "Sunday night, five minutes, one card. What will you track?",
         "hashtags": ["#bethemansystem"], "slides": [{"title": "One card", "text": "Five lines."}, {"title": "Sunday", "text": "Five minutes."}]},
        {"platform": "instagram", "format": "image", "hook": "x", "caption": "Studies show 90% of men quit.", "slides": [{"title": "t", "text": "x"}]},
    ]))
    res = generation.import_inbox(s, db)
    assert res["imported"] == 2
    st = {r[0]: r[1] for r in db.q("SELECT format, status FROM content WHERE generated_by='inbox'")}
    assert st == {"carousel": "ready", "image": "blocked"}          # unsourced statistic is blocked
    assert (inbox / "imported" / "week.json").exists()
