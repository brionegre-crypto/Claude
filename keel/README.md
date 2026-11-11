# Keel: an AI productivity super app for iPhone, built for ADHD brains

**Keel** combines your **email** (Gmail, Outlook, iCloud), **calendars**, **Apple Reminders**, **notes**, **habit stacks** and **distraction shutdown** in one calm, premium iOS app. AI sorts the mess and hands you *one thing at a time*.

> Think Superhuman + Spark (mail) × TickTick (tasks/calendar) × Notion (notes) × Opal/one sec (focus), redesigned for people with ADHD.

*Status: working prototype source code (SwiftUI, iOS 26). It was written on Linux, so it has **not been compiled in Xcode yet**. Expect a round of compile fixes on first build. The backend type-checks cleanly.*

---

## 1. Design principles (ADHD-first)

| Principle | What it means in the app |
|---|---|
| **One focal point** | The Today screen leads with a single "Just One Thing" card instead of a 40-item list. |
| **Make time visible** | Countdowns and shrinking rings instead of timestamps. Warnings 5 min before a block ends. A hyperfocus check 30 min after. |
| **Shrink the start** | AI breaks any task into 2–10 minute micro-steps, and the first step is always tiny ("Open the doc"). |
| **No shame** | No red overdue badges. "Reset my day" moves everything with no guilt. Streaks have grace days, and total completions never go down. |
| **Dopamine on completion** | Haptics, symbol bounces, and a celebration when you finish. Finishing should *feel* good. |
| **Fewer choices** | 5 tabs. Pick tasks by **energy level** (Low battery / Steady / Locked in), not just priority. |
| **Capture without friction** | Brain dump, command bar (⌘K), Siri ("Add a task in Keel"), natural-language dates. |

**Premium look:** iOS 26 Liquid Glass cards, SF Pro Rounded, one indigo accent, meaningful color (never decoration), spring motion, full Dynamic Type and VoiceOver labels. See `Keel/App/DesignSystem.swift`.

---

## 2. Features

### Unified mail (Gmail · Outlook · iCloud)
- One inbox across all accounts, with an AI **split inbox**: Important · Actionable · Calendar · Updates · Newsletters · Promotions · Low priority.
- One-line AI summary on each email. Tasks and deadlines are extracted automatically.
- Swipe: done / turn into a task / snooze. One-tap AI reply drafts ("Yes, sounds good", "Need more time", or your own instruction).
- **Writes AI labels back** to Gmail and Outlook, so every other client (and Claude) sees the sorting.
- The inbox **hides itself during focus** ("Inbox is resting").

### Calendars + Apple Reminders (synced the way TickTick does it)
- Uses Apple's EventKit, so **every calendar on your iPhone** syncs: iCloud, Google, Outlook/Exchange, Yahoo, and subscribed .ics calendars.
- **Two-way Apple Reminders sync** across all lists. Whichever side changed most recently wins.
- Time-blocking: "Block time on my calendar" finds a free slot and creates the event in a dedicated **Keel** calendar.

### Tasks (TickTick-style)
- Lists, priorities, natural-language entry ("call mom tomorrow 5pm"), "Waiting on others", and an energy level for each task.
- **Time-blindness calibrator**: learns how long things *really* take you and pads estimates ("25 min → really ~40").

### Notes (Notion-style)
- Block editor: text, headings, to-dos, bullets, quotes, dividers. Slash commands (`/todo`, `/h`, `/quote`).
- Meeting notes generated from your next calendar event, with attendees. Daily journal template.
- AI summary, and to-dos inside a note can become real tasks.

### Habit stacking
- "After **[anchor]**, I will **A → B → C**." Anchors can be a time, **when a calendar event ends** ("after standup"), **after a focus session**, **after inbox zero**, arriving somewhere, or a custom cue.
- Grace-day streaks (◇ tokens), so one missed day doesn't erase your progress.

