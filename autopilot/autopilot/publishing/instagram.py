"""Instagram publishing through the official Instagram API with Instagram Login (graph.instagram.com).

Needs a Professional (Business or Creator) account; Stories via API are documented for Business accounts.
Scopes: instagram_business_basic, instagram_business_content_publish, instagram_business_manage_insights.
Free: a Meta developer app in Development mode works for your own account (added as an Instagram tester).
"""
from __future__ import annotations

import json
import re
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx

from autopilot import logs
from autopilot.publishing.base import (AuthError, Capability, PermanentError, PublishResult, Publisher, RateLimited,
                                       TemporaryError)

log = logs.get("instagram")
RATE_CODES = {4, 17, 32, 613, 80002}
TEMP_CODES = {1, 2, 9004, 9007, 2207001, 2207003, 2207008, 2207032}
AUTH_CODES = {102, 190, 10, 200, 3, 463, 467}


def caption_key(text: str) -> str:
    return re.sub(r"\W+", "", (text or "").lower())[:120]


class InstagramPublisher(Publisher):
    platform = "instagram"
    name = "instagram_graph"

    def __init__(self, s, secrets, client: httpx.Client | None = None, media_host_factory=None, sleep=time.sleep):
        self.s, self.secrets = s, secrets
        self.base = f"{s.get('publishing.instagram_api_host')}/{s.get('publishing.instagram_api_version')}"
        self.client = client or httpx.Client(timeout=60)
        self.media_host_factory = media_host_factory
        self.sleep = sleep

    # ---- plumbing -------------------------------------------------------------------------------------------
    @property
    def token(self) -> str:
        t = self.secrets.get("instagram_access_token")
        if not t:
            raise AuthError("Instagram is not connected (run the setup wizard)")
        return t

    @property
    def uid(self) -> str:
        u = self.secrets.get("instagram_user_id")
        if not u:
            raise AuthError("Instagram user id missing (run the setup wizard)")
        return u

    def _call(self, method: str, path: str, **params) -> dict:
        url = path if path.startswith("http") else f"{self.base}/{path.lstrip('/')}"
        try:
            if method == "GET":
                r = self.client.get(url, params={**params, "access_token": self.token})
            else:
                r = self.client.post(url, data={**params, "access_token": self.token})
        except httpx.TransportError as e:
            raise TemporaryError(f"network error: {e.__class__.__name__}") from None
        return self._handle(r)

    @staticmethod
    def _handle(r: httpx.Response) -> dict:
        try:
            data = r.json()
        except Exception:
            data = {}
        if r.status_code < 400 and "error" not in data:
            return data
        err = data.get("error", {}) if isinstance(data, dict) else {}
        code, sub = err.get("code"), err.get("error_subcode")
        msg = f"HTTP {r.status_code} code={code} subcode={sub}: {err.get('message', r.text[:200])}"
        if r.status_code == 429 or code in RATE_CODES:
            raise RateLimited(msg, retry_after=3600)
        if code in AUTH_CODES or r.status_code in (401,):
            raise AuthError(msg)
        if r.status_code >= 500 or code in TEMP_CODES or err.get("is_transient"):
            raise TemporaryError(msg)
        raise PermanentError(msg)

    def _wait_ready(self, container_id: str, timeout: int = 600) -> None:
        deadline = time.monotonic() + timeout
        delay = 3
        while True:
            st = self._call("GET", container_id, fields="status_code,status").get("status_code")
            if st in ("FINISHED", "PUBLISHED"):
                return
            if st in ("ERROR", "EXPIRED"):
                raise PermanentError(f"container {container_id} status {st}")
            if time.monotonic() > deadline:
                raise TemporaryError(f"container {container_id} not ready after {timeout}s")
            self.sleep(delay)
            delay = min(delay * 2, 30)

    def _check_quota(self) -> None:
        try:
            d = self._call("GET", f"{self.uid}/content_publishing_limit", fields="quota_usage,config")
            row = (d.get("data") or [{}])[0]
            usage, total = row.get("quota_usage", 0), (row.get("config") or {}).get("quota_total", 100)
            if usage >= total:
                raise RateLimited(f"Instagram publishing quota used ({usage}/{total} in 24h)", retry_after=3600)
        except RateLimited:
            raise
        except (TemporaryError, PermanentError) as e:
            log.info("quota check unavailable: %s", e)

    def _resumable_video(self, video: Path, media_type: str, on_container, **extra) -> str:
        c = self._call("POST", f"{self.uid}/media", media_type=media_type, upload_type="resumable", **extra)
        cid, uri = c["id"], c.get("uri") or f"https://rupload.facebook.com/ig-api-upload/{self.s.get('publishing.instagram_api_version')}/{c['id']}"
        on_container(cid)
        data = video.read_bytes()
        try:
            r = self.client.post(uri, content=data, headers={"Authorization": f"OAuth {self.token}", "offset": "0",
                                                              "file_size": str(len(data))}, timeout=600)
        except httpx.TransportError as e:
            raise TemporaryError(f"upload network error: {e.__class__.__name__}") from None
        self._handle(r)
        return cid

    # ---- interface ------------------------------------------------------------------------------------------
    def capabilities(self):
        return [
            Capability("instagram", "image", True, "Graph API image container (JPEG via public URL)", "Business/Creator account"),
            Capability("instagram", "carousel", True, "Graph API CAROUSEL (2-10 items)", "Business/Creator account"),
            Capability("instagram", "reel", True, "Graph API REELS, resumable upload", "Business/Creator; audio is original"),
            Capability("instagram", "story", True, "Graph API STORIES (image)", "Business account; no interactive stickers via API"),
        ]

    def publish(self, content: dict, assets: list[dict], on_container) -> PublishResult:
        fmt = content["format"]
        caption = content["caption_full"]
        self._check_quota()
        imgs = sorted([a for a in assets if a["kind"] == "image"], key=lambda a: a["ordinal"])
        if fmt == "reel":
            video = next(a for a in assets if a["kind"] == "video")
            cid = self._resumable_video(Path(video["path"]), "REELS", on_container, caption=caption, share_to_feed="true", thumb_offset="0")
        else:
            if not self.media_host_factory:
                raise PermanentError("no media host configured for image publishing")
            with self.media_host_factory() as host:
                if fmt == "image":
                    cid = self._call("POST", f"{self.uid}/media", image_url=host.url_for(imgs[0]["path"]), caption=caption)["id"]
                elif fmt == "story":
                    cid = self._call("POST", f"{self.uid}/media", image_url=host.url_for(imgs[0]["path"]), media_type="STORIES")["id"]
                elif fmt == "carousel":
                    children = [self._call("POST", f"{self.uid}/media", image_url=host.url_for(a["path"]), is_carousel_item="true")["id"]
                                for a in imgs[:10]]
                    for ch in children:
                        self._wait_ready(ch, 300)
                    cid = self._call("POST", f"{self.uid}/media", media_type="CAROUSEL", children=",".join(children), caption=caption)["id"]
                else:
                    raise PermanentError(f"unsupported Instagram format {fmt}")
                on_container(cid)
                self._wait_ready(cid)  # Meta fetches the image while the tunnel is still up
        if fmt == "reel":
            self._wait_ready(cid, 900)
        pub = self._call("POST", f"{self.uid}/media_publish", creation_id=cid)
        mid = pub["id"]
        link = None
        try:
            link = self._call("GET", mid, fields="permalink").get("permalink")
        except Exception:
            pass
        return PublishResult(post_id=mid, permalink=link, raw={"container_id": cid})

    def reconcile(self, content: dict, container_id: str | None) -> PublishResult | None:
        """Never double-post: look at the account's recent media for this caption (stories have no caption: use time)."""
        if container_id:
            try:
                st = self._call("GET", container_id, fields="status_code").get("status_code")
                if st not in ("PUBLISHED",) and content["format"] != "story":
                    # FINISHED/ERROR/EXPIRED means media_publish never succeeded with this container
                    if st in ("ERROR", "EXPIRED", "FINISHED", "IN_PROGRESS"):
                        return None
            except PermanentError:
                pass
        edge = "stories" if content["format"] == "story" else "media"
        data = self._call("GET", f"{self.uid}/{edge}", fields="id,caption,timestamp,permalink,media_type", limit=25).get("data", [])
        key = caption_key(content.get("caption_full", ""))
        since = datetime.fromisoformat(content["scheduled_at"]) - timedelta(hours=2)
        for m in data:
            ts = datetime.strptime(m["timestamp"], "%Y-%m-%dT%H:%M:%S%z") if m.get("timestamp") else None
            if ts and ts < since:
                continue
            if (key and caption_key(m.get("caption", "")) == key) or (content["format"] == "story" and ts):
                return PublishResult(post_id=m["id"], permalink=m.get("permalink"), raw={"reconciled": True})
        return None

    def check_auth(self) -> tuple[bool, str]:
        try:
            me = self._call("GET", "me", fields="user_id,username,account_type")
        except Exception as e:
            return False, str(e)
        exp = self.secrets.get("instagram_token_expires_at")
        days = None
        if exp:
            days = (datetime.fromisoformat(exp) - datetime.now(timezone.utc)).days
        return True, f"@{me.get('username')} ({me.get('account_type')})" + (f", token expires in {days} days" if days is not None else "")

    def refresh_token(self) -> str:
        """Long-lived Instagram Login tokens last 60 days and can be refreshed when >24h old. Free."""
        r = self.client.get(f"{self.s.get('publishing.instagram_api_host')}/refresh_access_token",
                            params={"grant_type": "ig_refresh_token", "access_token": self.token})
        d = self._handle(r)
        self.secrets.set("instagram_access_token", d["access_token"])
        exp = datetime.now(timezone.utc) + timedelta(seconds=int(d.get("expires_in", 5184000)))
        self.secrets.set("instagram_token_expires_at", exp.isoformat())
        return exp.isoformat()

    def exchange_long_lived(self, short_token: str, app_secret: str) -> dict:
        r = self.client.get(f"{self.s.get('publishing.instagram_api_host')}/access_token",
                            params={"grant_type": "ig_exchange_token", "client_secret": app_secret, "access_token": short_token})
        return self._handle(r)

    METRICS = {
        "reel": ["reach", "views", "likes", "comments", "shares", "saved", "total_interactions"],
        "story": ["reach", "views", "replies", "shares", "total_interactions"],
        "image": ["reach", "views", "likes", "comments", "shares", "saved", "total_interactions"],
        "carousel": ["reach", "views", "likes", "comments", "shares", "saved", "total_interactions"],
    }

    def media_insights(self, post_id: str, fmt: str) -> dict:
        out = {}
        metrics = self.METRICS.get(fmt, self.METRICS["image"])
        try:
            d = self._call("GET", f"{post_id}/insights", metric=",".join(metrics))
            rows = d.get("data", [])
        except PermanentError:
            rows = []
            for m in metrics:  # one unsupported metric fails the whole call: fall back one by one
                try:
                    rows += self._call("GET", f"{post_id}/insights", metric=m).get("data", [])
                except PermanentError:
                    continue
        for row in rows:
            vals = row.get("values") or [{}]
            v = row.get("total_value", {}).get("value", vals[0].get("value"))
            if isinstance(v, (int, float)):
                out[row["name"]] = v
        return out

    def account_insights(self) -> dict:
        d = self._call("GET", "me", fields="followers_count,follows_count,media_count")
        return {k: d[k] for k in ("followers_count", "follows_count", "media_count") if k in d}
