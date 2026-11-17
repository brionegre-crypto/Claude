from __future__ import annotations

from dataclasses import dataclass, field


class PublishError(Exception):
    temporary = False


class TemporaryError(PublishError):
    temporary = True

    def __init__(self, msg, retry_after: int | None = None):
        super().__init__(msg)
        self.retry_after = retry_after


class PermanentError(PublishError):
    pass


class AuthError(PermanentError):
    pass


class RateLimited(TemporaryError):
    pass


@dataclass
class PublishResult:
    post_id: str
    permalink: str | None = None
    raw: dict = field(default_factory=dict)


@dataclass
class Capability:
    platform: str
    format: str
    autonomous: bool
    method: str
    notes: str


class Publisher:
    platform = ""
    name = ""

    def capabilities(self) -> list[Capability]:
        raise NotImplementedError

    def autonomous(self, fmt: str) -> bool:
        return any(c.format == fmt and c.autonomous for c in self.capabilities())

    def publish(self, content: dict, assets: list[dict], on_container) -> PublishResult:
        raise NotImplementedError

    def reconcile(self, content: dict, container_id: str | None) -> PublishResult | None:
        """After a crash/timeout: return the existing post if it was in fact published, else None."""
        return None

    def check_auth(self) -> tuple[bool, str]:
        return True, "n/a"

    def media_insights(self, post_id: str, fmt: str) -> dict:
        return {}

    def account_insights(self) -> dict:
        return {}
