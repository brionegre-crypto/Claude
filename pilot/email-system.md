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

## Added Nov 24: the men's portal

Every man gets his own portal at **bethemansystem.com/portal**. He signs in with an emailed link, or a text code once Twilio is set up. There's no password. On his phone, he can add it to his home screen so it opens like an app. Paper still works: every worksheet prints, and he can type in his number or upload a photo of his paper Ledger.

**Who gets one, automatically**
- **Founding Cohort purchase:** a full portal, plus a "Your portal is ready" email with a 7-day sign-in button.
- **Club join:** a full portal. A graduate who was read-only gets full access back.
- **Step 1 sign-up:** a mini portal with Step 1 only. Steps 2 to 4 show an invitation to the cohort.
- **Anyone else:** add him from Men, then "Add a man".

**What he does there**
- **Today:**
  - your next step for him;
  - his current step;
  - his commitments for today, each with Kept, Floor or Missed (he can mark today and the two days before; older days are locked);
  - his streak ("Weeks reported", or "Restart Monday");
  - the next session, with the Meet link, a "what I want help with" note, and an "I'm here" button during the call;
  - your notes to him;
  - an "I'm in a hard week" button.
- **Steps 1 to 4:** a worksheet for each, sent to you to approve. Starter examples, a calendar subscription for his commitments, and printable PDFs.
- **The Ledger:**
  - his week at a glance and the last eight weeks;
  - the group average, with no names;
  - the Sunday review: his number plus four questions;
  - editing his commitments any time, with every version kept.
- **Lessons:** six weeks. Each is text, an optional video, your teaching recording, an action checkbox and a reflection. Men who missed a session also see your catch-up note.
- **More:**
  - messages and prayer requests to you (private);
  - his partner's weekly numbers and Sunday answers;
  - settings: name, mobile, daily reminder time, large text, share link, download his data, and ask to delete it.

**Your side, in the dashboard**

| Tab | What it does |
|---|---|
| Men | Every portal, with where he is, his last two weekly numbers, when he last signed in, and flags. Buttons for: Add a man, Call sheet (each man's note for Thursday, his number and flags), Cohort insights (group trend, steps, attendance, what the men keep missing), Messages, Download backup, and My system. |
| A man's page | Approve or Revisit each step (with a note), open a step early, pace (with the cohort, his own pace, or custom dates), partner, next steps (he's emailed), notes he sees, private notes only you see, messages, Sunday reviews, reflections, Ledger photos, earlier commitment versions, Graduate, Coach view (his portal exactly as he sees it, read-only), and Delete portal. |
| Library | Edit the six lessons and the printables. "Restore the drafts" goes back to the originals. |
| Sessions | For each Thursday, the YouTube link to the teaching part only, and a catch-up note for men who missed. |
| My system | Your own portal: the same as the men's, to follow along and track your own Ledger. |

**What runs on its own (hourly scheduler)**
- **Daily reminder:** at the hour he chose, by email or text, only if something today is still unmarked.
- **Quiet check-in:** after 7 days without signing in, he gets one gentle note, and you get the list.
- **Call prep:** at 6 PM on the Wednesday before a session, men who haven't written a note are asked what they want help with.
- **Backup:** Monday at 7 AM, a backup file is emailed to you.
- **Club access:** daily, Club members whose membership has ended become read-only.

**Safety**
- The 988 line is on every portal screen.
- If anything he writes suggests self-harm, he sees the 988 and 911 message straight away. You get an email marked URGENT, plus a text to `ADMIN_PHONE` if it's set in Cloudflare. His page shows a safety flag.

## Added Nov 24: the Thursday email (weekly tips)

Ten weekly tips for the four-step system, one every Thursday at 8 AM Central, with no weeks skipped. Every man tagged "Step 1" gets them in order, starting the first Thursday after he joins. That covers new sign-ups, everyone already on the list, and Kit imports that carry the "Step 1" tag. Men who are unsubscribed, bounced or complained are skipped.

The men on the list on Nov 24 get email 1 on Thursday, Nov 26. Email 10 goes out on Jan 28.

| Week | Subject |
|---|---|
| 1 | "This week" is not a time |
| 2 | Start with who, not what |
| 3 | Three, not ten |
| 4 | The first ten minutes home |
| 5 | The smallest version that still counts |
| 6 | Fifteen minutes on Sunday |
| 7 | The miss that keeps coming back |
| 8 | Say it out loud to one man |
| 9 | When shame says quit |
| 10 | One evening to reset |

You can edit them in the dashboard under Email series, "The Thursday email". The source is functions/_weekly.js.

The daily email limit is 90. If more men are due on a Thursday than that, the rest go out the next morning.
