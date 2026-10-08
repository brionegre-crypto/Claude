# The Be The Man Club on bethemansystem.com

Built 2026-10-08. Replaces the systeme.io checkout (d6dd7931 / f05699c8) and course portal (go.bethemansystem.com/school/course/club).

## Billing (Stripe, live)
- Product prod_VP2P69gbKV3XiA. Prices: $19/month price_1UOELDIJyHMhQ40vrMP26SAG, $149/year price_1UOELGIJyHMhQ40v3ZjwH3Qn.
- Payment Links: monthly https://buy.stripe.com/3cIaEY3fB6e9app6zq6kg0f, yearly https://buy.stripe.com/6oUcN6cQbdGB5556zq6kg0g.
  Both redirect to /the-club/welcome/?session_id=...
- Customer portal (cancel at period end, update card, invoices): https://billing.stripe.com/p/login/3cIfZi17t31X0OPga06kg00 ("Manage membership" in the members area).
- Join buttons use these only when `web/club/config.json` has `"live": true`. Until then they still go to systeme.

## Members area
- /members/ (home), 17 lessons: Start here (3), the 7 steps, Months 1 to 6, the call and partner lesson.
  Lesson text: web/club/lessons.json (exported from the systeme course; comment, community and CLUB20 references rewritten).
- Access: functions/members/_middleware.js. Member = active/trialing/past-due Stripe subscription to a Club price.
- Sign in: /club-login/ → emailed link (30 min) via MailerLite automation "Club sign-in link" (group 200754587357939123, field login_url).
  After checkout, members are signed in automatically. Sessions last 30 days and are re-checked with Stripe daily, so cancelled members lose access within a day of the period ending.
- Drip: monthly members get Month N on day 30×(N−1); yearly members get everything on day one. Files are locked the same way (/api/club/file).
- Accountability pairs: opt in/out on the call lesson → MailerLite group "Accountability pairs" (200754588278589338). Brian pairs that list on the 1st.
- New members join MailerLite group "Club members" (200754586620789990) for call reminders.

## Not moved
- The systeme community ("brotherhood"). The website has no forum; the call and pairs replace it. The Club page never promised a community.
- No existing members needed moving (systeme had no Club members on 2026-10-08).
