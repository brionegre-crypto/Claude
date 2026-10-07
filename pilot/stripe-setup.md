# Stripe setup: the store and couples counseling

Brian creates one **Payment Link** for each row below in his Stripe dashboard. Claude has already built the page each customer lands on after paying, with their downloads.

## One-time settings (do these first)

1. Stripe dashboard → **Settings** (gear icon) → **Business** → **Public details**: set the name to **Be The Man** and the support email to **brian@bethemansystem.com**.
2. **Settings** → **Customer emails**: turn on **Successful payments**, so customers get a receipt.
3. **Settings** → **Branding**: upload the logo (`brand/favicon-B.png`) and set the brand color to `#E18B1F`.
4. Your own profile → **Communication preferences**: make sure **Successful payments** emails are on. This is how you hear about couples bookings.

## For each row: create a Payment Link

1. Go to **Product catalog** → **Add product**. Enter the name and price, and choose **One-off**. Click **Save product**.
2. On the product page, click **Create payment link**.
3. Open the **After payment** tab, choose **Don't show confirmation page**, then **Redirect customers to your website**. Paste the redirect URL from the table.
4. Click **Create link** and copy the link. It starts with `https://buy.stripe.com/`.
5. Send all the links to Claude, labelled with the row number. Claude swaps them into the website.

| # | Product | Price | Redirect after payment |
|---|---|---|---|
| 1 | The Weekly Scorecard | $7 | `https://bethemansystem.com/get/scorecard-lnxtejvx/` |
| 2 | The Godly Husband Field Guide | $19 | `https://bethemansystem.com/get/husband-guide-coaukruz/` |
| 3 | The Christian Marriage Workbook for Men | $19 | `https://bethemansystem.com/get/marriage-workbook-ojd7cel2/` |
| 4 | The Husband's Devotional: 30 Mornings | $9 | `https://bethemansystem.com/get/devotional-uwfdnzsj/` |
| 5 | The Father's Field Guide | $19 | `https://bethemansystem.com/get/father-guide-jnrvfbvb/` |
| 6 | Father and Son Conversation Cards | $9 | `https://bethemansystem.com/get/father-son-cards-f2gken5w/` |
| 7 | The Men's Bible Study: Eight Weeks | $19 | `https://bethemansystem.com/get/bible-study-edzfbhfw/` |
| 8 | The Men's Discipleship Workbook | $19 | `https://bethemansystem.com/get/discipleship-workbook-3mxy3iuy/` |
| 9 | The Prayer Strategy for Men | $9 | `https://bethemansystem.com/get/prayer-strategy-fyrdnigm/` |
| 10 | Forty Cards for Men | $9 | `https://bethemansystem.com/get/forty-cards-geqjmizi/` |
| 11 | The Husband Kit | $39 | `https://bethemansystem.com/get/husband-kit-soj4aqgs/` |
| 12 | The Father Kit | $29 | `https://bethemansystem.com/get/father-kit-1klcffxh/` |
| 13 | The Faith Kit | $29 | `https://bethemansystem.com/get/faith-kit-dz9xsaqw/` |
| 14 | The Complete Be The Man Library | $97 | `https://bethemansystem.com/get/library-zjcdznwk/` |
| 15 | Couples counseling: three sessions | $300 | `https://bethemansystem.com/get/couples-m7pwwkaj/` |

For row 15 (couples), also turn on **Collect customers' names** and **Collect phone numbers**.

## What stays on systeme.io for now

- The workshop (Oct 25), the 6-week group, the Inner Circle and the men's ministry kit.
- The Club ($19 a month / $149 a year). Its member area and monthly unlocks move last.

## How the switch works

`web/products.json` holds every offer. Once a row's `stripe_link` is filled in, `python3 web/build.py` replaces that offer's systeme.io checkout link everywhere on the site. If anything goes wrong, emptying the link switches that button back to systeme.io.

## If Claude does it through the Stripe connector

Once the Stripe connector is connected, a new Claude session can do all of this:

1. Read `web/products.json`. For each offer, create a Product, then a one-time USD Price (`price` × 100 cents). Then create a Payment Link with `after_completion.type = redirect` and `after_completion.redirect.url = https://bethemansystem.com/get/<slug>/`.
   - For `couples`, also collect the customer's name and phone number.
2. Write each Payment Link URL into that offer's `stripe_link`. Run `python3 web/build.py`, then commit and push to `claude/sharp-sagan-jrcxxn`. Cloudflare publishes it.
3. Ask Brian to buy the $7 Scorecard once as a test, then refund it.
4. Don't create anything for the workshop, the 6-week group, the Inner Circle, the ministry kit or the Club yet.

## Status 2026-10-07: links created, publishing waits on Brian

- Created in live Stripe, through the connector: 15 products, each with a one-time USD price and a Payment Link that redirects to its `/get/<slug>/` page. The couples link collects name, phone, partner's name and partner's email.
- PUBLISHED 2026-10-07 after Brian said yes. The links are live in `web/products.json`; `web/stripe-links-pending.json` is a backup copy.
- To publish once Brian says yes: copy the links into `web/products.json` (`stripe_link`), run `python3 web/build.py`, then commit and push.
