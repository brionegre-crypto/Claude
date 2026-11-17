# Capability matrix and final capability report

Researched November 2026 against Meta's Instagram Platform docs, the YouTube Data API v3 reference and Anthropic's
Claude Code docs. Platform APIs change; the dashboard's **Controls → Run diagnostics** and the wizard's permission
checks verify what is true for *your* account today.

"Tested" means something specific in the tables below:
- **Real** means it ran against the live service from this build environment.
- **Fake API** means it ran through the full publishing code against an in-memory Instagram Graph API. That fake covers success, rate limits, auth errors, timeouts, crashes and duplicate attempts.
- **Pending you** means it needs your account and runs in wizard step 6 (`formats`).

## 1. Publishing formats

| Platform / format | Official API? | Account type | Permissions (scopes) | Media transfer | Native scheduling via API? | Limits | Cost | Autonomy | Tested |
|---|---|---|---|---|---|---|---|---|---|
| Instagram single image | Yes: `POST /{ig-user-id}/media` → `media_publish` | Professional (Business or Creator) | `instagram_business_basic`, `instagram_business_content_publish` | JPEG at a **public HTTPS URL** (Meta fetches it) → free Cloudflare quick tunnel opened only during publish | No, so the internal scheduler handles it | 100 API posts / rolling 24h (read live from `content_publishing_limit`); 2,200-char caption; 30 hashtags | $0 | **Fully automated** | Fake API ✓ · Real: pending you |
| Instagram carousel | Yes: `media_type=CAROUSEL`, 2–10 children | Professional | same | Same as image (per-slide URLs) | No | Counts as 1 post; max 10 items via API (the app allows 20) | $0 | **Fully automated** | Fake API ✓ · Real: pending you |
| Instagram Reel | Yes: `media_type=REELS` | Professional | same | **Resumable upload** of the MP4 bytes to `rupload.facebook.com`, so no public URL is needed | No | ≤ 15 min, ≤ 300 MB; music from Instagram's library **cannot** be added via API | $0 | **Fully automated** (original synthesized audio bed) | Fake API ✓ · Real: pending you |
| Instagram Story | Yes: `media_type=STORIES` | **Business** (Meta documents Stories publishing for business accounts) | same | Image at public URL (tunnel) | No | Interactive stickers (link, poll, question) are **not** available via the API | $0 | **Fully automated** (text-only frames; no stickers) | Fake API ✓ · Real: pending you |
| YouTube Community: text | **No.** The Data API has no endpoint to create posts | Any channel with Community tab | — | — | YouTube Studio can schedule posts manually | — | $0 | **Assisted**: written, scheduled and alerted; you tap post | Dashboard flow ✓ |
| YouTube Community: image | **No** | — | — | — | Studio (manual) | — | $0 | **Assisted** (1080×1080 graphic rendered) | ✓ |
| YouTube Community: poll | **No** | — | — | — | Studio (manual) | 2–5 options | $0 | **Assisted** | ✓ |
| YouTube Community: quiz | **No** | — | — | — | Studio (manual) | 2–4 options, 1 correct | $0 | **Assisted** | ✓ |

**Why YouTube is assisted, not automated:**
- There is no official API for creating Community posts.
- YouTube's Terms of Service prohibit accessing the service "using any automated means" outside the API. Browser automation would therefore break the platform terms you asked me to respect.
- Third-party tools that claim to post there are either scrapers (read-only) or unofficial and unverifiable.

The closest compliant zero-cost alternative is already built:
- The system writes and designs every Community post.
- At the scheduled time it sends a push notification.
- It shows the post on the dashboard with a **Copy** button, a YouTube Studio link and a **Mark posted** button. That takes about 20 seconds per post.
- You can also schedule a week of posts in one sitting with Studio's own post scheduler.

## 2. Analytics availability

| Source | Metrics | Access | Cost |
|---|---|---|---|
| Instagram media insights | reach, views, likes, comments, shares, saved, total_interactions (stories: reach, views, replies, shares) | `instagram_business_manage_insights` | $0 |
| Instagram account | followers_count, follows_count, media_count | basic | $0 |
| YouTube channel | subscribers (unless hidden), total views, video count | free Data API key, 1 quota unit per call (10,000/day free) | $0 |
| YouTube Community post metrics | **Not available** through any API | — | — |

"Impressions" was deprecated by Meta in favour of "views". The system never estimates or fabricates a missing metric.

## 3. AI generation under your Claude Code subscription