### Shutdown / focus (escalating)
1. **Soft**: hides the inbox, holds Keel alerts, distraction-free screen.
2. **Shield**: also blocks the apps and websites *you* choose (Screen Time / FamilyControls, all on-device).
3. **Locked**: same blocks, plus a 60-second "breathe" cool-down before you can quit early.
- An **iOS Focus Filter** lets your system "Work" Focus auto-enter Keel's Soft mode.
- **End-of-day Shutdown Ritual**: capture → inbox → move unfinished work to tomorrow → one win → "Work is closed. You're allowed to rest."

### Promise tracker (Tasks → ✋ Promises, or a card on Today when one is due)
- After each sync, Keel reads mail you **sent** (Gmail and Outlook; iCloud once IMAP lands). A free keyword pre-filter skips most messages, then Apple Intelligence (or Claude as a fallback) pulls out real commitments with the exact sentence and a deadline. Relative dates like "Friday" are resolved against the day you sent the email.
- Grouped **Overdue · Today · This week · Later**. A promise with no date is treated as due a week after you sent it.
- Swipe: **Kept** / **Make it a task** (also lands in Apple Reminders) / **Not a promise**.
- Tap any promise for a **one-tap follow-up**: "Here it is", "Need a bit more time", or "Quick update", drafted by AI and sent from the right account.
- **"Did you keep these?"**: if you later replied in the same thread with "attached" or "here's…", Keel asks you to confirm instead of closing it silently.
- One gentle notification at 9am on the due day. A **kept rate** stat (no shaming).
- Siri: "What did I promise in Keel?" Claude can read your promises through the `list_promises` connector tool.

### Apple Intelligence + Siri
- On-device **Foundation Models** (Apple Intelligence) handle triage, summaries, extraction and quick drafts. Free and private.
- **Writing Tools** work in every text field automatically.
- **App Intents / Siri / Shortcuts**: "Add a task in Keel", "Start focus in Keel", "What should I do now in Keel?", "What did I promise in Keel?"

