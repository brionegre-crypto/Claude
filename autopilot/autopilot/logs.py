"""Structured JSON logs with rotation and secret redaction."""
from __future__ import annotations

import json
import logging
import re
from logging.handlers import RotatingFileHandler
from pathlib import Path

_SECRET_PATTERNS = [
    # "Bearer <tok>" / "OAuth <tok>" (also covers "Authorization: Bearer <tok>")
    (re.compile(r"\b(Bearer|OAuth)\s+[A-Za-z0-9._~+/=\-]{6,}", re.I), r"\1 [REDACTED]"),
    # key=value / "key": "value" / key: value
    (re.compile(r"(access_token|refresh_token|client_secret|app_secret|password|api_key|apikey|secret|token)"
                r"([\"']?\s*[=:]\s*[\"']?)(?!\[REDACTED\])([^\s\"'&,}]{6,})", re.I), r"\1\2[REDACTED]"),
    # bare token shapes: Instagram/Facebook, Anthropic, Google OAuth, Google API keys
    (re.compile(r"\b(IG[A-Za-z0-9_\-]{30,}|EAA[A-Za-z0-9]{30,}|sk-ant-[A-Za-z0-9_\-]{10,}|ya29\.[A-Za-z0-9_\-]{20,}|AIza[0-9A-Za-z_\-]{30,})"), "[REDACTED]"),
]


def redact(text) -> str:
    text = text if isinstance(text, str) else str(text)
    for pattern, repl in _SECRET_PATTERNS:
        text = pattern.sub(repl, text)
    return text


class JsonFormatter(logging.Formatter):
    def format(self, record):
        d = {"ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"), "level": record.levelname,
             "logger": record.name, "msg": redact(record.getMessage())}
        for k in ("content_id", "job", "platform"):
            if hasattr(record, k):
                d[k] = getattr(record, k)
        if record.exc_info:
            d["exc"] = redact(self.formatException(record.exc_info))
        return json.dumps(d, ensure_ascii=False)


_configured = False


def setup(log_dir: Path, level=logging.INFO) -> None:
    global _configured
    if _configured:
        return
    log_dir.mkdir(parents=True, exist_ok=True)
    root = logging.getLogger("autopilot")
    root.setLevel(level)
    fh = RotatingFileHandler(log_dir / "autopilot.log", maxBytes=5_000_000, backupCount=10, encoding="utf-8")
    fh.setFormatter(JsonFormatter())
    root.addHandler(fh)
    sh = logging.StreamHandler()
    sh.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s"))
    sh.addFilter(lambda r: setattr(r, "msg", redact(r.getMessage())) or setattr(r, "args", ()) or True)
    root.addHandler(sh)
    _configured = True


def get(name: str) -> logging.Logger:
    return logging.getLogger(f"autopilot.{name}")
