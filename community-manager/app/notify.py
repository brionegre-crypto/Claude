import logging

import httpx

log = logging.getLogger("community")


async def notify_flag(webhook_url: str, platform: str, author: str, text: str) -> None:
    msg = f"🚩 Manual review needed on {platform} from {author or 'unknown'}: {text[:500]}"
    log.warning(msg)
    if not webhook_url:
        return
    try:
        async with httpx.AsyncClient(timeout=10) as http:
            await http.post(webhook_url, json={"text": msg})
    except httpx.HTTPError as e:
        log.error("notify failed: %s", e)
