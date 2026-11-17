"""Pre-publication quality and safety gate. Ordinary content passes automatically; only serious risks block."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from autopilot.db import DB

OFFENSIVE = {"retard", "faggot", "nigger", "kike", "whore", "slut", "tranny"}  # minimal hard-block list
URL_RE = re.compile(r"https?://[^\s)\]>\"']+")
CLAIM_HINT = re.compile(r"\b(\d{1,3}(\.\d+)?\s?%|percent|studies show|research shows|scientists|according to|proven)\b", re.I)


def normalize(text: str) -> str:
    text = re.sub(r"#\w+", " ", text.lower())
    text = re.sub(r"[^a-z0-9 ]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def fingerprint(text: str) -> str:
    return hashlib.sha256(normalize(text).encode()).hexdigest()[:32]


def shingles(text: str, k: int = 3) -> set:
    w = normalize(text).split()
    return {" ".join(w[i:i + k]) for i in range(max(len(w) - k + 1, 1))}


def jaccard(a: set, b: set) -> float:
    return len(a & b) / len(a | b) if a and b else 0.0


def text_of(c: dict) -> str:
    body = c.get("body") or {}
    if isinstance(body, str):
        body = json.loads(body or "{}")
    parts = [c.get("hook") or "", c.get("caption") or ""]
    for key in ("slides", "script", "frames"):
        for it in body.get(key, []) or []:
            parts.append(" ".join(str(v) for v in it.values()))
    for key in ("poll", "quiz"):
        if body.get(key):
            parts.append(body[key].get("question", ""))
    return "\n".join(parts)


def check(s, db: DB, c: dict, link_checker=None, assets: list[dict] | None = None) -> dict:
    blocks, warnings, fixes = [], [], []
    body = c.get("body") or {}
    if isinstance(body, str):
        body = json.loads(body or "{}")
    fmt, platform = c["format"], c["platform"]
    caption = c.get("caption") or ""
    hashtags = c.get("hashtags") or []
    if isinstance(hashtags, str):
        hashtags = json.loads(hashtags or "[]")
    full = text_of(c)
    low = full.lower()

    # formatting / required fields
    if not caption.strip() and fmt not in ("story", "reel"):
        blocks.append("missing caption")
    if platform == "instagram" and len(caption) > 2200:
        blocks.append(f"caption too long for Instagram ({len(caption)} > 2200)")
    if fmt in ("image", "community_image") and len(body.get("slides", [])) < 1:
        blocks.append("image post has no slide text")
    if fmt == "carousel" and not (2 <= len(body.get("slides", [])) <= 10):
        blocks.append("carousel needs 2-10 slides (API limit)")
    if fmt == "reel" and not body.get("script"):
        blocks.append("reel has no script")
    if fmt == "story" and not body.get("frames"):
        blocks.append("story has no frames")
    if fmt == "community_poll":
        p = body.get("poll") or {}
        if not p.get("question") or not (2 <= len(p.get("options", [])) <= 5):
            blocks.append("poll needs a question and 2-5 options")
    if fmt == "community_quiz":
        q = body.get("quiz") or {}
        opts = q.get("options", [])
        if not q.get("question") or not (2 <= len(opts) <= 4) or not isinstance(q.get("answer_index"), int) \
                or not (0 <= q.get("answer_index", -1) < len(opts)):
            blocks.append("quiz needs a question, 2-4 options and a valid answer_index")
    if platform == "instagram" and len(hashtags) > 5:
        fixes.append(f"trimmed hashtags from {len(hashtags)} to 5")
        hashtags = hashtags[:5]
    if platform == "instagram" and "#bethemansystem" not in [h.lower() for h in hashtags] and s.get("brand.handle_instagram") == "bethemansystem":
        hashtags = (hashtags[:4] + ["#bethemansystem"])
        fixes.append("added #bethemansystem")

    # safety
    words = set(re.findall(r"[a-z]+", low))
    if words & OFFENSIVE:
        blocks.append("offensive language")
    for term in s.get("quality.sensitive_terms", []):
        if term.lower() in low:
            blocks.append(f"sensitive subject: '{term}' (needs a human)")
    for phrase in s.get("quality.banned_phrases", []):
        if phrase.lower() in low:
            blocks.append(f"banned/misleading phrase: '{phrase}'")
    if sum(1 for ch in caption if ch.isupper()) > max(40, len(caption) * 0.35):
        warnings.append("lots of capitals (spammy)")
    if re.search(r"(.)\1{5,}", caption):
        warnings.append("repeated characters (spammy)")
    if len(re.findall(r"(?i)\b(follow|like|share)\b", caption)) > 3:
        warnings.append("engagement-bait wording")

    # factual claims must be backed by a source we stored
    claims = body.get("claims") or []
    allowed = {x.get("url") for x in (json.loads(c["sources"]) if isinstance(c.get("sources"), str) else (c.get("sources") or [])) if x.get("url")}
    for cl in claims:
        src = (cl or {}).get("source_url")
        if not src or src not in allowed:
            blocks.append(f"unsupported claim: {str(cl.get('claim', ''))[:80]}")
    if CLAIM_HINT.search(full) and not claims:
        blocks.append("text looks like a factual/statistical claim but cites no source")
    if c.get("research_verification") == "disputed":
        blocks.append("research source is disputed")

    # links
    if link_checker:
        for u in set(URL_RE.findall(caption)) | allowed:
            if u and not link_checker(u):
                blocks.append(f"broken link: {u}")

    # duplicates
    fp = fingerprint(full)
    dup = db.one("SELECT id FROM content WHERE fingerprint=? AND id!=? AND status NOT IN ('cancelled','blocked','simulated')", (fp, c["id"]))
    if dup:
        blocks.append(f"exact duplicate of {dup[0]}")
    else:
        mine = shingles(full)
        thr = float(s.get("quality.similarity_threshold", 0.55))
        for r in db.q("""SELECT id,hook,caption,body,format,platform FROM content WHERE id!=? AND status NOT IN ('cancelled','blocked','planned','generating','simulated')
                         ORDER BY created_at DESC LIMIT 300""", (c["id"],)):
            sim = jaccard(mine, shingles(text_of(dict(r))))
            if sim >= thr:
                blocks.append(f"near-duplicate of {r['id']} (similarity {sim:.2f})")
                break

    # media
    if assets is not None:
        need = {"image": 1, "carousel": 2, "reel": 1, "story": 1, "community_image": 1}.get(fmt, 0)
        have = [a for a in assets if a["kind"] in ("image", "video") and Path(a["path"]).exists()]
        if len(have) < need:
            blocks.append(f"missing media ({len(have)}/{need})")
        for a in assets:
            if not str(a.get("license", "")).startswith(("original", "licensed:")):
                blocks.append(f"asset without verified license: {a['path']}")

    return {"ok": not blocks, "blocks": blocks, "warnings": warnings, "fixes": fixes,
            "fingerprint": fp, "hashtags": hashtags}
