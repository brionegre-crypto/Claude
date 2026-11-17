"""Instagram fetches images from a public HTTPS URL (there is no direct image upload). Videos use Meta's resumable
upload instead, so they need no hosting. Two zero-cost options:

- TunnelHost: serves only the files of the post being published, under a random one-time path, through a Cloudflare
  quick tunnel (`cloudflared`, free, no account). The tunnel exists only for the minutes of the publish call.
- PublicURLHost: you already sync data/assets to an https static host you own; we map paths onto that base URL.
"""
from __future__ import annotations

import http.server
import re
import secrets
import shutil
import subprocess
import threading
import time
from pathlib import Path

import httpx

from autopilot import logs

log = logs.get("mediahost")


class _Handler(http.server.BaseHTTPRequestHandler):
    files: dict[str, Path] = {}

    def do_GET(self):  # noqa: N802
        p = self.files.get(self.path.split("?")[0])
        if not p or not p.exists():
            self.send_error(404)
            return
        data = p.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg" if p.suffix.lower() in (".jpg", ".jpeg") else "video/mp4")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_HEAD = do_GET

    def log_message(self, *a):
        pass


class TunnelHost:
    def __init__(self, port: int, binary: str = "cloudflared"):
        self.port, self.binary = port, binary
        self.proc = None
        self.server = None
        self.base = None
        self.files: dict[str, Path] = {}

    def __enter__(self):
        if not shutil.which(self.binary):
            raise RuntimeError("cloudflared not installed (free). Run the setup wizard or see docs/OPERATIONS.md")
        handler = type("H", (_Handler,), {"files": self.files})
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", self.port), handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.proc = subprocess.Popen([self.binary, "tunnel", "--no-autoupdate", "--url", f"http://127.0.0.1:{self.port}"],
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        deadline = time.time() + 45
        while time.time() < deadline and not self.base:
            line = self.proc.stdout.readline()
            m = re.search(r"https://[a-z0-9-]+\.trycloudflare\.com", line or "")
            if m:
                self.base = m.group(0)
        if not self.base:
            self.__exit__(None, None, None)
            raise RuntimeError("cloudflared tunnel did not start")
        threading.Thread(target=lambda: [None for _ in self.proc.stdout], daemon=True).start()
        return self

    def url_for(self, path: str) -> str:
        p = Path(path)
        key = f"/m/{secrets.token_urlsafe(16)}/{p.name}"
        self.files[key] = p
        url = self.base + key
        for _ in range(20):  # DNS for a new quick tunnel can take a few seconds
            try:
                if httpx.head(url, timeout=10).status_code == 200:
                    return url
            except Exception:
                pass
            time.sleep(3)
        raise RuntimeError("tunnel URL not reachable")

    def __exit__(self, *exc):
        if self.proc:
            self.proc.terminate()
            try:
                self.proc.wait(10)
            except Exception:
                self.proc.kill()
        if self.server:
            self.server.shutdown()
            self.server.server_close()
        self.files.clear()


class PublicURLHost:
    def __init__(self, base_url: str, assets_dir: Path):
        self.base, self.assets_dir = base_url.rstrip("/"), assets_dir

    def __enter__(self):
        return self

    def url_for(self, path: str) -> str:
        rel = Path(path).resolve().relative_to(self.assets_dir.resolve())
        return f"{self.base}/{rel.as_posix()}"

    def __exit__(self, *exc):
        pass


def get_host(s):
    if s.get("publishing.media_host") == "public_url":
        return PublicURLHost(s.get("publishing.public_media_base_url"), s.assets_dir)
    return TunnelHost(int(s.get("publishing.local_media_port", 8766)))
