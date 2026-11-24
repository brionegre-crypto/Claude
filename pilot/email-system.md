# Be The Man email and text system (replaces Kit, Nov 24, 2026)

Your list lives on your own site. Resend sends the email and Twilio sends the texts. Kit is no longer used.

## Dashboard: bethemansystem.com/admin

Sign in with brian@bethemansystem.com. You get a link by email, and there's no password.

| Tab | What it does |
|---|---|
| Overview | Contacts on email and on texts, new this week, cohort seats sold, emails and texts sent today against the limits, unsubscribes and bounces. Also a 30-day sign-up chart, engagement levels, tags, setup status and recent emails. |
| Contacts | Search and filter by tag, status, engagement and text opt-in. Open a contact to edit his name, mobile, tags and custom fields, see his activity timeline, start a series or automation, or delete him. Import and export CSV (a Kit export works). |
| Segments | Saved filters: has all, any or none of some tags; status; engagement; joined between two dates; opted in to texts; a custom field value. They update themselves, and you can send a broadcast to any of them. |
| Automations | When a man signs up through a form, gets a tag, buys something, clicks a link or opts in to texts, run these steps: wait, send an email, send a text, add or remove a tag, start a series, email you an alert, or continue only if he has (or doesn't have) a tag. Each step shows its own sent, opened and clicked numbers. |
| Forms | Your own sign-up forms. Each has a page at bethemansystem.com/f/name and an embed code, and can carry a tag, a series to start, a mobile number field, the text-consent checkbox, double opt-in, and a thank-you message or page. |
| Email series | The Step 1 welcome series and the Founding Cohort reminders. A step can be an email, a text, or both, and each step shows its stats. |
| Broadcasts | Email or text to everyone, a tag, or a segment. Send now or schedule. A/B test two subject lines. See opens, clicks, the links clicked and unsubscribes. Resend to the people who didn't open. |
| Texts | A two-way inbox. Replies to your texts land here and are emailed to you, and you answer from the dashboard. |
| Setup and help | The setup steps below, with their status. |

## Better than Kit

- **One place for everything:** email, texts, purchases, cohort seats and the Club.
- **Texts in the same automations and series as email.**
- **A two-way text inbox.**
- **No monthly fee** at your size, and nothing that can lock you out.
- **Compliance built in:**
  - unsubscribe link and one-click unsubscribe on every list email;
  - your mailing address and the ADHD disclaimer in every footer;
  - texts only to men who checked the consent box;
  - every text starts "Be The Man:" and ends "Reply STOP to opt out.";
  - texts only between 9 AM and 8 PM Central;
  - STOP, START and HELP handled automatically;
  - a consent record kept for every text opt-in.

## What happens on its own

- **Step 1 page:** the man is tagged "Step 1" and gets the welcome series straight away. The mobile number is optional. If he checks the text box, he's opted in to texts.
- **Founding Cohort purchase:** "You're in", then an email reminder the morning before each session and a text at 5 PM on the day for men who opted in. Both carry the Meet link.
- **Forms, purchases, link clicks and text opt-ins:** each starts any automation you've set to that trigger.
- **Bounces and spam complaints:** once the Resend webhook is set up (step 2), they take the address off the list automatically.

## Setup (once)

1. **Hourly scheduler** (exact timing; mail still flows without it):
   1. In GitHub, set the default branch to `claude/sharp-sagan-jrcxxn`.
   2. Make a long random password.
   3. Add it as `CRON_SECRET` in two places: Cloudflare (Pages, Settings, Variables and Secrets, type Secret) and GitHub (Settings, Secrets and variables, Actions).
   4. Run "Email scheduler" once from GitHub's Actions tab.
2. **Bounce protection:**
   1. In Resend, go to Webhooks and add the endpoint `https://bethemansystem.com/api/mail/webhook` with the events `email.bounced` and `email.complained`.
   2. Save its signing secret in Cloudflare as `RESEND_WEBHOOK_SECRET`.
3. **Texts:**
   1. Create a Twilio account and buy a number. A toll-free number is usually simplest for a small sender.
   2. Get it approved for business texting. US carriers require toll-free verification, or A2P 10DLC registration for a local number. This takes days to weeks and has small fees, so check Twilio's current pricing.
   3. In Cloudflare, add `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` and `TWILIO_FROM`.
   4. On the Twilio number, set "A message comes in" to `https://bethemansystem.com/api/sms/inbound` (HTTP POST).
   5. Send yourself a test from the Texts tab.

Never paste these keys into chat.

## Limits

- **Email:** 90 list emails a day (Resend's free plan allows 100). Change it with `MAIL_DAILY_CAP`.
- **Texts:** 50 a day. Change it with `SMS_DAILY_CAP`.
- **Storage:** Cloudflare's free plan allows about 1,000 database writes a day. Each email, open or click uses one to three. That's fine at your size. If the list grows into the thousands, Cloudflare's $5-a-month Workers plan raises the limit about a thousandfold.
- **Open rates:** these run high, because some email apps load images automatically. Clicks are the honest number.

## Added Nov 24: cohort, growth and money tools

| Tab or feature | What it does |
|---|---|
| Cohort | Every man tagged "Founding Cohort": Step 1 done, attendance for each Thursday, his weekly Ledger numbers, notes, buttons to text or email the whole cohort, and the results he shares. |
| The Ledger by text | Sunday 6 PM Central, each cohort man is asked for his number by text (or by email if he isn't on texts). He replies "13/15" or uses the link. Monday at noon, anyone missing gets one nudge, and you get the list. Turn it on or off in Settings. |
| Results | "Ask for results" emails each man a short form: his first and latest numbers, two sentences, and a permission checkbox. Nothing shows on the home page unless he checked the box and you click Approve. |
| Where people come from | Short links tag the source: bethemansystem.com/yt, /ig, /fb, /tt, /sub, /pod, /dm (or add ?src=anything to a link). The site also reads the site a visitor came from. Sign-ups and purchases both carry it. |
| Referral links | Every contact gets bethemansystem.com/r/code (shown on his contact card, and `{{referral_link}}` in emails). Sign-ups through it are credited to him, and "Refers someone who signs up" can start an automation, for example a thank-you. |
| Waitlist | When the 10 seats sell out or the cohort starts, the cohort page swaps the buy button for a waitlist form. The waitlist is the tag "Cohort waitlist". |
| Substack to email | In Settings: do nothing, make a draft and email you, or send automatically when you publish. Posts published before you turn it on are never sent. |
| Money | Revenue this month and over 30 days, sales by product, Club members and monthly revenue, refunds, the path from Step 1 to buyer, and sign-ups, buyers and revenue by source. |
| Monday report | Every Monday at 8 AM Central, an email to you with the week's numbers. You can preview it in Settings. |
| Saved replies | Write them in Settings and insert them in the text inbox or in "Email him" on a contact. |
| Calls | Upcoming and past free calls. Record an outcome (joined, not now, follow up, no show) with a note. A follow-up date emails you a reminder that morning. |

The Ledger, the Monday report, Substack and the reminders run on the hourly scheduler. Until `CRON_SECRET` is set up, they run whenever you open the dashboard.
