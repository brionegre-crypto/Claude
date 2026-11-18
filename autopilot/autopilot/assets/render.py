"""Zero-cost asset production: Pillow for graphics, FFmpeg for Reels. Everything is generated locally from text,
bundled OFL fonts (Inter) and brand colours, so every asset is original and license-clean. Reel audio is an original
ambient pad synthesized by FFmpeg's lavfi sine generators (no samples, no third-party music)."""
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from autopilot.db import DB, iso

FONTS = Path(__file__).parent / "fonts"
SIZES = {"post": (1080, 1350), "story": (1080, 1920), "square": (1080, 1080)}


def font(weight: str, size: int):
    return ImageFont.truetype(str(FONTS / f"Inter-{weight}.otf"), size)


def wrap(draw, text, fnt, width):
    lines, cur = [], ""
    for word in text.split():
        trial = (cur + " " + word).strip()
        if draw.textlength(trial, font=fnt) <= width:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def fit(draw, text, weight, max_size, min_size, width, max_height, spacing=1.18):
    size = max_size
    while size >= min_size:
        f = font(weight, size)
        lines = wrap(draw, text, f, width)
        h = len(lines) * size * spacing
        if h <= max_height:
            return f, lines, size
        size -= 4
    f = font(weight, min_size)
    return f, wrap(draw, text, f, width), min_size


def slide(colors: dict, size, title: str, text: str = "", index: int | None = None, total: int | None = None,
          handle: str = "", kicker: str = "") -> Image.Image:
    W, H = size
    img = Image.new("RGB", size, colors.get("bg", "#0B0B0C"))
    d = ImageDraw.Draw(img)
    pad = int(W * 0.09)
    accent, fg, panel = colors.get("accent", "#E18B1F"), colors.get("text", "#F2EEE6"), colors.get("panel", "#141416")
    d.rectangle([0, 0, W, int(H * 0.012)], fill=accent)
    d.rectangle([pad, H - int(H * 0.16), W - pad, H - int(H * 0.16) + 3], fill=panel)
    y = int(H * 0.16) if size[1] > size[0] else int(H * 0.12)
    if kicker:
        d.text((pad, y - 70), kicker.upper(), font=font("SemiBold", 30), fill=accent)
    tf, tlines, ts = fit(d, title, "Bold", 96, 48, W - 2 * pad, H * 0.36)
    for line in tlines:
        d.text((pad, y), line, font=tf, fill=fg)
        y += int(ts * 1.18)
    y += 40
    d.rectangle([pad, y, pad + 120, y + 8], fill=accent)
    y += 50
    if text:
        bf, blines, bs = fit(d, text, "Regular", 52, 30, W - 2 * pad, H * 0.80 - y - H * 0.12)
        for line in blines:
            d.text((pad, y), line, font=bf, fill=fg)
            y += int(bs * 1.32)
    foot = font("SemiBold", 30)
    if handle:
        d.text((pad, H - int(H * 0.12)), "@" + handle.lstrip("@"), font=foot, fill=accent)
    if index and total and total > 1:
        label = f"{index}/{total}"
        d.text((W - pad - d.textlength(label, font=foot), H - int(H * 0.12)), label, font=foot, fill=fg)
    return img


