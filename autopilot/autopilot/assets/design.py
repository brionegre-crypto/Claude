"""Design engine: style families × colour palettes × slide layouts (incl. infographics), plus kinetic-type video.

Everything is drawn locally with Pillow (bundled fonts: Inter Display, Inter, JetBrains Mono; emoji from the system's
colour-emoji font), so every asset is original and license-clean. Markup: *word* = accent, **word** = emphasis.

Families
  ledger     dark field + faint engineering grid, accent words in highlighter boxes, mono system labels
  signal     solid colour field with a soft sheen, accent words knocked out in boxes, outline numerals
  paper      light paper grain, thick underline strokes under accent words
  spotlight  near-black with an off-centre colour glow and film grain
  notes      a phone-notes screenshot look (light or dark): personal, lo-fi, emoji — reads like a note, not an ad
Layouts: hook · point · list · quote · myth_truth · cta · timeline · compare · matrix · tracker · scale
"""
from __future__ import annotations

import hashlib
import random
import re
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONTS = Path(__file__).parent / "fonts"
INK, AMBER, DEEP, CREAM, MUTE = "#0B0B0C", "#E18B1F", "#B8680F", "#F2EEE6", "#8C877E"
LAYOUTS = ["hook", "point", "list", "quote", "myth_truth", "cta", "timeline", "compare", "matrix", "tracker", "scale"]


@dataclass
class Palette:
    bg: str
    ink: str            # headline text
    soft: str           # body text
    accent: str         # accent colour (underline / glow text / bars)
    label: str          # mono labels
    box: str            # highlighter box behind accent words
    box_text: str       # text on the box
    icon: str           # icons, checkmarks, numerals
    dimc: str           # inactive progress, dividers, ghost numerals
    mute: str = MUTE    # struck-through "myth" text
    extra: dict = field(default_factory=dict)   # grid / sheen / glow colours


P = Palette
PALETTES = {
    "ledger-charcoal": P("#121214", CREAM, "#C9C4BA", AMBER, AMBER, AMBER, INK, AMBER, "#2A2A30", extra={"grid": "#1C1C20"}),
    "ledger-navy": P("#0F1A2E", "#F4F1EA", "#B9C2D3", "#F2A541", "#F2A541", "#F2A541", "#0F1A2E", "#F2A541", "#24324D", "#7D8AA3", {"grid": "#16233B"}),
    "signal-amber": P(AMBER, INK, "#2A1C0B", INK, INK, INK, AMBER, INK, "#B36A12", "#5A3A10", {"sheen": "#F09A2C"}),
    "signal-forest": P("#1F4D3A", "#F3EFE4", "#CFE0D4", "#F2C14E", "#F2C14E", "#F2C14E", "#1F4D3A", "#F2C14E", "#2E644E", "#86A896", {"sheen": "#245841"}),
    "signal-clay": P("#C4553B", "#FFF7EE", "#FBE3D6", "#1B1B1B", "#1B1B1B", "#1B1B1B", "#FFD9C7", "#1B1B1B", "#A84530", "#7A2F1F", {"sheen": "#CC6047"}),
    "signal-cobalt": P("#2547D0", "#FFFFFF", "#DCE3FF", "#FFD23F", "#FFD23F", "#FFD23F", "#2547D0", "#FFD23F", "#3A5BE0", "#9DB0F5", {"sheen": "#2A4ED8"}),
    "paper-cream": P("#F2EEE6", INK, "#3B3832", AMBER, DEEP, AMBER, INK, AMBER, "#D8D1C3", extra={"tint": "#EDE6D8"}),
    "paper-sage": P("#DCE5D3", "#18261C", "#34473A", "#2F6B4F", "#2F6B4F", "#2F6B4F", "#F3F6EF", "#2F6B4F", "#C3D0B8", "#7D8F80", {"tint": "#D5DFCB"}),
    "paper-blush": P("#F4E4DC", "#2B1A16", "#4F3A33", "#C4553B", "#C4553B", "#C4553B", "#FFF5EF", "#C4553B", "#E6CFC4", "#A08A82", {"tint": "#EFDCD2"}),
    "spotlight-amber": P("#0B0B0C", CREAM, "#BDB8AE", AMBER, AMBER, AMBER, INK, AMBER, "#2A2622", extra={"glow": "#6B3A08"}),
    "spotlight-teal": P("#071A1C", "#EAF6F4", "#A9C9C5", "#3FD0B5", "#3FD0B5", "#3FD0B5", "#071A1C", "#3FD0B5", "#16363A", "#5E807C", {"glow": "#0E4F4A"}),
    "spotlight-plum": P("#140B17", "#F6EEF7", "#CDB9D1", "#F2A541", "#F2A541", "#F2A541", "#140B17", "#F2A541", "#2E1D33", "#8C7491", {"glow": "#4A1E52"}),
    "notes-light": P("#FFFFFF", "#1C1C1E", "#1C1C1E", "#E0A500", "#8E8E93", "#FFE58A", "#1C1C1E", "#E0A500", "#E5E5EA", "#8E8E93"),
    "notes-dark": P("#000000", "#F2F2F7", "#E5E5EA", "#FFD60A", "#8E8E93", "#5C4A00", "#FFF5CC", "#FFD60A", "#2C2C2E", "#8E8E93", {"panel": "#1C1C1E"}),
}
STYLES = list(PALETTES)
FAMILIES = ["ledger", "signal", "paper", "spotlight", "notes"]


