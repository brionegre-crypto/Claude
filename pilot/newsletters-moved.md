# Newsletters moved from systeme.io to MailerLite (2026-10-09)

New sign-ups land in MailerLite since 2026-10-08, so every scheduled email that should reach them was rebuilt there.
Email HTML (converted from systeme, with fixes) is in `pilot/emails/newsletters/` (`index.json` lists subject, date, source id).

## Thursday email: 11 campaigns, 8:00 AM Central
To MailerLite groups: Step 1, Moved from systeme.io, Club members.
Oct 15, 22, 29 · Nov 5, 12, 19, 26 · Dec 3, 10, 17, 24. All status "ready" (scheduled).

## Club call reminders: 4 campaigns, 9:00 AM Central on call day
To group: Club members. Nov 10, Dec 8, Jan 12, Feb 9.

## Welcome series: automation "Step 1 follow-up (Steps 1 to 6, weekly)" (200853084286485767)
Trigger: joins group Step 1. 7 days, email 2 ... 7 days, email 7 (six emails, all complete).
INACTIVE until Nov 6 on purpose (same plan as systeme): men who sign up before then get Steps 3-6 from the
Thursday emails, so switching it on earlier would double up. Reminder trig_01ShhRGAED49dbKK12p7NPkA fires Nov 6
and asks Brian to click Activate.

## Fixes made while moving
- "$12 founding" pricing → "$19 a month, or $149 a year".
- "The brotherhood" (systeme community) → monthly call and accountability partner.
- Links: Club checkout → /the-club/, product checkouts → /products/ sections, Step 1 PDF → site copy,
  partner opt-in → /members/call/#partner. Unsubscribe link added to every email.

## systeme.io
Unscheduled (kept as drafts, not deleted): the 11 Thursday newsletters and 4 Club call reminders.
Still scheduled there on purpose: the 7-week challenge (Week 1-7, Oct 20 to Dec 1, tag "7-week challenge")
and the workshop reminder (Oct 25, tag "Workshop: Fix Your Wednesday"), because those sign-ups still happen on systeme.
Framework campaign steps 2-7 stay inactive; step 1 stays active for anyone who still signs up on old systeme links.

## Watch
MailerLite's free plan (after the trial) may not include the custom HTML editor. Already-built emails should still
send; if MailerLite flags them after the trial, upgrade or rebuild in the drag-and-drop editor.
