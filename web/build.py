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
    if meta.get("members"):
        top, foot = MEMBERS_TOP, MEMBERS_FOOT
    return head + top + "\n<main id=\"main\">\n" + body.strip() + "\n</main>\n" + foot + \
        '<script src="/assets/site.js" defer></script>\n</body>\n</html>\n'


def all_file_labels(products):
    club, _ = club_data()
    return {**{k: v["label"] for k, v in products["files"].items()},
            **{k: v["label"] for k, v in club["step_files"].items()}}


def guide_pages(o):
    """Leader guide for the ministry kit, at /get/<slug>/guide/. Access is checked by functions/get/_middleware.js."""
    lessons = json.loads((ROOT / "club" / "more-lessons.json").read_text())["kit"]
    base = f"/get/{o['slug']}/guide/"
    pages = []
    cards = "\n".join(f'<a class="kit" href="{base}{l["slug"]}/"><div class="stack" style="gap:2px"><b>{html.escape(l["title"])}</b></div><span class="p">›</span></a>' for l in lessons)
    pages.append(({"path": base, "noindex": True, "bare": False, "nav": "store", "title": "Leader guide | Be The Man men's ministry kit", "description": "Leader guide"},
                  f"""<div class="wrap hero narrow"><p class="eyebrow"><a href="/get/{o['slug']}/">Your ministry kit</a></p>
<h1 style="font-size:clamp(36px,5.5vw,60px)">Lead your men through <span class="grad">seven steps.</span></h1>
<p class="lead">Start with the setup lesson. Each session has a timed plan, what to say, discussion questions and the worksheet to hand out.</p>
<div class="kit-list" style="margin-top:28px">{cards}</div></div><div style="height:80px"></div>"""))
    for i, l in enumerate(lessons):
        prev_l = lessons[i - 1] if i else None
        next_l = lessons[i + 1] if i + 1 < len(lessons) else None
        nav = '<div class="actions" style="justify-content:space-between;margin-top:40px">' + \
            (f'<a class="textlink" href="{base}{prev_l["slug"]}/">‹ {html.escape(prev_l["title"])}</a>' if prev_l else f'<a class="textlink" href="{base}">‹ All sessions</a>') + \
            (f'<a class="textlink" href="{base}{next_l["slug"]}/">{html.escape(next_l["title"])} ›</a>' if next_l else "") + "</div>"
        pages.append(({"path": f"{base}{l['slug']}/", "noindex": True, "nav": "store", "title": f"{l['title']} | Leader guide", "description": l["title"]},
                      f"""<div class="wrap hero narrow"><p class="eyebrow"><a href="{base}">Leader guide</a></p>
<h1 style="font-size:clamp(34px,5vw,54px)">{html.escape(l['title'])}</h1>
<article class="lesson-body">{l['html']}</article>{nav}</div><div style="height:60px"></div>"""))
    return pages


