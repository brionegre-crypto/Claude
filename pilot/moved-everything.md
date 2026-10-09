# Everything else moved off systeme.io (2026-10-09)

Everything below now runs on bethemansystem.com, Stripe and MailerLite. The systeme versions still work until you cancel.

| What | New home | Checkout (Stripe) | MailerLite group |
|---|---|---|---|
| Fix Your Wednesday workshop, Sun Oct 25, 7 PM Central, $27 | /workshop/ (switches itself to the group after Oct 26) | buy.stripe.com/4gM3cw8zV1XT9ll2ja6kg0h, Library add-on $49 at checkout | Workshop |
| 6-week group, Sundays from Nov 15, $147, 4 seats | /group/ | buy.stripe.com/6oUbJ2dUfgSN7dd1f66kg0i (closes itself after 4 sales) | 6-week group |
| Men's ministry kit, $199 | /ministry-kit/ | buy.stripe.com/14AdRa17tbyt6995vm6kg0j (asks for church name) | Ministry kit buyers |
| Inner Circle, by application | /inner-circle/ → /call/ | founding link buy.stripe.com/fZudRa2bx7id8hh4ri6kg0l, 8 seats, $197/mo | Inner Circle |
| Be The Man System, $97 | /products/#the-system, offered after the Scorecard | buy.stripe.com/5kQ3cw7vR9ql2WXe1S6kg0k | Customers |
| Free 15-minute call | /call/ request form (alert email to brian@) | none | Call requests |
| Free training | /training/ | none | none |
| Link in bio | /step-1/ (all links listed) | none | none |

How delivery works
- Every purchase lands on its /get/ page with the files, and the "Your downloads" email repeats the link.
- Workshop buyers see the Meet link (meet.google.com/mdt-djbx-kfo) on the page and in the email; a reminder campaign goes to the Workshop group Oct 25 at 2 PM Central.
- Ministry kit buyers get the 9-part leader guide online at /get/ministry-kit-bwiuh7ba/guide/, locked to buyers.
- Inner Circle members sign in at /club-login/ like Club members and see two extra lessons, including the monthly Meet link (meet.google.com/tcg-zspn-cco).

Old go.bethemansystem.com links
- functions/_middleware.js redirects every old systeme path (funnel pages, checkouts, /school) to its new page.
- It starts working once go.bethemansystem.com is added to Cloudflare Pages as a custom domain. Do that when you cancel systeme.

Not recreated
- The exit popup.
- The $19 workshop recording product (email the recording to the Workshop group instead).
- The systeme booking calendar: /call/ is a request form. A Google Calendar appointment schedule can replace it later.

Emails
- The challenge Week 3 email now points to /group/.
- The systeme workshop reminder was unscheduled. The systeme challenge emails stay scheduled as a safety net (0 contacts).
