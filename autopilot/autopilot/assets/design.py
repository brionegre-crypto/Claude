"""Design engine: four rotating visual styles × slide layouts, kinetic-type Reels and Story videos.

Everything is drawn locally with Pillow (fonts bundled: Inter Display, JetBrains Mono; OFL/Apache), so every asset is
original and license-clean. Markup inside text: *word* = accent treatment (style-specific), **word** = emphasis.

Styles
  ledger     charcoal + faint engineering grid, amber "marker" highlight behind accent words, mono system labels
  signal     full amber field, black type, accent words knocked out in black boxes, oversized outline numerals
  paper      warm cream with paper grain, black type, thick amber strokes under accent words
  spotlight  near-black with an off-centre amber glow and film grain, accent words in amber
Layouts: hook · point · list · quote · myth_truth · cta
"""
from __future__ import annotations

import math
import random
import re
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONTS = Path(__file__).parent / "fonts"
INK, CHAR, AMBER, DEEP, CREAM, MUTE = "#0B0B0C", "#141416", "#E18B1F", "#B8680F", "#F2EEE6", "#8C877E"
STYLES = ["ledger", "signal", "paper", "spotlight"]
LAYOUTS = ["hook", "point", "list", "quote", "myth_truth", "cta"]


@dataclass
class Palette:
    bg: str
    ink: str        # main text
    soft: str       # body text
    accent: str     # accent colour
    label: str      # mono labels
    on_accent: str  # text drawn on top of an accent box


PALETTES = {
    "ledger": Palette("#121214", CREAM, "#C9C4BA", AMBER, AMBER, INK),
    "signal": Palette(AMBER, INK, "#2A1C0B", INK, INK, AMBER),
    "paper": Palette("#F2EEE6", INK, "#3B3832", AMBER, DEEP, INK),
    "spotlight": Palette("#0B0B0C", CREAM, "#BDB8AE", AMBER, AMBER, INK),
}

_font_cache: dict = {}


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    files = {"black": "InterDisplay-Black.otf", "xbold": "InterDisplay-ExtraBold.otf", "semi": "InterDisplay-SemiBold.otf",
             "medium": "InterDisplay-Medium.otf", "body": "Inter-Regular.otf", "bodybold": "Inter-SemiBold.otf",
             "mono": "JetBrainsMono-Medium.ttf", "monobold": "JetBrainsMono-Bold.ttf"}
    key = (name, size)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(str(FONTS / files[name]), size)
    return _font_cache[key]


