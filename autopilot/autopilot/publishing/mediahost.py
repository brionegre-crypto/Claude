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
    def __init__(self, port: int, binary: str = "cloudflared", protocol: str = "http2"):
        self.port, self.binary, self.protocol = port, binary, protocol
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
        # --protocol http2 = ordinary HTTPS on TCP 443. The default (QUIC over UDP 7844) is blocked by many routers.
        self.proc = subprocess.Popen([self.binary, "tunnel", "--no-autoupdate", "--protocol", self.protocol,
                                      "--url", f"http://127.0.0.1:{self.port}"],
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.log_lines: list[str] = []
        self.registered = threading.Event()

        def pump():
            for line in self.proc.stdout:
                self.log_lines = (self.log_lines + [line.rstrip()])[-25:]
                m = re.search(r"https://[a-z0-9-]+\.trycloudflare\.com", line)
                if m and not self.base:
                    self.base = m.group(0)
                if "Registered tunnel connection" in line or "Connection registered" in line:
                    self.registered.set()

        threading.Thread(target=pump, daemon=True).start()
        deadline = time.time() + 60
        while time.time() < deadline and not (self.base and self.registered.is_set()):
            if self.proc.poll() is not None:
                break
            time.sleep(0.5)
        if not self.base or not self.registered.is_set():
            tail = "\n    ".join(self.log_lines[-8:])
            self.__exit__(None, None, None)
            raise RuntimeError("cloudflared could not connect to Cloudflare (a firewall may block it). Last log lines:\n    " + tail)
        time.sleep(2)
        return self

    def url_for(self, path: str) -> str:
        p = Path(path)
        key = f"/m/{secrets.token_urlsafe(16)}/{p.name}"
        self.files[key] = p
        url = self.base + key
        for _ in range(8):  # DNS for a new quick tunnel can take a few seconds
            if self.local_ok(url):
                return url
            time.sleep(3)
        if public_dns_resolves(self.base):
            # This computer's DNS (a filter, VPN or cache) can't see the tunnel, but the public internet can,
            # so Meta can fetch the file. Give the tunnel a few more seconds to settle and go ahead.
            log.warning("tunnel not visible from this computer's DNS but resolves publicly; continuing")
            time.sleep(5)
            return url
        raise RuntimeError("tunnel URL not reachable (not even via public DNS); run: ./scripts/autopilot tunnel-test")

    @staticmethod
    def local_ok(url: str) -> bool:
        try:
            return httpx.get(url, timeout=10).status_code == 200
        except Exception:
            return False

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


def public_dns_resolves(base_url: str) -> bool:
    """Look the tunnel's hostname up through Cloudflare's public DNS-over-HTTPS (free), bypassing local DNS."""
    host = re.sub(r"^https?://", "", base_url).split("/")[0]
    for _ in range(6):
        try:
            r = httpx.get("https://cloudflare-dns.com/dns-query", params={"name": host, "type": "A"},
                          headers={"accept": "application/dns-json"}, timeout=10)
            if r.status_code == 200 and r.json().get("Answer"):
                return True
        except Exception:
            pass
        time.sleep(3)
    return False


def tunnel_test(port: int = 8766) -> list[str]:
    """Diagnose the Instagram image hand-off. Returns human-readable lines."""
    import socket
    import tempfile
    out = []
    tmp = Path(tempfile.mkdtemp()) / "tunnel-test.jpg"
    tmp.write_bytes(b"\xff\xd8\xff\xe0tunnel-test")
    try:
        t = TunnelHost(port).__enter__()
    except RuntimeError as e:
        return [f"✗ {e}"]
    try:
        out.append(f"tunnel started and connected to Cloudflare: {t.base}")
        key = f"/m/{secrets.token_urlsafe(16)}/{tmp.name}"
        t.files[key] = tmp
        url = t.base + key
        host = t.base.split("//")[1]
        time.sleep(5)
        try:
            socket.gethostbyname(host)
            out.append("✓ this Mac's DNS can resolve the tunnel")
        except Exception as e:
            out.append(f"✗ this Mac's DNS cannot resolve it ({e}): a DNS filter, VPN, ad-blocker or router security feature may block trycloudflare.com")
        out.append(("✓" if public_dns_resolves(t.base) else "✗") + " public DNS (what Instagram uses) can resolve it")
        ok = any(TunnelHost.local_ok(url) or time.sleep(3) for _ in range(5))
        out.append(("✓" if ok else "✗") + " fetched the test file through the tunnel from this Mac")
        if not ok:
            out.append("  cloudflared log (last lines):")
            out += ["    " + l for l in t.log_lines[-6:]]
    finally:
        t.__exit__(None, None, None)
    return out


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