def _save(img: Image.Image, path: Path) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "JPEG", quality=92, optimize=True)  # Instagram's API only accepts JPEG images
    return {"path": str(path), "width": img.width, "height": img.height,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def ffmpeg() -> str | None:
    return shutil.which("ffmpeg")


def render_reel(colors, beats: list[dict], handle: str, out_dir: Path, name: str) -> list[dict]:
    if not ffmpeg():
        raise RuntimeError("ffmpeg not installed: required for Reels")
    out_dir.mkdir(parents=True, exist_ok=True)
    frames, durs = [], []
    for i, b in enumerate(beats):
        img = slide(colors, SIZES["story"], b.get("text", ""), "", handle=handle)
        p = out_dir / f"{name}-beat{i:02d}.jpg"
        img.save(p, "JPEG", quality=90)
        frames.append(p)
        durs.append(max(1.5, min(8.0, float(b.get("seconds", 3)))))
    total = sum(durs)
    video = out_dir / f"{name}.mp4"
    inputs, filters = [], []
    for i, (p, dur) in enumerate(zip(frames, durs)):
        inputs += ["-loop", "1", "-t", f"{dur}", "-i", str(p)]
        filters.append(f"[{i}:v]scale=1080:1920,setsar=1,fps=30,format=yuv420p,"
                       f"zoompan=z='min(zoom+0.0006,1.06)':d={int(dur*30)}:s=1080x1920:fps=30,"
                       f"fade=t=in:st=0:d=0.3,fade=t=out:st={dur-0.3:.2f}:d=0.3[v{i}]")
    concat = "".join(f"[v{i}]" for i in range(len(frames))) + f"concat=n={len(frames)}:v=1:a=0[vout]"
    # original ambient pad: A minor-ish triad of sines with slow tremolo, low volume
    audio = (f"sine=f=220:d={total},volume=0.05[a1];sine=f=261.63:d={total},volume=0.035[a2];"
             f"sine=f=329.63:d={total},volume=0.03[a3];[a1][a2][a3]amix=inputs=3,tremolo=f=0.25:d=0.4,"
             f"afade=t=in:d=1,afade=t=out:st={max(total-1.5,0):.2f}:d=1.5[aout]")
    cmd = ["ffmpeg", "-y", "-loglevel", "error", *inputs, "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
           "-filter_complex", ";".join(filters) + ";" + concat + ";" + audio.replace("[a1]", "[a1]", 1),
           "-map", "[vout]", "-map", "[aout]", "-c:v", "libx264", "-preset", "veryfast", "-profile:v", "high",
           "-pix_fmt", "yuv420p", "-r", "30", "-c:a", "aac", "-b:a", "128k", "-ar", "44100", "-movflags", "+faststart",
           "-t", f"{total}", str(video)]
    subprocess.run(cmd, check=True, capture_output=True, timeout=300)
    cover = out_dir / f"{name}-cover.jpg"
    shutil.copy(frames[0], cover)
    for p in frames[1:]:
        p.unlink(missing_ok=True)
    frames[0].unlink(missing_ok=True)
    return [{"kind": "video", "path": str(video), "width": 1080, "height": 1920, "duration": total,
             "sha256": hashlib.sha256(video.read_bytes()).hexdigest()},
            {"kind": "cover", "path": str(cover), "width": 1080, "height": 1920,
             "sha256": hashlib.sha256(cover.read_bytes()).hexdigest()}]


def produce(s, db: DB, content: dict) -> list[dict]:
    """Render all assets for a content record and store them in the assets table (replacing old ones)."""
    colors = s.get("brand.colors", {})
    handle = s.get("brand.handle_instagram", "")
    body = json.loads(content["body"] or "{}") if isinstance(content["body"], str) else (content["body"] or {})
    fmt = content["format"]
    out = s.assets_dir / content["id"]
    if out.exists():
        shutil.rmtree(out)
    made: list[dict] = []
    slides = body.get("slides", [])
    if fmt == "image":
        sl = slides[0] if slides else {"title": content.get("headline") or content["hook"], "text": ""}
        made.append({"kind": "image", **_save(slide(colors, SIZES["post"], sl["title"], sl.get("text", ""), handle=handle), out / "post.jpg")})
    elif fmt == "carousel":
        for i, sl in enumerate(slides[:10], 1):
            img = slide(colors, SIZES["post"], sl["title"], sl.get("text", ""), i, min(len(slides), 10), handle)
            made.append({"kind": "image", "ordinal": i, **_save(img, out / f"slide-{i:02d}.jpg")})
    elif fmt == "story":
        frames = body.get("frames", [])[:1] or [{"text": content["hook"]}]  # one story image per scheduled slot
        f0 = frames[0]
        made.append({"kind": "image", **_save(slide(colors, SIZES["story"], f0.get("text", ""), "", handle=handle), out / "story.jpg")})
        if ffmpeg():  # 6 s video version: Instagram accepts video Stories by direct upload, so no public URL is needed
            vid = render_reel(colors, [{"text": f0.get("text", ""), "seconds": 6}], handle, out, "story-video")
            made.append(vid[0])
    elif fmt == "reel":
        made += render_reel(colors, body.get("script", []), handle, out, "reel")
    elif fmt == "community_image":
        sl = slides[0] if slides else {"title": content["hook"], "text": ""}
        made.append({"kind": "image", **_save(slide(colors, SIZES["square"], sl["title"], sl.get("text", ""), handle=handle), out / "community.jpg")})
    elif fmt in ("community_poll", "community_quiz", "community_text"):
        pass  # text-only formats
    with db.tx() as c:
        c.execute("DELETE FROM assets WHERE content_id=?", (content["id"],))
        for i, a in enumerate(made):
            c.execute("INSERT INTO assets(content_id,kind,ordinal,path,width,height,duration,sha256,created_at) VALUES(?,?,?,?,?,?,?,?,?)",
                      (content["id"], a["kind"], a.get("ordinal", i), a["path"], a.get("width"), a.get("height"),
                       a.get("duration"), a.get("sha256"), iso()))
    return made
