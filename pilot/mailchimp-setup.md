# Moving email to Mailchimp (plan, 2026-10-12)

MailerLite terminated the account and denied the appeal. Nothing below has been done yet. Brian says when he is ready.

## Which plan
- Free: no automations or scheduling, so it can't run the welcome series, the challenge or the Thursday emails.
- Essentials (about $13/mo at 500 contacts): automations max 4 steps. The Step 1 welcome series has 6.
- **Standard (about $20/mo at 500 contacts): the one to pick.** Multi-step journeys, scheduling, custom HTML emails.
- Mailchimp bills by contact count, and unsubscribed contacts count unless archived.

## Brian's setup (about 30 minutes)
1. Sign up at mailchimp.com with brian@bethemansystem.com and choose Standard.
2. Business address: required in every email footer by law (a P.O. box is fine).
3. Domain: Website → Domains → add bethemansystem.com → Authenticate. Mailchimp shows two or three CNAME records; add them in Cloudflare DNS (Claude will list the old MailerLite records to delete).
4. Audience: keep the one audience Mailchimp creates, renamed "Be The Man". Tell Claude its Audience ID (Audience → Settings → Audience name and defaults). The ID is not secret.
5. API key: Profile → Extras → API keys → Create a key. Paste it ONLY into Cloudflare → Pages → bethemansystem → Settings → Variables and secrets, as `MAILCHIMP_API_KEY` (type: Secret). Never in chat.
6. Optional: a Resend account (free, 3,000 emails/month, 100/day) for the one-to-one emails, with its key in Cloudflare as `RESEND_API_KEY`.

## Adding subscribers by hand
- One at a time: Audience → Add contacts → Add a subscriber. Set status Subscribed only if the person asked for your emails, then add tags.
- Several at once: Audience → Add contacts → Import contacts → copy and paste, with the same rule.
- Only add people who signed up or bought. A new account that imports contacts is checked automatically (Mailchimp's "Omnivore"), and unexpected addresses can freeze sending.

## Pages
All pages stay on bethemansystem.com. Nothing gets rebuilt in Mailchimp. Claude rewires four site functions:
- `functions/api/subscribe.js`: Step 1 and challenge sign-ups → Mailchimp, with tags `step-1` / `challenge`.
- `functions/api/purchase.js`: buyers → tag `customer` + product tag, and the download email.
- `functions/api/inquiry.js`: couples and call requests → tags, and the alert to brian@.
- `functions/api/club/*`: Club sign-in link emails.

The download email, Club sign-in link and inquiry alert are one-to-one emails. They should go through Resend, not Mailchimp, so a marketing-account problem can never stop buyers getting their files or members signing in.

## Tags (replace MailerLite groups)
step-1, challenge, moved-from-systeme, customer, club-member, workshop, six-week-group, ministry-kit, inner-circle, couples-inquiry, call-request

## Emails to rebuild (HTML already in pilot/emails/)
- Step 1 follow-up: 6 weekly emails → Customer Journey, starts on tag `step-1`.
- 7-week challenge: welcome + 7 weekly emails → Customer Journey, starts on tag `challenge` (late joiners start at week 1).
- Thursday newsletters: 11 regular campaigns, Oct 15 to Dec 24, 8 AM Central.
- Club call reminders: 4 campaigns to tag `club-member`.
- Workshop reminder: Oct 25, 2 PM Central, tag `workshop`.

About 30 emails. The claude.ai Mailchimp connector only drafts campaign designs. It can't manage subscribers, tags or journeys, so Brian would paste the HTML for the journeys and schedule campaigns himself, using step-by-step notes from Claude. Kit (kit.com) has a full connector that would let Claude build all of this directly.
