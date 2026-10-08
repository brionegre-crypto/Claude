# Product downloads on bethemansystem.com

Status 2026-10-08: code is live. Two settings in Cloudflare are still needed from Brian (below).

## How it works
1. Someone pays on a Stripe Payment Link.
2. Stripe sends them to `bethemansystem.com/get/<product>/?session_id=...`.
3. Each download button goes to `/api/download`, which:
   - checks with Stripe that the session is a paid purchase of that product (once `STRIPE_KEY` is set);
   - serves the file from bethemansystem.com (Cloudflare KV namespace bound as `FILES`).
     The first time a file is requested it is copied from systeme.io automatically.
4. `/api/files-check` copies every file and lists what is stored. It never shows file contents.

Until the two settings exist, downloads still work exactly as before (they hand off to the systeme.io file links).

All 14 product Payment Links now redirect with `?session_id={CHECKOUT_SESSION_ID}` (changed 2026-10-08; nothing else on the links changed). Couples is unchanged (no files).

## Brian's steps
1. **File storage.** Cloudflare → Storage & Databases → KV → Create namespace `btm-files`.
   Then Workers & Pages → bethemansystem → Settings → Bindings → Add → KV namespace:
   variable name `FILES`, namespace `btm-files`. Save.
2. **Purchase check.** Stripe → Developers → API keys → Create restricted key, name "Website downloads".
   Set **Checkout Sessions: Read**, leave everything else None. Copy the key (don't paste it in chat).
   Cloudflare → bethemansystem → Settings → Variables and Secrets → Add → Secret, name `STRIPE_KEY`, paste. Save.
3. Tell Claude "done"; Claude pushes a redeploy so the new settings take effect.
4. Open `https://bethemansystem.com/api/files-check`. Expect `"binding": true`, `"purchase_check": true`, every file `"stored"`.
5. Buy the $7 Scorecard with a real card, download both files from the thank-you page, then refund it in Stripe.

## Before cancelling systeme.io
Step 4 must show every file "stored". After that, the systeme.io copies are no longer used.

## Lost links
A buyer who loses the page can email brian@bethemansystem.com. Find the payment in Stripe → Payments,
open its Checkout Session id (cs_live_...), and send them
`https://bethemansystem.com/get/<product-slug>/?session_id=<that id>`.
