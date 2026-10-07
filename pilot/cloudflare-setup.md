# Putting the coded site live on Cloudflare (free)

The site is the `site/` folder in this repo. Cloudflare Pages serves it as is, with no build step. Brian does these steps because they need his Cloudflare account and his domain login. It takes about 15 minutes of clicking, then waiting for the domain to switch over (usually under an hour, sometimes up to a day).

Nothing on systeme.io changes. go.bethemansystem.com keeps working exactly as it does now, as long as step 3 is followed carefully.

## 1. Create the free Cloudflare account and the site

1. Go to dash.cloudflare.com and sign up (free). Use brian@bethemansystem.com.
2. In the left menu open **Workers & Pages**, then **Create**.
3. Choose the **Pages** tab, then **Connect to Git**.
4. Connect GitHub and pick the repository **brionegre-crypto/Claude**.
5. Use these settings:
   - Production branch: `claude/sharp-sagan-jrcxxn` for now. After it's merged, switch it to `main`.
   - Framework preset: **None**
   - Build command: leave empty
   - Build output directory: `site`
6. Click **Save and Deploy**.
7. Cloudflare gives you a free test address ending in `.pages.dev`. Open it on your phone and click around.

From now on, every change pushed to that branch goes live by itself within about a minute.

## 2. Check the test address before touching the domain

- Every menu link works: Home, The Club, The Store, Couples, About.
- The buttons open your systeme.io pages (Step 1, Join the Club, checkout pages, couples inquiry).
- `/step-1/` shows the sign-up page with your links.

## 3. Move bethemansystem.com to Cloudflare. Read all of this first.

Your domain's DNS settings currently do three jobs. **All three must survive the move:**

| Job | Record type | Example name | Must stay exactly as it is |
|---|---|---|---|
| Email to brian@bethemansystem.com | MX, plus TXT (SPF, DKIM, DMARC) | `@`, `_dmarc`, something like `google._domainkey` | Yes |
| systeme.io funnels | CNAME | `go` | Yes. Set it to **DNS only** (grey cloud), not Proxied |
| Canva website | A or CNAME | `@`, `www` | No. These get replaced in step 4 |

1. In Cloudflare, click **Add a domain**, type `bethemansystem.com` and choose the **Free** plan.
2. Cloudflare copies your current DNS records. **Compare its list with the records at your domain company before going on.** Every MX, TXT and the `go` CNAME must be there. If anything is missing, add it by hand.
3. Cloudflare shows two nameservers (for example `ada.ns.cloudflare.com`). Log in where you bought the domain (GoDaddy, Namecheap, Google/Squarespace or Canva) and replace the nameservers with Cloudflare's two.
   - If the domain was bought through Canva, tell Claude first. Canva-bought domains have extra steps.
4. Wait for Cloudflare's email saying the domain is active.

## 4. Point the domain at the new site

1. In Cloudflare open **Workers & Pages**, then your project, then **Custom domains**.
2. Add `bethemansystem.com`, then add `www.bethemansystem.com`. Cloudflare creates the records and the security certificate for you.
3. If Cloudflare warns that an old Canva A or CNAME record is in the way, delete that old record and try again.
4. In Canva, unpublish the old site, or disconnect the domain from it, so the two don't compete.

## 5. Tell Google and Bing

1. **Google Search Console** (search.google.com/search-console):
   - Add a **Domain** property for `bethemansystem.com`. Cloudflare can add the verification record for you in one click.
   - Then go to Sitemaps and submit `https://bethemansystem.com/sitemap.xml`.
   - Use URL Inspection, then Request indexing for the home page, `/step-1/`, `/the-club/`, `/products/`, `/couples/` and `/about/`.
2. **Bing Webmaster Tools** (bing.com/webmasters): choose **Import from Google Search Console**. Bing's index feeds ChatGPT search and Microsoft Copilot, so this matters for AI discovery.

## Short links that work once the domain is live

| Link | Goes to |
|---|---|
| bethemansystem.com/free (also /start and /links) | Step 1 sign-up page (use this in bios) |
| bethemansystem.com/framework | systeme.io Step 1 opt-in |
| bethemansystem.com/join | Club checkout |
| bethemansystem.com/club | The Club page |
| bethemansystem.com/store | The Store page |
| bethemansystem.com/workshop | Workshop page |
| bethemansystem.com/inner-circle | Inner Circle application |
| bethemansystem.com/youtube | YouTube channel |

## Editing the site later

- Page wording lives in `web/pages/`. Shared styles are in `web/static/assets/site.css`.
- After editing, run `python3 web/build.py` and push. Cloudflare publishes it.
- After Oct 25, swap the workshop pill at the top of `web/pages/01-home.html` for the Inner Circle.
