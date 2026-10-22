# Community manager bot (Instagram + Facebook, TikTok drafts)

Webhooks/polling → Claude (your system prompt) → reply via Graph API. Starts in **dry-run**: it records what it
*would* post and posts nothing.

| Platform | Comments | Welcome DM | Notes |
|---|---|---|---|
| Instagram (Business/Creator) | auto | optional private reply to first-time commenters | no API exists for likes or new followers |
| Facebook Page | auto | optional private reply | |
| TikTok (personal) | `python -m app.draft` | – | Official comment API needs a TikTok **Business** account; switch in TikTok settings, then ask me to add it |

## 1. Meta app (the part only you can do)
1. Link your Instagram to your Facebook Page. Instagram must be public.
2. developers.facebook.com → Create app (Business type) → add **Webhooks** and **Instagram**.
3. Add yourself as admin. Permissions: `instagram_basic`, `instagram_manage_comments`, `pages_read_engagement`,
   `pages_manage_engagement`, `pages_show_list`; for welcome DMs also `instagram_manage_messages`, `pages_messaging`.
4. Generate a **long-lived Page access token** (Graph API Explorer → exchange for long-lived → `/me/accounts`).
5. Collect: App Secret, Page ID, Instagram user ID (`/{page-id}?fields=instagram_business_account`), Page token.
6. After deploy: Webhooks → Page → callback `https://<your-app>.fly.dev/webhook`, your verify token, subscribe to
   `feed`; Instagram → `comments`. Switch the app to **Live**.
7. Meta's docs conflict on whether comment webhooks need Advanced Access for your own account. Polling
   (`POLL_INTERVAL_SECONDS`) covers you either way. Dedup makes running both safe.

## 2. Deploy (Fly.io)
```
cd community-manager
fly launch --no-deploy --copy-config
fly volumes create community_data --size 1
fly secrets set ANTHROPIC_API_KEY=... META_APP_SECRET=... META_VERIFY_TOKEN=... META_PAGE_TOKEN=... \
  FB_PAGE_ID=... IG_USER_ID=... IG_USERNAME=bethemansystem ADMIN_TOKEN=... CONTACT_EMAIL=... NOTIFY_WEBHOOK_URL=...
fly deploy
```
Railway/Render work too: use the Dockerfile and mount a persistent volume at `/data`.

## 3. Review, then go live
```
curl -H "X-Admin-Token: $ADMIN_TOKEN" https://<your-app>.fly.dev/admin/log
```
Read a week of `dry_run` / `flagged` rows. Happy? `fly secrets set DRY_RUN=false`. Optional: `WELCOME_DM_ENABLED=true`.

## Safety built in
Dry-run default · own comments skipped · top-level comments only · SQLite dedup · randomized delay · daily cap ·
`[FLAG FOR MANUAL REVIEW]` never posts (Slack-compatible webhook + log) · comment text sanitized and treated as untrusted.

## Local
```
python -m venv .venv && .venv/bin/pip install -r requirements.txt && .venv/bin/pytest
cp .env.example .env   # fill in, then: set -a; . ./.env; set +a; uvicorn app.main:app
```
