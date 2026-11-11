#!/usr/bin/env bash
# One-time setup for Keel's Claude server (Cloudflare Workers, free tier). Run in Terminal on your Mac:
#   cd ~/Claude/keel/backend && ./setup.sh
# Your Claude API key is typed straight into Cloudflare here — it's never stored in this repo or shown to Claude.
set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "Node.js is needed. Install it with: brew install node   (then re-run ./setup.sh)"; exit 1; }

echo "▸ Installing server dependencies…"
npm install --silent

echo "▸ Signing in to Cloudflare (a browser window opens — log in or create a free account, then click Allow)…"
npx wrangler whoami >/dev/null 2>&1 || npx wrangler login

if grep -q 'REPLACE_WITH_KV_ID' wrangler.toml; then
  echo "▸ Creating Keel's storage…"
  KV_ID=$(npx wrangler kv namespace create KEEL 2>&1 | grep -oE '[0-9a-f]{32}' | head -1)
  [ -n "$KV_ID" ] || { echo "Couldn't create storage. Run: npx wrangler kv namespace list  and tell Claude what it shows."; exit 1; }
  sed -i '' "s/REPLACE_WITH_KV_ID/$KV_ID/" wrangler.toml
fi

# Access codes: generated once, kept in .keel-secrets (git-ignored) so re-running shows the same ones.
if [ -f .keel-secrets ]; then source .keel-secrets; else
  DEVICE_CODE=$(openssl rand -hex 16); MCP_CODE=$(openssl rand -hex 16)
  printf 'DEVICE_CODE=%s\nMCP_CODE=%s\n' "$DEVICE_CODE" "$MCP_CODE" > .keel-secrets
  chmod 600 .keel-secrets
fi

echo "▸ Deploying the server…"
DEPLOY_OUT=$(npx wrangler deploy 2>&1 | tee /dev/stderr)
URL=$(echo "$DEPLOY_OUT" | grep -oE 'https://[A-Za-z0-9.-]+\.workers\.dev' | head -1)

echo "▸ Saving access codes…"
echo "$DEVICE_CODE" | npx wrangler secret put KEEL_DEVICE_TOKEN >/dev/null
echo "$MCP_CODE" | npx wrangler secret put KEEL_MCP_TOKEN >/dev/null

if ! npx wrangler secret list 2>/dev/null | grep -q ANTHROPIC_API_KEY; then
  echo
  echo "▸ Paste your Claude API key (from console.anthropic.com → API Keys) and press Return."
  echo "  Nothing will show as you paste — that's normal."
  npx wrangler secret put ANTHROPIC_API_KEY
fi

echo
echo "────────────────────────────────────────────────────────"
echo " Keel server is live."
echo " Server address:  ${URL:-(see the workers.dev address printed above)}"
echo " Access code:     $DEVICE_CODE"
echo "────────────────────────────────────────────────────────"
printf '%s' "$DEVICE_CODE" | pbcopy && echo " (Access code copied — paste it on your iPhone.)"
echo " In Keel: Today → profile icon → Claude AI → Connect Claude."
