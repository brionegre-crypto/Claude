# Substack: 100 Notes + 2 Articles

- `notes.json` – 100 notes with `post_at` timestamps (Central), 3/day at 8:00 / 13:00 / 20:00, Nov 9 – Dec 12, 2026
- `NOTES-SCHEDULE.md` – the same notes, human-readable, to review/edit (edit `notes.json` to change what posts)
- `notes.txt` – source text, one note per block separated by `---`
- `articles/` – 2 Substack-ready articles in Markdown (paste into the Substack editor)
- `post_notes.py` – auto-poster (see header for setup). Substack has no public API, so it drives your own logged-in browser session. Login/2FA is done by you via `--login`.

## Fully automatic (cloud) setup

Runs on GitHub Actions every ~10 min; it only launches a browser when a note is due. Your computer can be off.

1. Merge this branch into `main` (GitHub only runs scheduled workflows from the default branch).
2. One time, on your computer: `pip install playwright && playwright install chromium`, then `python3 substack/post_notes.py --login`. Log in (2FA included); it saves `substack/session.json` (gitignored, never commit it).
3. Repo > Settings > Secrets and variables > Actions > New secret: name `SUBSTACK_STORAGE_STATE`, value = the full contents of `session.json`.
4. Actions tab > "Post Substack Notes" > Run workflow to test. Check `posted.json` and your Notes.

If the saved login ever expires, posting fails (a screenshot is attached to the run); repeat steps 2-3.
Notes more than 6 hours overdue are skipped rather than dumped. Scheduled runs can be delayed a few minutes by GitHub.
