# Instant mail alerts and app blocking: what you set up

## 1. Instant new-mail alerts (Gmail and Outlook, even when Keel is closed)

Keel's code is done. It needs an Apple push key and a shared secret on your Keel server. Everything below happens in your browser; never paste these values into a chat.

**A. Apple push key** (developer.apple.com)
1. Certificates, IDs & Profiles → **Keys** → **+**.
2. Name it "Keel push", tick **Apple Push Notifications service (APNs)**, Continue → Register → **Download** the `.p8` file (only downloadable once).
3. Note the **Key ID** on that page, and your **Team ID** (Membership details).

**B. Put them on your server** (Cloudflare → Workers & Pages → keel-backend → Settings → Variables and Secrets → Add, type *Secret*)
- `APNS_KEY`: open the `.p8` file in TextEdit and paste the whole contents, including the BEGIN/END lines.
- `APNS_KEY_ID`: the 10-character Key ID.
- `APNS_TEAM_ID`: the 10-character Team ID.
- `PUSH_SECRET`: any long random text, for example from a password generator (it proves the "new mail" notices are really for you).

**Outlook** works as soon as those are saved: open Keel and pull to refresh once.

**Gmail** also needs Google's notice service (Google Cloud console, in the same project as Keel's Gmail sign-in):
1. Enable the **Cloud Pub/Sub API**.
2. Pub/Sub → **Topics** → Create topic `keel-gmail`.
3. On the topic → **Permissions** → Add principal `gmail-api-push@system.gserviceaccount.com` with role **Pub/Sub Publisher**.
4. Topic → **Create subscription** → Delivery type **Push** → Endpoint `https://keel-backend.bbritt2223.workers.dev/push/gmail?secret=` followed by your PUSH_SECRET.
5. In Cloudflare add variable `GMAIL_PUBSUB_TOPIC` = `projects/YOUR-PROJECT-ID/topics/keel-gmail`.

**Needs:** the build must include push (set `KEEL_ICLOUD=1` in the Xcode Cloud workflow; it carries the push permission). iCloud Mail and other IMAP accounts can't send these notices, so they keep using background refresh. iOS limits silent wake-ups, so on a very busy day some alerts may wait for the next refresh.

## 2. App blocking (Screen Time)

Apple already approved Keel's Family Controls permission. What fails is Xcode Cloud: besides the TestFlight/App Store build it also exports an "ad hoc" copy, and Apple's ad-hoc profile doesn't carry Family Controls yet (exit code 70).

1. **Try it now:** in App Store Connect → Xcode Cloud → your workflow → Environment → add `KEEL_FAMILY_CONTROLS` = `1`, then start a build. If it succeeds, you're done.
2. **If it fails with exit code 70 again:** ask Apple to enable it for ad hoc. developer.apple.com/contact → Development and Technical → *Entitlements*, and paste:

   > Our app Keel (bundle ID com.briangreenejr.keel) was approved for the Family Controls (Distribution) entitlement. Xcode Cloud builds fail when exporting the Ad Hoc distribution because the Ad Hoc provisioning profile does not include com.apple.developer.family-controls. Could you please enable Family Controls for Ad Hoc distribution on this App ID as well? Keel uses it only for individual (self) authorization: during a focus session the user picks apps to shield on their own device.

3. Until then, builds leave app blocking out and the rest of Focus works.
