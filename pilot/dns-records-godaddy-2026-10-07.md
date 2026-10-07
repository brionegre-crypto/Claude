# bethemansystem.com DNS records at GoDaddy (from Brian's screenshots, 2026-10-07)

This is the checklist for the move to Cloudflare. Every record marked **Keep** must exist in Cloudflare before the nameservers change. Every CNAME must be **DNS only** (grey cloud), never Proxied.

| Type | Name | Value | What it does | In Cloudflare |
|---|---|---|---|---|
| A | @ | 103.169.142.0 | Old Canva website | Replaced by the Pages custom domain |
| A | www | 103.169.142.0 | Old Canva website | Replaced by the Pages custom domain |
| CNAME | go | d1a9zyuneowget.cloudfront.net | systeme.io funnels (go.bethemansystem.com) | Keep, DNS only |
| CNAME | _9a2bd0d4529b2cddc9491f6b2427da88.go | _2c1e143e4230f0786735da92c757e12f.jkddzztszm.acm-validations.aws | systeme.io HTTPS certificate for go. | Keep, DNS only |
| CNAME | si18912984 | inbound.systeme.io | systeme.io email domain | Keep, DNS only |
| CNAME | systemeio1._domainkey | key1.systeme.io | systeme.io email signing (DKIM) | Keep, DNS only |
| CNAME | systemeio2._domainkey | key2.systeme.io | systeme.io email signing (DKIM) | Keep, DNS only |
| CNAME | sig1._domainkey | sig1.dkim.bethemansystem.com.at.icloudmailadmin.com | iCloud email signing (DKIM) | Keep, DNS only |
| MX | @ | mx01.mail.icloud.com (priority 10) | Email to brian@bethemansystem.com (iCloud) | Keep |
| MX | @ | mx02.mail.icloud.com (priority 10) | Email (iCloud) | Keep |
| TXT | @ | v=spf1 include:icloud.com ~all | Email sender check (SPF) | Keep |
| TXT | @ | apple-domain=E4TJZkrfQYLB0NYF | iCloud custom domain ownership | Keep |
| TXT | _dmarc | v=DMARC1; p=quarantine; adkim=r; aspf=r; rua=mailto:dmarc_rua@onsecureserver.net; | Email policy (DMARC) | Keep |
| TXT | @ | canva-domain-verify=83e50517... | Canva ownership check | Keep for now (harmless) |
| CNAME | _domainconnect | _domainconnect.gd.domaincontrol.com | GoDaddy helper | Not needed |
| NS / SOA | @ | ns55/ns56.domaincontrol.com | GoDaddy nameservers | Replaced by Cloudflare's two |

## Cloudflare zone (set up 2026-10-07)

- All 15 records were imported or added by hand and checked against the list above. All are DNS only.
- Cloudflare nameservers: nadia.ns.cloudflare.com and otto.ns.cloudflare.com. They replace ns55/ns56.domaincontrol.com at GoDaddy.
- Pages project: bethemansystem (bethemansystem.pages.dev). Production branch: claude/sharp-sagan-jrcxxn. Output directory: site.
- Next: once the zone is active, add custom domains bethemansystem.com and www in the Pages project. That replaces the two Canva A records.
- DONE 2026-10-07: the nameservers were switched at GoDaddy and the zone is active.
  - Custom domains bethemansystem.com and www.bethemansystem.com are Active with SSL. Both are CNAMEs to bethemansystem.pages.dev (Proxied).
  - The Canva A records were deleted. go.bethemansystem.com still resolves to systeme.io (CloudFront).
- Still to do: AI Crawl Control (allow AI crawlers), Google Search Console and sitemap, Bing import. Optionally unpublish the Canva site.
- DONE 2026-10-07:
  - AI Crawl Control: Bot Preference Sync is turned OFF, so our own robots.txt is served. No crawler is blocked.
  - Google Search Console: Domain property verified and sitemap submitted.
  - Bing Webmaster Tools: imported from Search Console.
