# Google discoverability: settings to paste

Neither the Canva tools nor the systeme.io tools can change SEO settings, so Brian sets these by hand.
Titles stay under 60 characters and descriptions under 160 characters.

## Canva site (bethemansystem.com)

Where: Canva editor → Publish → Review settings (the same screen where the favicon is set).

1. Search engine visibility: make sure the site is NOT hidden from search engines.
2. Fill in the title and description for each page:

| Page | URL | SEO title | SEO description |
|---|---|---|---|
| Home | / | Be The Man: A Consistency System for Christian Men | Seven steps that help Christian men do what they said, every week. One sentence on who you are becoming, goals with dates, and a weekly scorecard. Step 1 is free. |
| Club | /the-club | The Be The Man Club: Accountability for Christian Men | A monthly membership for Christian men who want to keep their word. A lesson library, a monthly live call, and accountability pairs. $19 a month or $149 a year. |
| Store | /products | Be The Man Store: Worksheets, Kits and the Library | Printable worksheets, kits and the complete Be The Man library for Christian men who want a system that holds, not another fresh start. |
| About | /about | About Brian Greene: Pastor, Husband, Father of Three | Brian Greene is a pastor, a certified marriage counselor and the father of three. He built Be The Man to help Christian men keep their word when nobody is watching. |
| Couples | /couples | Christian Couples Coaching and Marriage Counseling | Certified marriage counseling for Christian couples, built on a validated relationship assessment. Find where you are strong and what to work on next. |

3. Preview image: use the homepage hero or Brian's photo, so links shared on Facebook and in texts show a picture.

## Google Search Console (one time, about 15 minutes)

1. Go to search.google.com/search-console and sign in with the Google account Brian wants to own the site.
2. Choose Add property → **Domain** → type `bethemansystem.com`. This one property also covers go.bethemansystem.com (systeme.io).
3. Google gives you a TXT record. Add it in the DNS settings wherever the domain was bought (Canva Domains, GoDaddy, Namecheap, etc.), then click Verify. It can take up to a few hours to go through.
4. Sitemaps → submit `https://bethemansystem.com/sitemap.xml` (Canva makes this file automatically).
5. URL Inspection → paste `https://bethemansystem.com/` → Request indexing. Do the same for `/about`, `/the-club`, `/couples` and `https://go.bethemansystem.com/framework`.

## systeme.io pages

Where: Funnels → open the funnel → the step → Settings (gear) → SEO / meta. There are page title, description and social image fields.

- Step 1 sign-up page (go.bethemansystem.com/framework)
  - Title: Free Step 1 Worksheet for Christian Men | Be The Man
  - Description: A free one-page worksheet that names the man you are building. 20 minutes, a pen, and one sentence every later step answers to.
- Thank-you, checkout, member and upsell pages: there's no reason for Google to show these. If a "block search engines" or noindex option exists, turn it on for them.

## After that

- Keep linking to bethemansystem.com from YouTube, Substack, Facebook and Instagram bios. Links from those profiles help Google find and trust the site.
- Check Search Console in 1 to 2 weeks: Pages report (are pages indexed?) and Performance (what people search to find you).
