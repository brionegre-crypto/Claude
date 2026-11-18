"""Asset production for each content record, using the design engine (design.py) and original music (music.py).

- image / carousel / community_image: designed slides in a rotating style, layout per slide
- reel: kinetic-type 9:16 video with an original soundtrack; cover = the moment the hook is fully on screen
- story: 9:16 still (fallback) + an ~8 s kinetic video with music (published by direct upload, no public URL needed)
The chosen style, music mood and Reel thumbnail offset are written back into content.body.
"""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image

from autopilot.assets import design, music
from autopilot.db import DB, iso

SIZES = {"post": (1080, 1350), "story": (1080, 1920), "square": (1080, 1080)}


def _save(img: Image.Image, path: Path) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(path, "JPEG", quality=92, optimize=True)  # Instagram's API only accepts JPEG images
    return {"path": str(path), "width": img.width, "height": img.height,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def ffmpeg() -> str | None:
    return shutil.which("ffmpeg")


def _vid(path: Path, w=1080, h=1920, duration=None) -> dict:
    return {"path": str(path), "width": w, "height": h, "duration": duration,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def recent_styles(db: DB, platform: str, exclude_id: str, n: int = 2) -> list[str]:
    out = []
    for r in db.q("""SELECT body FROM content WHERE platform=? AND id!=? AND body LIKE '%"style"%'
                     ORDER BY scheduled_at DESC LIMIT 12""", (platform, exclude_id)):
        st = (json.loads(r[0] or "{}") or {}).get("style")
        if st:
            out.append(st)
        if len(out) >= n:
            break
    return out


def label_for(content: dict, body: dict) -> str:
    return (body.get("label") or content.get("pillar") or "SYSTEM NOTES").split(":")[0][:28]


def produce(s, db: DB, content: dict) -> list[dict]:
    """Render all assets for a content record and store them in the assets table (replacing old ones)."""
    handle = s.get("brand.handle_instagram", "bethemansystem")
    body = json.loads(content["body"] or "{}") if isinstance(content["body"], str) else dict(content["body"] or {})
    fmt = content["format"]
    cid = content["id"]
    style = design.norm_style(body.get("style")) or design.pick_style(cid, recent_styles(db, content["platform"], cid))
    body["style"] = style
    label = label_for(content, body)
    stamp = ""
    if content.get("scheduled_at"):
        from datetime import datetime
        from zoneinfo import ZoneInfo
        dt = datetime.fromisoformat(content["scheduled_at"]).astimezone(ZoneInfo(s.get("general.timezone", "UTC")))
        stamp = f"{dt.day} {dt:%B %Y} at {dt:%H:%M}"
    out = s.assets_dir / cid
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    music_dir = s.data_dir / "music"
    made: list[dict] = []
    slides = design.legacy_layouts(body.get("slides") or [])

    if fmt in ("image", "community_image"):
        sl = slides[0] if slides else {"layout": "hook", "title": content.get("headline") or content.get("hook") or ""}
        if sl.get("layout") in (None, "point"):
            sl = {**sl, "layout": "hook"}
        size = SIZES["post"] if fmt == "image" else SIZES["square"]
        made.append({"kind": "image", **_save(design.slide(style, size, sl, label=label, seed=len(cid), stamp=stamp, handle=handle), out / "post.jpg")})
    elif fmt == "carousel":
        n = min(len(slides), 10)
        for i, sl in enumerate(slides[:10], 1):
            img = design.slide(style, SIZES["post"], sl, page=i, total=n, label=label, seed=i, stamp=stamp, handle=handle)
            made.append({"kind": "image", "ordinal": i, **_save(img, out / f"slide-{i:02d}.jpg")})
    elif fmt == "reel":
        mood = music.pick_mood(body.get("music_mood"), "reel", cid)
        body["music_mood"] = mood
        beats = body.get("script") or [{"text": content.get("hook") or "", "seconds": 3}]
        r = design.kinetic_video(style, beats, out, "reel", music.track_path(music_dir, mood), label=label, handle=handle,
                                 final_foot=body.get("end_button") or "COMMENT  STEP1  →", seed=len(cid))
        body["thumb_offset_ms"] = r["thumb_offset_ms"]
        made.append({"kind": "video", **_vid(r["video"], duration=r["duration"])})
        made.append({"kind": "cover", **_vid(r["cover"])})
    elif fmt == "story":
        frames = body.get("frames") or [{"text": content.get("hook") or ""}]
        first = frames[0].get("text", "")
        still = design.slide(style, SIZES["story"], {"layout": "hook", "title": first, "text": body.get("reply_prompt") or ""},
                             label=label, story=True, seed=len(cid), stamp=stamp, handle=handle)
        made.append({"kind": "image", **_save(still, out / "story.jpg")})
        if ffmpeg():
            mood = music.pick_mood(body.get("music_mood"), "story", cid)
            body["music_mood"] = mood
            beats = [{"text": f.get("text", ""), "seconds": max(2.5, 8.0 / max(1, len(frames[:3])))} for f in frames[:3]]
            r = design.kinetic_video(style, beats, out, "story-video", music.track_path(music_dir, mood), label=label,
                                     handle=handle, final_foot=body.get("reply_button") or "REPLY  “STEP1”", seed=len(cid))
            made.append({"kind": "video", "ordinal": 1, **_vid(r["video"], duration=r["duration"])})
            Path(r["cover"]).unlink(missing_ok=True)
    # community_text / poll / quiz: text only

    with db.tx() as c:
        c.execute("DELETE FROM assets WHERE content_id=?", (cid,))
        for i, a in enumerate(made):
            c.execute("INSERT INTO assets(content_id,kind,ordinal,path,width,height,duration,sha256,created_at) VALUES(?,?,?,?,?,?,?,?,?)",
                      (cid, a["kind"], a.get("ordinal", i), a["path"], a.get("width"), a.get("height"),
                       a.get("duration"), a.get("sha256"), iso()))
        c.execute("UPDATE content SET body=? WHERE id=?", (json.dumps(body), cid))
    return made
