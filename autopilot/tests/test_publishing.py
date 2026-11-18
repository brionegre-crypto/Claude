import json
from datetime import timedelta

import httpx

from autopilot import publisher
from autopilot.db import iso, utcnow
from conftest import make_ready


def status(db, cid):
    return db.one("SELECT status FROM content WHERE id=?", (cid,))[0]


def test_simulated_publish_writes_outbox(env):
    s, db = env
    cid = make_ready(s, db, "carousel")
    res = publisher.run_due(s, db)          # not activated → simulated
    assert res[cid] == "published" and status(db, cid) == "published"
    pid = db.one("SELECT platform_post_id FROM content WHERE id=?", (cid,))[0]
    assert pid.startswith("sim_")
    assert any((s.data_dir / "simulated-outbox").iterdir())


def test_not_live_until_activated(env):
    s, db = env
    s.raw["general"]["mode"] = "live"
    assert not publisher.is_live(s, db)       # mode alone is not enough
    db.kv_set("activated", True)
    assert publisher.is_live(s, db)


def test_instagram_image_happy_path(env, fake_ig):
    s, db = env
    fake, pubs = fake_ig
    cid = make_ready(s, db, "image")
    assert publisher.run_due(s, db, pubs)[cid] == "published"
    assert len(fake.media) == 1
    row = db.one("SELECT platform_post_id, permalink FROM content WHERE id=?", (cid,))
    assert row[0] == fake.media[0]["id"] and row[1].startswith("https://instagram.com/p/")
    assert "#bethemansystem" in fake.media[0]["caption"]


def test_carousel_reel_story_paths(env, fake_ig):
    s, db = env
    fake, pubs = fake_ig
    ids = [make_ready(s, db, f) for f in ("carousel", "reel", "story")]
    res = publisher.run_due(s, db, pubs)
    assert all(res[i] == "published" for i in ids), res
    assert fake.uploads == 1                                  # reel used resumable upload (no public URL needed)
    types = sorted(c["params"].get("media_type", "IMAGE") for c in fake.containers.values())
    assert "CAROUSEL" in types and "REELS" in types and "STORIES" in types


def test_no_duplicate_on_repeated_runs(env, fake_ig):
    s, db = env
    fake, pubs = fake_ig
    cid = make_ready(s, db, "image")
    publisher.run_due(s, db, pubs)
    publisher.run_due(s, db, pubs)
    db.x("UPDATE content SET status='ready' WHERE id=?", (cid,))   # even if status were corrupted back to ready…
    assert publisher.run_due(s, db, pubs)[cid] == "already_published"
    assert len(fake.media) == 1 and fake.publish_calls == 1


def test_timeout_after_publish_is_reconciled_not_duplicated(env, fake_ig):
    s, db = env
    fake, pubs = fake_ig
    cid = make_ready(s, db, "image", caption="Unique caption for reconcile test. What will you do Thursday?")
    fake.fail_next.append(("publish", "timeout_after"))
    assert publisher.run_due(s, db, pubs)[cid] == "published"
    assert len(fake.media) == 1
    assert db.one("SELECT state FROM publish_attempts WHERE content_id=?", (cid,))[0] == "reconciled"


def test_crash_recovery_after_container(env, fake_ig):
    s, db = env
    fake, pubs = fake_ig
    cid = make_ready(s, db, "image", caption="Crash recovery caption. Pick the hour, not the week.")
    # simulate: process died right after media_publish succeeded but before the DB was updated
    c = dict(db.one("SELECT * FROM content WHERE id=?", (cid,)))
    ig = pubs["instagram"]
    cont = ig._call("POST", "17841/media", image_url="https://fake.example/x.jpg", caption=publisher.caption_full(c))["id"]
    ig._call("POST", "17841/media_publish", creation_id=cont)
    db.x("UPDATE content SET status='publishing' WHERE id=?", (cid,))
    db.x("INSERT INTO publish_attempts(content_id,idempotency_key,attempt,state,container_id,started_at) VALUES(?,?,1,'container_created',?,?)",
         (cid, cid, cont, iso()))
    out = publisher.recover(s, db, pubs)
    assert "reconciled" in out[0] and status(db, cid) == "published"
    publisher.run_due(s, db, pubs)
    assert len(fake.media) == 1


