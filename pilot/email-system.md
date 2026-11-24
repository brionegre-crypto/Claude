# Be The Man email system (replaces Kit, Nov 24, 2026)

Your list now lives on your own site. Resend sends every email. Kit is no longer used.

## The dashboard: bethemansystem.com/admin

Sign in with brian@bethemansystem.com. You get a link by email, and there's no password. The session lasts 30 days.

- **Overview:** active contacts, new this week, cohort seats sold, emails sent today against the daily limit, unsubscribes, bounces, tags, and the last 30 emails sent. "Send due emails now" sends anything that's waiting.
- **Contacts:** search and filter by tag or status. Click a contact to rename, tag, unsubscribe, start a series or delete. Add one by hand, import a CSV (a Kit export works), or export everything.
- **Email series:** the Step 1 welcome series (5 emails over 14 days) and the Founding Cohort reminders (the day before each session, with the Meet link). Edit any email, preview it, send yourself a test, then save. "Restore the original" undoes your edits.
- **Broadcasts:** write one email to everyone, or to a tag, send yourself a test, then send.

## What happens automatically

- **Step 1 sign-up:** the man is tagged "Step 1" and gets email 1 straight away, then the rest of the series. You get an alert.
- **Low Seat Check:** he gets his result by email and is tagged "Low Seat Check".
- **Founding Cohort purchase:** he's tagged "Founding Cohort" and "Customer", gets the "You're in" email, then a reminder with the Meet link the morning before each session (10 AM Central).
- **Free call, couples inquiry, Club join:** each is added to the list with its tag, as Kit used to do.
- **Unsubscribe:** every list email has an unsubscribe link and Gmail's one-click unsubscribe. Unsubscribed and bounced contacts never get series emails or broadcasts. Receipts and sign-in links still go to them.
- **Footer:** every list email ends with the ADHD disclaimer and your mailing address (PO Box 3425, Huntsville, AL 35810, USA), as the law requires for marketing email. The address appears only in emails, never on the website.

## Limits

- **Daily limit:** 90 list emails a day, which keeps you inside Resend's free plan of 100 a day and leaves room for receipts. Anything over the limit goes out the next day. If you upgrade Resend, set MAIL_DAILY_CAP in Cloudflare to raise it.
- **Cloudflare's free storage:** about 1,000 writes a day, and each email sent uses about three. That's plenty at this size.

## One-time setup: the hourly scheduler (5 minutes)

Series emails go out on time even without this: every sign-up and every dashboard visit also sends what's due. The scheduler makes timing exact.

1. **Set the default branch on GitHub.** GitHub only runs scheduled jobs from a repository's default branch, and yours is currently `claude/betheman-instagram-strategy-qjlm3l`. In the brionegre-crypto/Claude repository, go to Settings, then General, then Default branch, and switch it to `claude/sharp-sagan-jrcxxn` (the branch the live site runs from).
2. **Make a long random password.** For example, a 32-character password from your password manager.
3. **Cloudflare:** Workers & Pages, then bethemansystem, Settings, Variables and Secrets, Add. Name it `CRON_SECRET`, paste the password, type Secret, environment Production. Save.
4. **GitHub:** the brionegre-crypto/Claude repository, then Settings, Secrets and variables, Actions, New repository secret. Name it `CRON_SECRET` and paste the same password.
5. **Check it:** in GitHub, open Actions, then "Email scheduler", then "Run workflow". It should finish green.

Don't paste the password into chat.
