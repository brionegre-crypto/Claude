"""Dashboard security: loopback-only bind, login token, signed session cookie, CSRF double-submit, Host check."""
from __future__ import annotations

import hashlib
import hmac
import os
import secrets
import stat
import time


def ensure_token(s, reset: bool = False) -> str:
    f = s.data_dir / ".dashboard_token"
    if reset or not f.exists():
        f.write_text(secrets.token_urlsafe(24))
        os.chmod(f, stat.S_IRUSR | stat.S_IWUSR)
    return f.read_text().strip()


def _key(s) -> bytes:
    f = s.data_dir / ".session_key"
    if not f.exists():
        f.write_bytes(secrets.token_bytes(32))
        os.chmod(f, stat.S_IRUSR | stat.S_IWUSR)
    return f.read_bytes()


def make_session(s, ttl=7 * 86400) -> str:
    exp = str(int(time.time()) + ttl)
    csrf = secrets.token_urlsafe(16)
    payload = f"{exp}.{csrf}"
    sig = hmac.new(_key(s), payload.encode(), hashlib.sha256).hexdigest()
    return f"{payload}.{sig}"


def read_session(s, cookie: str | None) -> str | None:
    """Returns the CSRF token bound to a valid session, else None."""
    if not cookie or cookie.count(".") != 2:
        return None
    exp, csrf, sig = cookie.split(".")
    good = hmac.new(_key(s), f"{exp}.{csrf}".encode(), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(sig, good) or int(exp) < time.time():
        return None
    return csrf
