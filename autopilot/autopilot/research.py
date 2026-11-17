"""Research engine: public RSS feeds (no scraping, no paid search APIs) + Claude evaluation and fact checks."""
from __future__ import annotations

import hashlib
import json
import random
from datetime import timedelta

import feedparser
import httpx

from autopilot import logs
from autopilot.ai import prompts
from autopilot.ai.provider import ProviderUnavailable
from autopilot.db import DB, iso, parse, utcnow

log = logs.get("research")
UA = "social-autopilot/1.0 (personal RSS reader)"


def _h(url: str) -> str:
    return hashlib.sha256(url.strip().lower().encode()).hexdigest()


def fetch_feed(url: str, client: httpx.Client, limit: int) -> list[dict]:
    r = client.get(url, headers={"User-Agent": UA}, timeout=20, follow_redirects=True)
    r.raise_for_status()
    feed = feedparser.parse(r.content)
    out = []
    for e in feed.entries[:limit]:
        published = None
        if getattr(e, "published_parsed", None):
            from datetime import datetime, timezone
            published = datetime(*e.published_parsed[:6], tzinfo=timezone.utc).isoformat()
        summary = (getattr(e, "summary", "") or "")
        import re
        summary = re.sub(r"<[^>]+>", " ", summary)
        summary = re.sub(r"\s+", " ", summary).strip()[:600]
        src = getattr(getattr(e, "source", None), "title", None) or feed.feed.get("title", url)
        out.append({"title": e.get("title", "").strip()[:300], "url": e.get("link", ""), "published_at": published,
                    "summary": summary, "source": src})
    return out


def seed_evergreen(s, db: DB) -> int:
    n = 0
    for t in s.get("research.evergreen_topics", []):
        key = _h("evergreen:" + t)
        if not db.one("SELECT 1 FROM research_items WHERE url_hash=?", (key,)):
            db.x("""INSERT INTO research_items(topic,title,source,url,url_hash,researched_at,relevance,kind,opportunities,verification)
                    VALUES(?,?,?,?,?,?,?,?,?,?)""",
                 (t, t, "brand evergreen list", None, key, iso(), 0.8, "evergreen", json.dumps([t]), "not_applicable"))
            n += 1
    return n


def collect(s, db: DB, client: httpx.Client | None = None) -> dict:
    client = client or httpx.Client()
    new, errors = 0, []
    for url in s.get("research.feeds", []):
        try:
            for it in fetch_feed(url, client, int(s.get("research.max_items_per_feed", 15))):
                if not it["url"] or not it["title"]:
                    continue
                key = _h(it["url"])
                if db.one("SELECT 1 FROM research_items WHERE url_hash=?", (key,)):
                    continue
                db.x("""INSERT INTO research_items(topic,title,source,url,url_hash,published_at,researched_at,summary,kind)
                        VALUES(?,?,?,?,?,?,?,?,?)""",
                     (it["title"], it["title"], it["source"], it["url"], key, it["published_at"], iso(), it["summary"],
                      "conversation" if "reddit.com" in url else "news"))
                new += 1
        except Exception as e:
            errors.append(f"{url}: {e}")
            log.warning("feed failed %s: %s", url, e)
    return {"new_items": new, "feed_errors": errors, "evergreen_added": seed_evergreen(s, db)}


def evaluate(s, db: DB, provider, batch: int = 15) -> dict:
    rows = db.q("SELECT id,title,summary,source,url,published_at FROM research_items WHERE kind!='evergreen' AND relevance=0 "
                "AND researched_at >= ? ORDER BY published_at DESC LIMIT ?", (iso(utcnow() - timedelta(days=14)), batch))
    if not rows:
        return {"evaluated": 0}
    items = [dict(r) for r in rows]
    data = provider.complete_json("research_eval", prompts.research_eval(s.brand_text(), items), web=False)
    n = 0
    valid = {r["id"] for r in rows}
    for it in data.get("items", []):
        if it.get("id") not in valid:
            continue
        ver = it.get("verification", "unverified")
        if ver not in ("verified", "disputed", "unverified", "not_applicable"):
            ver = "unverified"
        rel = max(0.01, min(1.0, float(it.get("relevance", 0.01))))
        db.x("""UPDATE research_items SET relevance=?, kind=?, topic=COALESCE(?,topic), opportunities=?, verification=?,
                verification_notes=? WHERE id=?""",
             (rel, it.get("kind", "news"), it.get("pillar") and f"{it.get('pillar')}: " + db.one("SELECT title FROM research_items WHERE id=?", (it["id"],))[0],
              json.dumps(it.get("opportunities", [])[:3]), ver, str(it.get("verification_notes", ""))[:1000], it["id"]))
        n += 1
    # items the model skipped get a floor score so they are not re-sent forever
    db.x(f"UPDATE research_items SET relevance=0.01 WHERE relevance=0 AND id IN ({','.join('?'*len(valid))})", tuple(valid))
    return {"evaluated": n}


