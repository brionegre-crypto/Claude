# MailerLite setup (replaces systeme.io email)

Goal: sign-ups on bethemansystem.com/step-1/ go straight into MailerLite. MailerLite sends the Step 1 email right away and the weekly emails after it. systeme.io keeps sending until MailerLite is tested.

## Brian's part (about 20 minutes)

1. **Sign up** at mailerlite.com with brian@bethemansystem.com. The Free plan covers up to 1,000 subscribers.
2. **Verify the domain** so emails come from brian@bethemansystem.com and don't land in spam. MailerLite shows 2 or 3 DNS records. Send Claude a screenshot; Claude tells you exactly where they go in Cloudflare (DNS → Add record, all DNS only).
3. **Create a group** called `Step 1` (Subscribers → Groups → Create group).
4. **Create an embedded form** (Forms → Embedded forms → Create). Name it `Step 1`, pick the `Step 1` group, use two fields (First name, Email) and turn double opt-in OFF. Save, open **Embed** → **HTML code**, and send Claude that code. It contains the form address the website needs.
5. **Export contacts from systeme.io** (Contacts → select all → Export CSV) and import that file into MailerLite (Subscribers → Import → Upload file). Only import people who signed up. Never import a bought list.

## Claude's part

- Point the Step 1 page's button at a form on bethemansystem.com that sends straight to MailerLite. The email box is on our own page, so there's no extra click.
- Write the MailerLite automation: Step 1 email immediately (same copy as the current systeme.io email, which now links to bethemansystem.com/step-1/worksheet/), then the weekly emails. Paste-ready copy for each email will be in `emails/`.
- Test with Brian's own email, then switch the site over and turn off the systeme.io campaign.

## Progress 2026-10-07 (Claude, via the MailerLite connector)

- The account is connected (login bogreenejr@gmail.com, account 2693662).
- Groups: "Step 1" (200695507810518732) for website sign-ups, and "Moved from systeme.io" (200695508514112659), which holds the 2 existing subscribers. They were imported with autoresponders off, so they didn't get the welcome email again.
- Automation "Step 1 welcome" (200695557413406570): when someone joins the Step 1 group, it sends the "Step 1." email straight away. The HTML body is set. It's still INACTIVE and waits on sender domain verification.
- Embedded form "Step 1 (website)" (200695528382530600). It isn't used; the website talks to MailerLite through its API instead.
- `functions/api/subscribe.js` (a Cloudflare Pages Function) posts sign-ups to the MailerLite API. If the `MAILERLITE_API_KEY` secret is missing or MailerLite fails, it falls back to the systeme.io opt-in. It's tested with a fake MailerLite.
- `/step-1/thanks/` page is built.
- Waiting on Brian:
  1. Add bethemansystem.com in MailerLite → Settings → Domains, then send Claude the DNS records.
  2. Create an API token and save it in Cloudflare as the secret `MAILERLITE_API_KEY`.
- Then Claude: help add the DNS records in Cloudflare, activate the automation, test, switch the Step 1 page and the "Get Step 1" buttons to the on-site form, and turn off the systeme.io Framework campaign.
