# Social Autopilot: @bethemansystem

A local, zero-cost system that researches, writes, designs, schedules, publishes and measures social content for
Instagram (image, carousel, Reel, Story) and prepares YouTube Community posts (text, image, poll, quiz).
Claude Code, on your existing subscription, is the only AI.

**Status: built and tested in simulation; waiting for your account connection and activation.** Nothing touches a
real account until you finish the wizard's real tests and type `ACTIVATE`.

| | |
|---|---|
| Fully automated | Research → fact-check → writing → graphics/Reels → 30-day calendar → Instagram publishing → analytics → optimization → reports |
| Assisted | YouTube Community posts: no official API exists, so you get a push notification plus a one-click Copy and Mark posted (about 20 s each) |
| Cost | **$0** recurring (details in [docs/CAPABILITY-MATRIX.md](docs/CAPABILITY-MATRIX.md#confirmed-ongoing-costs)) |
| Runs on | Your Mac (or any Linux/macOS machine). It publishes while the computer is on, awake and online. |

## Install (about 30 minutes including Meta setup)
Requirements: macOS or Linux, Python 3.11+, [Homebrew](https://brew.sh) on macOS, and the Claude Code CLI signed in to your plan.

```bash
cd autopilot
```

```bash
./scripts/install.sh
```

The install script creates `.venv`, installs the free dependencies, initializes the database, runs the test suite, and
then starts the **setup wizard**. The wizard:
1. Inspects your system and offers to install `ffmpeg` and `cloudflared` (both free).
2. Creates `config/settings.toml`, the database and a simulation plan. It asks for your time zone.
3. Checks network access.
4. Verifies Claude Code headless generation on your subscription (one tiny test call). Optionally it stores a `claude setup-token` token.
5. Walks you through the free Meta developer app and connecting Instagram (token entered hidden, stored encrypted). It validates permissions, and optionally adds a free YouTube API key for subscriber stats.
6. Renders every format and simulates publishing. It then offers **real test publishes** (start with a Story), each confirmed by typing its name.
7. Sets up notifications (ntfy push, webhook or email) and sends a test.
8. Shows the dashboard URL and login token.
9. Installs the background service (launchd on macOS, systemd on Linux).
10. Runs an end-to-end test with real Claude writing, published to the simulator.

Then go live:
```bash
./scripts/autopilot activate
```

Activation re-checks the setup, then asks for the **first posting date**, because that's only decided once everything is
ready. Pick a date after your Sprout schedule ends (it runs through Dec 2026). It shows the first few posts, and goes live
after you type `ACTIVATE`. Simulation posts scheduled before that date are dropped. Posts already written for
that date or later are kept.

## Start, stop, status
```bash
./scripts/start.sh
```

```bash
./scripts/stop.sh
```

```bash
./scripts/autopilot status
```

Dashboard: **http://127.0.0.1:8765** (log in with `./scripts/autopilot dashboard-token`). Pause, resume and
**emergency stop** are under Controls, or on the command line:
```bash
./scripts/autopilot stop
```

## Recovery and maintenance
- Backups are automatic (daily, last 14 kept). For a manual backup run `./scripts/backup.sh`, and to restore run `./scripts/restore.sh <zip>`.
- Keep a copy of `data/.secret.key` in your password manager.
- Crash, restart and late-slot behaviour, troubleshooting and every command are in [docs/OPERATIONS.md](docs/OPERATIONS.md).

## Documentation
| Doc | Contents |
|---|---|
| [docs/CAPABILITY-MATRIX.md](docs/CAPABILITY-MATRIX.md) | Per-format API research, Claude subscription findings, **final capability report**, costs, what is not yet verified |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Decisions and cost assessment, diagram, lifecycle, duplicate-prevention guarantees, database, modules |
| [docs/OPERATIONS.md](docs/OPERATIONS.md) | Operating manual, schedule changes, backup and restore, recovery, troubleshooting, environment variables |
| [docs/SECURITY.md](docs/SECURITY.md) | Secrets, AI sandboxing, dashboard hardening, publishing safety |
| [docs/CLOUD-ROUTINE.md](docs/CLOUD-ROUTINE.md) | Optional: have a Claude Code cloud routine write the content (laptop closed) |
| [config/settings.example.toml](config/settings.example.toml) | Every setting, commented |
| [config/brand.md](config/brand.md) | Brand brief used in every prompt (built from your existing playbook) |

## Tests
```bash
.venv/bin/python -m pytest -q tests
```

The 48 tests cover the following, all offline and with nothing published:
- config validation, DST scheduling and idempotent planning
- quality gate (claims, duplicates, sensitive topics)
- secret encryption and log redaction
- Instagram publishing of every format against a fake Graph API: timeouts after publish, crash recovery, rate limits, auth errors, retry exhaustion, emergency stop, late-slot skipping, media tampering
- assisted YouTube flow, analytics and reports, backup and restore, the worker across restarts
- dashboard login, CSRF and Host-header protection, inbox import, the activation gate, and setting the first posting date at activation
