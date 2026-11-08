# Substack: 100 Notes + 2 Articles

- `notes.json` – 100 notes with `post_at` timestamps (Central), 3/day at 8:00 / 13:00 / 20:00, Nov 9 – Dec 12, 2026
- `NOTES-SCHEDULE.md` – the same notes, human-readable, to review/edit (edit `notes.json` to change what posts)
- `notes.txt` – source text, one note per block separated by `---`
- `articles/` – 2 Substack-ready articles in Markdown (paste into the Substack editor)
- `post_notes.py` – auto-poster (see header for setup). Substack has no public API, so it drives your own logged-in browser session. Login/2FA is done by you via `--login`.

Quick start:
```bash
pip install playwright && playwright install chromium
python3 post_notes.py --login
python3 post_notes.py --dry-run
# crontab: */15 * * * * cd /path/to/substack && python3 post_notes.py >> post.log 2>&1
```
It never posts twice (`posted.json`), and skips notes overdue by more than 12 hours.
