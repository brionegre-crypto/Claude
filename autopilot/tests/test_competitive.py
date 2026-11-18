from datetime import timedelta
import re

from autopilot import competitive
from autopilot.db import iso, utcnow
from conftest import make_ready


def test_handles_are_cleaned():
    assert competitive.clean_handle("@Some.Account") == "some.account"
    assert competitive.clean_handle("https://www.instagram.com/dad_strong/?hl=en") == "dad_strong"
    assert competitive.clean_handle("not a handle!") is None


def test_collect_compare_and_insights(env, fake_ig, monkeypatch):
    s, db = env
    fake, pubs = fake_ig
    ig = pubs["instagram"]
    ig.secrets.set("instagram_api_host", "https://graph.facebook.com")
    # recent own media so "last 30 days" has data
    import autopilot.competitive as C
    competitive.add(db, "@strongdads")
    competitive.add(db, "personaluser")
    out = competitive.collect(s, db, ig)
    assert "strongdads" in out["collected"] and "personaluser" in out["errors"]
    db.x("UPDATE competitor_media SET posted_at=?", (iso(utcnow() - timedelta(days=2)),))
    comp = competitive.comparison(s, db)
    c = comp["competitors"][0]
    assert c["handle"] == "strongdads" and c["posts_30d"] == 4 and c["median_engagement_rate"] > 0
    assert c["format_mix"] and "#christianmen" in c["top_hashtags"]
    assert comp["errors"]["personaluser"].startswith("Not found")
    from autopilot.ai.provider import MockProvider
    ins = competitive.ai_insights(s, db, MockProvider(s, db))
    assert ins["experiments"] and db.kv_get("competitive_learnings")
    from autopilot import generation
    assert "never copy" in generation._learnings(db)


def test_competitors_page(env, fake_ig):
    s, db = env
    from test_system import _client, _login
    competitive.add(db, "strongdads")
    c, tok = _client(s, db)
    csrf = _login(c, tok)
    assert c.get("/competitors").status_code == 200
    c.post("/competitors/add", data={"csrf": csrf, "handle": "@another_one https://instagram.com/third.acct"})
    assert set(competitive.handles(db)) == {"strongdads", "another_one", "third.acct"}
    c.post("/competitors/remove", data={"csrf": csrf, "handle": "another_one"})
    assert "another_one" not in competitive.handles(db)
