import os
from dataclasses import dataclass, field


def _bool(name: str, default: bool) -> bool:
    return os.environ.get(name, str(default)).strip().lower() in ("1", "true", "yes", "on")


def _int(name: str, default: int) -> int:
    raw = os.environ.get(name, "").strip()
    return int(raw) if raw else default


@dataclass
class Settings:
    anthropic_model: str = "claude-haiku-5-5"
    dry_run: bool = True
    app_secret: str = ""
    verify_token: str = ""
    page_token: str = ""
    fb_page_id: str = ""
    ig_user_id: str = ""
    ig_username: str = ""
    graph_version: str = "v21.0"
    poll_interval: int = 120
    min_delay: int = 30
    max_delay: int = 120
    max_replies_per_day: int = 150
    welcome_dm_enabled: bool = False
    contact_email: str = "you@example.com"
    admin_token: str = ""
    notify_webhook_url: str = ""
    db_path: str = "data/community.db"
    system_prompt_path: str = "prompts/system_prompt.txt"
    own_ids: set = field(default_factory=set)

    @classmethod
    def from_env(cls) -> "Settings":
        s = cls(
            anthropic_model=os.environ.get("CLAUDE_MODEL", "claude-haiku-5-5"),
            dry_run=_bool("DRY_RUN", True),
            app_secret=os.environ.get("META_APP_SECRET", ""),
            verify_token=os.environ.get("META_VERIFY_TOKEN", ""),
            page_token=os.environ.get("META_PAGE_TOKEN", ""),
            fb_page_id=os.environ.get("FB_PAGE_ID", ""),
            ig_user_id=os.environ.get("IG_USER_ID", ""),
            ig_username=os.environ.get("IG_USERNAME", "").lstrip("@").lower(),
            graph_version=os.environ.get("GRAPH_VERSION", "v21.0"),
            poll_interval=_int("POLL_INTERVAL_SECONDS", 120),
            min_delay=_int("MIN_DELAY_SECONDS", 30),
            max_delay=_int("MAX_DELAY_SECONDS", 120),
            max_replies_per_day=_int("MAX_REPLIES_PER_DAY", 150),
            welcome_dm_enabled=_bool("WELCOME_DM_ENABLED", False),
            contact_email=os.environ.get("CONTACT_EMAIL", "you@example.com"),
            admin_token=os.environ.get("ADMIN_TOKEN", ""),
            notify_webhook_url=os.environ.get("NOTIFY_WEBHOOK_URL", ""),
            db_path=os.environ.get("DB_PATH", "data/community.db"),
        )
        s.own_ids = {i for i in (s.fb_page_id, s.ig_user_id) if i}
        return s
