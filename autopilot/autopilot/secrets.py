"""Encrypted secret store (Fernet / AES-128-CBC + HMAC).

The key lives in data/.secret.key (chmod 600) unless AUTOPILOT_SECRET_KEY is set. Secrets are never logged,
never committed (data/ is git-ignored) and never returned by the dashboard (only "set"/"not set").
"""
from __future__ import annotations

import json
import os
import stat
from pathlib import Path

from cryptography.fernet import Fernet, InvalidToken


class SecretStore:
    def __init__(self, data_dir: Path):
        self.file = data_dir / "secrets.enc"
        self.key_file = data_dir / ".secret.key"
        env = os.environ.get("AUTOPILOT_SECRET_KEY")
        if env:
            key = env.encode()
        else:
            if not self.key_file.exists():
                self.key_file.write_bytes(Fernet.generate_key())
                os.chmod(self.key_file, stat.S_IRUSR | stat.S_IWUSR)
            key = self.key_file.read_bytes().strip()
        self.f = Fernet(key)

    def _load(self) -> dict:
        if not self.file.exists():
            return {}
        try:
            return json.loads(self.f.decrypt(self.file.read_bytes()))
        except InvalidToken as e:
            raise RuntimeError("Secret store cannot be decrypted with the current key") from e

    def _save(self, d: dict) -> None:
        tmp = self.file.with_suffix(".tmp")
        tmp.write_bytes(self.f.encrypt(json.dumps(d).encode()))
        os.chmod(tmp, stat.S_IRUSR | stat.S_IWUSR)
        tmp.replace(self.file)

    def get(self, name: str, default=None):
        return self._load().get(name, default)

    def set(self, name: str, value) -> None:
        d = self._load()
        d[name] = value
        self._save(d)

    def delete(self, name: str) -> None:
        d = self._load()
        d.pop(name, None)
        self._save(d)

    def names(self) -> list[str]:
        return sorted(self._load().keys())
