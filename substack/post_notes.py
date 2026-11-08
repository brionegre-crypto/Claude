#!/usr/bin/env python3
"""Posts due Substack Notes from notes.json using your own logged-in browser session.

Setup (once):
  pip install playwright && playwright install chromium
  python3 post_notes.py --login      # opens a browser; log in to Substack yourself (2FA included), then close it

Then run on a schedule (every 15 min), e.g. crontab:
  */15 * * * * cd /path/to/substack && python3 post_notes.py >> post.log 2>&1

Flags: --dry-run (print what would post), --login, --limit N (max notes per run, default 1)
State is kept in posted.json so nothing is ever posted twice.
"""
import argparse, json, sys, time
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).parent
NOTES, STATE, PROFILE = HERE / "notes.json", HERE / "posted.json", HERE / ".browser-profile"
NOTES_URL = "https://substack.com/notes"
LATE_LIMIT_HOURS = 12  # skip anything more than this overdue instead of dumping a backlog

def load_state():
    return set(json.loads(STATE.read_text())) if STATE.exists() else set()

def due(notes, done):
    now = datetime.now(timezone.utc)
    for n in notes:
        if n["id"] in done:
            continue
        age = (now - datetime.fromisoformat(n["post_at"])).total_seconds() / 3600
        if age >= 0:
            yield n, age

def post_one(page, text):
    page.goto(NOTES_URL, wait_until="domcontentloaded")
    page.wait_for_timeout(3000)
    if "sign-in" in page.url or page.get_by_text("Sign in", exact=True).count():
        raise RuntimeError("Not logged in. Run: python3 post_notes.py --login")
    # Open the composer, type, post. Selectors are text/role based; Substack changes its UI,
    # so if this breaks, adjust the two locators below.
    page.get_by_text("What's on your mind?").first.click()
    box = page.locator('[contenteditable="true"]').last
    box.click()
    page.keyboard.insert_text(text)
    page.wait_for_timeout(800)
    page.get_by_role("button", name="Post", exact=True).last.click()
    page.wait_for_timeout(3000)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--login", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=1)
    a = ap.parse_args()
    notes, done = json.loads(NOTES.read_text()), load_state()

    if a.login:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as p:
            ctx = p.chromium.launch_persistent_context(str(PROFILE), headless=False)
            ctx.new_page().goto("https://substack.com/sign-in")
            input("Log in in the browser window, then press Enter here...")
            ctx.close()
        return

    todo = []
    for n, age in due(notes, done):
        if age > LATE_LIMIT_HOURS:
            print(f"skip #{n['id']} (overdue {age:.0f}h)"); done.add(n["id"]); continue
        todo.append(n)
    todo = todo[: a.limit]
    if not todo:
        STATE.write_text(json.dumps(sorted(done))); print("nothing due"); return
    if a.dry_run:
        for n in todo: print(f"WOULD POST #{n['id']} ({n['post_at']}):\n{n['text']}\n")
        return

    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        ctx = p.chromium.launch_persistent_context(str(PROFILE), headless=True)
        page = ctx.new_page()
        for n in todo:
            try:
                post_one(page, n["text"])
                done.add(n["id"]); STATE.write_text(json.dumps(sorted(done)))
                print(f"posted #{n['id']}")
            except Exception as e:
                page.screenshot(path=str(HERE / "last-error.png"))
                print(f"FAILED #{n['id']}: {e}", file=sys.stderr); break
            time.sleep(5)
        ctx.close()
    STATE.write_text(json.dumps(sorted(done)))

if __name__ == "__main__":
    main()
