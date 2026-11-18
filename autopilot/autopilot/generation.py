"""Content generation engine: topic selection → Claude → validation → quality gate → assets."""
from __future__ import annotations

import json
from datetime import timedelta

from autopilot import logs, quality, research
from autopilot.ai import prompts
from autopilot.ai.provider import ProviderError, ProviderUnavailable
from autopilot.assets import render
from autopilot.db import DB, iso, utcnow
from autopilot.notify import notify

log = logs.get("generation")
BODY_KEYS = ("slides", "script", "frames", "poll", "quiz", "claims", "cover_text", "music_mood", "end_button",
             "reply_prompt", "reply_button", "keyword")


def _recent_bodies(db: DB, where: str, args=(), n=40) -> list[dict]:
    return [json.loads(r[0] or "{}") for r in db.q(f"SELECT body FROM content WHERE {where} AND body IS NOT NULL "
                                                     f"ORDER BY updated_at DESC LIMIT {int(n)}", args)]


def pick_archetype(db: DB, fmt: str, rng=None) -> str:
    """Least-recently-used archetype for this format, so no two neighbouring posts share a shape."""
    import random as _r
    rng = rng or _r
    options = list(prompts.ARCHETYPES.get(fmt, {"general": ""}))
    recent = [b.get("archetype") for b in _recent_bodies(db, "format=?", (fmt,), 30)]
    counts = {o: (recent.index(o) if o in recent else 10_000) for o in options}   # larger = used longer ago
    best = max(counts.values())
    return rng.choice([o for o, c in counts.items() if c == best])


def pick_keyword(s, db: DB, rng=None, avoid=()) -> str:
    import random as _r
    rng = rng or _r
    bank = [k for k in (s.get("brand.keywords") or prompts.KEYWORDS) if k not in avoid] or list(prompts.KEYWORDS)
    recent = [b.get("keyword") for b in _recent_bodies(db, "1=1", (), 40)]
    unused = [k for k in bank if k not in recent]
    return rng.choice(unused or bank)


def neighbour_posts(db: DB, content: dict, days: int = 4) -> list[dict]:
    """Posts scheduled within ±days (any platform): the writer must not repeat their topic, angle or keyword."""
    if not content.get("scheduled_at"):
        return []
    from datetime import datetime
    t = datetime.fromisoformat(content["scheduled_at"])
    rows = db.q("""SELECT format, hook, topic, body FROM content WHERE id!=? AND hook IS NOT NULL
                   AND status IN ('ready','published','manual_due','generating','draft') AND scheduled_at BETWEEN ? AND ?
                   ORDER BY scheduled_at""", (content["id"], iso(t - timedelta(days=days)), iso(t + timedelta(days=days))))
    out = []
    for r in rows:
        b = json.loads(r["body"] or "{}")
        out.append({"format": r["format"], "hook": r["hook"], "keyword": b.get("keyword"), "archetype": b.get("archetype")})
    return out[:20]


def _learnings(db: DB) -> str:
    own = db.kv_get("learnings", "") or ""
    comp = db.kv_get("competitive_learnings", "") or ""
    return own + (f"\nPatterns in competitors' best posts (adapt to our voice; never copy wording or designs): {comp}" if comp else "")


def recent_hooks(db: DB, n=60) -> list[str]:
    return [r[0] for r in db.q("SELECT hook FROM content WHERE hook IS NOT NULL ORDER BY created_at DESC LIMIT ?", (n,))]


def _research_for(db, content) -> dict | None:
    ids = json.loads(content["research_ids"] or "[]")
    if ids:
        r = db.one("SELECT * FROM research_items WHERE id=?", (ids[0],))
        return dict(r) if r else None
    return None