### Works with Claude (and Claude Duet)
- The backend exposes a **remote MCP server**, the standard way Claude apps connect to outside tools. Claude can call `get_today`, `list_tasks`, `list_promises`, `search_notes`, `add_task` and `start_focus`.
- Add it in Claude: **Settings → Connectors → Add custom connector → `https://<your-worker>/mcp`**.
- **Claude Duet** (Anthropic's proactive agent, research preview since Oct 2026) has **no public API yet**, and it isn't confirmed whether it accepts custom connectors. Keel still works alongside it today: its sorting is written back to Gmail/Outlook labels, Apple Reminders and a Keel calendar, which Duet's own connectors can read. Once Duet supports custom connectors, the MCP server above is ready.
- Claude never starts app-blocking silently. A `start_focus` request from Claude becomes a suggestion you confirm on the phone.

---

## 3. Features no other app has (as far as I know)

1. **Just One Thing**: picks a single next action from your energy, the free time before your next meeting, deadlines and avoidance history.
2. **Wall of Awful detector**: when a task slips 3+ times, Keel stops nagging and offers to *shrink it*, *body-double it*, or *let it go*.
3. **Time-blindness calibrator**: a personal estimate multiplier learned from your real focus sessions.
4. **Calendar-anchored habit stacks**: habits fire when real events end ("after standup → stretch → water"), not at a guessed time.
5. **Promise tracker**: scans your **sent** mail for "I'll send it Friday" and keeps every commitment you made in one place (see Features above).
6. **Reset my day**: one tap, no guilt. Overdue tasks move to tomorrow, and chronic ones go to "Someday".
7. **Escalating shutdown with a cool-down**, plus a hyperfocus guard after the block ends.
8. **Energy-matched planning**: the AI planner puts your hardest work where your energy peaks and plans only ~70% of free time.
9. **Body-double mode**: a focus session where Keel checks in every 10 min (voice body-double with Claude is on the roadmap).
10. **AI labels written back to your real mailboxes**, so other apps and agents benefit too.

**More ideas for the roadmap:**
- *Dopamine menu*: a personal list of quick rewards to pick from after finishing something.
- *Context-switch cost meter*: shows how many app switches you made and how much time you lost.
- *"Waiting on" auto-follow-ups*: Keel drafts a polite nudge when someone hasn't replied in N days.
- *Live Activity + Dynamic Island* focus timer.
- *Lock-screen widget* showing your "one thing".
- *Apple Watch* haptic transition warnings.
- *Weekly review* that turns your notes, mail and completed tasks into a "what you actually did" summary (great for ADHD imposter feelings).
- *Doom-scroll interrupt*: a Shortcuts automation opens Keel's breathing screen when you open a shielded app.

---

## 4. What it costs

### Personal use (just you)
| Item | Cost |
|---|---|
| Apple Developer Program (needed to install on your phone long-term and to use Screen Time APIs) | **$99/year** |
| Apple Intelligence (on-device triage, summaries, extraction) | **$0** |
| Backend (Cloudflare Workers free tier: 100k requests/day) | **$0** |
| Claude API (day planning, long drafts, task breakdown; Opus 5.5 at $4/M input, $20/M output tokens) | **~$5–20/month** |
| Gmail/Outlook APIs | $0 |

How the Claude estimate works: 1 day plan (~20K tokens in, 2K out) ≈ $0.12/day, plus ~20 heavy requests/day (drafts, breakdowns) ≈ $0.60/day, which comes to **~$20/month** at heavy use. A built-in **daily cap** (`DAILY_AI_LIMIT`, default 200 requests) means a bug can never run up a big bill.
If every email went to the cloud instead of Apple Intelligence, it would cost ~$40/month more. That's why on-device AI does the high-volume work.
Cost lever (your choice): set the `triage`/`summarize` routes in `backend/src/ai.ts` to `claude-haiku-5-5` ($0.10/$0.50 per M tokens) for older iPhones without Apple Intelligence.

### Going to market
1. **Gmail security review (the big one).** A public app that reads Gmail needs Google's *restricted-scope verification* plus an annual **CASA security assessment** by a third-party lab, roughly **$500–$5,000+/year**, and it takes weeks. In "testing" mode you can have up to 100 users with no audit. Microsoft needs free publisher verification; iCloud has no review.
2. **Subscription (the "paywall").** Free app with a **Keel Pro** subscription through Apple. Already built (`PaywallView`, StoreKit 2) but **switched off** (`Entitlements.paywallEnabled = false`), so you get everything free. Market comparison: Superhuman $30/mo, Spark Premium ~$8/mo, TickTick $3/mo, Opal ~$8/mo. A reasonable launch price is **$9.99/mo or $79/yr**, with a free tier of 1 mail account and on-device AI only.
3. **Apple's cut:** 15% under the Small Business Program (under $1M/yr revenue), otherwise 30% (15% after a subscriber's first year).
4. **Unit economics:** with Apple Intelligence doing triage and per-user AI caps, cloud AI should cost ~$1–4 per Pro user per month. At $9.99, after Apple's 15%, you net about $8.49, leaving roughly $4.50–7.50 margin per user per month.
5. **Also needed:** privacy policy and data-deletion flow, App Store privacy "nutrition label", Screen Time API entitlement request to Apple (FamilyControls distribution), per-user accounts on the backend (Sign in with Apple), and APNs keys for instant mail push.

---

## 5. Architecture

```
iPhone (SwiftUI, iOS 26)                         Keel backend (Cloudflare Worker)
├─ SwiftData store (App Group)                   ├─ /v1/messages  AI proxy → Claude (key never on phone)
├─ EventKit: all calendars + Reminders ⇄          ├─ /mcp          Claude / Duet custom connector
├─ Gmail REST · Microsoft Graph · iCloud IMAP     ├─ /snapshot, /actions  phone ⇄ connector
├─ AIRouter ─┬─ Apple Intelligence (on-device)    └─ /push/*       Gmail Pub/Sub & Graph webhooks → APNs (TODO)
│            └─ Claude via backend (heavy work)
├─ FamilyControls / ManagedSettings (Shutdown)
└─ App Intents (Siri, Shortcuts, Focus Filter)
```

