# Discovery plan: Google, AI assistants and YouTube

One set of words, used everywhere. Google, ChatGPT, Perplexity, Claude and YouTube connect a brand to a topic when the same phrases show up on the website, in video titles, in descriptions and in what you say out loud. Keep every channel saying the same things.

## The core phrases (use these word for word, often)

| Priority | Phrase | Where it lives on the site |
|---|---|---|
| 1 | consistency system for Christian men | Home title, llms.txt |
| 1 | accountability for Christian men | Club title |
| 1 | how to be a godly man / godly husband | Store (Godly Husband Field Guide), YouTube |
| 2 | Christian discipline for men | Home FAQ, YouTube |
| 2 | weekly scorecard / habit tracker for Christian men | Home product shot, Store |
| 2 | Christian marriage workbook for men | Store |
| 2 | devotional for husbands | Store |
| 2 | Christian fatherhood / father and son questions | Store |
| 2 | men's Bible study, men's discipleship workbook | Store |
| 2 | Christian premarital counseling / marriage counseling for couples | Couples title |
| 3 | how to keep your word, follow through, stop starting over | Home hero, YouTube |
| 3 | accountability partner for Christian men | Club |

Rules: say "certified marriage counseling" and "validated relationship assessment". Never name the assessment brand, and never imply a church connection. Use "built on" or "linked to", never "proven".

## What's already built into the site

- **Page titles and descriptions** use the phrases above, one main phrase per page.
- **Structured data (schema.org)** on every page tells Google and AI tools what each thing is: Organization, Brian as a Person, the Club and all 11 store items as Products with prices, couples counseling as a Service, and an FAQ on every page. FAQs are the format AI answers quote most often.
- **llms.txt** (bethemansystem.com/llms.txt) is a plain-language summary written for AI assistants: what Be The Man is, the 7 steps, every offer with prices, and who Brian is.
- **robots.txt** openly allows Google, Bing and the AI crawlers (ChatGPT, Claude, Perplexity, Gemini, Apple).
- **sitemap.xml** lists every page for search engines.
- **A share image** so links on Facebook, iMessage and X show a branded card.
- **Links to YouTube, Substack and Facebook**, marked as the same owner, so Google ties the channel to the site.

## YouTube: make the channel findable

### Channel setup (one time)
- **Name:** Be The Man. **Handle:** @BeTheManSystem (keep it).
- **Channel description.** The first two lines matter most:

  > Be The Man is a seven-step consistency system for Christian men. Learn how to keep your word at home, lead your family and build discipline with a weekly scorecard instead of starting over every Monday.
  >
  > I'm Brian Greene: a pastor, a certified marriage counselor and a father of three. New videos every week on Christian discipline, being a godly husband, Christian fatherhood and accountability for men.
  >
  > Get Step 1 free: bethemansystem.com/free

- **Channel links:** Step 1 free → bethemansystem.com/free, then Website → bethemansystem.com.
- **Channel keywords** (Settings → Channel → Basic info): Christian men, Christian discipline, godly man, godly husband, Christian fatherhood, accountability for men, men's Bible study, biblical manhood, Christian habits, Christian marriage
- **Playlists named after searches**, so each one ranks on its own:
  - Christian Discipline for Men
  - How to Be a Godly Husband
  - Christian Fatherhood
  - Accountability for Christian Men
  - Men's Bible Study

### Every video
1. **Title = what a man would type**, then the specific hook. Under 60 characters.
   - How to Keep Your Word as a Christian Man
   - Why Christian Men Keep Starting Over (and the Fix)
   - How to Be a Godly Husband This Week, Not Someday
   - The Weekly Scorecard: A Habit Tracker for Christian Men
   - How to Lead Family Devotions When You've Never Done It
   - 52 Questions Every Father Should Ask His Son
   - How to Find an Accountability Partner as a Christian Man
   - What Premarital Counseling Actually Covers
2. **Say the main phrase out loud in the first 30 seconds.** YouTube and AI tools read the transcript.
3. **Upload or check captions** (YouTube Studio → Subtitles). Fix any names it got wrong.
4. **Description template:**

   ```
   [One sentence that repeats the title phrase naturally.]
   Get Step 1 free: bethemansystem.com/free

   In this video:
   0:00 [Chapter]
   1:15 [Chapter]
   ...

   The Be The Man System is seven steps that help Christian men do what they said, every week.
   The Club: bethemansystem.com/club
   The Store: bethemansystem.com/store
   Couples counseling: bethemansystem.com/couples

   #ChristianMen #GodlyMan #BeTheMan
   ```

5. **Chapters** (timestamps starting at 0:00). Google often shows these right in search results.
6. **Pinned comment:** "Step 1 is free: bethemansystem.com/free. What's the one thing you keep starting over?"
7. **Thumbnail:** 3 to 5 words, high contrast, black and orange to match the site.
8. **End screen:** the matching playlist plus your best video.

### Connecting YouTube back to the site
Send Claude the links to your best 3 to 6 videos. They'll be added to the matching pages with video schema, so Google can show them under your site and the site gets credit for the views.

## Other wins (outside the site)
- **Google Business Profile:** if you see couples in person, a free profile under your city helps "Christian marriage counseling near me" searches. Only do this if you actually offer in-person sessions.
- **Bing Webmaster Tools:** import from Search Console (covered in pilot/cloudflare-setup.md). Bing powers ChatGPT search.
- **Substack:** every post links to bethemansystem.com/free and uses one core phrase in its title.
- **Real stories:** once members give written permission, add them. AI answers and Google both favor real proof.
