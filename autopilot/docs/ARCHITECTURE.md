# Architecture

## Decision summary and cost assessment

| Concern | Options evaluated | Chosen | Why |
|---|---|---|---|
| Where it runs | Free cloud (Render/Fly/Railway free tiers, Oracle Always Free, GitHub Actions), hybrid, local | **Local-first** on your computer | Free web hosts sleep idle processes or cap hours. Oracle and some others need a card, which risks becoming paid. GitHub Actions cron on a *private* repo burns the 2,000 free minutes/month quickly (a 10-minute publish check uses about 4,300). It also can't reach your local `claude` login. Local gives $0, full control and direct access to your subscription CLI. |
| AI | Claude Code CLI headless; Agent SDK; cloud routines | **`claude -p` (official CLI)**, with a **cloud routine → inbox** fallback | The CLI is documented for scripts with `claude setup-token`. Anthropic restricts third-party Agent SDK products from using subscription login, so the SDK is not used. |
| Language | Python, Node/TS | **Python 3.11+** | Best fit for Pillow/FFmpeg/feeds/SQLite tooling. Your repo already uses Python for automation. |
| Database | SQLite, PostgreSQL | **SQLite (WAL)** | Zero-ops, single file, crash-safe, trivially backed up. Volume is tiny (hundreds of posts/month). |
| Scheduler | APScheduler, Celery+Redis, cron, custom | **DB-driven loop** (30 s tick) | All schedule state lives in the database, not memory. Restarts lose nothing, and duplicate prevention is enforced by data. |
| Process supervision | pm2, supervisord, launchd/systemd | **launchd (macOS) / systemd user unit (Linux)** | Built into the OS, restarts on crash, starts at login. |
| Dashboard | Django, Flask, FastAPI, static | **FastAPI + Jinja (server-rendered)** | No JS build chain; small attack surface. |
| Graphics | Paid AI images, HTML→PNG, SVG, Pillow | **Pillow + bundled Inter (OFL)** | Deterministic, license-clean, fast, no browser needed. |
| Video | Paid video APIs, MoviePy, FFmpeg | **FFmpeg** | Free, robust. The audio bed is synthesized by FFmpeg itself, so there's no copyright risk. |
| Research | Paid search APIs, scraping, RSS | **RSS + Claude web tools for fact checks** | Permitted, free. Scraping is avoided. |
| IG image hosting | Paid CDN, S3, GitHub raw, tunnel | **Cloudflare quick tunnel, only during publish**; optional own HTTPS host | Meta requires a public URL for images. Video uses resumable upload, which needs no hosting. |
| Notifications | Paid SMS/Push, email | **Dashboard + ntfy.sh + webhook + your own SMTP** | All free. The dashboard always works with no setup. |
| Monitoring | Hosted APM | **Heartbeat, health endpoint, job_runs table, structured JSON logs, alerts** | $0 and local. |

**Recurring cost: $0.** Every dependency in `requirements.txt` is open source. External services are free tiers with no billing attached (see CAPABILITY-MATRIX.md §4).

## System diagram

```mermaid
flowchart LR
  subgraph You["Your computer (launchd/systemd: autopilot run)"]
    W[Worker loop<br/>30 s tick] -->|plan| S[(SQLite WAL<br/>content · research · attempts<br/>metrics · kv flags)]
    W --> R[Research engine<br/>RSS + scoring]
    W --> G[Generation engine]
    G -->|claude -p| C[[Claude Code CLI<br/>your subscription]]
    R -->|score + fact-check| C
    G --> Q[Quality & safety gate]
    Q --> A[Asset engine<br/>Pillow · FFmpeg]
    W --> P[Publish engine<br/>lease · idempotency · retry]
    P --> IG[(Instagram Graph API)]
    P -->|assisted| N[Notifications]
    W --> AN[Analytics + optimizer] --> IG
    W --> B[Backups · integrity · auth monitor]
    D[Dashboard 127.0.0.1:8765] --> S
  end
  P -. images only, during publish .-> T[cloudflared quick tunnel] -.-> IG
  N --> NT[ntfy / webhook / email]
  CR[Optional: Claude Code cloud routine] -. inbox/*.json via git .-> G
```

## Content lifecycle

```
planned ──generate──▶ ready ──due──▶ publishing ──▶ published
   │                   │                 │  ├─temporary error──▶ failed ──backoff──▶ publishing
   │                   │                 │  ├─permanent / max attempts──▶ failed_permanent (alert)
   │                   │                 │  └─crash──▶ (startup) recover(): reconcile with Instagram
   │                   └─quality block──▶ blocked (alert; regenerated once with a new topic)
   └─YouTube slot due──▶ manual_due ──you tap "Mark posted"──▶ published
late by > publish_window ──▶ skipped (alert)       dashboard delete ──▶ cancelled
```

## Duplicate-publication guarantees
1. **Planning:** `content.slot_key` is UNIQUE, so re-planning or restarts can never create a second post for a slot.
2. **Lease:** `UPDATE … SET status='publishing' WHERE status IN ('ready','failed')` is atomic. Only one worker can claim a post, and a file lock (`data/worker.lock`) prevents two workers.
3. **Journal before act:** each attempt row is written before the network call. The container id is recorded the moment Instagram returns it.
4. **Reconcile on uncertainty:** after a timeout or crash, the engine checks the container status (`PUBLISHED`?) and the account's recent media (caption match) *before* any retry.
5. **Terminal check:** if any attempt for a content id is `published`/`reconciled`, the post is never sent again.

All five are covered by tests in `tests/test_publishing.py`.

## Database (migrations in `autopilot/migrations/`)
| Table | Purpose |
|---|---|
| `research_items` | topic, source, URL (hash-unique), publication date, research date, relevance, kind, opportunities, verification status and notes, usage |
| `content` | id, platform, format, topic, pillar, hook, headline, caption, hashtags, CTA, body (slides/script/frames/poll/quiz/claims), image concept, status, scheduled time (UTC), slot key, sources, fingerprint, quality report, block reason, publication id and permalink |
| `assets` | files per content (path, size, duration, sha256, license) |
| `publish_attempts` | idempotency key, attempt number, state, container id, response, error, next retry |
| `metrics`, `account_metrics` | time series from the APIs only |
| `notifications`, `job_runs`, `reports`, `ai_calls`, `kv` | alerts, job history, reports, AI usage accounting, runtime flags (paused, emergency stop, activated, optimizer state) |

## Module map
```
autopilot/
  cli.py            commands            worker.py      background loop and jobs
  config.py         settings+validation db.py          SQLite, migrations, kv
  research.py       RSS, scoring, fact-check, topic selection
  generation.py     Claude → validation → quality → assets; inbox import
  quality.py        safety/duplicate/claims/format gate
  assets/render.py  Pillow graphics, FFmpeg reels
  scheduler.py      slots, DST, rolling queue, trends, queue health
  publisher.py      publish engine (lease, journal, retry, recover)
  publishing/       instagram.py · youtube.py (assisted) · simulated.py · mediahost.py
  analytics.py      collection, aggregation, optimizer, reports
  notify.py         dashboard/ntfy/webhook/email      backup.py  snapshot/restore
  secrets.py        Fernet-encrypted secret store      logs.py    JSON logs + redaction
  diagnostics.py    health checks                     wizard.py  setup + activation
  web/              dashboard (FastAPI + Jinja)
```
