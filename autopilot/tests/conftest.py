import json
import os
import re
import shutil
import sys
from pathlib import Path

import httpx
import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
os.environ.pop("ANTHROPIC_API_KEY", None)


@pytest.fixture
def env(tmp_path, monkeypatch):
    cfg = (ROOT / "config" / "settings.example.toml").read_text()
    cfg = cfg.replace('provider = "claude_cli"', 'provider = "mock"').replace('feeds = [', 'feeds_unused = [')
    cfg = cfg.replace('[research]\n', '[research]\nfeeds = []\n')
    p = tmp_path / "settings.toml"
    p.write_text(cfg)
    monkeypatch.setenv("AUTOPILOT_CONFIG", str(p))
    monkeypatch.setenv("AUTOPILOT_DATA_DIR", str(tmp_path / "data"))
    from autopilot import config
    from autopilot.db import DB
    s = config.load(p)
    db = DB(s.db_path)
    yield s, db
    db.close()


class FakeIG:
    """In-memory Instagram Graph API (Instagram Login flavour) for publishing tests."""

    def __init__(self):
        self.containers = {}
        self.media = []
        self.n = 0
        self.fail_next = []          # list of ("publish"|"create"|"upload", kind) where kind in rate|auth|transient|timeout_after|permanent
        self.uploads = 0
        self.publish_calls = 0

    def _id(self, prefix):
        self.n += 1
        return f"{prefix}{self.n}"

    def _maybe_fail(self, op):
        for i, (o, kind) in enumerate(self.fail_next):
            if o == op:
                self.fail_next.pop(i)
                return kind
        return None

    def err(self, code, status=400, transient=False):
        return httpx.Response(status, json={"error": {"message": "fake", "code": code, "is_transient": transient}})

    def handler(self, req: httpx.Request):
        url = str(req.url)
        path = req.url.path
        form = dict(httpx.QueryParams(req.content.decode())) if req.method == "POST" and req.headers.get("content-type", "").startswith("application/x-www-form") else {}
        if "rupload" in url:
            self.uploads += 1
            cid = path.rsplit("/", 1)[-1]
            self.containers[cid]["status"] = "FINISHED"
            return httpx.Response(200, json={"success": True})
        if path.endswith("/content_publishing_limit"):
            return httpx.Response(200, json={"data": [{"quota_usage": len(self.media), "config": {"quota_total": 100}}]})
        if path.endswith("/media") and req.method == "POST":
            k = self._maybe_fail("create")
            if k == "rate":
                return self.err(4, 400)
            if k == "auth":
                return self.err(190, 400)
            cid = self._id("c")
            resumable = form.get("upload_type") == "resumable"
            self.containers[cid] = {"status": "IN_PROGRESS" if resumable else "FINISHED", "params": form, "published": False}
            out = {"id": cid}
            if resumable:
                out["uri"] = f"https://rupload.facebook.com/ig-api-upload/v23.0/{cid}"
            return httpx.Response(200, json=out)
        if path.endswith("/media_publish"):
            self.publish_calls += 1
            k = self._maybe_fail("publish")
            if k == "rate":
                return self.err(4, 400)
            if k == "transient":
                return self.err(2, 500, True)
            if k == "permanent":
                return self.err(100, 400)
            if k == "auth":
                return self.err(190, 400)
            cid = form["creation_id"]
            c = self.containers[cid]
            if c["published"]:
                return self.err(100, 400)
            c["published"] = True
            c["status"] = "PUBLISHED"
            mid = self._id("m")
            p = c["params"]
            self.media.append({"id": mid, "caption": p.get("caption", ""), "timestamp": "2099-01-01T00:00:00+0000",
                               "permalink": f"https://instagram.com/p/{mid}", "media_type": p.get("media_type", "IMAGE")})
            if k == "timeout_after":
                raise httpx.ReadTimeout("simulated timeout after publish", request=req)
            return httpx.Response(200, json={"id": mid})
        if path.endswith("/media") and req.method == "GET":
            return httpx.Response(200, json={"data": list(reversed(self.media))})
        if path.endswith("/stories"):
            return httpx.Response(200, json={"data": [m for m in self.media if m["media_type"] == "STORIES"]})
        if path.endswith("/insights"):
            return httpx.Response(200, json={"data": [{"name": m, "values": [{"value": 10}]} for m in req.url.params["metric"].split(",")]})
        if path.endswith("/me"):
            return httpx.Response(200, json={"user_id": "17841", "username": "bethemansystem", "account_type": "BUSINESS",
                                             "followers_count": 1000, "follows_count": 10, "media_count": len(self.media)})
        seg = path.rsplit("/", 1)[-1]
        if seg == "17841":
            return httpx.Response(200, json={"id": "17841", "username": "bethemansystem", "followers_count": 1000,
                                             "follows_count": 10, "media_count": len(self.media)})
        if seg in self.containers:
            return httpx.Response(200, json={"status_code": self.containers[seg]["status"]})
        for m in self.media:
            if m["id"] == seg:
                return httpx.Response(200, json={"permalink": m["permalink"]})
        return httpx.Response(404, json={"error": {"message": "not found " + path, "code": 803}})


class FakeHost:
    def __enter__(self):
        return self

    def __exit__(self, *a):
        pass

    def url_for(self, path):
        return "https://fake.example/" + Path(path).name


@pytest.fixture
def fake_ig(env):
    s, db = env
    from autopilot.publishing.instagram import InstagramPublisher
    from autopilot.secrets import SecretStore
    sec = SecretStore(s.data_dir)
    sec.set("instagram_access_token", "IGtesttoken1234567890")
    sec.set("instagram_user_id", "17841")
    fake = FakeIG()
    client = httpx.Client(transport=httpx.MockTransport(fake.handler))
    ig = InstagramPublisher(s, sec, client=client, media_host_factory=FakeHost, sleep=lambda x: None)
    from autopilot.publishing.youtube import YouTubeCommunityAssisted
    return fake, {"instagram": ig, "youtube": YouTubeCommunityAssisted(s, sec)}


def make_ready(s, db, fmt="image", platform="instagram", minutes_ago=1, caption=None):
    """Create a generated, rendered, ready content row due now."""
    import uuid
    from datetime import timedelta
    from autopilot import generation
    from autopilot.ai.provider import MockProvider
    from autopilot.db import iso, utcnow
    from autopilot import research
    research.seed_evergreen(s, db)
    cid = str(uuid.uuid4())
    db.x("INSERT INTO content(id,platform,format,status,scheduled_at,slot_key,created_at,updated_at) VALUES(?,?,?,'planned',?,?,?,?)",
         (cid, platform, fmt, iso(utcnow() + timedelta(days=1)), f"t|{cid}", iso(), iso()))
    res = generation.generate_one(s, db, MockProvider(s, db), dict(db.one("SELECT * FROM content WHERE id=?", (cid,))))
    assert res["status"] == "ready", res
    if caption:
        db.x("UPDATE content SET caption=? WHERE id=?", (caption, cid))
    db.x("UPDATE content SET scheduled_at=? WHERE id=?", (iso(utcnow() - timedelta(minutes=minutes_ago)), cid))
    return cid