```
keel/
├─ project.yml                  XcodeGen spec (generates the Xcode project)
├─ open-in-xcode.sh             one command: generate + open in Xcode
├─ Keel/App                     app entry, design system, command bar + Siri intents
├─ Keel/Models                  SwiftData models
├─ Keel/Services/AI             AIRouter, OnDeviceAI (Apple Intelligence), CloudAI (Claude), ADHDCoach
├─ Keel/Services/Mail           Gmail, Outlook, iCloud providers + PromiseTracker
├─ Keel/Services/Auth           OAuth + PKCE, Keychain
├─ Keel/Services/Calendar       EventKit calendars + Reminders sync
├─ Keel/Services/Sync           SyncEngine (background refresh), ClaudeBridge
├─ Keel/Services/Focus          ShutdownManager, Focus Filter
├─ Keel/Services/Habits         HabitEngine
├─ Keel/Features/*              Today, Inbox, Tasks, Promises, Notes, Habits, Focus, Settings
└─ backend/                     Cloudflare Worker (TypeScript, official Anthropic SDK)
```

---

## 6. Setup

**You need:** a Mac with Xcode 26+, an iPhone 15 Pro or newer (for Apple Intelligence), and an Apple Developer account.

1. **Generate and open the Xcode project** (installs XcodeGen with Homebrew if needed). Pass your Team ID, found at developer.apple.com → Account → Membership details:
   ```bash
   cd keel && ./open-in-xcode.sh YOURTEAMID
   ```
   The `.xcodeproj` is generated from `project.yml`, so edit `project.yml` (not Xcode's project settings) and re-run the script after adding files. With your developer account, Screen Time app blocking works on your own iPhone during development. Shipping it on the App Store needs a separate FamilyControls distribution request to Apple.
2. **Google:** in Google Cloud Console, create a project, enable the Gmail API, and create an *iOS* OAuth client. Put the client ID in `OAuthManager.google` (two places) and add the reversed client ID URL scheme in `project.yml`.
3. **Microsoft:** in Azure Portal → App registrations, create a *public client* with redirect `msauth.com.keel.Keel://auth`. Put the client ID in `OAuthManager.microsoft`.
4. **iCloud Mail:** create an app-specific password at account.apple.com. ⚠️ The IMAP client isn't written yet (`ICloudMailProvider` is a stub). The next step is adding Apple's `swift-nio-imap` package.
5. **Backend:**
   ```bash
   cd backend && npm install
   ```
   ```bash
   npx wrangler kv namespace create KEEL
   ```
   Paste the id into `wrangler.toml`, then set the secrets:
   ```bash
   npx wrangler secret put ANTHROPIC_API_KEY
   ```
   ```bash
   npx wrangler secret put KEEL_DEVICE_TOKEN
   ```
   ```bash
   npx wrangler secret put KEEL_MCP_TOKEN
   ```
   ```bash
   npx wrangler deploy
   ```
   Put `https://<worker>/v1/messages` in `project.yml` → `KeelAIProxyURL`. The device token must also be saved to the iPhone Keychain under `keel.session`; a settings field for it is still to do.
6. **Claude connector:** in Claude, go to Settings → Connectors → Add custom connector and enter `https://<worker>/mcp`. Auth for the connector is still to do (see below).

## 7. Known gaps / next steps
- [ ] First Xcode compile pass (the code was written without a compiler).
- [ ] iCloud IMAP client (`swift-nio-imap`).
- [ ] APNs silent push from `/push/gmail` and `/push/graph`, plus subscribing Gmail `watch()` and Graph subscriptions.
- [ ] A settings field to enter the backend device token (stored in Keychain as `keel.session`).
- [ ] Connector auth: Claude custom connectors expect OAuth, but the MCP endpoint currently checks a static bearer token. Add OAuth (or authless + an unguessable URL path) before connecting it in Claude.
- [ ] Gmail label creation (`Keel/<category>` labels must be created before `applyLabel`).
- [ ] Live Activity / widgets / Watch.
- [ ] Per-user auth (Sign in with Apple) before anyone else uses the backend.