| Question | Finding (Anthropic docs, Nov 2026) | What the system does |
|---|---|---|
| Can a scheduled script use the subscription? | `claude setup-token` creates a **one-year token** documented "for CI pipelines, scripts, or other environments where interactive browser login isn't available". Requires a Pro/Max/Team/Enterprise plan. | Uses the official `claude` CLI in headless mode (`claude -p`) with that token (stored encrypted) or your `/login` session. |
| Restrictions? | Anthropic does not allow *third-party developers* to offer claude.ai login or rate limits in *their products*, including Agent SDK apps. No page restricts your own use of the official CLI. | Calls only the official CLI, for your own account, on your own computer. It never embeds the Agent SDK or reuses credentials elsewhere. |
| API billing risk | If `ANTHROPIC_API_KEY` is set, `claude -p` uses it and bills the API. | **Refuses to run** while `ANTHROPIC_API_KEY` is set (tested). |
| Usage limits | Shared with claude.ai and interactive Claude Code: a 5-hour window plus weekly limits. | Daily call cap (`ai.max_calls_per_day`, default 25). Content is written ~10 days ahead. When a limit is hit, writing pauses but publishing continues from the buffer, and you are alerted. |
| Does it need my interactive session open? | No. Headless calls are independent processes. | Each call is a short `claude -p` subprocess in an empty sandbox folder with Bash/Edit/Write disabled. |
| Laptop-closed alternative | Claude Code cloud **routines** run on Anthropic's infrastructure (minimum hourly, count against your subscription). | Optional `inbox` provider: a routine writes posts into `inbox/`, and the local system imports, validates, renders and publishes them. See `docs/CLOUD-ROUTINE.md`. |
| **Tested?** | **Real ✓.** In this build environment, a live headless call succeeded (6 s). Claude also generated a full on-brand 8-slide carousel that passed the quality gate and rendered (29 s). A real web-tools fact check verified a news item against an independent source (ScienceDaily). | — |

Anthropic's docs do not explicitly *endorse* unattended personal cron use; they document the token for scripts. If
Anthropic changes this policy, set `ai.provider = "inbox"` (cloud routine) or `"mock"` (pause writing). Never
switch to an API key.

## 4. Final capability report

### Fully automated (after activation)
- Research: public RSS (Google News search feeds, Reddit RSS where it isn't rate-limited), Claude relevance scoring, Claude web fact-checks on the top candidates, source and date tracking, reuse prevention.
- Generation: hooks, captions, headlines, CTAs, hashtags, image concepts, carousel outlines, Reel scripts, Story frames, Community text, polls and quizzes. Platform-specific, with duplicate and near-duplicate detection.
- Visuals: post images, carousels, Story graphics, Community graphics (Pillow + bundled OFL Inter font), and 9:16 Reels with an original synthesized audio bed (FFmpeg).
- Calendar: rolling 30-day queue, automatic replenishment, DST-safe time zones, minimum gaps, trend-triggered slot takeover, and posting-time exploration plus optimization.
- Instagram publishing of image, carousel, Reel and Story. It includes idempotency, leases, crash reconciliation, exponential backoff, rate-limit handling, auth monitoring, automatic token refresh and late-post skipping.
- Analytics collection, optimizer (topic weights, posting times, writer learnings), weekly and monthly reports.
- Notifications (dashboard, plus ntfy, webhook or email when configured), daily backups, integrity checks, log rotation, crash restart (launchd/systemd).

### Partially automated
- **YouTube Community (all 4 types):** everything except the final tap.
- **Instagram Story stickers** (link, poll, question): not available via the API, so frames are designed to work without them.
- **Reel music:** Instagram's licensed music library is not available via the API. Reels ship with an original ambient bed. To use trending audio you'd have to post that Reel manually.
- **Comments and DMs:** out of scope here (your existing `community-manager/` project covers this).

### Unsupported
- YouTube Community metrics (no API).
- YouTube Shorts and long-form video (excluded by your brief).
- Image hosting without a tunnel for Instagram image formats. This is a Meta requirement, and the free tunnel covers it.

### Remaining manual requirements (one-time unless noted)
1. Switch Instagram to a Business account (if it isn't already) and create the free Meta developer app (about 15 min, guided).
2. Paste the Instagram token into the wizard. Refresh is automatic every 60 days. You're alerted only if refresh fails.
3. Run `claude setup-token` once (valid for a year), or stay logged in.
4. Install `cloudflared` (free; `brew install cloudflared`).
5. Confirm the real test publishes in wizard step 6, then type `ACTIVATE`.
6. **Ongoing:** tap-to-post for YouTube Community posts (4/week by default).

### Confirmed ongoing costs
**$0.** No API keys with billing, no paid hosting, no paid schedulers. All dependencies are open source (MIT/BSD/Apache/OFL). External services used:
- Meta Graph API: free.
- YouTube Data API key: free quota, no billing account.
- Cloudflare quick tunnels: free, no account.
- ntfy.sh: free.
- Your existing Claude subscription.

### Dependencies on your computer
- The service runs on **your computer**. It publishes only while the computer is **on, awake and online**.
- Slots missed by more than 3 hours (configurable) are **skipped and reported**, never dumped in a burst afterwards.
- On a Mac, set Energy settings to prevent sleep while the display is off. A spare always-on Mac or Linux box is ideal.
- Writing happens about 10 days ahead, so short Claude outages or usage-limit windows don't interrupt publishing.
- Free "always-on" cloud hosts were evaluated and rejected. Free tiers sleep idle apps, cap hours, or require a card, which risks becoming paid service.

### Not verified in this build environment (honest list)
- **Live Instagram publishing.** It needs your account. It's exercised end-to-end against a faithful fake Graph API, including failure modes. Real tests run in wizard step 6, and activation **requires** at least one to succeed.
- **The Cloudflare quick tunnel.** Downloading and running the `cloudflared` binary was not permitted in this sandbox. The local file server it fronts is unit-tested, and the wizard's real image test exercises the tunnel on your machine.
- **launchd install.** This environment is Linux. The generated plist follows Apple's format. The wizard installs it and you can confirm with `launchctl list | grep socialautopilot`.
