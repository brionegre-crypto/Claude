# Couples inquiries on bethemansystem.com

Status 2026-10-08: form is live at /couples/#inquire. The alert email needs Brian's sender setting (below).

- Form posts to `/api/inquiry` (functions/api/inquiry.js).
- The couple is saved in MailerLite group **Couples inquiries** (200754210229192006), with `inquiry_name`, `inquiry_phone`, `inquiry_type`.
- Brian's own MailerLite record (brian@bethemansystem.com) gets the details and rejoins group
  **Inquiry alerts (Brian only)** (200754210963195398). That starts automation
  **New inquiry alert (to Brian)** (200754218724754839), subject "New {$inquiry_type} inquiry: {$inquiry_name}".
- If MailerLite fails or the key is missing, the visitor is sent to the old systeme.io form (0d29fa39), so nothing is lost.
- Thank-you page: /couples/thanks/.

## Brian's step
MailerLite → Automations → "New inquiry alert (to Brian)" → email step → sender brian@bethemansystem.com.
Tell Claude; Claude fills in the email (name, email, phone, reply button), then Brian activates it.
Do the same for "Your downloads" (see downloads-setup.md).

## Other links moved 2026-10-08
- Inner Circle: now /inner-circle/ on the site (was go.bethemansystem.com/7ccfe2c8). Footer links to it.
- Application call: /call → systeme booking calendar (085b95e4). Stays on systeme until a booking tool replaces it.
- /apply → /inner-circle/, /inquire → /couples/#inquire.
- Still on systeme: Club join (d6dd7931) and its member area, the Oct 25 workshop (f0217426), the booking calendar.