def fam(style: str) -> str:
    return style.split("-")[0]


def pal(style: str) -> Palette:
    return PALETTES.get(style) or PALETTES[{"ledger": "ledger-charcoal", "signal": "signal-amber", "paper": "paper-cream",
                                            "spotlight": "spotlight-amber", "notes": "notes-light"}.get(style, "ledger-charcoal")]


def norm_style(style: str | None) -> str | None:
    """Accept old family-only names ('signal') saved on earlier posts."""
    if not style:
        return None
    if style in PALETTES:
        return style
    return {"ledger": "ledger-charcoal", "signal": "signal-amber", "paper": "paper-cream", "spotlight": "spotlight-amber"}.get(style)


_font_cache: dict = {}


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    files = {"black": "InterDisplay-Black.otf", "xbold": "InterDisplay-ExtraBold.otf", "semi": "InterDisplay-SemiBold.otf",
             "medium": "InterDisplay-Medium.otf", "body": "Inter-Regular.otf", "bodybold": "Inter-SemiBold.otf",
             "bold": "Inter-Bold.otf", "mono": "JetBrainsMono-Medium.ttf", "monobold": "JetBrainsMono-Bold.ttf"}
    key = (name, size)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(str(FONTS / files[name]), size)
    return _font_cache[key]


# ---------------------------------------------------------------------------------------------------- emoji
EMOJI_RE = re.compile("[\U0001F000-\U0001FAFF☀-➿⬀-⯿️‍]+")
_EMOJI_FONTS = [("/System/Library/Fonts/Apple Color Emoji.ttc", 160), ("/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf", 109)]
_emoji_font = None


def _efont():
    global _emoji_font
    if _emoji_font is None:
        _emoji_font = False
        for path, size in _EMOJI_FONTS:
            if Path(path).exists():
                try:
                    _emoji_font = ImageFont.truetype(path, size)
                    break
                except OSError:
                    continue
    return _emoji_font or None


def emoji_width(text: str, size: int) -> float:
    return sum(size * 1.12 for _ in EMOJI_RE.findall(text))


def text_width(fnt, text: str) -> float:
    return fnt.getlength(EMOJI_RE.sub("", text)) + emoji_width(text, fnt.size)


def draw_text(img, xy, text, fnt, fill):
    """Draw text that may contain emoji (rendered from the system colour-emoji font, scaled to the text size)."""
    x, y = xy
    d = ImageDraw.Draw(img)
    for part in re.split(f"({EMOJI_RE.pattern})", text):
        if not part:
            continue
        if EMOJI_RE.fullmatch(part):
            ef = _efont()
            if ef:
                glyph = part.replace("‍", "").replace("️", "")[:1]
                tile = Image.new("RGBA", (int(ef.size * 1.4), int(ef.size * 1.4)), (0, 0, 0, 0))
                ImageDraw.Draw(tile).text((0, 0), glyph, font=ef, embedded_color=True)
                bb = tile.getbbox()
                if bb:
                    tile = tile.crop(bb)
                    h = int(fnt.size * 0.95)
                    tile = tile.resize((max(1, int(tile.width * h / tile.height)), h), Image.LANCZOS)
                    img.paste(tile, (int(x + fnt.size * 0.06), int(y + fnt.size * 0.12)), tile)
            x += fnt.size * 1.12
        else:
            d.text((x, y), part, font=fnt, fill=fill)
            x += fnt.getlength(part)
    return x


