"""Analytics collection (only what the APIs return — nothing is estimated or invented) and optimization."""
from __future__ import annotations

import json
from collections import defaultdict
from datetime import timedelta

from autopilot import logs
from autopilot.ai import prompts
from autopilot.db import DB, iso, parse, utcnow
from autopilot.notify import notify

log = logs.get("analytics")


def collect(s, db: DB, pubs: dict) -> dict:
    out = {"posts": 0, "account": {}, "errors": []}
    after = utcnow() - timedelta(hours=int(s.get("analytics.collect_after_hours", 24)))
    rows = db.q("""SELECT * FROM content WHERE status='published' AND platform='instagram' AND platform_post_id NOT LIKE 'sim_%'
                   AND published_at <= ? AND published_at >= ?""", (iso(after), iso(utcnow() - timedelta(days=60))))
    for r in rows:
        try:
            m = pubs["instagram"].media_insights(r["platform_post_id"], r["format"])
            for k, v in m.items():
                db.x("INSERT INTO metrics(content_id,platform,platform_post_id,collected_at,metric,value) VALUES(?,?,?,?,?,?)",
                     (r["id"], "instagram", r["platform_post_id"], iso(), k, float(v)))
            out["posts"] += 1
        except Exception as e:
            out["errors"].append(f"{r['id']}: {e}")
    for plat, pub in pubs.items():
        try:
            acct = pub.account_insights() if hasattr(pub, "account_insights") else {}
            for k, v in acct.items():
                db.x("INSERT INTO account_metrics(platform,collected_at,metric,value) VALUES(?,?,?,?)", (plat, iso(), k, float(v)))
            out["account"][plat] = acct
        except Exception as e:
            out["errors"].append(f"{plat} account: {e}")
    return out


def latest_post_metrics(db: DB, since=None) -> list[dict]:
    q = """SELECT c.id, c.platform, c.format, c.pillar, c.topic, c.hook, c.scheduled_at, c.published_at, c.permalink, m.metric, m.value
           FROM content c JOIN metrics m ON m.content_id=c.id
           WHERE m.id IN (SELECT MAX(id) FROM metrics GROUP BY content_id, metric)"""
    args = ()
    if since:
        q += " AND c.published_at >= ?"
        args = (iso(since),)
    posts: dict[str, dict] = {}
    for r in db.q(q, args):
        p = posts.setdefault(r["id"], {k: r[k] for k in ("id", "platform", "format", "pillar", "topic", "hook", "scheduled_at", "published_at", "permalink")})
        p[r["metric"]] = r["value"]
    for p in posts.values():
        reach = p.get("reach") or p.get("views")
        inter = p.get("total_interactions")
        if inter is None:
            inter = sum(p.get(k, 0) for k in ("likes", "comments", "shares", "saved"))
        p["engagement_rate"] = round(inter / reach, 4) if reach else None
    return list(posts.values())


def aggregate(s, posts: list[dict]) -> dict:
    groups = {"format": defaultdict(list), "pillar": defaultdict(list), "hour": defaultdict(list), "weekday": defaultdict(list)}
    for p in posts:
        if p.get("engagement_rate") is None:
            continue
        local = parse(p["published_at"]).astimezone(s.tz)
        groups["format"][p["format"]].append(p)
        groups["pillar"][p.get("pillar") or "unknown"].append(p)
        groups["hour"][f"{local.hour:02d}:00"].append(p)
        groups["weekday"][local.strftime("%a")].append(p)
    agg = {}
    for g, d in groups.items():
        agg[g] = {k: {"posts": len(v), "avg_engagement_rate": round(sum(x["engagement_rate"] for x in v) / len(v), 4),
                      "avg_reach": round(sum((x.get("reach") or 0) for x in v) / len(v), 1)} for k, v in d.items()}
    ranked = sorted([p for p in posts if p.get("engagement_rate") is not None], key=lambda p: p["engagement_rate"], reverse=True)
    agg["top_posts"] = [{k: p.get(k) for k in ("hook", "format", "pillar", "engagement_rate", "reach", "permalink")} for p in ranked[:5]]
    agg["weak_posts"] = [{k: p.get(k) for k in ("hook", "format", "pillar", "engagement_rate", "reach")} for p in ranked[-5:]] if len(ranked) >= 10 else []
    agg["sample_size"] = len(ranked)
    return agg


def growth(db: DB, platform: str, metric: str, days: int) -> dict | None:
    rows = db.q("SELECT collected_at, value FROM account_metrics WHERE platform=? AND metric=? AND collected_at >= ? ORDER BY collected_at",
                (platform, metric, iso(utcnow() - timedelta(days=days))))
    if len(rows) < 2:
        return None
    return {"start": rows[0]["value"], "end": rows[-1]["value"], "change": rows[-1]["value"] - rows[0]["value"]}


