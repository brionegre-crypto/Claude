# The Be The Man Club: member portal (systeme.io)

The member portal is a systeme.io classic course, delivered through the membership product.

- **Member URL:** https://go.bethemansystem.com/school/course/club
- **Edit in dashboard:** https://systeme.io/dashboard/courses/680886/curriculum
- **Theme:** ember (dark header, amber accent). Headlines in Oswald, body text in Inter.
- **Sales page link:** "Join the Club - Membership Checkout" (go.bethemansystem.com/d6dd7931)

## How members get access

"The Be The Man Club - Membership" ($17/month) grants:
- Full access to the portal course (added 2026-09-28)
- The 22 downloadable files it already delivered (kept unchanged)
- Access to the "Be The Man Club" community (https://go.bethemansystem.com/community/be-the-man-club)

Buying the membership enrolls the man in the portal and the community automatically.

## Portal structure

| Module | Lessons | Comments |
|---|---|---|
| Start here | Welcome to the club · Your first week in the club | On |
| The 7-step framework | Steps 1–7, one lesson each, each linking its worksheet PDF | On |
| The member library | The Weekly Scorecard · Marriage · Fatherhood · Faith (all 11 tools, PDF and Excel links) | Off |
| The brotherhood | Join the brotherhood: link to https://go.bethemansystem.com/community/be-the-man-club, a first-post template and community norms | Off |

All lessons unlock at once (no drip).

## Members-only discount

- Code **CLUB20**, 20% off, no expiry, unlimited uses. It is mentioned on the welcome lesson.
- Coupons only work on offers where coupons are enabled in the checkout settings. Turn them on only for future products that the membership does not include. Do **not** turn them on for the membership checkout or the store's 11 tools: anyone who sees the code could use it.

## Known gaps / to-dos

- **Check that canceling removes access.** According to systeme.io's help pages, subscription resources are revoked automatically when the subscription ends. Confirm it with a test purchase and cancel (100% coupon). If access stays, note that the plan allows only one automation rule, and the opt-in form already uses it. Either upgrade and add a rule (sale canceled → revoke portal access), or remove canceled members by hand under Contacts.
- **Monthly Club-only tool:** add each month's tool as a new lesson (e.g. a "Monthly tools" module) and link its file.
- **Instagram copy:** the Club caption in `instagram/bethemansystem-playbook.md` says "No group chat". Update it once the community is live.

## Join the Club page

On 2026-09-28 the checkout page ("Join the Club - Membership Checkout") was updated to describe the portal, the full framework, the brotherhood and the 20% member discount. The "What this is not" section no longer says there's no group chat. The form and payment button were not touched.

## Promo videos

See `instagram/posts/README.md`: `out/reel-club-portal.mp4` (9:16) and `out/youtube-club-portal.mp4` (16:9).
- Framework lesson pages describe how to work each step. They do not reproduce the worksheet contents. If a lesson's framing does not match its PDF, edit it in the course editor.

## Growth features (added 2026-09-29)

- **Founding price:** the Club product now uses a $12/month plan ("BTM Club Founding Monthly $12"). The $17 plan still exists, so reattach it to the product when founding pricing ends. Existing members stay on the plan they joined on. The checkout headline, button, "What this is not" line, welcome email and Thursday emails 2 and 6 now say $12 for founding members.
- **Scorecard order bump:** the Scorecard checkout has a checkbox add-on, "Yes, add the Club for $12 a month". It sells the same Club product, so buyers get the portal, community, files and Framework tag.
- **Affiliate commission:** 30% on the Club checkout offer and on the Scorecard add-on (payout delay 30 days). **You still have to switch on the affiliate program in systeme.io** (Settings → Affiliate program) and choose whether members join automatically or need approval.
- **Welcome sequence:** emails 2–7 (the six framework lessons, reworded to say "the next email" instead of "next week") are saved **inactive** in the "Framework" campaign. They're activated on Nov 6, the day after the last Thursday broadcast, each 7 days after the previous one, so October subscribers don't get every lesson twice. A reminder is scheduled in the Claude session.

- **Free intro call:** booking calendar "Free 15-minute call: where are you stuck?" (https://systeme.io/dashboard/calendar/45235). 15 minutes, Mon–Thu 7:00–9:00 PM Central, booked 12 h to 30 days ahead, max 4 a day, 15-minute buffer, reminders 24 h and 1 h before, cancellation up to 2 h before. Location: phone (Brian calls the man; Brian's number is shown as a fallback).

### Blocked by the plan's 15-page limit

The account is at 15 funnel pages, the plan maximum across all funnels, so no new pages can be added. That blocks the upsell page (replaced by the order bump above), the link-in-bio page, the exit popup and the training sign-up/watch pages. An empty funnel called "Links, popups and training" was created while testing the limit; delete it or use it after upgrading. To unblock these, upgrade the plan or delete some of the 11 separate store checkout pages.

### Invite for members (affiliate program)

Post this in the brotherhood or email it to members once the affiliate program is on. Replace the link with your affiliate sign-up link from systeme.io.

> **Bring a brother, and the Club pays you for it.**
>
> If the Club has helped you, you already know a man who needs it. Share your link with him. For every month he stays, you get 30% of his membership: $3.60 a month, every month.
>
> Sign up for your link here: [YOUR AFFILIATE SIGN-UP LINK]
>
> Don't send it to everyone you know. Send it to the one man you'd want next to you in the brotherhood.
