# Cloud publishing: posts go out while your Mac sleeps

| Job | Where it runs | Needs the Mac on? |
|---|---|---|
| Research, writing (Claude Code), rendering | Your Mac | Now and then: posts are written ~10 days ahead |
| Publishing Instagram posts at their time | GitHub Actions in your **private** repo | **No** |
| Syncing ready posts up and results back | Your Mac, every 10 min while it's on | Only to pick up new/edited posts and report results |
| YouTube Community posts | You (assisted) | — |

Cost: **$0.**
- A private repo gets 2,000 free GitHub Actions minutes a month. A trigger every 30 minutes (8 AM–midnight) plus publishing uses about 900–1,300.
- cron-job.org is free.
- The Instagram token sits in the repo encrypted (Fernet). The key is a GitHub Actions secret that the setup sets for you.

## One-time setup (about 10 minutes)
```bash
brew install gh
```

```bash
gh auth login
```

For `gh auth login`, choose: GitHub.com → HTTPS → **Yes** to authenticate Git → Login with a web browser.

```bash
./scripts/autopilot cloud setup
```

This:
1. creates a **private** repo (default name `btm-publisher`)
2. stores the encryption key as the Actions secret `CLOUD_KEY`
3. pushes the publishing workflow
4. prints the cron-job.org steps

After the cron-job.org setup, run:

```bash
./scripts/restart.sh
```

## Why cron-job.org?
GitHub's built-in schedule is best-effort. Your Substack job, set to every 10 minutes, actually ran 6–9 hours apart on Nov 17.
- cron-job.org calls GitHub's "run workflow" API on time, using a key that can **only** start workflows in the publishing repo.
- The workflow also has a slow fallback schedule every 6 hours, in case cron-job.org is down.
- Posts go out within 30 minutes after their slot time.

## Safety
- **No double posts.**
  - Each attempt is written to `state/<id>.json` and pushed *before* Instagram is asked to publish.
  - After any interruption, the next run checks Instagram (container status and recent captions) before retrying.
  - One post equals one `results/<id>.json`.
  - While cloud publishing is on, the Mac never publishes Instagram posts itself.
- **Pause and emergency stop** reach the cloud on the next sync (within 10 minutes while the Mac is on).
  - If the Mac is off and you need to stop immediately: GitHub → your publishing repo → **Actions → Publish → ••• → Disable workflow**.
- **Edits, reschedules and deletions** made on the dashboard are synced. A post is withdrawn from the queue unless the cloud has already started publishing it.
- **Late posts** (more than 3 hours past their slot, e.g. the trigger was down) are skipped and reported, never posted in a burst.
- Simulation mode exports nothing. Only `autopilot activate` makes the queue live.

## Commands
```bash
./scripts/autopilot cloud status
```

```bash
./scripts/autopilot cloud sync
```

```bash
./scripts/autopilot cloud trigger-info
```

```bash
./scripts/autopilot cloud disable
```

- `status`: what's queued and the last sync
- `sync`: sync right now
- `trigger-info`: show the cron-job.org steps again
- `disable`: go back to Mac-only publishing (also disable the workflow on GitHub)

## Housekeeping
Published media is deleted from the queue, but git history keeps it, roughly 50–100 MB a month. Once or twice a year, if the repo gets big:
1. Create a fresh private repo.
2. Run `./scripts/autopilot cloud setup --repo NEW-NAME`.
3. Delete the old repo.

The fine-grained GitHub key used by cron-job.org expires after the period you choose (max 1 year). Create a new one and paste it into the cron-job.org job.
