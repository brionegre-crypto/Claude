#!/usr/bin/env python3
"""Builds the static site into ../site from pages/, partials/ and static/.

Each file in pages/ starts with a JSON block between two lines of '---',
followed by the page body HTML. Run:  python3 web/build.py
Cloudflare Pages serves the ../site folder as is (no build step there).
"""
import json, shutil, html, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT.parent / "site"
BASE = "https://bethemansystem.com"

ORG = {
    "@type": "Organization",
    "@id": BASE + "/#org",
    "name": "Be The Man",
    "alternateName": "The Be The Man System",
    "url": BASE + "/",
    "logo": BASE + "/assets/favicon.png",
    "slogan": "Faith should function.",
    "description": "A seven-step consistency system for Christian men: one sentence on who you are becoming, goals with dates, and a weekly scorecard.",
    "founder": {"@id": BASE + "/about/#brian"},
    "sameAs": [
        "https://www.youtube.com/@BeTheManSystem",
        "https://bethemansystem.substack.com",
        "https://www.facebook.com/profile.php?id=61593655779820",
    ],
}
PERSON = {
    "@type": "Person",
    "@id": BASE + "/about/#brian",
    "name": "Brian Greene",
    "jobTitle": "Pastor and certified marriage counselor",
    "description": "Founder of Be The Man. Husband of eleven years, father of three, pastor of ten years and certified marriage counselor.",
    "image": BASE + "/assets/brian.jpg",
    "url": BASE + "/about/",
    "worksFor": {"@id": BASE + "/#org"},
    "sameAs": ["https://www.youtube.com/@BeTheManSystem", "https://bethemansystem.substack.com"],
}

NAV = [("home", "/", "Home"), ("club", "/the-club/", "The Club"), ("store", "/products/", "The Store"),
       ("couples", "/couples/", "Couples"), ("about", "/about/", "About")]


def read_page(path):
    text = path.read_text()
    _, meta, body = text.split("---\n", 2)
    return json.loads(meta), body


def header(current):
    cur = ' aria-current="page"'
    links = "\n".join(
        f'      <a href="{href}"{cur if key == current else ""}>{label}</a>'
        for key, href, label in NAV)
    drawer = "\n".join(f'      <a href="{href}">{label}</a>' for _, href, label in NAV)
    return (ROOT / "partials" / "header.html").read_text().replace("{{links}}", links).replace("{{drawer}}", drawer)


def render(meta, body):
    path = meta["path"]
    url = BASE + path
    title = meta["title"]
    desc = meta["description"]
    graph = [ORG]
    if meta.get("person"):
        graph.append(PERSON)
    graph.append({
        "@type": "WebPage", "@id": url + "#page", "url": url, "name": title,
        "description": desc, "isPartOf": {"@id": BASE + "/#site"}, "about": {"@id": BASE + "/#org"},
        "inLanguage": "en-US",
    })
    if path == "/":
        graph.append({"@type": "WebSite", "@id": BASE + "/#site", "url": BASE + "/", "name": "Be The Man",
                      "publisher": {"@id": BASE + "/#org"}, "inLanguage": "en-US"})
    if path != "/":
        crumbs = [{"@type": "ListItem", "position": 1, "name": "Home", "item": BASE + "/"},
                  {"@type": "ListItem", "position": 2, "name": meta.get("crumb", title), "item": url}]
        graph.append({"@type": "BreadcrumbList", "itemListElement": crumbs})
    graph.extend(meta.get("schema", []))
    if meta.get("faq"):
        graph.append({"@type": "FAQPage", "mainEntity": [
            {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}}
            for q, a in meta["faq"]]})
        faq_html = "\n".join(
            f"        <details><summary>{html.escape(q)}</summary><p>{html.escape(a)}</p></details>"
            for q, a in meta["faq"])
        body = body.replace("{{faq}}", f'<div class="faq">\n{faq_html}\n      </div>')
    ld = json.dumps({"@context": "https://schema.org", "@graph": graph}, ensure_ascii=False, indent=1)
    robots = "noindex, follow" if meta.get("noindex") else "index, follow, max-image-preview:large"
    og_image = BASE + meta.get("og_image", "/assets/og.png")
    head = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(desc)}">
<meta name="robots" content="{robots}">
<link rel="canonical" href="{url}">
<link rel="icon" type="image/png" href="/assets/favicon.png">
<link rel="apple-touch-icon" href="/assets/favicon.png">
<meta name="theme-color" content="#000000">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Be The Man">
<meta property="og:title" content="{html.escape(meta.get('og_title', title))}">
<meta property="og:description" content="{html.escape(desc)}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{og_image}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&family=Geist+Mono:wght@500&family=Caveat:wght@500&display=swap">
<link rel="stylesheet" href="/assets/site.css">
<script type="application/ld+json">
{ld}
</script>
</head>
<body>
"""
    chrome = not meta.get("bare")
    top = header(meta.get("nav", "")) if chrome else ""
    foot = (ROOT / "partials" / "footer.html").read_text() if chrome else ""
    return head + top + "\n<main id=\"main\">\n" + body.strip() + "\n</main>\n" + foot + \
        '<script src="/assets/site.js" defer></script>\n</body>\n</html>\n'


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(ROOT / "static", OUT)
    urls = []
    for page in sorted((ROOT / "pages").glob("*.html")):
        meta, body = read_page(page)
        rel = "404.html" if meta["path"] == "/404" else (meta["path"].strip("/") + "/index.html").lstrip("/")
        out = OUT / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(render(meta, body))
        if not meta.get("noindex"):
            urls.append((meta["path"], meta.get("priority", "0.8")))
    today = datetime.date.today().isoformat()
    sm = ['<?xml version="1.0" encoding="UTF-8"?>',
          '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    for path, pr in sorted(urls, key=lambda u: (u[0] != "/", u[0])):
        sm.append(f"  <url><loc>{BASE}{path}</loc><lastmod>{today}</lastmod><priority>{pr}</priority></url>")
    sm.append("</urlset>")
    (OUT / "sitemap.xml").write_text("\n".join(sm) + "\n")
    print(f"Built {len(urls)} indexable pages into {OUT}")


if __name__ == "__main__":
    main()