def verify_top(s, db: DB, provider, n: int = 2) -> dict:
    """Real fact check (web tools) only for the best unverified candidates: keeps AI usage small."""
    rows = db.q("""SELECT id,title,summary,source,url,published_at FROM research_items WHERE kind IN ('news','conversation')
                   AND verification='unverified' AND relevance >= ? AND url IS NOT NULL AND researched_at >= ?
                   ORDER BY relevance DESC LIMIT ?""", (float(s.get("research.min_relevance", 0.55)), iso(utcnow() - timedelta(days=5)), n))
    done = []
    for r in rows:
        if r["source"] and "reddit" in (r["url"] or ""):
            db.x("UPDATE research_items SET verification='not_applicable', verification_notes='discussion thread: used as a question prompt, not as a fact' WHERE id=?", (r["id"],))
            continue
        d = provider.complete_json("research_verify", prompts.verify(s.get("brand.name", ""), dict(r)), web=True)
        ver = d.get("verification") if d.get("verification") in ("verified", "disputed", "unverified") else "unverified"
        notes = f"{d.get('claim', '')} | source: {d.get('source_url', '')} | corroborated by: {d.get('corroborating_url', '')} | {d.get('notes', '')}"
        db.x("UPDATE research_items SET verification=?, verification_notes=? WHERE id=?", (ver, notes[:1000], r["id"]))
        if ver != "verified":   # never retry the same item forever
            db.x("UPDATE research_items SET relevance=MIN(relevance, ?) WHERE id=?", (float(s.get("research.min_relevance", 0.55)) - 0.01, r["id"]))
        done.append({"id": r["id"], "verification": ver})
    return {"verified_checks": done}


def check_link(url: str, client: httpx.Client) -> bool:
    try:
        r = client.head(url, headers={"User-Agent": UA}, timeout=15, follow_redirects=True)
        if r.status_code in (403, 405):
            r = client.get(url, headers={"User-Agent": UA}, timeout=15, follow_redirects=True)
        return r.status_code < 400
    except Exception:
        return False


def run(s, db: DB, provider, client=None) -> dict:
    res = collect(s, db, client)
    try:
        res.update(evaluate(s, db, provider))
        res.update(verify_top(s, db, provider))
    except ProviderUnavailable as e:
        res["evaluation_skipped"] = str(e)
    return res


def pick_topic(s, db: DB, platform: str, fmt: str, pillar_weights: dict | None = None, rng=random) -> dict | None:
    """Balanced selection: ~40% timely verified items, ~60% evergreen; never reuse an item within 21 days,
    and never the same pillar twice in a row on a platform."""
    min_rel = float(s.get("research.min_relevance", 0.55))
    cutoff = iso(utcnow() - timedelta(days=21))
    timely = db.q("""SELECT * FROM research_items WHERE kind!='evergreen' AND relevance>=? AND verification IN ('verified','not_applicable')
                     AND (last_used_at IS NULL) AND researched_at >= ? ORDER BY relevance DESC LIMIT 20""",
                  (min_rel, iso(utcnow() - timedelta(days=10))))
    evergreen = db.q("SELECT * FROM research_items WHERE kind='evergreen' AND (last_used_at IS NULL OR last_used_at < ?) "
                     "ORDER BY used_count ASC, RANDOM() LIMIT 20", (cutoff,))
    last = db.one("SELECT pillar FROM content WHERE platform=? AND pillar IS NOT NULL ORDER BY created_at DESC LIMIT 1", (platform,))
    pool = list(timely) if (timely and rng.random() < 0.4) else list(evergreen) or list(timely)
    if not pool:
        pool = db.q("SELECT * FROM research_items WHERE kind='evergreen' ORDER BY used_count ASC, last_used_at ASC LIMIT 10")
    if not pool:
        return None
    weights = []
    for r in pool:
        w = float(r["relevance"] or 0.5)
        topic = r["topic"] or ""
        if pillar_weights:
            for p, pw in pillar_weights.items():
                if topic.lower().startswith(p.lower()):
                    w *= pw
        if last and last[0] and topic.lower().startswith(last[0].lower()):
            w *= 0.3
        weights.append(max(w, 0.01))
    choice = rng.choices(pool, weights=weights, k=1)[0]
    return dict(choice)


def mark_used(db: DB, rid: int) -> None:
    db.x("UPDATE research_items SET used_count=used_count+1, last_used_at=? WHERE id=?", (iso(), rid))