# ---------------------------------------------------------------------------------------------------- backgrounds
def background(style: str, size, seed: int = 0) -> Image.Image:
    W, H = size
    p = PALETTES[style]
    img = Image.new("RGB", size, p.bg)
    d = ImageDraw.Draw(img)
    if style == "ledger":
        step = 54
        for x in range(0, W, step):
            d.line([(x, 0), (x, H)], fill="#1C1C20", width=1)
        for y in range(0, H, step):
            d.line([(0, y), (W, y)], fill="#1C1C20", width=1)
        for x in range(0, W, step * 5):
            d.line([(x, 0), (x, H)], fill="#232328", width=2)
    elif style == "signal":
        # subtle diagonal sheen bands
        over = Image.new("L", size, 0)
        od = ImageDraw.Draw(over)
        for i in range(-H, W, 140):
            od.polygon([(i, 0), (i + 60, 0), (i + 60 + H, H), (i + H, H)], fill=10)
        img = Image.composite(Image.new("RGB", size, "#F09A2C"), img, over)
    elif style == "paper":
        grain = Image.effect_noise(size, 18).convert("L")
        img = Image.blend(img, Image.merge("RGB", [grain] * 3), 0.06)
        img = Image.blend(img, Image.new("RGB", size, "#EDE6D8"), 0.25)
    elif style == "spotlight":
        rnd = random.Random(seed)
        cx, cy = int(W * rnd.uniform(0.62, 0.9)), int(H * rnd.uniform(0.55, 0.85))
        glow = Image.new("L", size, 0)
        gd = ImageDraw.Draw(glow)
        r = int(max(W, H) * 0.55)
        gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=120)
        glow = glow.filter(ImageFilter.GaussianBlur(r // 2))
        img = Image.composite(Image.new("RGB", size, "#6B3A08"), img, glow)
        grain = Image.effect_noise(size, 30).convert("L")
        img = Image.blend(img, Image.merge("RGB", [grain] * 3), 0.05)
    return img


# ---------------------------------------------------------------------------------------------------- rich text
TOKEN = re.compile(r"(\*\*[^*]+\*\*|\*[^*]+\*|\S+)")


def parse(text: str) -> list[tuple[str, str]]:
    """'You *lack* three **decisions**' → [(word, style)] with style normal|accent|bold (multi-word spans split)."""
    out = []
    for m in TOKEN.finditer(text or ""):
        t = m.group(0)
        if t.startswith("**") and t.endswith("**") and len(t) > 4:
            out += [(w, "bold") for w in t[2:-2].split()]
        elif t.startswith("*") and t.endswith("*") and len(t) > 2:
            out += [(w, "accent") for w in t[1:-1].split()]
        else:
            w = t.replace("*", "")
            if out and re.fullmatch(r"[.,!?;:…’'\")\]]+", w):
                out[-1] = (out[-1][0] + w, out[-1][1])   # keep punctuation attached: "WHEN." not "WHEN ."
            else:
                out.append((w, "normal"))
    return out


def plain(text: str) -> str:
    return " ".join(w for w, _ in parse(text))


def wrap_tokens(tokens, fnt, width):
    lines, cur, cur_w = [], [], 0
    space = fnt.getlength(" ")
    for w, st in tokens:
        wl = fnt.getlength(w)
        if cur and cur_w + space + wl > width:
            lines.append(cur)
            cur, cur_w = [], 0
        cur_w += (space if cur else 0) + wl
        cur.append((w, st))
    if cur:
        lines.append(cur)
    return lines


def fit_tokens(tokens, face, max_size, min_size, width, max_h, leading=1.04, upper=False):
    if upper:
        tokens = [(w.upper(), s) for w, s in tokens]
    size = max_size
    while True:
        f = font(face, size)
        lines = wrap_tokens(tokens, f, width)
        h = len(lines) * size * leading
        if (h <= max_h and all(f.getlength(" ".join(w for w, _ in ln)) <= width for ln in lines)) or size <= min_size:
            return f, lines, size
        size -= 4


def draw_lines(img, style, x, y, lines, fnt, size, leading=1.04, color=None, align="left", box_w=None, reveal=None):
    """Draw wrapped token lines with the style's accent treatment. reveal = number of words visible (kinetic)."""
    p = PALETTES[style]
    d = ImageDraw.Draw(img)
    color = color or p.ink
    space = fnt.getlength(" ")
    asc, desc = fnt.getmetrics()
    shown = 0
    for line in lines:
        lw = fnt.getlength(" ".join(w for w, _ in line))
        cx = x + ((box_w - lw) / 2 if align == "center" and box_w else 0)
        for w, st in line:
            if reveal is not None and shown >= reveal:
                return y
            ww = fnt.getlength(w)
            fill = color
            if st == "accent":
                if style == "ledger":
                    pad = max(6, int(size * 0.12))
                    d.rectangle([cx - pad, y + size * 0.06, cx + ww + pad, y + size * 1.0], fill=p.accent)
                    fill = p.on_accent
                elif style == "signal":
                    pad = max(6, int(size * 0.12))
                    d.rectangle([cx - pad, y + size * 0.04, cx + ww + pad, y + size * 1.02], fill=INK)
                    fill = AMBER
                elif style == "paper":
                    th = max(6, size // 9)
                    d.rectangle([cx - 2, y + size * 0.86, cx + ww + 2, y + size * 0.86 + th], fill=p.accent)
                else:
                    fill = p.accent
            elif st == "bold" and style in ("ledger", "spotlight", "paper"):
                fill = p.ink
            d.text((cx, y), w, font=fnt, fill=fill)
            cx += ww + space + (max(6, int(size * 0.12)) if st == "accent" and style in ("ledger", "signal") else 0)
            shown += 1
        y += int(size * leading)
    return y


# ---------------------------------------------------------------------------------------------------- chrome
def mono_label(d, xy, text, style, size=26, color=None):
    d.text(xy, text.upper(), font=font("mono", size), fill=color or PALETTES[style].label)


def chrome(img, style, label, page=None, total=None, handle="bethemansystem", swipe=False, story=False):
    W, H = img.size
    p = PALETTES[style]
    d = ImageDraw.Draw(img)
    top = 120 if story else 72
    mono_label(d, (84, top), f"BE THE MAN // {label}", style, 24)
    if page and total and total > 1:
        t = f"{page:02d} / {total:02d}"
        d.text((W - 84 - font("mono", 24).getlength(t), top), t, font=font("mono", 24), fill=p.label)
        seg = (W - 168 - (total - 1) * 8) / total
        for i in range(total):
            x0 = 84 + i * (seg + 8)
            d.rectangle([x0, H - 64, x0 + seg, H - 60], fill=p.accent if i < page else _dim(p))
    hy = H - (250 if story else 118)
    hf = font("monobold", 26)
    d.text((W - 84 - hf.getlength("@" + handle), hy), "@" + handle, font=hf, fill=p.ink)
    if swipe:
        sf = font("monobold", 26)
        txt = "SWIPE  →"
        w = sf.getlength(txt) + 44
        d.rounded_rectangle([84, hy - 14, 84 + w, hy + 40], radius=27, outline=p.ink, width=3)
        d.text((106, hy - 2), txt, font=sf, fill=p.ink)


def _dim(p: Palette) -> str:
    return {"#121214": "#2A2A30", AMBER: "#B36A12", "#F2EEE6": "#D8D1C3", "#0B0B0C": "#2A2622"}.get(p.bg, MUTE)


def icon(d, kind, x, y, s, color, bg):
    if kind == "save":
        d.polygon([(x, y), (x + s * 0.72, y), (x + s * 0.72, y + s), (x + s * 0.36, y + s * 0.72), (x, y + s)], outline=color, width=5)
    elif kind == "send":
        d.polygon([(x, y + s * 0.45), (x + s, y), (x + s * 0.62, y + s), (x + s * 0.48, y + s * 0.58)], outline=color, width=5)
        d.line([(x + s * 0.48, y + s * 0.58), (x + s, y)], fill=color, width=5)
    elif kind == "comment":
        d.rounded_rectangle([x, y, x + s, y + s * 0.78], radius=int(s * 0.22), outline=color, width=5)
        d.polygon([(x + s * 0.22, y + s * 0.74), (x + s * 0.18, y + s), (x + s * 0.46, y + s * 0.76)], fill=color)
    elif kind == "check":
        d.rectangle([x, y, x + s, y + s], outline=color, width=5)
        d.line([(x + s * 0.2, y + s * 0.52), (x + s * 0.42, y + s * 0.74), (x + s * 0.82, y + s * 0.26)], fill=color, width=7)
    elif kind == "box":
        d.rectangle([x, y, x + s, y + s], outline=color, width=5)
    elif kind == "x":
        d.line([(x, y), (x + s, y + s)], fill=color, width=7)
        d.line([(x + s, y), (x, y + s)], fill=color, width=7)


# ---------------------------------------------------------------------------------------------------- slides
def slide(style: str, size, sl: dict, page=None, total=None, label="SYSTEM NOTES", seed=0, story=False) -> Image.Image:
    """Render one slide dict: {"layout","title","text","items","myth","truth","number","attribution"}."""
    W, H = size
    p = PALETTES[style]
    img = background(style, size, seed)
    d = ImageDraw.Draw(img)
    layout = sl.get("layout") or "point"
    M = 84
    inner = W - 2 * M
    top = 260 if story else 190
    bottom = H - (330 if story else 190)
    title = sl.get("title") or ""
    text = sl.get("text") or ""

    dry: dict = {}

    def content(img, y0):
        d = ImageDraw.Draw(img)
        if layout == "hook":
            f, lines, s_ = fit_tokens(parse(title), "black", 176 if not story else 184, 80, inner, (bottom - top) * 0.66, 0.96, upper=True)
            y = draw_lines(img, style, M, y0, lines, f, s_, 0.96)
            if text:
                bf, bl, bs = fit_tokens(parse(text), "medium", 54, 34, inner * 0.94, (bottom - top) * 0.26, 1.28)
                y = draw_lines(img, style, M, y + 46, bl, bf, bs, 1.28, color=p.soft)
            return y
        if layout == "point":
            f, lines, s_ = fit_tokens(parse(title), "xbold", 112, 60, inner * 0.96, (bottom - top) * 0.46, 1.0)
            y = draw_lines(img, style, M, y0, lines, f, s_, 1.0)
            if text:
                bf, bl, bs = fit_tokens(parse(text), "body", 54, 34, inner * 0.96, (bottom - top) * 0.36, 1.34)
                y = draw_lines(img, style, M, y + 40, bl, bf, bs, 1.34, color=p.soft)
            return y
        if layout == "list":
            f, lines, s_ = fit_tokens(parse(title), "xbold", 100, 56, inner, (bottom - top) * 0.24, 1.0)
            y = draw_lines(img, style, M, y0, lines, f, s_, 1.0) + 46
            items = sl.get("items") or [t for t in re.split(r"\s*[•\n;]\s*", text) if t][:6]
            room = ((bottom - top) * 0.7) / max(1, len(items))
            gap = 26 if dry.get("gap") is None else dry["gap"]
            for i, it in enumerate(items):
                ic = "check" if i < len(items) - 1 or len(items) == 1 else "box"
                bf, bl, bs = fit_tokens(parse(it), "semi", 58, 32, inner - 90, room - 18, 1.18)
                icon(d, ic, M, y + bs * 0.12, int(bs * 0.82), p.accent if style != "signal" else INK, p.bg)
                y = draw_lines(img, style, M + 90, y, bl, bf, bs, 1.18) + gap
            return y
        if layout == "quote":
            qf = font("black", 280)
            d.text((M - 12, y0 - 40), "“", font=qf, fill=p.accent if style != "signal" else INK)
            f, lines, s_ = fit_tokens(parse(title or text), "semi", 100, 50, inner, (bottom - top) * 0.6, 1.12)
            y = draw_lines(img, style, M, y0 + 200, lines, f, s_, 1.12)
            attr = sl.get("attribution") or (text if title else "")
            if attr:
                mono_label(d, (M, y + 34), "— " + plain(attr)[:60], style, 30)
                y += 80
            return y
        if layout == "cta":
            f, lines, s_ = fit_tokens(parse(title or "Save this for Sunday night."), "black", 140, 64, inner, (bottom - top) * 0.42, 0.96, upper=True)
            y = draw_lines(img, style, M, y0, lines, f, s_, 0.96) + 76
            rows = sl.get("items") or [text or "Comment *STEP1* for the free worksheet", "Save it for later", "Send it to a brother who needs it"]
            for i, r in enumerate(rows[:3]):
                icon(d, ["comment", "save", "send"][i % 3], M, y + 6, 54, p.accent if style != "signal" else INK, p.bg)
                bf, bl, bs = fit_tokens(parse(r), "semi", 52, 32, inner - 96, 150, 1.18)
                y = draw_lines(img, style, M + 96, y, bl, bf, bs, 1.18) + 40
            return y
        # myth_truth
        myth, truth = sl.get("myth") or title, sl.get("truth") or text
        mono_label(d, (M, y0), "MYTH", style, 36, MUTE if style != "signal" else "#5A3A10")
        mf, ml, ms = fit_tokens(parse(myth), "semi", 76, 42, inner, (bottom - top) * 0.26, 1.12)
        y = y0 + 70
        for line in ml:
            lw = mf.getlength(" ".join(w for w, _ in line))
            d.text((M, y), " ".join(w for w, _ in line), font=mf, fill=MUTE if style != "signal" else "#5A3A10")
            d.line([(M - 6, y + ms * 0.58), (M + lw + 6, y + ms * 0.58)], fill=p.accent if style != "signal" else INK, width=7)
            y += int(ms * 1.12)
        y += 50
        d.line([(M, y), (W - M, y)], fill=_dim(p), width=3)
        mono_label(d, (M, y + 46), "TRUTH", style, 36)
        tf, tl, ts = fit_tokens(parse(truth), "black", 112, 54, inner, (bottom - top) * 0.4, 1.0, upper=True)
        return draw_lines(img, style, M, y + 116, tl, tf, ts, 1.0)

    if layout == "point":   # oversized section number behind the content
        num = sl.get("number") or (f"{page - 1:02d}" if page and page > 1 else "01")
        nf = font("black", 360)
        nx = W - M - nf.getlength(num) + 24
        if style == "signal":
            d.text((nx, top - 80), num, font=nf, fill=None, stroke_width=4, stroke_fill=INK)
        else:
            d.text((nx, top - 80), num, font=nf, fill=_dim(p))
    if layout not in LAYOUTS:
        layout = "point"
    scratch = img.copy()
    end = content(scratch, 0)
    start = top + (290 if layout == "point" else 0)
    free = bottom - start - end
    if layout == "list" and free > 0:   # spread the checklist over the slide instead of bunching it at the top
        n = max(1, len(sl.get("items") or [1]))
        dry["gap"] = 26 + min(110, free * 0.6 / n)
        end = content(img.copy(), 0)
        free = bottom - start - end
    content(img, start + max(0, free * 0.5))
    chrome(img, style, label, page, total, swipe=(page == 1 and (total or 0) > 1), story=story)
    return img


def legacy_layouts(slides: list[dict]) -> list[dict]:
    """Older posts have plain {title,text} slides: give them sensible layouts."""
    out = []
    n = len(slides)
    for i, s in enumerate(slides):
        s = dict(s)
        if not s.get("layout"):
            low = (s.get("title", "") + " " + s.get("text", "")).lower()
            if i == 0:
                s["layout"] = "hook"
            elif i == n - 1 and any(k in low for k in ("step1", "comment", "save", "send", "share", "worksheet")):
                s["layout"] = "cta"
            else:
                s["layout"] = "point"
                s.setdefault("number", f"{i:02d}")
        out.append(s)
    return out


def pick_style(seed_text: str, recent: list[str]) -> str:
    """Rotate styles: never repeat the last two used; otherwise deterministic by content id."""
    options = [s for s in STYLES if s not in recent[:2]] or STYLES
    h = int(__import__("hashlib").md5(seed_text.encode()).hexdigest(), 16)
    return options[h % len(options)]


# ---------------------------------------------------------------------------------------------------- kinetic video
def _beat_frame(bg, style, size, tokens, visible, progress, label, handle, hook=False, foot=None, story=False):
    W, H = size
    p = PALETTES[style]
    img = bg.copy()
    d = ImageDraw.Draw(img)
    M = 84
    # progress bar across the top (Reels/Stories retention cue)
    d.rectangle([0, 0, W, 10], fill=_dim(p))
    d.rectangle([0, 0, int(W * progress), 10], fill=p.accent if style != "signal" else INK)
    mono_label(d, (M, 150), f"BE THE MAN // {label}", style, 30)
    top, bottom = 330, H - 520          # keep clear of Instagram's caption/UI overlay at the bottom
    face = "black" if hook else "xbold"
    f, lines, s = fit_tokens(tokens, face, 150 if hook else 120, 64, W - 2 * M, bottom - top, 1.0, upper=hook)
    th = len(lines) * s * 1.0
    y = top + (bottom - top - th) / 2
    draw_lines(img, style, M, y, lines, f, s, 1.0, reveal=visible)
    if foot:
        ff = font("monobold", 34)
        w = ff.getlength(foot) + 56
        d.rounded_rectangle([M, bottom + 60, M + w, bottom + 128], radius=34, fill=p.accent if style != "signal" else INK)
        d.text((M + 28, bottom + 76), foot, font=ff, fill=p.on_accent if style != "signal" else AMBER)
    hf = font("monobold", 30)
    d.text((W - M - hf.getlength("@" + handle), 150), "@" + handle, font=hf, fill=p.ink)
    return img


def kinetic_video(style: str, beats: list[dict], out_dir: Path, name: str, music_wav: Path | None, label="SYSTEM NOTES",
                  handle="bethemansystem", size=(1080, 1920), final_foot: str | None = None, seed: int = 0) -> dict:
    """Word-by-word kinetic type. Returns {"video","cover","duration","thumb_offset_ms"}."""
    import subprocess
    out_dir.mkdir(parents=True, exist_ok=True)
    bg = background(style, size, seed)
    beats = [b for b in beats if (b.get("text") or "").strip()] or [{"text": "Be the man.", "seconds": 3}]
    durs = [max(1.6, min(6.0, float(b.get("seconds", 3)))) for b in beats]
    total = sum(durs)
    frames, t, thumb_ms, cover = [], 0.0, 0, None
    for i, (b, dur) in enumerate(zip(beats, durs)):
        toks = parse(b["text"])
        n = len(toks)
        reveal_total = 0.35 if i == 0 else min(0.12 * n, 1.1)
        step = reveal_total / max(n, 1)
        foot = final_foot if i == len(beats) - 1 else None
        for k in range(1, n + 1):
            hold = step if k < n else max(0.3, dur - reveal_total + step)
            img = _beat_frame(bg, style, size, toks, k, (t + (k - 1) * step) / total, label, handle, hook=(i == 0),
                              foot=foot if k == n else None)
            path = out_dir / f"{name}-f{len(frames):03d}.jpg"
            img.save(path, "JPEG", quality=90)
            frames.append((path, hold))
            if i == 0 and k == n:
                thumb_ms = int((t + reveal_total + 0.05) * 1000)
                cover = out_dir / f"{name}-cover.jpg"
                img.save(cover, "JPEG", quality=92)
        t += dur
    lst = out_dir / f"{name}-frames.txt"
    lst.write_text("".join(f"file '{p.name}'\nduration {d:.3f}\n" for p, d in frames) + f"file '{frames[-1][0].name}'\n")
    video = out_dir / f"{name}.mp4"
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(lst)]
    if music_wav and Path(music_wav).exists():
        cmd += ["-i", str(music_wav), "-filter_complex",
                f"[0:v]fps=30,format=yuv420p[v];[1:a]atrim=0:{total:.2f},asetpts=PTS-STARTPTS,afade=t=in:d=0.25,"
                f"afade=t=out:st={max(total - 1.2, 0):.2f}:d=1.2,volume=0.85[a]", "-map", "[v]", "-map", "[a]",
                "-c:a", "aac", "-b:a", "160k", "-ar", "44100"]
    else:
        cmd += ["-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-filter_complex", "[0:v]fps=30,format=yuv420p[v]",
                "-map", "[v]", "-map", "1:a", "-c:a", "aac"]
    cmd += ["-t", f"{total:.2f}", "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p",
            "-movflags", "+faststart", str(video)]
    subprocess.run(cmd, check=True, capture_output=True, timeout=600, cwd=out_dir)
    for p, _ in frames:
        p.unlink(missing_ok=True)
    lst.unlink(missing_ok=True)
    return {"video": video, "cover": cover, "duration": total, "thumb_offset_ms": thumb_ms}
