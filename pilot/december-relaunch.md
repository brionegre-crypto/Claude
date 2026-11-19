# December relaunch: new dates (set Nov 19, 2026, holiday breaks added the same day)

Everything that has a start date now begins in December, with a break over the holidays. Stripe shows no workshop tickets, group seats, Club members or Inner Circle members yet, so nobody was promised an old date.

## New dates

| Program | Was | Now |
|---|---|---|
| 7-week challenge (Tuesdays) | Oct 20 to Dec 1 | **Dec 1**, Dec 8, Dec 15, **break (no emails Dec 22 or 29)**, Jan 5, Jan 12, Jan 19, Jan 26 |
| 6-week group (Sundays, 7 to 8 PM Central) | Nov 15 to Dec 20 | **Dec 6**, Dec 13, Dec 20, **break (no session Dec 27 or Jan 3)**, Jan 10, Jan 17, Jan 24 |
| Fix Your Wednesday (every other Wednesday, 7 to 8 PM Central) | From Nov 4 | From **Dec 2**: Dec 2, Dec 16, Dec 30, Jan 13 (Dec 30 kept) |
| Inner Circle (Thursdays, 7 to 8 PM Central) | Founding circle Nov 5 | Weekly from **Dec 3** (every Thursday, including Dec 24 and 31) |
| Thursday emails (8 AM Central) | Oct 22 to Dec 24 | **Dec 3**, Dec 10, Dec 17, **break (none Dec 24 or 31)**, Jan 7, Jan 14, Jan 21, Jan 28, Feb 4, Feb 11, Feb 18 |
| Club monthly call | Second Tuesday | Unchanged (next: Dec 8) |
| Truth Ledger | You pick Day 1 | Unchanged |

## Done

- **Website:** challenge, group, workshop and Inner Circle pages; the homepage banner; event data for search engines; the group checkout confirmation; the workshop "next session" dates.
- **Code:** the workshop schedule and the free-call booking (blocks Thursdays 7 to 8 PM from Dec 3 and workshop Wednesdays from Dec 2).
- **Stripe:** the 6-week group description now lists the six dates and the break. Prices and payment links are unchanged.
- **Google Calendar:** the recurring workshop starts Dec 2; the recurring Inner Circle class starts Dec 3.
- **Emails, rewritten in this repo (pilot/emails):**
  - Thursday emails 7 ("Say it at the table"), 10 ("The smallest version that still counts") and 11 (now "One evening to reset") no longer mention Thanksgiving, December, Christmas or January, so they work in any month. The teasers at the end of emails 6, 9 and 10 match. All ten Thursday emails now end "Built for the brain God gave you."
  - 7-week challenge: week 3 tells people the next email is Tuesday, January 5; week 4 refers to "week three"; weeks 5 and 6 no longer mention a Thanksgiving week; the welcome email says "if you joined after December 1".

## Still to do in Kit (locked behind its paid plan; the key in this environment is rejected)

When Kit is active again, say "retry" and a fresh session runs this. Or run it yourself:

```
KIT_API_KEY=... node scripts/kit-apply-plan.mjs            # dry run: lists every change
KIT_API_KEY=... node scripts/kit-apply-plan.mjs --apply    # makes the changes
```

It reschedules the 10 Thursday emails and 7 challenge emails to the dates above, rewrites the wording in Kit to match this repo, and checks each one afterward. It never touches an email whose text doesn't match what it expects, and it skips anything Kit has already sent (add `--resend-completed` only if you want a fresh copy of an already-delivered email to go to the same subscribers again).

| Challenge email | Kit id | New send (6 AM Central) |
|---|---|---|
| Week 1: one sentence | 26434585 | Tue Dec 1 |
| Week 2: three goals, not ten | 26434587 | Tue Dec 8 |
| Week 3: name the wall | 26434588 | Tue Dec 15 |
| Week 4: give it a time | 26434589 | Tue Jan 5 |
| Week 5: decide what a miss is | 26434596 | Tue Jan 12 |
| Week 6: count it | 26434597 | Tue Jan 19 |
| Week 7: God at the center | 26434598 | Tue Jan 26 |

| Thursday email | Kit id | New send (8 AM Central) |
|---|---|---|
| 2 "This week" is not a time | 26434619 | Thu Dec 3 |
| 3 The empty pillar | 26434620 | Thu Dec 10 |
| 4 A mechanism, not a mood | 26434621 | Thu Dec 17 |
| 5 The first ten minutes home | 26434630 | Thu Jan 7 |
| 6 Fifteen minutes on Sunday | 26434631 | Thu Jan 14 |
| 7 Say it at the table | 26434632 | Thu Jan 21 |
| 8 The conversation you keep postponing | 26434639 | Thu Jan 28 |
| 9 The best meeting of your day | 26434640 | Thu Feb 4 |
| 10 The smallest version that still counts | 26434650 | Thu Feb 11 |
| 11 One evening to reset (was "One evening before January") | 26434651 | Thu Feb 18 |

**By hand in Kit**
- The challenge welcome email (sequence "7-week challenge welcome", email id 10440045) says "If you joined after October 20". Change it to "December 1". The script only handles broadcasts.
- Delete the obsolete workshop drafts for the Nov 4 and Nov 18 sessions: reminders 26627697 and 26627699, feedback 26627709 and 26627710.
- Schedule the workshop drafts for Dec 2, Dec 16, Dec 30 and Jan 13 (reminders 26627700 to 26627703 at 2 PM on the day; feedback 26627711 to 26627714 at 9 AM the next morning): `node scripts/kit-schedule.mjs --apply`.
- Already-sent emails: if Kit delivered Thursday emails 2 to 6 or challenge weeks 1 to 3 before it locked, subscribers got them on the old dates. Decide whether a December copy to the same people is what you want, or whether only new subscribers should get the restart. A Kit sequence (an evergreen series that starts for each new subscriber) is the better long-term shape for the Thursday emails.

## Not changed

- Step 1 welcome and follow-up sequences; the weekly Step 1 follow-up still starts for sign-ups from Nov 6 (FOLLOW_UP_FROM in functions/_mail.js). Revisit it when you decide about the Thursday series.
- Inner Circle Thursdays Dec 24 and 31 are still on the calendar. Tell me if you want those skipped too.
- The ADHD wording of the emails themselves (beyond the fixes above). They are mechanism emails and read fine for the audience, but none yet speaks to ADHD directly.