def test_crash_before_container_returns_to_queue(env, fake_ig):
    s, db = env
    fake, pubs = fake_ig
    cid = make_ready(s, db, "image")
    db.x("UPDATE content SET status='publishing' WHERE id=?", (cid,))
    db.x("INSERT INTO publish_attempts(content_id,idempotency_key,attempt,state,started_at) VALUES(?,?,1,'started',?)", (cid, cid, iso()))
    publisher.recover(s, db, pubs)
    assert status(db, cid) == "ready"
    publisher.run_due(s, db, pubs)
    assert status(db, cid) == "published" and len(fake.media) == 1


def test_rate_limit_backoff_then_success(env, fake_ig):
    s, db = env
    fake, pubs = fake_ig
    cid = make_ready(s, db, "image")
    fake.fail_next.append(("publish", "rate"))
    assert publisher.run_due(s, db, pubs)[cid] == "retry_scheduled"
    nxt = db.one("SELECT next_retry_at FROM publish_attempts WHERE content_id=? ORDER BY id DESC", (cid,))[0]
    assert nxt > iso(utcnow() + timedelta(minutes=50))          # rate limit honours retry_after (1h)
    assert cid not in publisher.run_due(s, db, pubs)            # not yet due
    db.x("UPDATE publish_attempts SET next_retry_at=? WHERE content_id=?", (iso(utcnow() - timedelta(seconds=1)), cid))
    assert publisher.run_due(s, db, pubs)[cid] == "published"
    assert len(fake.media) == 1


def test_transient_errors_exhaust_to_permanent_failure(env, fake_ig):
    s, db = env
    fake, pubs = fake_ig
    s.raw["publishing"]["max_attempts"] = 3
    cid = make_ready(s, db, "image")
    for _ in range(3):
        fake.fail_next.append(("publish", "transient"))
        db.x("UPDATE publish_attempts SET next_retry_at=? WHERE content_id=?", (iso(utcnow() - timedelta(seconds=1)), cid))
        publisher.run_due(s, db, pubs)
    assert status(db, cid) == "failed_permanent"
    assert db.one("SELECT COUNT(*) FROM notifications WHERE category='publish_failed'")[0] == 1


def test_auth_error_alerts(env, fake_ig):
    s, db = env
    fake, pubs = fake_ig
    cid = make_ready(s, db, "image")
    fake.fail_next.append(("create", "auth"))
    assert publisher.run_due(s, db, pubs)[cid] == "auth_error"
    assert db.kv_get("auth_problem:instagram")
    assert db.one("SELECT COUNT(*) FROM notifications WHERE category='auth'")[0] == 1


def test_emergency_stop_and_pause(env, fake_ig):
    s, db = env
    fake, pubs = fake_ig
    cid = make_ready(s, db, "image")
    db.kv_set("emergency_stop", True)
    assert publisher.run_due(s, db, pubs) == {"halted": True}
    db.kv_set("emergency_stop", False); db.kv_set("paused", True)
    assert publisher.run_due(s, db, pubs) == {"halted": True}
    assert len(fake.media) == 0 and status(db, cid) == "ready"


def test_late_posts_are_skipped_not_dumped(env, fake_ig):
    s, db = env
    fake, pubs = fake_ig
    cid = make_ready(s, db, "image", minutes_ago=600)
    assert publisher.run_due(s, db, pubs)[cid] == "skipped"
    assert len(fake.media) == 0


def test_media_tampering_blocks(env, fake_ig):
    s, db = env
    fake, pubs = fake_ig
    cid = make_ready(s, db, "image")
    p = db.one("SELECT path FROM assets WHERE content_id=?", (cid,))[0]
    open(p, "ab").write(b"x")
    assert publisher.run_due(s, db, pubs)[cid] == "blocked" and len(fake.media) == 0


def test_youtube_is_assisted(env, fake_ig):
    s, db = env
    fake, pubs = fake_ig
    cid = make_ready(s, db, "community_poll", platform="youtube")
    assert publisher.run_due(s, db, pubs)[cid] == "manual_due"
    assert db.one("SELECT COUNT(*) FROM notifications WHERE category='manual_due'")[0] == 1


