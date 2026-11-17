"""Calendar: rolling queue of slots in the account's time zone (DST-safe), idempotent planning."""
from __future__ import annotations

import hashlib
import json
import uuid
from datetime import date, datetime, time, timedelta, timezone

from autopilot.config import DAYS
from autopilot.db import DB, iso, utcnow


def local_to_utc(d: date, hhmm: str, tz) -> datetime:
    h, m = map(int, hhmm.split(":"))
    naive = datetime.combine(d, time(h, m))
    aware = naive.replace(tzinfo=tz, fold=0)
    # Non-existent local times (spring-forward gap) are normalised by a UTC round-trip (moves forward one hour).
    roundtrip = aware.astimezone(timezone.utc).astimezone(tz)
    if roundtrip.replace(tzinfo=None) != naive:
        aware = roundtrip
    return aware.astimezone(timezone.utc).replace(microsecond=0)


def slot_time(s, db: DB, slot: dict) -> str:
    overrides = db.kv_get("slot_overrides", {}) or {}
    return overrides.get(f"{slot['platform']}|{slot['format']}|{slot['time']}", slot["time"])


def planned_slots(s, db: DB, start: date, days: int) -> list[dict]:
    tz = s.tz
    gap = timedelta(minutes=int(s.get("calendar.min_gap_minutes", 90)))
    out = []
    for i in range(days):
        d = start + timedelta(days=i)
        dname = DAYS[d.weekday()]
        todays = []
        for slot in s.get("calendar.slots", []):
            if dname in slot.get("days", []):
                hhmm = slot_time(s, db, slot)
                key = f"{slot['platform']}|{slot['format']}|{d.isoformat()}|{slot['time']}"
                # ~15% of Instagram slots explore ±60 min so the optimizer can compare posting windows
                if s.get("calendar.explore_times", True) and slot["platform"] == "instagram" and slot["format"] != "story":
                    hv = int(hashlib.md5(key.encode()).hexdigest(), 16)
                    if hv % 100 < 15:
                        h, m = map(int, hhmm.split(":"))
                        h = max(6, min(22, h + (1 if hv % 2 else -1)))
                        hhmm = f"{h:02d}:{m:02d}"
                todays.append({"platform": slot["platform"], "format": slot["format"], "local_date": d.isoformat(),
                               "base_time": slot["time"], "utc": local_to_utc(d, hhmm, tz)})
        todays.sort(key=lambda x: x["utc"])
        last_by_platform: dict[str, datetime] = {}
        for t in todays:
            prev = last_by_platform.get(t["platform"])
            if prev and t["utc"] - prev < gap and t["format"] != "story":
                t["utc"] = prev + gap
            last_by_platform[t["platform"]] = t["utc"]
            t["slot_key"] = f"{t['platform']}|{t['format']}|{t['local_date']}|{t['base_time']}"
            out.append(t)
    return out


def start_date(s) -> date:
    sd = s.get("calendar.start_date", "")
    today_local = utcnow().astimezone(s.tz).date()
    if sd:
        return max(date.fromisoformat(sd), today_local)
    return today_local + timedelta(days=1)


def plan(s, db: DB) -> dict:
    """Ensure every slot in the rolling horizon has a content row. Idempotent via UNIQUE(slot_key)."""
    st = start_date(s)
    horizon = int(s.get("calendar.horizon_days", 30))
    created = 0
    now = utcnow()
    for t in planned_slots(s, db, st, horizon):
        if t["utc"] <= now:
            continue
        with db.tx() as c:
            created += c.execute("""INSERT OR IGNORE INTO content(id,platform,format,status,scheduled_at,slot_key,created_at,updated_at)
                                    VALUES(?,?,?,'planned',?,?,?,?)""",
                                 (str(uuid.uuid4()), t["platform"], t["format"], iso(t["utc"]), t["slot_key"], iso(), iso())).rowcount
    return {"start": st.isoformat(), "horizon_days": horizon, "created": created}