def delivery_pages(products):
    """Thank-you and download pages Stripe redirects to after payment."""
    pages = []
    for o in products["offers"]:
        meta = {"path": f"/get/{o['slug']}/", "noindex": True, "nav": "store",
                "title": f"Thank you: {o['name']} | Be The Man",
                "description": f"Your download for {o['name']}."}
        if o["key"] == "couples":
            body = f"""<div class="wrap hero narrow">
  <p class="eyebrow">Payment received</p>
  <h1 style="font-size:clamp(40px,6vw,64px)">Thank you. <span class="grad">You're booked in.</span></h1>
  <p class="lead">Brian will email you both within 24 hours with your relationship assessment link and your first session date. Check your spam folder if you don't see it.</p>
  <div class="tile stack" style="margin-top:32px">
    <h3>What happens next</h3>
    <ul class="check">
      <li>Each of you takes the validated relationship assessment online, separately, on your own time. The $35 assessment fee is paid directly to the assessment provider.</li>
      <li>Then you meet for three sessions to go through your results together and choose what to work on.</li>
      <li>Questions before then? Reply to your receipt email and it reaches Brian.</li>
    </ul>
  </div>
</div>
<div style="height:clamp(80px,12vw,140px)"></div>"""
        else:
            labels = all_file_labels(products)
            def dl(f, cls="dl"):
                return (f'      <a class="kit {cls}" href="/api/download?o={o["key"]}&amp;f={f}" rel="nofollow"><div class="stack" style="gap:2px">'
                        f'<b>{html.escape(labels[f])}</b><span>Download</span></div><span class="p">↓</span></a>')
            links = "\n".join(dl(f) for f in o["files"])
            addons = "".join(
                f'<div class="addon" data-price="{a["price"]}" hidden><p class="label" style="margin-top:28px">{html.escape(a["label"])} (your add-on)</p>'
                f'<div class="kit-list" style="margin-top:12px">' + "\n".join(dl(f) for f in a["files"]) + "</div></div>"
                for a in o.get("addons", []))
            headline = html.escape(o.get("headline") or "")
            h1 = (f'<h1 style="font-size:clamp(36px,5.5vw,60px)">{headline}</h1>' if headline else
                  f'<h1 style="font-size:clamp(40px,6vw,64px)">Thank you. <span class="grad">Here\'s {html.escape(o["name"])}.</span></h1>')
            body = f"""<div class="wrap hero narrow">
  <p class="eyebrow">Payment received</p>
  {h1}
  <p class="lead">Download your files below. Bookmark this page so you can come back to it. A receipt is on its way to your email.</p>
  <p class="muted" id="emailed" hidden></p>
  {o.get("extra_html", "")}
  <div class="kit-list" style="margin-top:32px">
{links}
  </div>
  {addons}
  <div class="tile stack" style="margin-top:24px">
    <p class="label">How to start</p>
    <p style="color:var(--fg)">{html.escape(o['start'])}</p>
  </div>
  {o.get("after_html", "")}
  <div class="tile hi stack" style="margin-top:16px">
    <p class="label">Keep going</p>
    <h3>Get every tool, plus the monthly call.</h3>
    <p>The Be The Man Club is $19 a month: all seven steps, a new set of tools every month, a Club-only tool, and a live call on the second Tuesday.</p>
    <div class="actions"><a class="btn btn-primary" href="/the-club/">See the Club</a></div>
  </div>
  <p class="fine" style="margin-top:20px">Trouble downloading? Email <a class="textlink" href="mailto:brian@bethemansystem.com">brian@bethemansystem.com</a> and you'll get your files the same day.</p>
</div>
<script>
(function(){{
  var q=new URLSearchParams(location.search), s=q.get('session_id');
  if(q.get('guide')==='locked'){{var g=document.getElementById('emailed');g.textContent='To open the leader guide, use the link in your "Your download" email (or the page you reached right after checkout).';g.hidden=false;}}
  if(!s) return;
  document.querySelectorAll('a.dl').forEach(function(a){{a.href+='&s='+encodeURIComponent(s);}});
  if(!window.fetch) return;
  fetch('/api/purchase',{{method:'POST',headers:{{'content-type':'application/json'}},body:JSON.stringify({{o:'{o["key"]}',s:s}})}})
    .then(function(r){{return r.json();}}).then(function(d){{
      if(d.emailed){{var n=document.getElementById('emailed');n.textContent='We also emailed you a link to this page.';n.hidden=false;}}
      (d.addons||[]).forEach(function(p){{document.querySelectorAll('.addon[data-price="'+p+'"]').forEach(function(el){{el.hidden=false;}});}});
    }}).catch(function(){{}});
}})();
</script>
<div style="height:clamp(80px,12vw,140px)"></div>"""
            if o.get("guide"):
                pages.extend(guide_pages(o))
        pages.append((meta, body))
    return pages


MEMBERS_TOP = """<a class="skip" href="#main">Skip to content</a>
<header class="nav">
  <div class="wrap nav-in">
    <a class="logo" href="/members/" aria-label="Members home">BE <span>THE MAN</span> <small class="muted" style="font-weight:500">Club</small></a>
    <nav class="links" aria-label="Members" style="display:flex">
      <a href="/members/">Members home</a>
      <a href="/api/club/logout">Sign out</a>
    </nav>
  </div>
</header>"""
MEMBERS_FOOT = """<footer>
  <div class="wrap">
    <div class="foot-base">
      <p>© 2026 Be The Man · Questions? Reply to any Club email, or write to brian@bethemansystem.com.</p>
      <a class="manage" href="{portal}">Manage membership ›</a>
    </div>
  </div>
</footer>"""


def club_data():
    club = json.loads((ROOT / "club" / "lessons.json").read_text())
    cfg = json.loads((ROOT / "club" / "config.json").read_text())
    return club, cfg


