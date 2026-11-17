# Security

## Secrets
- Tokens (Instagram, Claude setup-token, YouTube API key, SMTP app password) live in `data/secrets.enc`, encrypted with Fernet (AES-128-CBC + HMAC-SHA256).
- The key is in `data/.secret.key` (chmod 600). You can supply it through `AUTOPILOT_SECRET_KEY` instead, to keep it off disk.
- `data/` is git-ignored. Secrets are never written to `config/settings.toml`, never returned by the dashboard (it shows only "set"/"not set") and never logged.
- Every log line passes through a redactor that strips `access_token=…`, `Bearer …`/`OAuth …` headers and token-shaped strings (`IG…`, `EAA…`, `sk-ant-…`, `ya29.…`, `AIza…`). This is covered by tests.
- The wizard never asks for account passwords. Instagram uses an OAuth token you generate in Meta's dashboard, typed into a hidden prompt.
- Backups include `secrets.enc` but **not** the key. Keep a copy of `data/.secret.key` somewhere safe and separate, such as a password manager. Without it, restored secrets can't be decrypted and you would just reconnect accounts.

## AI isolation
- `claude -p` runs in an empty sandbox folder (`data/ai-sandbox`) with `Bash`, `Edit`, `Write`, `NotebookEdit` and `Task` disabled. During research fact-checks only `WebSearch`/`WebFetch` are allowed.
- Web content is passed to Claude as clearly delimited *untrusted data*, and its output must be JSON that is validated field by field.
- The provider refuses to run while `ANTHROPIC_API_KEY` is set, so you cannot be billed through the API by accident.

## Dashboard
- Binds to `127.0.0.1` only. Config validation rejects any other host.
- Login token (`data/.dashboard_token`) leads to an HMAC-signed, HttpOnly, SameSite=Strict session cookie (7 days).
- CSRF token on every POST, a Host-header allowlist (blocks DNS rebinding), `X-Frame-Options: DENY`, a strict CSP and no-referrer.
- Asset downloads are confined to `data/assets/`, with path resolution checked.
- Reset the token with `./scripts/autopilot dashboard-token --reset`.

## Media tunnel
- During an Instagram image publish, a Cloudflare quick tunnel exposes **only** the post's files, at unguessable one-time paths (`/m/<128-bit random>/file.jpg`). Everything else returns 404.
- The tunnel exists only for the seconds Meta needs to fetch the image, then the process is terminated.

## Publishing safety
- Real publishing requires `general.mode = "live"` **and** the database flag `activated`, which only `autopilot activate` sets. Activation requires a working Instagram connection, a verified Claude call and at least one successful real test publish.
- Emergency stop is checked before every network publish call. Pause halts generation and publishing.
- The quality gate blocks the following, and logs and alerts every block:
  - offensive language and sensitive topics
  - banned or misleading phrases
  - unsupported factual claims (any claim must cite a stored, fact-checked source)
  - disputed research, duplicates and near-duplicates
  - broken media and files changed after validation (sha256 check)

## Least privilege
- Instagram scopes: `instagram_business_basic`, `instagram_business_content_publish`, `instagram_business_manage_insights` only. No messaging, no comment management.
- The YouTube key is a read-only API key restricted to the YouTube Data API. No OAuth write scopes exist for Community posts anyway.
