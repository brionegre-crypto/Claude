# Keel: App Store Connect walkthrough

Step by step, in the order to do it. Everything here happens at **appstoreconnect.apple.com** (it works in Safari on your phone, but screenshots are easier on the Mac). Keel already exists there because TestFlight uses it, so you're filling in the store page, not creating an app.

---

## Before you start: decide two things

1. **Free or paid?** Keel's paywall is off (`Entitlements.paywallEnabled = false`), so every feature is free right now. If you want Keel Pro, do **Step 7** and tell Claude to turn the paywall on before you submit. The subscription IDs the app already looks for are `keel.pro.monthly` and `keel.pro.yearly`.
2. **The version number.** The app is `0.1.0`. A first public release is usually `1.0`. Tell Claude "set the version to 1.0" and it's one line.

---

## Step 1: Agreements, tax and banking (only if charging)

App Store Connect → **Business** (top menu; it was called Agreements, Tax, and Banking).
- Accept the **Paid Apps Agreement**.
- Add a bank account and fill in the tax forms (W-9 in the US).
- Skip this if Keel stays free.

## Step 2: App Information

App Store Connect → **Apps → Keel → General → App Information**.
- **Name:** `Keel` (if it's taken, try `Keel: ADHD Planner` or `Keel – Calm Productivity`).
- **Subtitle (30 characters):** for example `Tasks, mail & focus for ADHD`.
- **Category:** Primary **Productivity**, Secondary **Health & Fitness** (or Lifestyle).
- **Content Rights:** "No, it does not contain, show, or access third-party content." (Mail and notes are the user's own.)
- **Age Rating:** click **Set Up Age Rating** and answer **None / No** to everything. Keel has no user-generated public content, gambling or mature themes. Expect **4+**.

## Step 3: Pricing and Availability

**Apps → Keel → Monetization → Pricing and Availability** (in the sidebar).
- **Price:** Free (even with Keel Pro, the app itself is free; the subscription is an in-app purchase).
- **Availability:** all countries, or just the US to start.
- **Mac:** under "Mac App Store availability" (or the macOS platform section), make sure the Mac Catalyst version is **available**. You already ship it to TestFlight, so it's listed as a separate platform on the left (iOS App / macOS App).

## Step 4: App Privacy (the "nutrition label")

**Apps → Keel → Trust & Safety → App Privacy** (older layouts: **App Privacy** in the sidebar).
1. **Privacy Policy URL:** `https://keel-backend.bbritt2223.workers.dev/privacy`
2. Click **Get Started** → "Do you or your third-party partners collect data from this app?" → **Yes**.
3. Tick these data types, and nothing else:

| Data type | Used for | Linked to the user? | Tracking? |
|---|---|---|---|
| **Contact Info → Name** | App Functionality | Yes | No |
| **Contact Info → Email Address** | App Functionality | Yes | No |
| **Identifiers → User ID** | App Functionality | Yes | No |
| **Diagnostics → Crash Data** | App Functionality | No | No |
| **Diagnostics → Performance Data** | App Functionality | No | No |
| **User Content → Other User Content** | App Functionality | No | No |

Why these:
- Name, email and user ID come from Sign in with Apple and are kept on your Keel server.
- Crash data is only sent if someone turns on "Share crash reports".
- "Other User Content" covers shared lists and published pages, which are stored on your server when someone chooses to share.
- Mail, notes, tasks, calendar and Health stay on the device or in the user's own iCloud. Apple doesn't count data you never receive, so they don't go on the label.
- If someone uses Claude AI, their question is sent through your server to Anthropic. Add **User Content → Other User Content** (already ticked above) and you're covered.

4. Click **Publish**.

## Step 5: The version page (screenshots and text)

**Apps → Keel → iOS App → 1.0 Prepare for Submission** (click **+ Version** if there isn't one).

**Screenshots:** you need two sets on iOS, plus a Mac set if you're releasing on Mac.
- **iPhone 6.9"** (1320 × 2868, from an iPhone 16/17 Pro Max), 3 to 10 screenshots.
- **iPad 13"** (2064 × 2752), because Keel runs on iPad.
- **Mac** (2880 × 1800 or 1440 × 900), on the macOS App page.
- Easiest way: take them on your phone with the side button + volume up. Good screens:
  - Today
  - Inbox with categories
  - Notes home with folders
  - a task list with This Evening
  - the food scanner result
  - Autopilot suggestions
  - the Meal plan
- Smaller iPhone sizes are generated from the 6.9" set automatically.

**Promotional Text (170 characters, can change any time):**
> Now with a paperwork vault, meal plans with a grocery list, shared lists, rewards and a "Start now" timer for time blindness.

**Description:** a starting draft:
> Keel is a calm home for everything on your mind, built for ADHD brains.
>
> One place for email, calendar, tasks, notes, habits and focus, with an assistant that does the prep work so you only have to say yes.
>
> • TODAY: your single best next step, not a wall of everything
> • INBOX: sorted for you, with drafted replies and one-tap unsubscribe
> • TASKS: This Evening, deadlines, errands by place, and a Start-now timer sized to how long things really take you
> • NOTES: pages, folders, canvases, meeting notes that write themselves, and a paperwork vault for receipts and warranties
> • FOCUS: block distractions, body-double in a focus room, and pick up where you left off
> • HEALTH: habits, medication reminders, and a food scanner that checks products against your diet
> • PRIVATE: AI runs on your device with Apple Intelligence. Your data lives on your devices and your iCloud.
>
> Works on iPhone, iPad, Mac and Apple Watch, synced with iCloud.

**Keywords (100 characters, commas, no spaces):**
`adhd,planner,focus,to do,tasks,habits,email,calendar,notes,routine,reminders,executive function`

**Support URL:** required. Either a simple page, or for now `https://keel-backend.bbritt2223.workers.dev/privacy` plus your support email in the description. A real page is better; Claude can add a `/support` page to the server.

**Marketing URL:** optional, leave blank.

**Version / Copyright:** `© 2026 Brian Greene Jr.` (or your company name).

## Step 6: App Review Information (same page, scroll down)

- **Sign-in required?** Tick **No**: Sign in with Apple is optional and the app works without it. (If you'd rather, tick it and give a demo account.)
- **Contact:** your name, phone and email.
- **Notes**, paste something like this:

> Keel is a productivity app for people with ADHD. No account is needed: tap through onboarding and every feature works.
>
> • Mail: connect any Gmail or Outlook account in Settings → Mail Accounts. We are happy to provide a test Gmail account if needed.
> • AI features use Apple Intelligence on supported devices. Optional Claude features go through our own server, with no setup needed by the user.
> • Sign in with Apple is optional and only used to sync the user's Keel server account across devices. Account deletion: Settings → Account → Delete Account.
> • Shared lists and published pages create links on our server (keel-backend.bbritt2223.workers.dev) only when the user chooses to share.
> • Microphone is used only for meeting notes, which the user starts. Health access is optional (nutrition and focus).

**Account deletion:** Apple requires an in-app way to delete an account when there's sign-in. Keel has this: **Settings → Account → Delete Account…** (shows once signed in). Reviewers check for it.

## Step 7: Keel Pro subscription (only if charging)

**Apps → Keel → Monetization → Subscriptions**.
1. Create a **Subscription Group** called `Keel Pro`.
2. Add a subscription with:
   - **Product ID** `keel.pro.monthly` (must match exactly)
   - **Reference name** "Keel Pro Monthly"
   - **Duration** 1 month
   - a price, for example $5.99
3. Add another with **Product ID** `keel.pro.yearly`, **Duration** 1 year, and a price, for example $39.99.
4. For each one, fill in:
   - display name and description (Localization)
   - a review screenshot of the paywall
5. Optional: a free trial under **Subscription Prices → Introductory Offers**, for example 1 week free.
6. On the version page, under **In-App Purchases and Subscriptions**, add both so they're reviewed with the app.
7. Tell Claude to flip `paywallEnabled` to true, then wait for the new build.

## Step 8: Export compliance

Already handled: the app declares `ITSAppUsesNonExemptEncryption = NO` (standard HTTPS only), so you won't be asked.

## Step 9: Pick the build and submit

1. On the version page, in **Build**, click **+** and pick the latest TestFlight build that you've tested.
2. **Release options:** pick "Manually release this version" so you choose the launch moment.
3. Click **Add for Review** → **Submit to App Review**.
4. Do the same on the **macOS App** page with the Mac build if you're launching on Mac too.
5. Review usually takes 1 to 3 days. If Apple rejects something, paste the message to Claude; most fixes are small.

## Step 10: CloudKit (one check before launch)

Open **icloud.developer.apple.com → CloudKit Console → iCloud.com.briangreenejr.keel**. Check that the **Production** schema has every record type the Development schema has. If they differ, click **Deploy Schema Changes**. Otherwise sync breaks for App Store users while still working in TestFlight.

---

## Not done in App Store Connect

- **Family Controls (app blocking):** Apple must approve the distribution entitlement before it can ship. Request it at developer.apple.com/contact/request/family-controls-distribution. Until approved, builds leave app blocking out automatically.
- **Test before submitting:**
  - a fresh install through onboarding
  - the largest text size (Settings → Accessibility → Display & Text Size)
  - the oldest iPhone you can borrow