def member_pages(products):
    """The members area (/members/...). Access is enforced by functions/members/_middleware.js."""
    global MEMBERS_FOOT
    club, cfg = club_data()
    MEMBERS_FOOT = MEMBERS_FOOT.replace("{portal}", cfg["portal"])
    labels = {**{k: v["label"] for k, v in products["files"].items()},
              **{k: v["label"] for k, v in club["step_files"].items()}}
    ic_lessons = [{**l, "module": "The Inner Circle", "month": 1, "ic": True}
                  for l in json.loads((ROOT / "club" / "more-lessons.json").read_text())["ic"]]
    lessons = club["lessons"] + ic_lessons
    pages = []
    modules = []
    for l in lessons:
        if not modules or modules[-1][0] != l["module"]:
            modules.append((l["module"], []))
        modules[-1][1].append(l)
    # Members home
    secs = []
    for name, ls in modules:
        cards = "\n".join(
            f'      <a class="kit lesson" href="/members/{l["slug"]}/" data-month="{l["month"]}">'
            f'<div class="stack" style="gap:2px"><b>{html.escape(l["title"])}</b>'
            f'<span class="when">{"Open" if l["month"] == 1 else "Month " + str(l["month"])}</span></div><span class="p">›</span></a>'
            for l in ls)
        ic_attr = ' data-ic hidden' if name == "The Inner Circle" else ""
        secs.append(f'<section class="section tight"{ic_attr}><div class="wrap narrow"><h2 class="mod">{html.escape(name)}</h2>'
                    f'<div class="kit-list">\n{cards}\n    </div></div></section>')
    home = f"""<div class="wrap hero narrow">
  <p class="eyebrow">The Be The Man Club</p>
  <h1 style="font-size:clamp(40px,6vw,64px)">Welcome <span class="grad">back.</span></h1>
  <p class="lead" id="who">Start with "Welcome to the club", then one step a week. Your monthly tools open every 30 days.</p>
  <p class="signup-msg" id="locked" hidden>That one isn't open yet. It opens on the date shown below.</p>
</div>
{"".join(secs)}
<section class="section tight"><div class="wrap narrow">
  <div class="tile hi stack">
    <p class="label">Monthly call</p>
    <h3>Second Tuesday, 7:00 to 8:00 PM Central.</h3>
    <p>Google Meet, same link every month. Details and your accountability partner are in <a class="textlink" href="/members/call/">the call lesson</a>.</p>
  </div>
</div></section>
<div style="height:60px"></div>
<script>
(function(){{
  var q=new URLSearchParams(location.search); if(q.get('locked')) document.getElementById('locked').hidden=false;
  fetch('/api/club/me',{{credentials:'same-origin'}}).then(function(r){{return r.json();}}).then(function(d){{
    if(!d.member) return;
    var fmt=function(t){{return new Date(t*1000).toLocaleDateString(undefined,{{month:'long',day:'numeric'}});}};
    document.querySelectorAll('a.lesson').forEach(function(a){{
      var m=+a.dataset.month; if(m<2) return; var info=d.months[m], w=a.querySelector('.when');
      if(info.open){{w.textContent='Open';}} else {{w.textContent='Opens '+fmt(info.opens);a.classList.add('locked');a.removeAttribute('href');}}
    }});
    var p=document.querySelector('a.manage'); if(p&&d.email) p.href=d.portal+'?prefilled_email='+encodeURIComponent(d.email);
    if(d.ic) document.querySelectorAll('[data-ic]').forEach(function(el){{el.hidden=false;}});
  }}).catch(function(){{}});
}})();
</script>
<style>.mod{{font-size:clamp(24px,3vw,32px);font-weight:700;margin-bottom:14px}}.kit.locked{{opacity:.5;cursor:default}}.kit .when{{color:var(--muted);font-size:14px}}</style>"""
    pages.append(({"path": "/members/", "noindex": True, "members": True, "title": "Members | The Be The Man Club",
                   "description": "The Be The Man Club members area."}, home))
    # Lesson pages
    for i, l in enumerate(lessons):
        prev_l = lessons[i - 1] if i else None
        next_l = lessons[i + 1] if i + 1 < len(lessons) else None
        if next_l and next_l.get("ic") and not l.get("ic"):
            next_l = None  # don't lead Club members into the Inner Circle lessons
        files = ""
        if l["files"]:
            files = '<div class="kit-list" style="margin-top:28px">' + "".join(
                f'<a class="kit" href="/api/club/file?f={f}" rel="nofollow"><div class="stack" style="gap:2px">'
                f'<b>{html.escape(labels[f])}</b><span>Download</span></div><span class="p">↓</span></a>'
                for f in l["files"]) + "</div>"
        extra = ""
        if l["slug"] == "call":
            extra = """<div class="tile stack" id="partner" style="margin-top:28px">
  <p class="label" style="color:var(--accent)">Accountability partner</p>
  <p style="color:var(--fg)">Want a partner each month? Opt in once. On the first of each month you'll get an email introducing you to one other member.</p>
  <div class="actions"><button class="btn btn-primary" id="pair-in" type="button">Pair me each month</button>
  <button class="btn btn-ghost" id="pair-out" type="button">Stop pairing me</button></div>
  <p class="muted" id="pair-msg" role="status"></p>
</div>
<script>
(function(){
  var m=document.getElementById('pair-msg');
  function go(stop){
    m.textContent='Saving…';
    fetch('/api/club/pair',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({stop:stop})})
      .then(function(r){return r.json();}).then(function(d){
        m.textContent=d.ok?(d.paired?"You're in. Watch for your partner's introduction on the 1st.":"Done. You won't be paired from next month."):(d.error||'Please try again.');
      }).catch(function(){m.textContent='Please try again.';});
  }
  document.getElementById('pair-in').onclick=function(){go(false);};
  document.getElementById('pair-out').onclick=function(){go(true);};
})();
</script>"""
        nav = '<div class="actions" style="justify-content:space-between;margin-top:40px">' + \
            (f'<a class="textlink" href="/members/{prev_l["slug"]}/">‹ {html.escape(prev_l["title"])}</a>' if prev_l else "<span></span>") + \
            (f'<a class="textlink" href="/members/{next_l["slug"]}/">{html.escape(next_l["title"])} ›</a>' if next_l else "") + "</div>"
        body = f"""<div class="wrap hero narrow">
  <p class="eyebrow"><a href="/members/">Members</a> · {html.escape(l["module"])}</p>
  <h1 style="font-size:clamp(34px,5vw,54px)">{html.escape(l["title"])}</h1>
  <article class="lesson-body">
{l["html"]}
  </article>
  {files}
  {extra}
  {nav}
</div>
<div style="height:60px"></div>"""
        pages.append(({"path": f"/members/{l['slug']}/", "noindex": True, "members": True,
                       "title": f"{l['title']} | The Be The Man Club", "description": l["title"]}, body))
    return pages