def generate_one(s, db: DB, provider, content: dict, link_checker=None) -> dict:
    cid = content["id"]
    db.x("UPDATE content SET status='generating', updated_at=? WHERE id=? AND status IN ('planned','failed_generation')", (iso(), cid))
    item = _research_for(db, content) or research.pick_topic(s, db, content["platform"], content["format"],
                                                              db.kv_get("pillar_weights"))
    if not item:
        db.x("UPDATE content SET status='planned', updated_at=? WHERE id=?", (iso(), cid))
        raise ProviderError("no research topics available; run research first")
    angle = (json.loads(item.get("opportunities") or "[]") or [item["topic"]])[0]
    sources = [{"title": item["title"], "url": item["url"], "published": item.get("published_at"),
                "notes": item.get("verification_notes")}] if item.get("url") else []
    import re
    for u in re.findall(r"(?:source|corroborated by): (https?://\S+)", item.get("verification_notes") or ""):
        if u not in [x["url"] for x in sources]:
            sources.append({"title": "corroborating source", "url": u})
    archetype = pick_archetype(db, content["format"])
    neighbours = neighbour_posts(db, content)
    keyword = pick_keyword(s, db, avoid=[n["keyword"] for n in neighbours if n.get("keyword")])
    from autopilot.assets import design
    prev_body = json.loads(content.get("body") or "{}") if isinstance(content.get("body"), str) else (content.get("body") or {})
    style = design.norm_style(prev_body.get("style")) or design.pick_style(cid, render.recent_styles(db, content["platform"], cid))
    prompt = prompts.generate(s.brand_text(), content["platform"], content["format"], item["topic"], angle, sources,
                              recent_hooks(db), _learnings(db), s.get("brand.cta_default", ""), s.get("brand.link", ""),
                              archetype=archetype, keyword=keyword, style=style, neighbours=neighbours)
    try:
        data = provider.complete_json("generate", prompt)
    except (ProviderUnavailable, ProviderError):
        db.x("UPDATE content SET status='planned', updated_at=? WHERE id=?", (iso(), cid))
        raise
    body = {k: data[k] for k in BODY_KEYS if k in data}
    body.update({"archetype": archetype, "keyword": data.get("keyword") or keyword, "style": style})
    if content["format"] in ("image", "community_image") and not body.get("slides"):
        title = data.get("headline") or data.get("hook")
        if title:
            body["slides"] = [{"title": str(title)[:90], "text": ""}]
    rec = {**content, "topic": str(data.get("topic") or item["topic"])[:200], "pillar": data.get("pillar"),
           "hook": str(data.get("hook", ""))[:300], "headline": str(data.get("headline", ""))[:200],
           "caption": str(data.get("caption", "")), "hashtags": [h if h.startswith("#") else "#" + h for h in data.get("hashtags", [])][:30],
           "cta": data.get("cta"), "body": body, "image_concept": data.get("image_concept"),
           "sources": json.dumps(sources), "research_ids": json.dumps([item["id"]]),
           "research_verification": item.get("verification")}
    report = quality.check(s, db, rec, link_checker=link_checker)
    rec["hashtags"] = report["hashtags"]
    status = "draft"
    if report["ok"]:
        assets = render.produce(s, db, {**rec, "body": json.dumps(body)})
        body = json.loads(db.one("SELECT body FROM content WHERE id=?", (cid,))[0] or "{}")   # keep style / music / thumb chosen by the renderer
        report2 = quality.check(s, db, rec, link_checker=None,
                                assets=[{**a, "license": "original"} for a in assets])
        report["blocks"] += [b for b in report2["blocks"] if b not in report["blocks"]]
        report["ok"] = not report["blocks"]
    status = "ready" if report["ok"] else "blocked"
    db.x("""UPDATE content SET topic=?, pillar=?, hook=?, headline=?, caption=?, hashtags=?, cta=?, body=?, image_concept=?,
            sources=?, research_ids=?, fingerprint=?, quality_report=?, block_reason=?, status=?, generated_by=?, updated_at=? WHERE id=?""",
         (rec["topic"], rec["pillar"], rec["hook"], rec["headline"], rec["caption"], json.dumps(rec["hashtags"]), rec["cta"],
          json.dumps(body), rec["image_concept"], rec["sources"], rec["research_ids"], report["fingerprint"],
          json.dumps(report), "; ".join(report["blocks"]) or None, status, provider.name, iso(), cid))
    research.mark_used(db, item["id"])
    if status == "blocked":
        log.warning("content %s blocked: %s", cid, report["blocks"])
        notify(s, db, "warning", "blocked", f"Post blocked before publishing ({content['platform']} {content['format']})",
               f"{content.get('scheduled_at')}: " + "; ".join(report["blocks"]))
    return {"id": cid, "status": status, "report": report}


def generate_due(s, db: DB, provider, limit: int = 6, link_checker=None) -> dict:
    """Fill planned slots inside the generate-ahead window, soonest first. Blocked posts are retried once with a new topic."""
    horizon = utcnow() + timedelta(days=int(s.get("calendar.generate_ahead_days", 10)))
    rows = db.q("SELECT * FROM content WHERE status='planned' AND scheduled_at <= ? AND scheduled_at > ? ORDER BY scheduled_at LIMIT ?",
                (iso(horizon), iso(utcnow()), limit))
    done, errors = [], []
    for r in rows:
        try:
            res = generate_one(s, db, provider, dict(r), link_checker)
            if res["status"] == "blocked" and not db.kv_get(f"regen:{r['id']}"):
                db.kv_set(f"regen:{r['id']}", True)
                db.x("UPDATE content SET status='planned', research_ids=NULL WHERE id=?", (r["id"],))
                res = generate_one(s, db, provider, dict(db.one("SELECT * FROM content WHERE id=?", (r["id"],))), link_checker)
            done.append(res["status"])
        except ProviderUnavailable as e:
            errors.append(str(e))
            break  # budget/limit: stop for now, buffer keeps publishing
        except Exception as e:
            log.exception("generation failed for %s", r["id"])
            errors.append(f"{r['id']}: {e}")
    return {"generated": len(done), "ready": done.count("ready"), "blocked": done.count("blocked"), "errors": errors}


