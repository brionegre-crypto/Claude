# Keel — App Store launch checklist

What's left before Keel can go on the App Store. Items marked **(you)** happen in App Store Connect or on developer.apple.com.

## Already done in the app
- [x] Privacy manifests (PrivacyInfo.xcprivacy) for the app, widgets, share extension and watch app
- [x] Every permission explains why it's needed (camera, microphone, calendars, Health, location…)
- [x] Opt-in crash reports (Settings → Data & Storage → Crash reports)
- [x] Export everything (ZIP) and full import from other apps
- [x] Sign in with Apple, iCloud sync, accessibility (text size, VoiceOver labels), Mac and iPad versions
- [x] Privacy and terms pages on your Keel server: `/privacy` and `/terms`

## In App Store Connect (you)
1. **App Privacy** (App Store Connect → Keel → App Privacy): data is used only for app functionality.
   - Contact info (name, email from Sign in with Apple): App functionality, linked to the user, not used for tracking.
   - Health & fitness (only if Health sharing is on): App functionality, not linked to identity.
   - Diagnostics (crash data, opt-in): App functionality, not linked.
   - Emails, notes, tasks and calendar stay on device or in the user's iCloud and aren't collected by you.
2. **Privacy Policy URL**: `https://keel-backend.bbritt2223.workers.dev/privacy`
3. **Support URL**: a page or email address people can reach you at.
4. **Screenshots**: 6.9" iPhone (required), 13" iPad (required now that iPad is supported), and Mac (16:10). Today, Inbox, Notes with folders, the food scanner and Autopilot make a strong set.
5. **Description, keywords, subtitle** ("Calm productivity for ADHD minds" or similar), category Productivity, age rating questionnaire.
6. **App Review notes**: explain Sign in with Apple is optional, how to try mail (a test Gmail account helps), and that Claude is optional (on-device Apple Intelligence works without it).
7. **Keel Pro** (if charging): create the subscription products in App Store Connect, then turn on `Entitlements.paywallEnabled` in the app. Make sure the paywall has Restore Purchases and links to the terms and privacy pages.
8. **Family Controls** (app blocking): Apple has to approve the distribution entitlement before it can ship; until then builds leave it out (KEEL_FAMILY_CONTROLS).

## Before submitting
- [ ] Turn off the developer-only "Create iCloud schema" (it's only in Debug builds, so Release is already clean)
- [ ] Deploy the latest CloudKit schema to Production if data types changed (CloudKit Console)
- [ ] Run through onboarding on a fresh install
- [ ] Test on the oldest supported iPhone and with the largest text size