def write_catalog(products):
    """Product and file list for the /api/download Pages Function."""
    club, cfg = club_data()
    all_files = {**products["files"], **club["step_files"]}
    files = {k: {"url": v["url"], "name": v["url"].rsplit("/", 1)[1].split("_", 1)[1]}
             for k, v in all_files.items()}
    club_files = {}
    for l in club["lessons"]:
        for f in l["files"]:
            club_files.setdefault(f, l["month"])
    ic = cfg["inner_circle"]
    club_js = {"plinks": list(cfg["plinks"].values()) + list(ic["plinks"].values()), "prices": cfg["prices"],
               "ic_prices": list(ic["prices"].values()), "ic_group": ic["mailerlite_group"], "portal": cfg["portal"],
               "mailerlite": cfg["mailerlite"], "files": club_files,
               "lessons": {l["slug"]: l["month"] for l in club["lessons"] if l["month"] > 1}}
    offers = {o["key"]: {"plink": o["stripe_plink"], "files": o["files"], "slug": o["slug"], "name": o["name"],
                         "addons": [{"price": a["price"], "files": a["files"]} for a in o.get("addons", [])],
                         "group": o.get("ml_group"), "guide": bool(o.get("guide"))}
              for o in products["offers"]}
    (ROOT.parent / "functions" / "_catalog.js").write_text(
        "// Generated by web/build.py from web/products.json. Do not edit by hand.\n"
        f"export const FILES = {json.dumps(files, indent=1)};\n"
        f"export const OFFERS = {json.dumps(offers, indent=1)};\n"
        f"export const CLUB = {json.dumps(club_js, indent=1)};\n")


def swap_checkout_links(text, products):
    for o in products["offers"]:
        if o.get("stripe_link"):
            text = text.replace(o["systeme_link"], o["stripe_link"])
    # Club: until the members area is switched on, Join buttons keep using the systeme checkout.
    _, cfg = club_data()
    if not cfg.get("live"):
        for plan, link in cfg["links"].items():
            text = text.replace(link, cfg["old_systeme_checkout"][plan])
    return text


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(ROOT / "static", OUT)
    urls = []
    products = json.loads((ROOT / "products.json").read_text())
    write_catalog(products)
    entries = [read_page(p) for p in sorted((ROOT / "pages").glob("*.html"))] + delivery_pages(products) + member_pages(products)
    for meta, body in entries:
        body = swap_checkout_links(body, products)
        rel = "404.html" if meta["path"] == "/404" else (meta["path"].strip("/") + "/index.html").lstrip("/")
        out = OUT / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(swap_checkout_links(render(meta, body), products))
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
