# December relaunch: new dates (set Nov 19, 2026)

Everything that has a start date now begins in December. Stripe shows no workshop tickets, group seats, Club members or Inner Circle members yet, so nobody was promised an old date.

## New dates

| Program | Was | Now |
|---|---|---|
| 7-week challenge | Tuesdays Oct 20 to Dec 1 | Tuesdays **Dec 1**, Dec 8, Dec 15, Dec 22, Dec 29, Jan 5, Jan 12 (join any week) |
| 6-week group | Sundays Nov 15 to Dec 20 | Sundays **Dec 6**, Dec 13, Dec 20, Dec 27, Jan 3, Jan 10 (7 to 8 PM Central) |
| Fix Your Wednesday | Every other Wednesday from Nov 4 | Every other Wednesday from **Dec 2**: Dec 2, Dec 16, Dec 30, Jan 13 (7 to 8 PM Central) |
| Inner Circle founding circle | Thursday Nov 5 | Thursdays from **Dec 3** (7 to 8 PM Central) |
| Club monthly call | Second Tuesday | Unchanged (next: Dec 8) |
| Truth Ledger | You pick Day 1 | Unchanged |

## Done

- **Website:** challenge, group, workshop and Inner Circle pages, the homepage banner, event data for search engines, the checkout confirmation text for the group, the workshop "next session" dates.
- **Code:** the workshop schedule (functions/_workshop.js, web/build.py) and the free-call booking, which now blocks Thursdays 7 to 8 PM from Dec 3 and workshop Wednesdays from Dec 2.
- **Stripe:** the 6-week group product description now says December 6 to January 10. Prices and payment links are unchanged. (The workshop description is date-free.)
- **Google Calendar:** the recurring workshop event now starts Dec 2, the recurring Inner Circle class starts Dec 3 (weekly, Thursdays).

## Still on the old dates (Kit is locked behind its paid plan, so I can't change it)

Reschedule these in Kit once the plan is active. Subscribers on these tags are unaffected until you do.

**7-week challenge emails** (to the "7-week challenge" tag): each is already scheduled or sent on the old Tuesday. New dates, 6:00 AM Central:

| Email | Kit id | New send date |
|---|---|---|
| Week 1: one sentence | 26434585 | Tue Dec 1 |
| Week 2: three goals, not ten | 26434587 | Tue Dec 8 |
| Week 3: name the wall | 26434588 | Tue Dec 15 |
| Week 4: give it a time | 26434589 | Tue Dec 22 |
| Week 5: decide what a miss is | 26434596 | Tue Dec 29 |
| Week 6: count it | 26434597 | Tue Jan 5 |
| Week 7: God at the center | 26434598 | Tue Jan 12 |

Week 1's text says "by Monday at 9 PM, finish the Step 1 worksheet" and "On Tuesday, that sentence decides which of your goals stay." Both still read correctly on Dec 1.

**Thursday emails** (Step 1 and Club tags, Thursdays 8 AM Central, ids 26434619 to 26434651): scheduled Oct 22 to Dec 24. Decide whether to restart this series in December. Moving the whole run by six weeks would end it Feb 4.

**Workshop emails:** the drafts for the Nov 4 and Nov 18 sessions are obsolete and can be deleted (reminders 26627697 and 26627699, feedback 26627709 and 26627710). The Dec 2, Dec 16, Dec 30 and Jan 13 drafts are the ones to schedule (reminders 26627700 to 26627703 at 2 PM on the day; feedback 26627711 to 26627714 at 9 AM the next morning).

**Step 1 welcome and follow-up sequences:** unchanged. The weekly Step 1 follow-up starts for sign-ups from Nov 6 (FOLLOW_UP_FROM in functions/_mail.js), which was chosen to avoid doubling with the Thursday emails. Revisit it if you restart that series.

## Heads-up on holidays

The group meets Sunday Dec 27 and Jan 3, and the challenge emails go out Dec 22 and Dec 29. If you'd rather skip a holiday week, tell me and I'll shift the schedule.
