"""Meta Graph API: webhook parsing/verification, replying, and polling fallback."""
import hashlib
import hmac
from dataclasses import dataclass

import httpx

from .config import Settings


@dataclass
class Event:
    platform: str  # "Instagram" | "Facebook"
    comment_id: str
    text: str
    author_id: str = ""
    author_name: str = ""
    is_reply: bool = False  # reply inside a thread; we only answer top-level comments


def valid_signature(app_secret: str, body: bytes, header: str) -> bool:
    expected = "sha256=" + hmac.new(app_secret.encode(), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header or "")


def parse_webhook(payload: dict) -> list[Event]:
    events: list[Event] = []
    for entry in payload.get("entry", []):
        for ch in entry.get("changes", []):
            v = ch.get("value", {})
            if ch.get("field") == "comments":  # Instagram
                frm = v.get("from", {})
                events.append(Event(
                    "Instagram", v.get("id", ""), v.get("text", ""),
                    frm.get("id", ""), frm.get("username", ""), bool(v.get("parent_id")),
                ))
            elif ch.get("field") == "feed" and v.get("item") == "comment" and v.get("verb") == "add":
                frm = v.get("from", {})
                events.append(Event(
                    "Facebook", v.get("comment_id", ""), v.get("message", ""),
                    frm.get("id", ""), frm.get("name", ""),
                    v.get("parent_id") not in (None, v.get("post_id")),
                ))
    return [e for e in events if e.comment_id]


class MetaClient:
    def __init__(self, s: Settings, http: httpx.AsyncClient | None = None):
        self.s = s
        self.http = http or httpx.AsyncClient(timeout=20)
        self.base = f"https://graph.facebook.com/{s.graph_version}"

    async def _post(self, path: str, **kw) -> dict:
        r = await self.http.post(f"{self.base}/{path}", params={"access_token": self.s.page_token}, **kw)
        r.raise_for_status()
        return r.json()

    async def _get(self, path: str, **params) -> dict:
        r = await self.http.get(f"{self.base}/{path}", params={**params, "access_token": self.s.page_token})
        r.raise_for_status()
        return r.json()

    async def reply(self, ev: Event, text: str) -> None:
        if ev.platform == "Instagram":
            await self._post(f"{ev.comment_id}/replies", data={"message": text})
        else:
            await self._post(f"{ev.comment_id}/comments", data={"message": text})

    async def private_reply(self, ev: Event, text: str) -> None:
        """One DM per comment, within 7 days. Needs messaging permissions."""
        owner = self.s.ig_user_id if ev.platform == "Instagram" else self.s.fb_page_id
        await self._post(
            f"{owner}/messages",
            json={"recipient": {"comment_id": ev.comment_id}, "message": {"text": text}},
        )

    # ---- polling fallback (works even if comment webhooks need Advanced Access) ----
    async def poll(self) -> list[Event]:
        events: list[Event] = []
        if self.s.ig_user_id:
            media = await self._get(f"{self.s.ig_user_id}/media", fields="id", limit=10)
            for m in media.get("data", []):
                c = await self._get(f"{m['id']}/comments", fields="id,text,username,from,parent_id", limit=50)
                for x in c.get("data", []):
                    events.append(Event(
                        "Instagram", x["id"], x.get("text", ""),
                        x.get("from", {}).get("id", ""), x.get("username", ""), bool(x.get("parent_id")),
                    ))
        if self.s.fb_page_id:
            posts = await self._get(f"{self.s.fb_page_id}/posts", fields="id", limit=10)
            for p in posts.get("data", []):
                c = await self._get(f"{p['id']}/comments", fields="id,message,from", filter="toplevel", limit=50)
                for x in c.get("data", []):
                    events.append(Event(
                        "Facebook", x["id"], x.get("message", ""),
                        x.get("from", {}).get("id", ""), x.get("from", {}).get("name", ""),
                    ))
        return events
