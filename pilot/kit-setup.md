# Email on Kit (set up 2026-10-15)

Kit (kit.com, account "Be The Man System", Creator plan) holds the list and sends the newsletters and email series.
Resend (resend.com) sends one-to-one emails: download links, Club sign-in links, inquiry alerts to Brian.
MailerLite terminated the account on 2026-10-09; nothing uses it any more.

## Done by Claude
- Tags: Step 1 (24600590), 7-week challenge (24600591), Customer (24600592), Club member (24600593),
  Inner Circle (24600594), Workshop: Fix Your Wednesday (24600595), 6-week group (24600596),
  Ministry kit buyer (24600597), Couples inquiry (24600598), Call request (24600599), Low Seat Check (24600600),
  Accountability pair (24600601).
- Sequences (all published, Central time):
  - "Step 1 welcome (sends the worksheet right away)" (2931291): the "Step 1." email, immediately.
  - "Step 1 follow-up (Steps 1 to 6, weekly)" (2928502): 6 emails, 7 days apart. The site only starts it for
    sign-ups from Nov 6 (before that the Thursday emails cover the same steps).
  - "7-week challenge welcome" (2928501): the welcome email, immediately.
- 22 broadcast drafts. Each one's description says when to schedule it:
  - Challenge weeks 1-7: Tuesdays Oct 20 to Dec 1, 6 AM Central, tag 7-week challenge.
  - Thursday emails 2-11: Oct 22 to Dec 24, 8 AM Central, tags Step 1 or Club member.
    (Thursday email 1 went out from systeme on Oct 15.)
  - Club call reminders: Nov 10, Dec 8, Jan 12, Feb 9, 9 AM Central, tag Club member.
  - Workshop reminder: Sun Oct 25, 2 PM Central, tag Workshop.
- Site code (functions/_mail.js, functions/_emails.js): sign-ups, purchases, inquiries, Club join/sign-in/pairs
  all go to Kit and Resend. Without the keys, sign-ups and inquiries fall back to the old systeme forms.

## Brian's steps
1. Kit → Settings → Email → Sending addresses → add brian@bethemansystem.com (name: Brian Greene) →
   click the link Kit emails you → make it the default. Remove the .org address.
2. Kit → Settings → Email → Sending domain → add bethemansystem.com → copy the records into Cloudflare DNS.
   Delete any old record that mentions MailerLite.
3. Kit → Settings → Developer → create a v4 API key → Cloudflare → Pages → bethemansystem → Settings →
   Variables and secrets → add `KIT_API_KEY` (type Secret). Never in chat.
4. resend.com → sign up free → Domains → add bethemansystem.com → copy its records into Cloudflare DNS →
   API Keys → create → Cloudflare secret `RESEND_API_KEY`.
5. Cloudflare → Pages → bethemansystem → Deployments → Retry the latest deployment (so the new secrets load).
   Optional: delete the old `MAILERLITE_API_KEY` secret.
6. Kit → Broadcasts: open each draft, check the sender is the .com address, and schedule it for the date in
   its description. The first two: Week 1 (Tue Oct 20, 6 AM) and Thursday email 2 (Thu Oct 22, 8 AM).
7. Move your existing subscribers: systeme → Contacts → filter tag "Framework" → export CSV →
   Kit → Subscribers → Import → tag them "Step 1". Only people who signed up.
8. Test: sign up for Step 1 on the site with a second email, buy the $7 Scorecard, request a Club sign-in link,
   send a /call/ request. Each should arrive within a minute.