def import_inbox(s, db: DB) -> dict:
    """Inbox mode: a Claude Code cloud routine commits JSON posts into inbox/*.json; fill matching planned slots."""
    inbox = s.resolve(s.get("ai.inbox_dir", "inbox"))
    if not inbox.exists():
        return {"imported": 0}
    imported, rejected = 0, []
    done_dir = inbox / "imported"
    done_dir.mkdir(exist_ok=True)
    for f in sorted(inbox.glob("*.json")):
        try:
            posts = json.loads(f.read_text())
            posts = posts if isinstance(posts, list) else [posts]
            for p in posts:
                row = db.one("SELECT * FROM content WHERE status='planned' AND platform=? AND format=? AND scheduled_at > ? ORDER BY scheduled_at LIMIT 1",
                             (p.get("platform"), p.get("format"), iso(utcnow())))
                if not row:
                    rejected.append(f"{f.name}: no open {p.get('platform')}/{p.get('format')} slot")
                    continue
                body = {k: p[k] for k in BODY_KEYS if k in p}
                rec = {**dict(row), **{k: p.get(k) for k in ("topic", "pillar", "hook", "headline", "caption", "cta", "image_concept")},
                       "hashtags": p.get("hashtags", []), "body": body, "sources": json.dumps(p.get("sources", []))}
                rep = quality.check(s, db, rec)
                status = "blocked"
                if rep["ok"]:
                    render.produce(s, db, {**rec, "body": json.dumps(body)})
                    body = json.loads(db.one("SELECT body FROM content WHERE id=?", (row["id"],))[0] or "{}")
                    status = "ready"
                db.x("""UPDATE content SET topic=?, pillar=?, hook=?, headline=?, caption=?, hashtags=?, cta=?, body=?, sources=?,
                        fingerprint=?, quality_report=?, block_reason=?, status=?, generated_by='inbox', updated_at=? WHERE id=?""",
                     (rec["topic"], rec["pillar"], rec["hook"], rec["headline"], rec["caption"], json.dumps(rep["hashtags"]), rec["cta"],
                      json.dumps(body), rec["sources"], rep["fingerprint"], json.dumps(rep), "; ".join(rep["blocks"]) or None,
                      status, iso(), row["id"]))
                imported += 1
            f.rename(done_dir / f.name)
        except Exception as e:
            rejected.append(f"{f.name}: {e}")
    return {"imported": imported, "rejected": rejected}


def refresh_queue(s, db: DB, provider, rewrite: bool = True, max_n: int | None = None, say=print) -> dict:
    """User-requested overhaul of everything already scheduled: rewrite with the current prompts (archetypes, keywords)
    and re-render with the current design + music. Posts the cloud has already started publishing are left alone.
    This explicit run ignores the daily AI budget (it's the user's call); the regular worker still respects it."""
    from autopilot import cloud
    started = set()
    if cloud.enabled(s) and (cloud.repo_dir(s) / "state").exists():
        started = {p.stem for p in (cloud.repo_dir(s) / "state").glob("*.json")}
    cutoff = iso(utcnow() + timedelta(minutes=45))
    rows = db.q("""SELECT * FROM content WHERE status IN ('ready','blocked','draft','failed') AND scheduled_at > ?
                   ORDER BY scheduled_at""", (cutoff,))
    rows = [dict(r) for r in rows if r["id"] not in started][: max_n or None]
    provider.ignore_budget = True
    out = {"rewritten": 0, "rerendered": 0, "blocked": 0, "errors": []}
    for i, c in enumerate(rows, 1):
        when = c["scheduled_at"][:16].replace("T", " ")
        try:
            if rewrite:
                with db.tx() as t:   # claim it so the background worker can't pick it up mid-rewrite
                    ok = t.execute("UPDATE content SET status='generating', updated_at=? WHERE id=? AND status IN ('ready','blocked','draft','failed')",
                                   (iso(), c["id"])).rowcount
                if not ok:
                    continue
                body = json.loads(c["body"] or "{}")
                body.pop("style", None)
                db.x("UPDATE content SET body=? WHERE id=?", (json.dumps(body), c["id"]))
                res = generate_one(s, db, provider, {**c, "status": "generating", "body": json.dumps(body)})
                out["rewritten"] += 1
                out["blocked"] += res["status"] == "blocked"
                say(f"[{i}/{len(rows)}] {when} {c['platform']} {c['format']}: {res['status']}")
            elif c["status"] == "ready":
                render.produce(s, db, c)
                out["rerendered"] += 1
                say(f"[{i}/{len(rows)}] {when} {c['platform']} {c['format']}: re-rendered")
        except ProviderUnavailable as e:
            db.x("UPDATE content SET status='ready' WHERE id=? AND status='generating'", (c["id"],))
            out["errors"].append(str(e))
            say(f"stopped: {e}")
            break
        except Exception as e:
            db.x("UPDATE content SET status=? WHERE id=? AND status='generating'", (c["status"], c["id"]))
            out["errors"].append(f"{c['id']}: {e}")
            say(f"[{i}/{len(rows)}] {when}: error {e}")
    provider.ignore_budget = False
    if cloud.enabled(s):
        out["cloud"] = cloud.sync(s, db)
    return out
