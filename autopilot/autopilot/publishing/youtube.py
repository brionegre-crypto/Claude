"""YouTube Community posts.

The YouTube Data API v3 has no endpoint to create Community posts (text, image, poll or quiz), and YouTube's Terms
of Service forbid accessing the service by automated means outside the API. So publishing is ASSISTED: the system
researches, writes and renders the post, then at the scheduled time sends you a notification and shows it on the
dashboard with one-click copy. You can also batch-schedule a week at once with YouTube Studio's own post scheduler.

Free analytics that IS available: public channel statistics (subscribers, views, video count) with a free YouTube
Data API key (10,000 quota units/day; channels.list costs 1 unit).
"""
from __future__ import annotations

import httpx

from autopilot.publishing.base import Capability, PermanentError, Publisher


class YouTubeCommunityAssisted(Publisher):
    platform = "youtube"
    name = "youtube_assisted"

    def __init__(self, s, secrets, client: httpx.Client | None = None):
        self.s, self.secrets = s, secrets
        self.client = client or httpx.Client(timeout=30)

    def capabilities(self):
        note = "No official API; YouTube ToS forbids automating the site. Assisted: notification + copy + mark posted."
        return [Capability("youtube", f, False, "assisted (manual tap)", note)
                for f in ("community_text", "community_image", "community_poll", "community_quiz")]

    def publish(self, content, assets, on_container):
        raise PermanentError("YouTube Community posts cannot be published autonomously (no official API)")

    def check_auth(self):
        key, ch = self.secrets.get("youtube_api_key"), self.s.get("youtube.channel_id") or self.secrets.get("youtube_channel_id")
        if not key or not ch:
            return False, "optional: add a free YouTube Data API key + channel id for subscriber stats"
        try:
            self.account_insights()
            return True, "YouTube stats API key works"
        except Exception as e:
            return False, str(e)

    def account_insights(self) -> dict:
        key = self.secrets.get("youtube_api_key")
        ch = self.s.get("youtube.channel_id") or self.secrets.get("youtube_channel_id")
        if not key or not ch:
            return {}
        r = self.client.get("https://www.googleapis.com/youtube/v3/channels", params={"part": "statistics", "id": ch, "key": key})
        r.raise_for_status()
        items = r.json().get("items", [])
        if not items:
            return {}
        st = items[0]["statistics"]
        out = {"view_count": float(st.get("viewCount", 0)), "video_count": float(st.get("videoCount", 0))}
        if not st.get("hiddenSubscriberCount"):
            out["subscriber_count"] = float(st.get("subscriberCount", 0))
        return out
