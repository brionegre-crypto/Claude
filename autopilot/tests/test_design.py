import json
from datetime import timedelta

from autopilot import generation, scheduler
from autopilot.assets import design
from autopilot.db import iso, utcnow
from conftest import make_ready


def test_markup_parsing_keeps_punctuation_attached():
    toks = design.parse("You lack a *when*. **Write** it, now!")
    assert ("when.", "accent") in toks and ("Write", "bold") in toks and toks[-1] == ("now!", "normal")


def test_every_style_and_layout_renders():
    for st in design.STYLES:
        for lay in design.LAYOUTS:
            im = design.slide(st, (1080, 1350), {"layout": lay, "title": "The *Sunday* reset", "text": "Five minutes.",
                                                 "items": ["One", "Two *three*"], "myth": "A", "truth": "B"}, 2, 6)
            assert im.size == (1080, 1350)


def test_legacy_slides_get_layouts():
    out = design.legacy_layouts([{"title": "a"}, {"title": "b"}, {"title": "Comment STEP1", "text": "free"}])
    assert [s["layout"] for s in out] == ["hook", "point", "cta"]


def test_styles_rotate_and_reel_has_music_and_cover_offset(env):
    s, db = env
    a = make_ready(s, db, "reel")
    b = make_ready(s, db, "reel")
    body_a = json.loads(db.one("SELECT body FROM content WHERE id=?", (a,))[0])
    body_b = json.loads(db.one("SELECT body FROM content WHERE id=?", (b,))[0])
    assert body_a["style"] != body_b["style"]
    assert body_a["thumb_offset_ms"] > 0 and body_a["music_mood"]
    import subprocess
    vid = db.one("SELECT path FROM assets WHERE content_id=? AND kind='video'", (a,))[0]
    streams = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type", "-of", "csv=p=0", vid],
                             capture_output=True, text=True).stdout.split()
    assert streams == ["video", "audio"]


def test_archetypes_rotate_per_format(env):
    s, db = env
    seen = []
    for _ in range(4):
        cid = make_ready(s, db, "carousel")
        seen.append(json.loads(db.one("SELECT body FROM content WHERE id=?", (cid,))[0])["archetype"])
    assert len(set(seen)) == 4                      # four carousels, four different shapes


def test_refresh_queue_rewrites_future_posts_and_skips_imminent(env):
    s, db = env
    from autopilot.ai.provider import MockProvider
    soon = make_ready(s, db, "image")
    db.x("UPDATE content SET scheduled_at=? WHERE id=?", (iso(utcnow() + timedelta(minutes=10)), soon))
    later = make_ready(s, db, "carousel")
    db.x("UPDATE content SET scheduled_at=?, body=? WHERE id=?", (iso(utcnow() + timedelta(days=2)), json.dumps({"slides": [{"title": "old"}]}), later))
    p = MockProvider(s, db)
    res = generation.refresh_queue(s, db, p, rewrite=True, say=lambda *a: None)
    assert res["rewritten"] == 1 and not p.ignore_budget
    body = json.loads(db.one("SELECT body FROM content WHERE id=?", (later,))[0])
    assert body.get("archetype") and body.get("style") and db.one("SELECT status FROM content WHERE id=?", (later,))[0] == "ready"


def test_neighbours_are_passed_and_their_keywords_avoided(env):
    s, db = env
    from autopilot import generation
    from autopilot.ai import prompts
    a = make_ready(s, db, "image")
    db.x("UPDATE content SET scheduled_at=?, body=? WHERE id=?",
         (iso(utcnow() + timedelta(days=2)), json.dumps({"keyword": "morning routine for men", "slides": [{"title": "x"}]}), a))
    c = {"id": "new", "scheduled_at": iso(utcnow() + timedelta(days=3))}
    nb = generation.neighbour_posts(db, c)
    assert any(n["keyword"] == "morning routine for men" for n in nb)
    for _ in range(30):
        assert generation.pick_keyword(s, db, avoid=["morning routine for men"]) != "morning routine for men"
    p = prompts.generate("b", "instagram", "image", "t", "a", [], [], "", "", "", neighbours=nb)
    assert "morning routine for men" in p and "DIFFERENT topic" in p