def go_live_reset(s, db: DB, start: date) -> dict:
    """At activation: simulated posts stop counting as published, nothing before the first posting date goes out,
    and the queue is planned from that date. Already-written posts on/after the date are kept."""
    cutoff = local_to_utc(start, "00:00", s.tz)
    with db.tx() as c:
        sim = c.execute("UPDATE content SET status='simulated', updated_at=? WHERE status='published' AND platform_post_id LIKE 'sim_%'",
                        (iso(),)).rowcount
        dropped = c.execute("""UPDATE content SET status='cancelled', block_reason='before first posting date', updated_at=?
                               WHERE status IN ('planned','generating','draft','ready','blocked','failed','manual_due') AND scheduled_at < ?""",
                            (iso(), iso(cutoff))).rowcount
    res = plan(s, db)
    return {"simulated_archived": sim, "cancelled_before_start": dropped, "planned": res["created"], "start": start.isoformat()}


def rebuild(s, db: DB) -> dict:
    """Drop future slots that have no content yet and re-plan (e.g. after changing slot settings)."""
    with db.tx() as c:
        n = c.execute("DELETE FROM content WHERE status='planned' AND scheduled_at > ?", (iso(),)).rowcount
    res = plan(s, db)
    res["removed"] = n
    return res


def reschedule(db: DB, content_id: str, new_utc: datetime) -> None:
    db.x("UPDATE content SET scheduled_at=?, updated_at=? WHERE id=? AND status IN ('planned','draft','ready','blocked','failed','manual_due')",
         (iso(new_utc), iso(), content_id))


def apply_trends(s, db: DB, notify_fn=None) -> list[str]:
    """Event-driven content: a fresh, verified, highly relevant item takes over the next open Instagram slot in 72h."""
    used = []
    items = db.q("""SELECT * FROM research_items WHERE kind IN ('news','conversation') AND relevance >= 0.85
                    AND verification IN ('verified','not_applicable') AND last_used_at IS NULL AND researched_at >= ?
                    ORDER BY relevance DESC LIMIT 3""", (iso(utcnow() - timedelta(days=2)),))
    for it in items:
        slot = db.one("""SELECT id, scheduled_at FROM content WHERE status='planned' AND platform='instagram' AND format IN ('image','carousel','reel')
                         AND research_ids IS NULL AND scheduled_at BETWEEN ? AND ? ORDER BY scheduled_at LIMIT 1""",
                      (iso(utcnow() + timedelta(hours=3)), iso(utcnow() + timedelta(hours=72))))
        if not slot:
            break
        db.x("UPDATE content SET research_ids=?, updated_at=? WHERE id=?", (json.dumps([it["id"]]), iso(), slot["id"]))
        db.x("UPDATE research_items SET last_used_at=? WHERE id=?", (iso(), it["id"]))
        used.append(it["title"])
        if notify_fn:
            notify_fn("info", "trend", "Trend picked up", f"'{it['title']}' will be covered in the post at {slot['scheduled_at']} UTC")
    return used


def queue_health(s, db: DB) -> dict:
    now = utcnow()
    week = iso(now + timedelta(days=7))
    counts = {r[0]: r[1] for r in db.q("SELECT status, COUNT(*) FROM content WHERE scheduled_at > ? GROUP BY status", (iso(now),))}
    ready_week = db.one("SELECT COUNT(*) FROM content WHERE status='ready' AND scheduled_at BETWEEN ? AND ?", (iso(now), week))[0]
    total_week = db.one("SELECT COUNT(*) FROM content WHERE scheduled_at BETWEEN ? AND ? AND status NOT IN ('cancelled')", (iso(now), week))[0]
    days_ready = 0
    d = now
    for _ in range(60):
        nxt = d + timedelta(days=1)
        tot = db.one("SELECT COUNT(*) FROM content WHERE scheduled_at BETWEEN ? AND ? AND platform='instagram' AND status NOT IN ('cancelled','skipped')", (iso(d), iso(nxt)))[0]
        rdy = db.one("SELECT COUNT(*) FROM content WHERE scheduled_at BETWEEN ? AND ? AND platform='instagram' AND status IN ('ready','published')", (iso(d), iso(nxt)))[0]
        if rdy < tot:
            break
        if tot == 0 and not db.one("SELECT 1 FROM content WHERE scheduled_at > ? AND platform='instagram' AND status NOT IN ('cancelled','skipped') LIMIT 1", (iso(nxt),)):
            break   # nothing planned beyond this point
        days_ready += 1
        d = nxt
    state = "healthy" if days_ready >= 3 else ("thin" if days_ready >= 1 else "empty")
    return {"by_status": counts, "ready_next_7d": ready_week, "slots_next_7d": total_week, "days_fully_ready": days_ready, "state": state}
