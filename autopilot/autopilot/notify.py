"""Notifications: always to the dashboard + log; optionally to free channels (ntfy.sh push, Discord/Slack webhook,
SMTP email with your own mailbox). Nothing paid."""
from __future__ import annotations

import json
import smtplib
from email.message import EmailMessage

import httpx

from autopilot import logs
from autopilot.db import DB, iso

log = logs.get("notify")
PUSH_LEVELS = {"error", "warning", "success", "report"}


def _channels(s) -> list[str]:
    out = []
    if s.get("notifications.ntfy_topic"):
        out.append("ntfy")
    if s.get("notifications.webhook_url"):
        out.append("webhook")
    if s.get("notifications.email_to") and s.get("notifications.smtp_host"):
        out.append("email")
    return out


def send_external(s, title: str, body: str, level: str = "info", channels: list[str] | None = None) -> dict:
    results = {}
    for ch in channels if channels is not None else _channels(s):
        try:
            if ch == "ntfy":
                httpx.post(f"https://ntfy.sh/{s.get('notifications.ntfy_topic')}", content=body.encode()[:4000],
                           headers={"Title": title[:200].encode("ascii", "ignore").decode(),
                                    "Priority": "high" if level == "error" else "default"}, timeout=15).raise_for_status()
            elif ch == "webhook":
                httpx.post(s.get("notifications.webhook_url"), json={"content": f"**{title}**\n{body}"[:1900], "text": f"*{title}*\n{body}"},
                           timeout=15).raise_for_status()
            elif ch == "email":
                from autopilot.secrets import SecretStore
                pw = SecretStore(s.data_dir).get("smtp_password")
                msg = EmailMessage()
                msg["Subject"], msg["From"], msg["To"] = f"[Autopilot] {title}", s.get("notifications.smtp_user"), s.get("notifications.email_to")
                msg.set_content(body)
                with smtplib.SMTP(s.get("notifications.smtp_host"), int(s.get("notifications.smtp_port", 587)), timeout=20) as m:
                    m.starttls()
                    if pw:
                        m.login(s.get("notifications.smtp_user"), pw)
                    m.send_message(msg)
            results[ch] = "ok"
        except Exception as e:
            results[ch] = f"failed: {e}"
            log.warning("notification channel %s failed: %s", ch, e)
    return results


def notify(s, db: DB, level: str, category: str, title: str, body: str = "", external: bool | None = None) -> int:
    getattr(log, "error" if level == "error" else "warning" if level == "warning" else "info")("%s: %s %s", category, title, body[:300])
    nid = db.x("INSERT INTO notifications(created_at,level,category,title,body) VALUES(?,?,?,?,?)", (iso(), level, category, title, body))
    if external is None:
        external = level in PUSH_LEVELS
    if external and _channels(s):
        res = send_external(s, title, body, level)
        db.x("UPDATE notifications SET delivered=? WHERE id=?", (json.dumps(res), nid))
    return nid
