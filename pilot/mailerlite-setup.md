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
