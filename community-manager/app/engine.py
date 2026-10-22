import asyncio
import logging
import random

from .claude_client import FLAG
from .config import Settings
from .meta import Event
from .notify import notify_flag
from .store import Store

log = logging.getLogger("community")


class Engine:
    """Decides what to do with each comment. Pure logic; I/O is injected."""

    def __init__(self, settings: Settings, store: Store, generate, poster, sleep=asyncio.sleep):
        self.s, self.store, self.generate, self.poster, self.sleep = settings, store, generate, poster, sleep

    def _is_own(self, ev: Event) -> bool:
        return ev.author_id in self.s.own_ids or (
            bool(self.s.ig_username) and ev.author_name.lower() == self.s.ig_username
        )

    async def handle(self, ev: Event) -> str:
        if ev.is_reply or not ev.text.strip():
            return "ignored"
        if self._is_own(ev):
            return "own"
        if not self.store.claim(ev.platform, ev.comment_id, ev.author_id, ev.text):
            return "duplicate"
        try:
            if self.store.sent_today() >= self.s.max_replies_per_day:
                self.store.finish(ev.platform, ev.comment_id, "capped")
                return "capped"

            reply = await self.generate(ev.platform, "Comment", ev.text)
            if not reply or FLAG in reply:
                self.store.finish(ev.platform, ev.comment_id, "flagged")
                await notify_flag(self.s.notify_webhook_url, ev.platform, ev.author_name, ev.text)
                return "flagged"

            if self.s.dry_run:
                self.store.finish(ev.platform, ev.comment_id, "dry_run", reply)
                log.info("[dry-run] %s -> %s", ev.text, reply)
                return "dry_run"

            await self.sleep(random.uniform(self.s.min_delay, self.s.max_delay))
            await self.poster.reply(ev, reply)
            self.store.finish(ev.platform, ev.comment_id, "sent", reply)
            await self._maybe_welcome(ev)
            return "sent"
        except Exception as e:  # never let one bad comment kill the loop
            log.exception("failed handling %s", ev.comment_id)
            self.store.finish(ev.platform, ev.comment_id, "error", detail=str(e)[:300])
            return "error"

    async def _maybe_welcome(self, ev: Event) -> None:
        if not (self.s.welcome_dm_enabled and ev.author_id):
            return
        if not self.store.first_time_author(ev.platform, ev.author_id):
            return
        try:
            dm = await self.generate(ev.platform, "New Follower", ev.text)
            if dm and FLAG not in dm:
                await self.poster.private_reply(ev, dm)
        except Exception:
            log.exception("welcome DM failed for %s", ev.comment_id)
