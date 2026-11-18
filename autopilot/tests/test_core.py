import json
from datetime import date, timedelta, timezone
from zoneinfo import ZoneInfo

import pytest

from autopilot import config, quality, scheduler
from autopilot.logs import redact


def test_config_validation_catches_errors():
    raw = {"general": {"timezone": "Mars/Base", "mode": "yolo"}, "dashboard": {"host": "0.0.0.0"},
           "calendar": {"slots": [{"platform": "instagram", "format": "short", "days": ["xyz"], "time": "25:00"}]}}
    errs = config.validate(raw)
    assert any("timezone" in e for e in errs) and any("loopback" in e for e in errs)
    assert any("unsupported platform/format" in e for e in errs) and any("HH:MM" in e for e in errs)


def test_example_config_is_valid():
    assert config.load(config.PROJECT_ROOT / "config" / "settings.example.toml").errors == []


def test_set_value_preserves_comment(tmp_path):
    p = tmp_path / "s.toml"
    p.write_text('[general]\nmode = "simulation"   # keep me\n')
    config.set_value(p, "general.mode", "live")
    assert "# keep me" in p.read_text() and 'mode = "live"' in p.read_text()


def test_dst_conversion():
    tz = ZoneInfo("America/Chicago")
    # summer: CDT = UTC-5, winter: CST = UTC-6
    assert scheduler.local_to_utc(date(2026, 7, 1), "18:30", tz).hour == 23
    assert scheduler.local_to_utc(date(2026, 12, 1), "18:30", tz).hour == 0
    # spring-forward gap 2026-03-08 02:30 does not exist → moved forward, still a valid instant
    t = scheduler.local_to_utc(date(2026, 3, 8), "02:30", tz)
    assert t.astimezone(tz).hour == 3


def test_plan_is_idempotent(env):
    s, db = env
    a = scheduler.plan(s, db)
    b = scheduler.plan(s, db)
    assert a["created"] > 50 and b["created"] == 0
    keys = [r[0] for r in db.q("SELECT slot_key FROM content")]
    assert len(keys) == len(set(keys))


def test_min_gap_enforced(env):
    s, db = env
    s.raw["calendar"]["slots"] = [{"platform": "instagram", "format": "image", "days": ["mon"], "time": "18:00"},
                                  {"platform": "instagram", "format": "reel", "days": ["mon"], "time": "18:30"}]
    s.raw["calendar"]["explore_times"] = False
    slots = scheduler.planned_slots(s, db, date(2026, 11, 23), 1)
    assert (slots[1]["utc"] - slots[0]["utc"]) >= timedelta(minutes=90)


def _c(**kw):
    base = {"id": "x", "platform": "instagram", "format": "image", "caption": "Write down the when. What will you do Thursday?",
            "hook": "The when beats the why", "hashtags": ["#bethemansystem"], "sources": "[]",
            "body": {"slides": [{"title": "Write the when", "text": "This week is not a time."}]}}
    base.update(kw)
    return base


def test_quality_ordinary_content_passes(env):
    s, db = env
    assert quality.check(s, db, _c())["ok"]


@pytest.mark.parametrize("caption,needle", [
    ("Studies show 73% of men fail.", "factual"),
    ("This is guaranteed to fix your marriage.", "banned"),
    ("Talk about suicide prevention.", "sensitive"),
])
def test_quality_blocks_risky(env, caption, needle):
    s, db = env
    rep = quality.check(s, db, _c(caption=caption))
    assert not rep["ok"] and any(needle in b for b in rep["blocks"]), rep


def test_quality_claim_needs_stored_source(env):
    s, db = env
    body = {"slides": [{"title": "t", "text": "x"}], "claims": [{"claim": "x", "source_url": "https://made.up/source"}]}
    assert not quality.check(s, db, _c(body=body))["ok"]
    ok = quality.check(s, db, _c(body=body, sources=json.dumps([{"url": "https://made.up/source"}])))
    assert ok["ok"]


def test_quality_detects_near_duplicates(env):
    s, db = env
    from autopilot.db import iso
    text = "Write down the when. This week is not a time. Pick the day and the hour and tell your wife."
    db.x("INSERT INTO content(id,platform,format,status,caption,hook,created_at,updated_at) VALUES('old','instagram','image','published',?,?,?,?)",
         (text, "hook", iso(), iso()))
    rep = quality.check(s, db, _c(caption=text + " Today.", hook="hook"))
    assert not rep["ok"] and any("duplicate" in b for b in rep["blocks"])


def test_hashtags_trimmed_and_brand_tag_added(env):
    s, db = env
    rep = quality.check(s, db, _c(hashtags=[f"#t{i}" for i in range(9)]))
    assert len(rep["hashtags"]) == 5 and "#bethemansystem" in rep["hashtags"]


def test_redaction():
    out = redact("POST access_token=IGQVJabcdefghijklmnopqrstuvwxyz0123456789ABCDEFG&x=1 Authorization: Bearer abcdef123456")
    assert "IGQVJ" not in out and "abcdef123456" not in out


def test_secret_store_encrypts(env):
    s, db = env
    from autopilot.secrets import SecretStore
    st = SecretStore(s.data_dir)
    st.set("instagram_access_token", "IGsupersecretvalue")
    assert b"IGsupersecretvalue" not in (s.data_dir / "secrets.enc").read_bytes()
    assert SecretStore(s.data_dir).get("instagram_access_token") == "IGsupersecretvalue"


def test_claude_provider_refuses_api_key(env, monkeypatch):
    s, db = env
    from autopilot.ai.provider import ClaudeCLIProvider, ProviderUnavailable
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test")
    with pytest.raises(ProviderUnavailable, match="ANTHROPIC_API_KEY"):
        ClaudeCLIProvider(s, db)._env()


def test_ai_budget_enforced(env):
    s, db = env
    from autopilot.ai.provider import ClaudeCLIProvider, MockProvider, ProviderUnavailable
    s.raw["ai"]["max_calls_per_day"] = 2
    c = ClaudeCLIProvider(s, db)
    c._complete = lambda purpose, prompt, web: '{"ok": true}'
    c.complete_json("healthcheck", "x"); c.complete_json("healthcheck", "x")
    with pytest.raises(ProviderUnavailable):
        c.complete_json("healthcheck", "x")
    m = MockProvider(s, db)          # offline mock never counts against the subscription budget
    for _ in range(5):
        m.complete_json("healthcheck", "x")


def test_extract_json_variants():
    from autopilot.ai.provider import extract_json
    assert extract_json('Sure!\n```json\n{"a": 1}\n```') == {"a": 1}
    assert extract_json('noise {"b": [1,2]} trailing') == {"b": [1, 2]}
