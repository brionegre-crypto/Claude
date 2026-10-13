# Moving email to Kit (decided 2026-10-13)

Kit (kit.com) replaces MailerLite, which terminated the account. Resend (resend.com) handles the one-to-one emails:
download links, Club sign-in links and inquiry alerts.

## Brian's steps (about 30 minutes)
1. kit.com → sign up with brian@bethemansystem.com → start the **Creator** plan's 14-day free trial (no card).
   If Kit asks about your list during onboarding: a newsletter for Christian men, subscribers come from sign-up forms
   on bethemansystem.com and from customers. Nothing imported.
2. Kit → Settings → Account → add your business address (required in every email footer; a P.O. box is fine).
3. Kit → Settings → Email → Sending domain → add bethemansystem.com → copy the records it shows into
   Cloudflare DNS. While you're there, delete any old record that mentions MailerLite.
4. Kit → Settings → Developer → create a **v4 API key**. Paste it ONLY into Cloudflare → Pages → bethemansystem →
   Settings → Variables and secrets as `KIT_API_KEY` (type: Secret). Never in chat.
5. claude.ai → Settings → Connectors → **Kit** → Connect, and make sure it's switched on for this chat.
6. resend.com → sign up free → Domains → add bethemansystem.com → copy its records into Cloudflare DNS →
   API Keys → create one → Cloudflare secret `RESEND_API_KEY`.
7. Tell Claude: "Kit's connected."

## Claude then builds
- Tags: step-1, challenge, customer, club-member, workshop, six-week-group, ministry-kit, inner-circle,
  couples-inquiry, call-request, low-seat-check.
- Sequences: Step 1 follow-up (6 weekly emails), 7-week challenge (welcome + 7 weekly).
- Automations: tag added → sequence.
- Broadcasts: 11 Thursday emails (Oct 15 to Dec 24, 8 AM Central), 4 Club call reminders, the workshop reminder (Oct 25, 2 PM).
- Site code: sign-ups, purchases, inquiries → Kit tags; downloads, Club sign-in links and inquiry alerts → Resend.
  The old MailerLite shortcut that forced brian@ back to "subscribed" is removed.
- Double opt-in on all forms.

## Going slow on purpose
A brand-new account loaded with dozens of scheduled emails on day one is what most likely tripped MailerLite.
The build goes in this order: sequences first, then a few broadcasts a day, nothing imported.
