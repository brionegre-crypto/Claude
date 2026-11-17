# Operating manual

All commands run from the `autopilot/` folder. `./scripts/autopilot <command>` uses the project's virtualenv.

## Daily life
Nothing is required. You'll get:
- a daily summary (08:00 local time by default)
- a push notification whenever a YouTube Community post is due (dashboard → Overview → **Ready for you to post** → Copy → YouTube Studio → **Mark posted**)
- alerts for failures, blocked posts, auth problems or a thin queue
- a weekly report every Monday and a monthly report on the 1st

## Commands
| Command | What it does |
|---|---|
| `./scripts/start.sh` / `stop.sh` / `restart.sh` | Start/stop the background service (launchd/systemd if installed, else nohup) |
| `./scripts/autopilot status` | Diagnostics (`--live-ai` adds one tiny Claude call; `--offline` skips network checks) |
| `./scripts/autopilot pause` / `resume` | Pause/resume all generation and publishing |
| `./scripts/autopilot stop` / `clear-stop` | Emergency stop / clear it |
| `./scripts/autopilot research` | Run research now |
| `./scripts/autopilot generate --limit 6` | Write the next N planned posts now |
| `./scripts/autopilot plan [--rebuild]` | Extend the 30-day queue / rebuild it after editing slots |
| `./scripts/autopilot publish-due` | Publish anything due now (normally the worker does this) |
| `./scripts/autopilot analytics [--ai]` | Collect metrics and run the optimizer |
| `./scripts/autopilot report weekly\|monthly` | Generate a report |
| `./scripts/autopilot capabilities` | Print what is autonomous and what is assisted |
| `./scripts/autopilot secrets list\|set NAME\|delete NAME` | Manage encrypted secrets (values are never printed) |
| `./scripts/autopilot dashboard-token [--reset]` | Show or rotate the dashboard login token |
| `./scripts/autopilot wizard [--step NAME]` | Re-run setup (steps: system, project, network, ai, accounts, formats, notifications, dashboard, service, e2e) |
| `./scripts/autopilot activate` | Go live (checklist + typed confirmation) |
| `./scripts/backup.sh [--assets]` / `./scripts/restore.sh FILE` | Back up or restore |

## Changing the schedule
1. Edit the `[[calendar.slots]]` blocks in `config/settings.toml`. Days are `mon`…`sun`, times are 24-hour local time.
2. Run `./scripts/autopilot plan --rebuild`. Only posts that haven't been written yet are re-planned. Written and ready posts stay where they are.
3. To move one post, open it in the dashboard → **Reschedule**.

About 15% of Instagram slots are deliberately shifted by ±1 hour (`calendar.explore_times`). This gives the optimizer real data to compare posting windows. After 8 or more measured posts, it moves a slot only when another hour is at least 15% better across 4 or more posts in each bucket.

## Backups and restore
- Automatic: every 24 hours to `data/backups/autopilot-YYYYmmdd-HHMMSS.zip`, keeping the newest 14. Each zip holds a consistent SQLite snapshot, `secrets.enc` and `settings.toml`. Add `--assets` for rendered media.
- **Keep `data/.secret.key` separately** (password manager). It's deliberately not inside backups.
- Restore:
  ```bash
  ./scripts/restore.sh data/backups/autopilot-20261201-030000.zip
  ./scripts/start.sh
  ```
  The restore stops the service, verifies the backup's integrity, saves the current database as `data/pre-restore-<time>.db`, restores, and tells you to start again.
- Moving to a new computer: copy the whole `autopilot/` folder, including `data/` and `.secret.key`, run `./scripts/install.sh --no-wizard`, then `./scripts/autopilot wizard --step service`.

## Recovery behaviour (automatic)
| Situation | What happens |
|---|---|
| Crash or power loss mid-publish | On restart, `recover()` asks Instagram whether the post went out. If it did, the post is marked published; otherwise it is re-queued. Never duplicated. |
| Computer off through a slot | Slots up to 3 hours late (`publishing.publish_window_minutes`) publish on wake. Later ones are skipped and reported. |
| Instagram rate limit / 5xx / network | Retried with exponential backoff (1, 2, 4, 8 min… ±20% jitter; rate limits wait ≥1 h), up to 5 attempts, then alert. |
| Instagram token problem | Alert immediately. Token auto-refresh runs when fewer than 15 days remain. |
| Claude usage limit / login expired | Writing pauses, with one alert per 6 h. Publishing continues from the roughly 10-day buffer. |
| Corrupt database | Daily integrity check alerts you. Restore the latest backup. |
| Worker killed | launchd/systemd restarts it after 30 s. |

## Troubleshooting
| Symptom | Check / fix |
|---|---|
| Dashboard won't load | Is the service running? `./scripts/autopilot status` → "worker heartbeat". Logs: `data/logs/autopilot.log`, `service.err.log`. Port in use? Change `dashboard.port`. |
| "Claude Code unavailable: Login expired" | Run `claude` and `/login`, or `claude setup-token` then `./scripts/autopilot secrets set claude_code_oauth_token`. |
| "ANTHROPIC_API_KEY is set: refusing" | Remove that variable from your shell profile or launchd environment, then `./scripts/restart.sh`. |
| "daily AI budget reached" | Expected protection. Raise `ai.max_calls_per_day` in Settings if your plan has headroom. |
| Queue "thin"/"empty" | Claude unavailable or budget too low. Look at Alerts. Run `./scripts/autopilot generate`. |
| Image posts fail "cloudflared not installed" | `brew install cloudflared` (macOS) and restart. |
| Image posts fail "tunnel URL not reachable" | A firewall or VPN is blocking Cloudflare. Allow `cloudflared`, or set `publishing.media_host = "public_url"` with your own HTTPS static host. |
| Instagram error code 190 | Token expired or revoked: `./scripts/autopilot wizard --step accounts`. |
| Instagram error 9007 / "media not ready" | Retried automatically. |
| Story publish fails with a permissions error | Stories via the API need a **Business** account (not Creator). |
| Post blocked | Open it in the dashboard to see the exact reason. Edit and save to re-check, **Replace** to regenerate, or **Release block** if you've reviewed it. |
| Reddit feeds show 429 | Reddit rate-limits anonymous RSS from some networks. It's harmless (the feed is skipped). Remove those feeds if it's persistent. |
| Mac slept and posts were skipped | System Settings → Battery → Options → "Prevent automatic sleeping when the display is off" (on power adapter). |

## Maintenance
- Logs rotate automatically (10 × 5 MB).
- Updates: `git pull`, then `./scripts/install.sh --no-wizard`. Migrations apply automatically on start, and the install script runs the test suite.
- Rotate the dashboard token occasionally: `./scripts/autopilot dashboard-token --reset`.
- Once a year: `claude setup-token` again (one-year token).

## Environment variables
| Variable | Purpose |
|---|---|
| `AUTOPILOT_CONFIG` | Path to an alternate settings file |
| `AUTOPILOT_DATA_DIR` | Alternate data directory |
| `AUTOPILOT_SECRET_KEY` | Fernet key for `secrets.enc` (instead of `data/.secret.key`) |
| `AUTOPILOT_FORCE_MOCK_AI` | Use the mock AI even when `ai.provider = claude_cli` (testing) |
| `ANTHROPIC_API_KEY` | **Must not be set** for the service (it would bill the API) |
