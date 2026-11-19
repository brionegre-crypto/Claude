"""Settings loading and validation. Secrets are never read from here (see secrets.py)."""
from __future__ import annotations

import os
import re
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from zoneinfo import ZoneInfo

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
FORMATS = {
    "instagram": {"image", "carousel", "reel", "story"},
    "youtube": {"community_text", "community_image", "community_poll", "community_quiz"},
}


class ConfigError(ValueError):
    pass


@dataclass
class Settings:
    raw: dict
    path: Path
    root: Path = PROJECT_ROOT
    errors: list[str] = field(default_factory=list)

    def get(self, dotted: str, default=None):
        node = self.raw
        for part in dotted.split("."):
            if not isinstance(node, dict) or part not in node:
                return default
            node = node[part]
        return node

    @property
    def tz(self) -> ZoneInfo:
        return ZoneInfo(self.get("general.timezone", "UTC"))

    @property
    def data_dir(self) -> Path:
        d = Path(os.environ.get("AUTOPILOT_DATA_DIR") or self.get("general.data_dir", "data"))
        d = d if d.is_absolute() else self.root / d
        d.mkdir(parents=True, exist_ok=True)
        return d

    @property
    def db_path(self) -> Path:
        return self.data_dir / "autopilot.db"

    @property
    def assets_dir(self) -> Path:
        p = self.data_dir / "assets"
        p.mkdir(parents=True, exist_ok=True)
        return p

    @property
    def mode(self) -> str:
        return self.get("general.mode", "simulation")

    def resolve(self, rel: str) -> Path:
        p = Path(rel)
        return p if p.is_absolute() else self.root / p

    def brand_text(self) -> str:
        p = self.resolve(self.get("brand.brand_file", "config/brand.md"))
        return p.read_text() if p.exists() else ""


def validate(raw: dict) -> list[str]:
    errs: list[str] = []
    tz = raw.get("general", {}).get("timezone", "UTC")
    try:
        ZoneInfo(tz)
    except Exception:
        errs.append(f"general.timezone: unknown time zone {tz!r}")
    mode = raw.get("general", {}).get("mode", "simulation")
    if mode not in ("simulation", "live"):
        errs.append("general.mode must be 'simulation' or 'live'")
    prov = raw.get("ai", {}).get("provider", "claude_cli")
    if prov not in ("claude_cli", "inbox", "mock"):
        errs.append("ai.provider must be claude_cli, inbox or mock")
    for i, s in enumerate(raw.get("calendar", {}).get("slots", [])):
        p, f = s.get("platform"), s.get("format")
        if p not in FORMATS or f not in FORMATS[p]:
            errs.append(f"calendar.slots[{i}]: unsupported platform/format {p}/{f}")
        for d in s.get("days", []):
            if d not in DAYS:
                errs.append(f"calendar.slots[{i}]: bad day {d!r}")
        if not re.fullmatch(r"([01]\d|2[0-3]):[0-5]\d", s.get("time", "")):
            errs.append(f"calendar.slots[{i}]: time must be HH:MM (24h)")
    sd = raw.get("calendar", {}).get("start_date", "")
    if sd and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", sd):
        errs.append("calendar.start_date must be YYYY-MM-DD or empty")
    host = raw.get("dashboard", {}).get("host", "127.0.0.1")
    if host not in ("127.0.0.1", "localhost", "::1"):
        errs.append("dashboard.host: only loopback addresses are allowed (security)")
    mh = raw.get("publishing", {}).get("media_host", "tunnel")
    if mh not in ("tunnel", "public_url"):
        errs.append("publishing.media_host must be tunnel or public_url")
    if mh == "public_url" and not raw.get("publishing", {}).get("public_media_base_url", "").startswith("https://"):
        errs.append("publishing.public_media_base_url must be an https:// URL when media_host = public_url")
    for k in ("ntfy_topic",):
        v = raw.get("notifications", {}).get(k, "")
        if v and (len(v) < 12 or not re.fullmatch(r"[A-Za-z0-9_-]+", v)):
            errs.append("notifications.ntfy_topic must be 12+ characters: letters, numbers, - and _ only (topics are public)")
    return errs


AUDIENCE_FILE = PROJECT_ROOT / "config" / "audience.toml"
_LIST_ADD = {("quality", "banned_phrases"), ("quality", "sensitive_terms")}


def apply_audience_profile(raw: dict, path: Path | None = None) -> None:
    """Overlay config/audience.toml (tracked in git) onto settings: lists are replaced, except the quality lists,
    which are extended. Disable with AUTOPILOT_AUDIENCE=none (tests)."""
    if os.environ.get("AUTOPILOT_AUDIENCE") == "none":
        return
    path = path or AUDIENCE_FILE
    if not path.exists():
        return
    with open(path, "rb") as fh:
        prof = tomllib.load(fh)
    for section, values in prof.items():
        target = raw.setdefault(section, {})
        for k, v in values.items():
            if (section, k) in _LIST_ADD:
                target[k] = list(dict.fromkeys(list(target.get(k, [])) + list(v)))
            else:
                target[k] = v


def load(path: str | os.PathLike | None = None, strict: bool = True) -> Settings:
    p = Path(path or os.environ.get("AUTOPILOT_CONFIG") or PROJECT_ROOT / "config" / "settings.toml")
    if not p.exists():
        p = PROJECT_ROOT / "config" / "settings.example.toml"
    with open(p, "rb") as fh:
        raw = tomllib.load(fh)
    apply_audience_profile(raw)
    errs = validate(raw)
    if errs and strict:
        raise ConfigError("Invalid configuration:\n  - " + "\n  - ".join(errs))
    return Settings(raw=raw, path=p, errors=errs)


def set_value(path: Path, dotted: str, value: str) -> None:
    """Minimal in-place TOML scalar edit (keeps comments). Used by wizard/dashboard for simple keys."""
    section, key = dotted.rsplit(".", 1)
    lines = path.read_text().splitlines()
    cur = None
    rendered = value if value in ("true", "false") or re.fullmatch(r"-?\d+(\.\d+)?", value) else '"' + value.replace('"', '\\"') + '"'
    for i, line in enumerate(lines):
        m = re.match(r"^\[([^\[\]]+)\]\s*$", line)
        if m:
            cur = m.group(1)
            continue
        m2 = re.match(rf'^{re.escape(key)}\s*=\s*("(?:[^"\\]|\\.)*"|[^#\s]+)(\s+#.*)?$', line)
        if cur == section and m2:
            lines[i] = f"{key} = {rendered}{m2.group(2) or ''}"
            path.write_text("\n".join(lines) + "\n")
            return
    raise ConfigError(f"{dotted} not found in {path}")