# ---------------------------------------------------------------------------------------------------- backgrounds
def background(style: str, size, seed: int = 0) -> Image.Image:
    W, H = size
    p = pal(style)
    f = fam(style)
    img = Image.new("RGB", size, p.bg)
    d = ImageDraw.Draw(img)
    if f == "ledger":
        step = 54
        for x in range(0, W, step):
            d.line([(x, 0), (x, H)], fill=p.extra["grid"], width=1)
        for y in range(0, H, step):
            d.line([(0, y), (W, y)], fill=p.extra["grid"], width=1)
        for x in range(0, W, step * 5):
            d.line([(x, 0), (x, H)], fill=p.dimc, width=2)
    elif f == "signal":
        over = Image.new("L", size, 0)
        od = ImageDraw.Draw(over)
        for i in range(-H, W, 140):
            od.polygon([(i, 0), (i + 60, 0), (i + 60 + H, H), (i + H, H)], fill=14)
        img = Image.composite(Image.new("RGB", size, p.extra["sheen"]), img, over)
    elif f == "paper":
        grain = Image.effect_noise(size, 18).convert("L")
        img = Image.blend(img, Image.merge("RGB", [grain] * 3), 0.06)
        img = Image.blend(img, Image.new("RGB", size, p.extra["tint"]), 0.25)
    elif f == "spotlight":
        rnd = random.Random(seed)
        cx, cy = int(W * rnd.uniform(0.62, 0.9)), int(H * rnd.uniform(0.55, 0.85))
        glow = Image.new("L", size, 0)
        r = int(max(W, H) * 0.55)
        ImageDraw.Draw(glow).ellipse([cx - r, cy - r, cx + r, cy + r], fill=120)
        glow = glow.filter(ImageFilter.GaussianBlur(r // 2))
        img = Image.composite(Image.new("RGB", size, p.extra["glow"]), img, glow)
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
        wl = text_width(fnt, w)
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
        if (h <= max_h and all(text_width(f, " ".join(w for w, _ in ln)) <= width for ln in lines)) or size <= min_size:
            return f, lines, size
        size -= 4


def _boxed(style):
    return fam(style) in ("ledger", "signal")


def draw_lines(img, style, x, y, lines, fnt, size, leading=1.04, color=None, align="left", box_w=None, reveal=None):
    """Draw wrapped token lines with the style's accent treatment. reveal = number of words visible (kinetic)."""
    p = pal(style)
    f = fam(style)
    d = ImageDraw.Draw(img)
    color = color or p.ink
    space = fnt.getlength(" ")
    pad = max(6, int(size * 0.12))
    shown = 0
    for line in lines:
        lw = text_width(fnt, " ".join(w for w, _ in line))
        cx = x + ((box_w - lw) / 2 if align == "center" and box_w else 0)
        for w, st in line:
            if reveal is not None and shown >= reveal:
                return y
            ww = text_width(fnt, w)
            fill = color
            if st == "accent":
                if f in ("ledger", "signal"):
                    d.rectangle([cx - pad, y + size * 0.05, cx + ww + pad, y + size * 1.01], fill=p.box)
                    fill = p.box_text
                elif f == "paper":
                    th = max(6, size // 9)
                    d.rectangle([cx - 2, y + size * 0.86, cx + ww + 2, y + size * 0.86 + th], fill=p.accent)
                elif f == "notes":   # highlighter, like marking text in a note
                    d.rectangle([cx - 4, y + size * 0.14, cx + ww + 4, y + size * 1.06], fill=p.box)
                    fill = p.box_text
                else:
                    fill = p.accent
            elif st == "bold":
                fill = p.ink
            draw_text(img, (cx, y), w, fnt, fill)
            cx += ww + space + (pad if st == "accent" and _boxed(style) else 0)
            shown += 1
        y += int(size * leading)
    return y


# ---------------------------------------------------------------------------------------------------- chrome & icons
def mono_label(d, xy, text, style, size=26, color=None):
    d.text(xy, text.upper(), font=font("mono", size), fill=color or pal(style).label)


def chrome(img, style, label, page=None, total=None, handle="bethemansystem", swipe=False, story=False):
    W, H = img.size
    p = pal(style)
    d = ImageDraw.Draw(img)
    top = 120 if story else 72
    mono_label(d, (84, top), f"BE THE MAN // {label}", style, 24)
    if page and total and total > 1:
        t = f"{page:02d} / {total:02d}"
        d.text((W - 84 - font("mono", 24).getlength(t), top), t, font=font("mono", 24), fill=p.label)
        seg = (W - 168 - (total - 1) * 8) / total
        for i in range(total):
            x0 = 84 + i * (seg + 8)
            d.rectangle([x0, H - 64, x0 + seg, H - 60], fill=p.icon if i < page else p.dimc)
    hy = H - (250 if story else 118)
    hf = font("monobold", 26)
    d.text((W - 84 - hf.getlength("@" + handle), hy), "@" + handle, font=hf, fill=p.ink)
    if swipe:
        sf = font("monobold", 26)
        txt = "SWIPE  →"
        w = sf.getlength(txt) + 44
        d.rounded_rectangle([84, hy - 14, 84 + w, hy + 40], radius=27, outline=p.ink, width=3)
        d.text((106, hy - 2), txt, font=sf, fill=p.ink)


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
    elif kind == "circle_check":
        d.ellipse([x, y, x + s, y + s], fill=color)
        d.line([(x + s * 0.26, y + s * 0.52), (x + s * 0.44, y + s * 0.7), (x + s * 0.76, y + s * 0.32)], fill=bg, width=max(4, s // 9))
    elif kind == "circle":
        d.ellipse([x, y, x + s, y + s], outline=color, width=max(3, s // 14))
    elif kind == "x":
        d.line([(x, y), (x + s, y + s)], fill=color, width=7)
        d.line([(x + s, y), (x, y + s)], fill=color, width=7)


# ---------------------------------------------------------------------------------------------------- more families
PALETTES.update({
    "gradient-sunset": P("#E85D3F", "#FFFFFF", "#FFF1E8", "#FFFFFF", "#FFF1E8", "#FFFFFF", "#C94A2E", "#FFFFFF", "#F08A62", "#FFD2C2", {"to": "#F2A541"}),
    "gradient-ocean": P("#1E3C72", "#FFFFFF", "#DDEBF5", "#7FE3D1", "#7FE3D1", "#7FE3D1", "#16325F", "#7FE3D1", "#2D5A8C", "#9DB7CF", {"to": "#2A9D8F"}),
    "gradient-ember": P("#1A1416", "#FFF4E6", "#E8D3BC", "#FF8A3D", "#FF8A3D", "#FF8A3D", "#1A1416", "#FF8A3D", "#3A2620", "#9A8270", {"to": "#7A2E12"}),
    "editorial-white": P("#FAFAF7", "#111111", "#333333", "#D7263D", "#111111", "#D7263D", "#FFFFFF", "#D7263D", "#E2E0DA", "#9A978F"),
    "editorial-black": P("#0E0E0E", "#F5F2EA", "#CFCAC0", "#E18B1F", "#F5F2EA", "#E18B1F", "#0E0E0E", "#E18B1F", "#2B2B2B", "#7E7A72"),
    "card-walnut": P("#FBF8F2", "#1E1A16", "#3E3832", "#B8680F", "#B8680F", "#F6D9A8", "#1E1A16", "#B8680F", "#E7DFD2", "#9C9387", {"table": "#3B2A20"}),
    "card-slate": P("#F4F4F2", "#16191D", "#3A3F46", "#2F6B4F", "#2F6B4F", "#CFE7D9", "#16191D", "#2F6B4F", "#E1E3E0", "#8F959C", {"table": "#2B3036"}),
    "post-light": P("#FFFFFF", "#0F1419", "#0F1419", "#E18B1F", "#536471", "#FFE6C2", "#0F1419", "#536471", "#EFF3F4", "#536471", {"page": "#F2EEE6"}),
    "post-dark": P("#15202B", "#F7F9F9", "#F7F9F9", "#F2A541", "#8B98A5", "#4A3410", "#FFE6C2", "#8B98A5", "#38444D", "#8B98A5", {"page": "#0B0F14"}),
})
STYLES[:] = list(PALETTES)
FAMILIES[:] = ["ledger", "signal", "paper", "spotlight", "notes", "gradient", "editorial", "card", "post"]

_base_background = background


def background(style: str, size, seed: int = 0) -> Image.Image:   # noqa: F811 (extends the base families)
    W, H = size
    p = pal(style)
    f = fam(style)
    if f == "gradient":
        g = Image.linear_gradient("L").resize((W * 2, H * 2)).rotate(-35, expand=False).crop((W // 2, H // 2, W // 2 + W, H // 2 + H))
        img = Image.composite(Image.new("RGB", size, p.extra["to"]), Image.new("RGB", size, p.bg), g)
        grain = Image.effect_noise(size, 22).convert("L")
        return Image.blend(img, Image.merge("RGB", [grain] * 3), 0.035)
    if f == "editorial":
        img = Image.new("RGB", size, p.bg)
        d = ImageDraw.Draw(img)
        d.rectangle([60, 40, W - 60, 52], fill=p.ink)
        d.rectangle([60, H - 52, W - 60, H - 46], fill=p.ink)
        return img
    if f == "card":
        img = Image.new("RGB", size, p.extra["table"])
        grain = Image.effect_noise(size, 40).convert("L").filter(ImageFilter.GaussianBlur(1))
        img = Image.blend(img, Image.merge("RGB", [grain] * 3), 0.08)
        shadow = Image.new("L", size, 0)
        ImageDraw.Draw(shadow).rounded_rectangle([58, 70, W - 46, H - 40], radius=26, fill=150)
        img = Image.composite(Image.new("RGB", size, "#000000"), img, shadow.filter(ImageFilter.GaussianBlur(18)))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([48, 52, W - 48, H - 52], radius=24, fill=p.bg)
        for y in range(330, H - 120, 66):   # faint ruled lines like an index card
            d.line([(90, y), (W - 90, y)], fill=p.dimc, width=2)
        d.line([(90, 250), (W - 90, 250)], fill="#E4A0A0", width=3)
        return img
    if f in ("notes", "post"):
        return Image.new("RGB", size, p.bg if f == "notes" else p.extra["page"])
    return _base_background(style, size, seed)


def _boxed(style):   # noqa: F811
    return fam(style) in ("ledger", "signal", "gradient")


# ---------------------------------------------------------------------------------------------------- special renderers
def _slide_text(sl: dict) -> tuple[str, list[str], list[str]]:
    """Flatten any layout into (title, paragraphs, checklist items) for the notes / post renderers."""
    lay = sl.get("layout") or "point"
    title = sl.get("title") or ""
    paras, items = [], []
    if lay == "myth_truth":
        title = title or "Myth vs truth"
        paras = [f"❌ {plain(sl.get('myth', ''))}", f"✅ {plain(sl.get('truth', ''))}"]
    elif lay == "quote":
        paras = [f"“{plain(sl.get('title') or sl.get('text', ''))}”"] + ([f"— {sl['attribution']}"] if sl.get("attribution") else [])
        title = ""
    elif lay in ("list", "timeline", "tracker", "cta"):
        items = list(sl.get("items") or [])
        if sl.get("text"):
            paras = [sl["text"]]
    elif lay == "compare":
        title = title or f"{sl.get('a', 'Before')} vs {sl.get('b', 'After')}"
        paras = [f"{sl.get('a', 'Before')}: " + "; ".join(sl.get("left", [])), f"{sl.get('b', 'After')}: " + "; ".join(sl.get("right", []))]
    elif lay == "matrix":
        paras = [f"{q.get('title', '')}: {q.get('text', '')}" for q in sl.get("quadrants", [])]
    elif lay == "scale":
        paras = [sl.get("text") or "", "1 · · · · · · · · · 10"] + [f"{k}: {v}" for k, v in (sl.get("levels") or {}).items()]
    else:
        paras = [sl.get("text") or ""]
    return title, [p_ for p_ in paras if p_], items


def notes_slide(style, size, sl, page=None, total=None, stamp="", story=False):
    """A phone-notes style page: personal and lo-fi, with the brand's own words."""
    W, H = size
    p = pal(style)
    img = background(style, size)
    d = ImageDraw.Draw(img)
    top = 150 if story else 70
    # toolbar: back chevron + "Notes", share and more icons
    d.line([(70, top + 14), (52, top + 34), (70, top + 54)], fill=p.accent, width=6)
    d.text((88, top + 6), "Notes", font=font("body", 46), fill=p.accent)
    sx = W - 210
    d.rounded_rectangle([sx, top + 18, sx + 40, top + 62], radius=6, outline=p.accent, width=4)
    d.line([(sx + 20, top - 2), (sx + 20, top + 38)], fill=p.accent, width=4)
    d.line([(sx + 8, top + 10), (sx + 20, top - 2), (sx + 32, top + 10)], fill=p.accent, width=4)
    d.ellipse([W - 130, top + 4, W - 70, top + 64], outline=p.accent, width=4)
    for k in range(3):
        d.ellipse([W - 114 + k * 14, top + 30, W - 106 + k * 14, top + 38], fill=p.accent)
    sf = font("body", 32)
    d.text(((W - sf.getlength(stamp)) / 2, top + 110), stamp, font=sf, fill=p.mute)
    M, inner = 80, W - 160
    title, paras, items = _slide_text(sl)
    y = top + 190
    if title:
        tf, tl, ts = fit_tokens(parse(title.replace("*", "")), "bold", 82, 52, inner, 360, 1.12)
        y = draw_lines(img, style, M, y, tl, tf, ts, 1.12) + 30
    for para in paras:
        bf, bl, bs = fit_tokens(parse(para), "body", 54, 36, inner, 420, 1.3)
        y = draw_lines(img, style, M, y, bl, bf, bs, 1.3, color=p.soft) + 30
    for i, it in enumerate(items):
        bf, bl, bs = fit_tokens(parse(it), "body", 52, 34, inner - 90, 240, 1.28)
        icon(d, "circle_check" if i < len(items) - 1 else "circle", M, y + 6, 50, p.accent, p.bg)
        y = draw_lines(img, style, M + 84, y, bl, bf, bs, 1.28, color=p.soft) + 26
    if total and total > 1:   # tiny page hint instead of loud chrome
        t = f"{page}/{total}"
        d.text((W - 80 - font("body", 30).getlength(t), H - (250 if story else 90)), t, font=font("body", 30), fill=p.mute)
    d.rounded_rectangle([W / 2 - 120, H - 34, W / 2 + 120, H - 24], radius=5, fill=p.ink)
    return img


def post_slide(style, size, sl, page=None, total=None, handle="bethemansystem", story=False):
    """A social-post card: avatar, name, handle, words. No fake likes or counts."""
    W, H = size
    p = pal(style)
    img = background(style, size)
    d = ImageDraw.Draw(img)
    title, paras, items = _slide_text(sl)
    M = 120
    inner = W - 2 * M
    body = [t for t in [title] + paras if t] + [f"→ {it}" for it in items]
    # measure, then place the card in the middle of the page
    scratch = img.copy()

    def draw(target, y0):
        dd = ImageDraw.Draw(target)
        y = y0 + 60
        dd.ellipse([M, y, M + 110, y + 110], fill=AMBER)
        dd.text((M + 55 - font("black", 40).getlength("BTM") / 2, y + 32), "BTM", font=font("black", 40), fill=INK)
        dd.text((M + 136, y + 12), "Be The Man", font=font("bold", 42), fill=p.ink)
        dd.text((M + 136, y + 62), "@" + handle, font=font("body", 36), fill=p.mute)
        y += 160
        for k, para in enumerate(body):
            bf, bl, bs = fit_tokens(parse(para), "bold" if k == 0 and title else "body", 60 if k == 0 else 50, 34, inner, 520, 1.3)
            y = draw_lines(target, style, M, y, bl, bf, bs, 1.3, color=p.ink) + 26
        y += 20
        dd.line([(M, y), (W - M, y)], fill=p.dimc, width=2)
        y += 34
        for i, kind in enumerate(["comment", "send", "save"]):
            icon(dd, kind, M + i * 200, y, 44, p.mute, p.bg)
        return y + 90
    end = draw(scratch, 0)
    y0 = max(80, (H - end) / 2)
    d.rounded_rectangle([60, y0, W - 60, y0 + end], radius=36, fill=p.bg)
    draw(img, y0)
    if total and total > 1:
        t = f"{page}/{total}"
        d.text((W - 80 - font("body", 30).getlength(t), H - 80), t, font=font("body", 30), fill=p.mute)
    return img


# ---------------------------------------------------------------------------------------------------- standard slides
def slide(style: str, size, sl: dict, page=None, total=None, label="SYSTEM NOTES", seed=0, story=False,
          stamp: str = "", handle: str = "bethemansystem") -> Image.Image:
    style = norm_style(style) or "ledger-charcoal"
    f = fam(style)
    if f == "notes":
        return notes_slide(style, size, sl, page, total, stamp=stamp, story=story)
    if f == "post":
        return post_slide(style, size, sl, page, total, handle=handle, story=story)
    W, H = size
    p = pal(style)
    img = background(style, size, seed)
    d = ImageDraw.Draw(img)
    layout = sl.get("layout") if sl.get("layout") in LAYOUTS else "point"
    M = 130 if f == "card" else 84
    inner = W - 2 * M
    top = (260 if story else 190) + (70 if f == "card" else 0)
    bottom = H - (330 if story else 190)
    title = sl.get("title") or ""
    text = sl.get("text") or ""
    head_face = "black"
    dry: dict = {}

    def content(img, y0):
        d = ImageDraw.Draw(img)
        if layout == "hook":
            fnt, lines, s_ = fit_tokens(parse(title), head_face, 176 if not story else 184, 80, inner, (bottom - top) * 0.66, 0.96, upper=f != "card")
            y = draw_lines(img, style, M, y0, lines, fnt, s_, 0.96)
            if text:
                bf, bl, bs = fit_tokens(parse(text), "medium", 54, 34, inner * 0.94, (bottom - top) * 0.26, 1.28)
                y = draw_lines(img, style, M, y + 46, bl, bf, bs, 1.28, color=p.soft)
            return y
        if layout == "point":
            fnt, lines, s_ = fit_tokens(parse(title), "xbold", 112, 60, inner * 0.96, (bottom - top) * 0.46, 1.0)
            y = draw_lines(img, style, M, y0, lines, fnt, s_, 1.0)
            if text:
                bf, bl, bs = fit_tokens(parse(text), "body", 54, 34, inner * 0.96, (bottom - top) * 0.36, 1.34)
                y = draw_lines(img, style, M, y + 40, bl, bf, bs, 1.34, color=p.soft)
            return y
        if layout in ("list", "timeline"):
            fnt, lines, s_ = fit_tokens(parse(title), "xbold", 100, 56, inner, (bottom - top) * 0.24, 1.0)
            y = draw_lines(img, style, M, y0, lines, fnt, s_, 1.0) + 46
            items = sl.get("items") or [t for t in re.split(r"\s*[•\n;]\s*", text) if t][:6]
            room = ((bottom - top) * 0.7) / max(1, len(items))
            gap = 26 if dry.get("gap") is None else dry["gap"]
            prev = None
            for i, it in enumerate(items):
                bf, bl, bs = fit_tokens(parse(it), "semi", 58, 32, inner - 110, room - 18, 1.18)
                if layout == "timeline":   # numbered nodes joined by a line
                    r = int(bs * 0.62)
                    cx, cy = M + r, y + bs * 0.55
                    if prev:
                        d.line([(cx, prev + r), (cx, cy - r)], fill=p.icon, width=5)
                    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=p.icon)
                    n = str(i + 1)
                    nf = font("black", int(r * 1.15))
                    d.text((cx - nf.getlength(n) / 2, cy - r * 0.68), n, font=nf, fill=p.bg)
                    prev = cy
                else:
                    ic = "check" if i < len(items) - 1 or len(items) == 1 else "box"
                    icon(d, ic, M, y + bs * 0.12, int(bs * 0.82), p.icon, p.bg)
                y = draw_lines(img, style, M + 110, y, bl, bf, bs, 1.18) + gap
            return y
        if layout == "quote":
            d.text((M - 12, y0 - 40), "“", font=font("black", 280), fill=p.icon)
            fnt, lines, s_ = fit_tokens(parse(title or text), "semi", 100, 50, inner, (bottom - top) * 0.6, 1.12)
            y = draw_lines(img, style, M, y0 + 200, lines, fnt, s_, 1.12)
            attr = sl.get("attribution") or (text if title else "")
            if attr:
                mono_label(d, (M, y + 34), "— " + plain(attr)[:60], style, 30)
                y += 80
            return y
        if layout == "cta":
            fnt, lines, s_ = fit_tokens(parse(title or "Save this for Sunday night."), head_face, 140, 64, inner, (bottom - top) * 0.42, 0.96, upper=True)
            y = draw_lines(img, style, M, y0, lines, fnt, s_, 0.96) + 76
            rows = sl.get("items") or [text or "Comment *STEP1* for the free worksheet", "Save it for later", "Send it to a brother who needs it"]
            for i, r in enumerate(rows[:3]):
                icon(d, ["comment", "save", "send"][i % 3], M, y + 6, 54, p.icon, p.bg)
                bf, bl, bs = fit_tokens(parse(r), "semi", 52, 32, inner - 96, 150, 1.18)
                y = draw_lines(img, style, M + 96, y, bl, bf, bs, 1.18) + 40
            return y
        if layout == "compare":   # two columns: before/after, this/that
            fnt, lines, s_ = fit_tokens(parse(title), "xbold", 92, 52, inner, (bottom - top) * 0.2, 1.0)
            y = draw_lines(img, style, M, y0, lines, fnt, s_, 1.0) + 50
            colw = (inner - 40) / 2
            heads = [sl.get("a") or "Before", sl.get("b") or "After"]
            cols = [sl.get("left") or [], sl.get("right") or []]
            for c in range(2):
                x = M + c * (colw + 40)
                d.rectangle([x, y, x + colw, y + 76], fill=p.dimc if c == 0 else p.icon)
                hf = font("monobold", 34)
                d.text((x + 24, y + 18), plain(heads[c]).upper()[:18], font=hf, fill=p.ink if c == 0 else p.bg)
            y += 110
            rows = max(len(cols[0]), len(cols[1]), 1)
            room = (bottom - y - 20) / rows
            for r in range(rows):
                for c in range(2):
                    it = cols[c][r] if r < len(cols[c]) else ""
                    if it:
                        bf, bl, bs = fit_tokens(parse(it), "semi", 46, 28, colw - 20, room - 16, 1.16)
                        draw_lines(img, style, M + c * (colw + 40) + 10, y, bl, bf, bs, 1.16,
                                   color=p.mute if c == 0 else p.ink)
                y += room
                if r < rows - 1:
                    d.line([(M, y - 12), (W - M, y - 12)], fill=p.dimc, width=2)
            return y
        if layout == "matrix":   # 2x2 grid with axis labels
            fnt, lines, s_ = fit_tokens(parse(title), "xbold", 88, 50, inner, (bottom - top) * 0.18, 1.0)
            y = draw_lines(img, style, M, y0, lines, fnt, s_, 1.0) + 40
            quads = (sl.get("quadrants") or [])[:4]
            side = min(inner, bottom - y - 60)
            cell = (side - 20) / 2
            x0 = M + (inner - side) / 2
            for i in range(4):
                q = quads[i] if i < len(quads) else {}
                cx0, cy0 = x0 + (i % 2) * (cell + 20), y + (i // 2) * (cell + 20)
                hot = i == 1
                d.rectangle([cx0, cy0, cx0 + cell, cy0 + cell], fill=p.icon if hot else None, outline=p.icon, width=4)
                tf, tl, ts = fit_tokens(parse(q.get("title", "")), "xbold", 52, 30, cell - 40, cell * 0.4, 1.0)
                yy = draw_lines(img, style, cx0 + 20, cy0 + 20, tl, tf, ts, 1.0, color=p.bg if hot else p.ink)
                bf, bl, bs = fit_tokens(parse(q.get("text", "")), "body", 36, 22, cell - 40, cell - (yy - cy0) - 30, 1.2)
                draw_lines(img, style, cx0 + 20, yy + 10, bl, bf, bs, 1.2, color=p.bg if hot else p.soft)
            if sl.get("x"):
                mono_label(d, (x0, y + side + 14), plain(sl["x"])[:40] + "  →", style, 26)
            return y + side + 50
        if layout == "tracker":   # 7-day habit grid
            fnt, lines, s_ = fit_tokens(parse(title), "xbold", 88, 50, inner, (bottom - top) * 0.18, 1.0)
            y = draw_lines(img, style, M, y0, lines, fnt, s_, 1.0) + 50
            habits = (sl.get("items") or ["Pray", "Move", "Phone down at dinner"])[:5]
            labw = inner * 0.38
            cw = (inner - labw) / 7
            for k, dname in enumerate("MTWTFSS"):
                mono_label(d, (M + labw + k * cw + cw / 2 - 9, y), dname, style, 30)
            y += 60
            rnd = random.Random(title)
            rh = min(130, (bottom - y) / max(1, len(habits)))
            for h in habits:
                bf, bl, bs = fit_tokens(parse(h), "semi", 40, 24, labw - 16, rh - 10, 1.1)
                draw_lines(img, style, M, y + 10, bl, bf, bs, 1.1)
                for k in range(7):
                    x = M + labw + k * cw + cw * 0.15
                    s2 = cw * 0.7
                    done = k < 5 and rnd.random() > 0.25    # example week: mostly kept, a miss or two (that's the point)
                    if done:
                        d.rounded_rectangle([x, y + 8, x + s2, y + 8 + s2], radius=8, fill=p.icon)
                    else:
                        d.rounded_rectangle([x, y + 8, x + s2, y + 8 + s2], radius=8, outline=p.dimc, width=4)
                y += rh
            return y
        if layout == "scale":   # 1-10 self-rating meter
            fnt, lines, s_ = fit_tokens(parse(title), "xbold", 96, 52, inner, (bottom - top) * 0.34, 1.0)
            y = draw_lines(img, style, M, y0, lines, fnt, s_, 1.0) + 70
            bw = (inner - 9 * 12) / 10
            for k in range(10):
                x = M + k * (bw + 12)
                hgt = 50 + k * 14
                d.rounded_rectangle([x, y + 190 - hgt, x + bw, y + 190], radius=8, fill=p.icon if k < 6 else p.dimc)
                n = str(k + 1)
                d.text((x + bw / 2 - font("mono", 30).getlength(n) / 2, y + 205), n, font=font("mono", 30), fill=p.label)
            y += 270
            levels = sl.get("levels") or {}
            for k, v in list(levels.items())[:3]:
                bf, bl, bs = fit_tokens(parse(f"**{k}** · {v}"), "body", 42, 28, inner, 120, 1.25)
                y = draw_lines(img, style, M, y, bl, bf, bs, 1.25, color=p.soft) + 14
            if text:
                bf, bl, bs = fit_tokens(parse(text), "medium", 46, 30, inner, 160, 1.25)
                y = draw_lines(img, style, M, y + 20, bl, bf, bs, 1.25)
            return y
        # myth_truth
        myth, truth = sl.get("myth") or title, sl.get("truth") or text
        mono_label(d, (M, y0), "MYTH", style, 36, p.mute)
        mf, ml, ms = fit_tokens(parse(myth), "semi", 76, 42, inner, (bottom - top) * 0.26, 1.12)
        y = y0 + 70
        for line in ml:
            lw = text_width(mf, " ".join(w for w, _ in line))
            d.text((M, y), " ".join(w for w, _ in line), font=mf, fill=p.mute)
            d.line([(M - 6, y + ms * 0.58), (M + lw + 6, y + ms * 0.58)], fill=p.icon, width=7)
            y += int(ms * 1.12)
        y += 50
        d.line([(M, y), (W - M, y)], fill=p.dimc, width=3)
        mono_label(d, (M, y + 46), "TRUTH", style, 36)
        tf, tl, ts = fit_tokens(parse(truth), head_face, 112, 54, inner, (bottom - top) * 0.4, 1.0, upper=True)
        return draw_lines(img, style, M, y + 116, tl, tf, ts, 1.0)

    if layout == "point":   # oversized section number behind the content
        num = sl.get("number") or (f"{page - 1:02d}" if page and page > 1 else "01")
        nf = font("black", 360)
        nx = W - M - nf.getlength(num) + 24
        if f in ("signal", "gradient"):
            d.text((nx, top - 80), num, font=nf, fill=p.dimc, stroke_width=4, stroke_fill=p.ink)
        else:
            d.text((nx, top - 80), num, font=nf, fill=p.dimc)
    if f == "editorial":
        mono_label(d, (W - 84 - font("mono", 24).getlength(f"ISSUE Nº {seed:03d}"), 112), f"ISSUE Nº {seed:03d}", style, 24)
    scratch = img.copy()
    end = content(scratch, 0)
    start = top + (290 if layout == "point" else 0)
    free = bottom - start - end
    if layout in ("list", "timeline") and free > 0:   # spread items over the slide instead of bunching them at the top
        n = max(1, len(sl.get("items") or [1]))
        dry["gap"] = 26 + min(110, free * 0.6 / n)
        end = content(img.copy(), 0)
        free = bottom - start - end
    content(img, start + max(0, free * 0.5))
    if f == "card":
        _card_chrome(img, style, label, page, total, handle)
    else:
        chrome(img, style, label, page, total, handle=handle, swipe=(page == 1 and (total or 0) > 1), story=story)
    return img


def _card_chrome(img, style, label, page, total, handle):
    W, H = img.size
    p = pal(style)
    d = ImageDraw.Draw(img)
    mono_label(d, (130, 150), f"BE THE MAN // {label}", style, 24)
    if page and total and total > 1:
        t = f"{page}/{total}"
        d.text((W - 130 - font("mono", 26).getlength(t), 150), t, font=font("mono", 26), fill=p.label)
    hf = font("monobold", 26)
    d.text((W - 130 - hf.getlength("@" + handle), H - 120), "@" + handle, font=hf, fill=p.ink)


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


def pick_style(seed_text: str, recent: list[str], allow: list[str] | None = None) -> str:
    """Rotate: never reuse a family from the last 3 posts or a palette from the last 6; then pick by content id."""
    h = int(hashlib.md5(seed_text.encode()).hexdigest(), 16)
    recent = [norm_style(r) for r in recent if norm_style(r)]
    fams_recent = [fam(r) for r in recent[:3]]
    pool = [s for s in (allow or STYLES) if fam(s) not in fams_recent and s not in recent[:6]] or list(allow or STYLES)
    return pool[h % len(pool)]


# ---------------------------------------------------------------------------------------------------- kinetic video
def _beat_frame(bg, style, size, tokens, visible, progress, label, handle, hook=False, foot=None, story=False):
    W, H = size
    p = pal(style)
    img = bg.copy()
    d = ImageDraw.Draw(img)
    M = 84
    # progress bar across the top (Reels/Stories retention cue)
    d.rectangle([0, 0, W, 10], fill=p.dimc)
    d.rectangle([0, 0, int(W * progress), 10], fill=p.icon)
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
        d.rounded_rectangle([M, bottom + 60, M + w, bottom + 128], radius=34, fill=p.icon)
        d.text((M + 28, bottom + 76), foot, font=ff, fill=p.bg if fam(style) not in ("notes", "post") else p.box_text)
    hf = font("monobold", 30)
    d.text((W - M - hf.getlength("@" + handle), 150), "@" + handle, font=hf, fill=p.ink)
    return img


def kinetic_video(style: str, beats: list[dict], out_dir: Path, name: str, music_wav: Path | None, label="SYSTEM NOTES",
                  handle="bethemansystem", size=(1080, 1920), final_foot: str | None = None, seed: int = 0) -> dict:
    """Word-by-word kinetic type. Returns {"video","cover","duration","thumb_offset_ms"}."""
    import subprocess
    out_dir.mkdir(parents=True, exist_ok=True)
    style = norm_style(style) or "ledger-charcoal"
    if fam(style) in ("card", "post", "notes"):   # these are still-image looks; for motion use a matching solid family
        style = {"card-walnut": "paper-cream", "card-slate": "paper-sage", "post-light": "paper-cream",
                 "post-dark": "ledger-navy", "notes-light": "paper-cream", "notes-dark": "spotlight-amber"}[style]
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