def optimize(s, db: DB, provider=None) -> dict:
    """Data-driven adjustments, only when samples are big enough. Records reasoning for the dashboard."""
    posts = latest_post_metrics(db, utcnow() - timedelta(days=90))
    agg = aggregate(s, posts)
    changes = {"sample_size": agg["sample_size"]}
    if agg["sample_size"] < 8:
        changes["note"] = "Not enough published posts with metrics yet (need 8+). No changes made."
        db.kv_set("optimizer_last", changes)
        return changes
    pillars = agg["pillar"]
    overall = sum(v["avg_engagement_rate"] * v["posts"] for v in pillars.values()) / max(sum(v["posts"] for v in pillars.values()), 1)
    weights = {}
    for k, v in pillars.items():
        if v["posts"] >= 3 and overall:
            weights[k] = round(min(2.0, max(0.5, v["avg_engagement_rate"] / overall)), 2)
    db.kv_set("pillar_weights", weights)
    changes["pillar_weights"] = weights
    # posting time: move a slot to a better-performing hour only with >=4 posts in each bucket
    overrides = db.kv_get("slot_overrides", {}) or {}
    hours = agg["hour"]
    for slot in s.get("calendar.slots", []):
        if slot["platform"] != "instagram":
            continue
        base_h = f"{slot['time'][:2]}:00"
        best = max(((h, v) for h, v in hours.items() if v["posts"] >= 4), key=lambda x: x[1]["avg_engagement_rate"], default=None)
        if best and base_h in hours and hours[base_h]["posts"] >= 4 and best[0] != base_h \
                and best[1]["avg_engagement_rate"] > hours[base_h]["avg_engagement_rate"] * 1.15:
            overrides[f"{slot['platform']}|{slot['format']}|{slot['time']}"] = best[0][:2] + slot["time"][2:]
    db.kv_set("slot_overrides", overrides)
    changes["slot_overrides"] = overrides
    if provider:
        try:
            ins = provider.complete_json("insights", prompts.insights(s.brand_text(), agg))
            db.kv_set("learnings", str(ins.get("learnings_for_writers", ""))[:1500])
            changes["ai_summary"] = ins.get("summary")
            changes["recommendations"] = ins.get("recommendations", [])
        except Exception as e:
            changes["ai_summary"] = f"skipped: {e}"
    changes["at"] = iso()
    db.kv_set("optimizer_last", changes)
    return changes


def report(s, db: DB, kind: str = "weekly") -> str:
    days = 7 if kind == "weekly" else 30
    since = utcnow() - timedelta(days=days)
    posts = latest_post_metrics(db, since)
    agg = aggregate(s, posts)
    published = db.q("SELECT platform, format, COUNT(*) n FROM content WHERE status='published' AND published_at >= ? GROUP BY platform, format", (iso(since),))
    failed = db.one("SELECT COUNT(*) FROM content WHERE status IN ('failed_permanent','blocked','skipped') AND scheduled_at >= ?", (iso(since),))[0]
    manual = db.one("SELECT COUNT(*) FROM content WHERE status='manual_due' AND scheduled_at >= ?", (iso(since),))[0]
    lines = [f"# {kind.title()} report: {since.astimezone(s.tz):%b %d} – {utcnow().astimezone(s.tz):%b %d, %Y}", "",
             "## Published"]
    lines += [f"- {r['platform']} {r['format']}: {r['n']}" for r in published] or ["- nothing published"]
    lines += [f"- blocked/failed/skipped: {failed}", f"- YouTube posts waiting for you: {manual}", ""]
    for plat, metric in (("instagram", "followers_count"), ("youtube", "subscriber_count")):
        g = growth(db, plat, metric, days)
        lines.append(f"- {plat} {metric.replace('_', ' ')}: " + (f"{g['start']:.0f} → {g['end']:.0f} ({g['change']:+.0f})" if g else "not enough data"))
    lines += ["", f"## Performance (real API metrics, {agg['sample_size']} posts with data)"]
    if agg["sample_size"] == 0:
        lines.append("No metrics available yet. (Simulated posts and YouTube Community posts have no API metrics.)")
    else:
        for g in ("format", "pillar", "hour"):
            lines.append(f"### By {g}")
            for k, v in sorted(agg[g].items(), key=lambda kv: -kv[1]["avg_engagement_rate"]):
                lines.append(f"- {k}: {v['avg_engagement_rate']*100:.1f}% engagement, avg reach {v['avg_reach']:.0f} ({v['posts']} posts)")
        lines.append("### Top posts")
        lines += [f"- {p['engagement_rate']*100:.1f}% · {p['format']} · {p['hook']}" for p in agg["top_posts"]]
    opt = db.kv_get("optimizer_last")
    if opt:
        lines += ["", "## Optimizer", f"- {opt.get('note') or opt.get('ai_summary') or ''}"]
        lines += [f"- {r}" for r in opt.get("recommendations", [])]
    body = "\n".join(lines)
    db.x("INSERT INTO reports(kind,period_start,period_end,created_at,body) VALUES(?,?,?,?,?)", (kind, iso(since), iso(), iso(), body))
    notify(s, db, "info", "report", f"{kind.title()} report ready", body[:3500], external=True)
    return body
