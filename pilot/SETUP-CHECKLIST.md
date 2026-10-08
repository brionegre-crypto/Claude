# Brian's setup checklist (one sitting, about 20 minutes)

Everything below was built on 2026-10-08. The code is live. These settings switch it on.
Never paste keys into chat. Tell Claude "done" after each block.

## 1. Cloudflare: file storage ✅ done 2026-10-08
Storage & Databases → KV → Create namespace `btm-files`.
Workers & Pages → bethemansystem → Settings → Bindings → Add → KV namespace: variable `FILES`, namespace `btm-files`.

## 2. Stripe: one restricted key (covers store downloads, buyer emails and the Club) ✅ done 2026-10-08
Developers → API keys → Create restricted key, name "Website".
Set to **Read**: Checkout Sessions, Customers, Subscriptions. Everything else None.
Cloudflare → bethemansystem → Settings → Variables and Secrets → Add → Secret `STRIPE_KEY`.

## 3. MailerLite: sender on three automations ✅ done 2026-10-08 (designs loaded; all four automations incl. Step 1 welcome active)
Open each and set the email sender to brian@bethemansystem.com (Brian Greene):
- Your downloads
- New inquiry alert (to Brian)
- Club sign-in link
Then tell Claude, who loads the email designs (pilot/emails/). Then activate all three.

## 4. Claude then
- redeploys, opens /api/files-check (every file "stored") ✅ 2026-10-08: binding true, purchase_check true, all 22 files stored,
- switches the Club Join buttons from systeme to Stripe (`web/club/config.json` → `"live": true`) ✅ 2026-10-08

## 5. Tests (real card, refund after)
- Store: buy the $7 Scorecard → files download → "Your download" email arrives → refund.
- Club: join monthly → you land in /members/ → sign out → sign in from /members with your email → refund and cancel in Stripe.
- Couples: send an inquiry from /couples/ → alert email reaches brian@.

## Recommended
- Make the GitHub repo private (GitHub → brionegre-crypto/Claude → Settings → Danger zone → Change visibility).
  The site source, including the Club lesson text, is currently public. Cloudflare Pages keeps deploying from a private repo.