def test_insights_and_report(env, fake_ig):
    s, db = env
    fake, pubs = fake_ig
    from autopilot import analytics
    cid = make_ready(s, db, "image")
    publisher.run_due(s, db, pubs)
    db.x("UPDATE content SET published_at=? WHERE id=?", (iso(utcnow() - timedelta(days=2)), cid))
    out = analytics.collect(s, db, pubs)
    assert out["posts"] == 1 and out["account"]["instagram"]["followers_count"] == 1000
    rep = analytics.report(s, db, "weekly")
    assert "Performance (real API metrics, 1 posts" in rep


def _detect_client(kind):
    def handler(req):
        host, path = req.url.host, req.url.path
        if host == "graph.instagram.com":
            if kind == "instagram":
                return httpx.Response(200, json={"user_id": "17841", "username": "bethemansystem", "account_type": "BUSINESS"})
            return httpx.Response(400, json={"error": {"message": "Invalid OAuth access token", "code": 190}})
        if path.endswith("/me/accounts"):
            if kind == "facebook":
                return httpx.Response(200, json={"data": [
                    {"name": "Other page", "instagram_business_account": {"id": "999", "username": "someoneelse"}},
                    {"name": "Be The Man", "instagram_business_account": {"id": "17841", "username": "bethemansystem"}}]})
            return httpx.Response(400, json={"error": {"message": "bad", "code": 190}})
        return httpx.Response(400, json={"error": {"message": "bad", "code": 190}})
    return httpx.Client(transport=httpx.MockTransport(handler))


def test_detects_instagram_login_token(env):
    s, db = env
    from autopilot.publishing.instagram import detect_account
    a = detect_account(s, "IGAAtoken", client=_detect_client("instagram"))
    assert a["host"] == "https://graph.instagram.com" and a["user_id"] == "17841"


def test_detects_unified_facebook_login_token_and_picks_brand_account(env):
    s, db = env
    from autopilot.publishing.instagram import detect_account
    a = detect_account(s, "EAAtoken", client=_detect_client("facebook"))
    assert a["host"] == "https://graph.facebook.com" and a["user_id"] == "17841" and a["username"] == "bethemansystem"


def test_unusable_token_is_rejected_clearly(env):
    s, db = env
    import pytest
    from autopilot.publishing.base import PermanentError
    from autopilot.publishing.instagram import detect_account
    with pytest.raises(PermanentError, match="No Instagram account"):
        detect_account(s, "junk", client=_detect_client("none"))


def test_publishing_via_facebook_host(env, fake_ig):
    s, db = env
    fake, pubs = fake_ig
    ig = pubs["instagram"]
    ig.secrets.set("instagram_api_host", "https://graph.facebook.com")
    assert ig.flavor == "facebook" and ig.base.startswith("https://graph.facebook.com/")
    ok, detail = ig.check_auth()
    assert ok and "@bethemansystem" in detail
    ids = [make_ready(s, db, f) for f in ("image", "reel")]
    res = publisher.run_due(s, db, pubs)
    assert all(res[i] == "published" for i in ids) and len(fake.media) == 2
    assert ig.account_insights()["followers_count"] == 1000


def test_token_cleaning_and_error_scrubbing():
    from autopilot.publishing.instagram import clean_token, scrub
    tok = "EAAFAKEtoken" + "x1y2z3" * 10
    assert clean_token(f'  "{tok[:30]}\n{tok[30:]} "\n') == tok
    assert clean_token(f"Bearer {tok}") == tok
    leaked = f'{{"error":{{"message":"Malformed access token {tok[:50]}","code":190}}}}'
    out = scrub(leaked, tok)
    assert tok[:20] not in out and "Malformed access token" in out


def test_detect_reports_expiry_and_scopes(env):
    s, db = env
    from autopilot.publishing.instagram import detect_account
    def handler(req):
        if req.url.path.endswith("/debug_token"):
            return httpx.Response(200, json={"data": {"type": "USER", "expires_at": 1999999999,
                                                      "scopes": ["instagram_basic", "instagram_content_publish"]}})
        if req.url.host == "graph.instagram.com":
            return httpx.Response(400, json={"error": {"message": "Cannot parse access token", "code": 190}})
        return httpx.Response(200, json={"data": [{"name": "BTM", "instagram_business_account": {"id": "17841", "username": "bethemansystem"}}]})
    a = detect_account(s, "EAAtok", client=httpx.Client(transport=httpx.MockTransport(handler)))
    assert a["expires_at"] == 1999999999 and "instagram_content_publish" in a["scopes"]
