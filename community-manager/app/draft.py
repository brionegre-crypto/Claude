"""TikTok (and anything else without API access): paste comments, get replies to post by hand.

    python -m app.draft                     # interactive
    python -m app.draft comments.txt        # one comment per line -> prints replies
"""
import asyncio
import sys
from pathlib import Path

from .claude_client import FLAG, ReplyGenerator
from .config import Settings


async def main() -> None:
    s = Settings.from_env()
    gen = ReplyGenerator(Path(s.system_prompt_path).read_text(), s.anthropic_model, s.contact_email)
    platform = "TikTok"
    if len(sys.argv) > 1:
        lines = [l.strip() for l in Path(sys.argv[1]).read_text().splitlines() if l.strip()]
    else:
        print("Paste a TikTok comment per line (empty line to quit):")
        lines = iter(lambda: input("> ").strip(), "")
    for line in lines:
        reply = await gen(platform, "Comment", line)
        print(f"  {'🚩 REVIEW' if FLAG in reply else '↳'} {reply}\n")


if __name__ == "__main__":
    asyncio.run(main())
