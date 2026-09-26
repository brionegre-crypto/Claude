#!/usr/bin/env python3
"""
Copy a Notion page tree into Apple Notes using the Forever ✱ Notes framework.

- Everything goes in one Apple Notes folder ("Notes" by default); structure
  comes from ✱ notes and links, not subfolders.
- The root page becomes a ✱ hub ("✱ Sermon Prep & Teaching") and each of its
  sections becomes a ✱ collection note ("✱ Sabbath Classes") whose list links
  to every class, in the same order as Notion.
- Every class note is tagged for its collection (#SabbathClass, #FeastsClass,
  ...) so a Smart Folder can gather them, and links back up to its ✱ note.
- Adds a "Classes" headline to your ✱ Ministry Hub note linking to each class
  collection (Sabbath Classes, Feasts Classes, ...).

Runs on your Mac. Python 3 standard library only. See README.md for setup.

    python3 notion_to_apple_notes.py --dry-run
    python3 notion_to_apple_notes.py --only "Sabbath Classes"
    python3 notion_to_apple_notes.py
"""
import argparse
import getpass
import html
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

NOTION_VERSION = "2022-06-28"
DEFAULT_ROOT = "ff30c41b81b744458e84cfc51099ef01"  # Sermon Prep & Teaching
HERE = os.path.dirname(os.path.abspath(__file__))
STATE_PATH = os.path.join(HERE, "state.json")
NOTESTORE = os.path.expanduser(
    "~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")

# Placeholder left in note HTML wherever one note links to another. Resolved
# once every note exists and its Apple Notes identifier is known.
LINK_RE = re.compile(r"\{\{NOTE:([0-9a-f]{32})\|(.*?)\}\}")
HEX32_RE = re.compile(r"([0-9a-f]{32})")


def norm(page_id):
    return page_id.replace("-", "").lower()


def esc(text):
    return html.escape(text or "", quote=True)


def link_placeholder(page_id, fallback_text):
    return "{{NOTE:%s|%s}}" % (norm(page_id), esc(fallback_text).replace("}}", "} }"))


def clean_title(title):
    title = re.sub(r"<br\s*/?>", " ", title or "")
    title = title.replace("**", "").replace("\\", "").strip().strip("*").strip()
    return re.sub(r"\s+", " ", title) or "Untitled"


def notion_url(page_id):
    return "https://www.notion.so/" + norm(page_id)


# --------------------------------------------------------------------------
# Notion API
# --------------------------------------------------------------------------

class NotionError(Exception):
    pass


class Notion:
    def __init__(self, token):
        self.token = token

    def request(self, method, path, body=None):
        url = "https://api.notion.com/v1" + path
        data = json.dumps(body).encode() if body is not None else None
        for attempt in range(7):
            req = urllib.request.Request(url, data=data, method=method, headers={
                "Authorization": "Bearer " + self.token,
                "Notion-Version": NOTION_VERSION,
                "Content-Type": "application/json",
            })
            try:
                with urllib.request.urlopen(req, timeout=60) as resp:
                    time.sleep(0.34)  # Notion allows ~3 requests/second
                    return json.load(resp)
            except urllib.error.HTTPError as e:
                if e.code == 429 or e.code >= 500:
                    time.sleep(float(e.headers.get("Retry-After") or 2 ** attempt))
                    continue
                raise NotionError("Notion API %s on %s: %s" % (
                    e.code, path, e.read().decode(errors="replace")[:300]))
            except urllib.error.URLError:
                time.sleep(2 ** attempt)
        raise NotionError("Notion API kept failing on " + path)

    def children(self, block_id):
        results, cursor = [], None
        while True:
            query = "?page_size=100" + ("&start_cursor=" + cursor if cursor else "")
            r = self.request("GET", "/blocks/%s/children%s" % (block_id, query))
            results += r["results"]
            if not r.get("has_more"):
                return results
            cursor = r["next_cursor"]

    def page_title(self, page_id):
        page = self.request("GET", "/pages/" + page_id)
        return title_from_properties(page)

    def query_database(self, db_id):
        results, body = [], {"page_size": 100}
        while True:
            r = self.request("POST", "/databases/%s/query" % db_id, body)
            results += r["results"]
            if not r.get("has_more"):
                return results
            body["start_cursor"] = r["next_cursor"]


def title_from_properties(page):
    for prop in page.get("properties", {}).values():
        if prop.get("type") == "title":
            return clean_title("".join(t.get("plain_text", "") for t in prop["title"]))
    return "Untitled"


# --------------------------------------------------------------------------
# Notion blocks -> Apple Notes HTML
# --------------------------------------------------------------------------

def rich(rich_text):
    out = []
    for t in rich_text or []:
        plain = t.get("plain_text", "")
        if t.get("type") == "mention" and t["mention"].get("type") == "page":
            out.append(link_placeholder(t["mention"]["page"]["id"], plain))
            continue
        s = esc(plain).replace("\n", "<br>")
        a = t.get("annotations", {})
        if a.get("code"):
            s = "<tt>%s</tt>" % s
        if a.get("bold"):
            s = "<b>%s</b>" % s
        if a.get("italic"):
            s = "<i>%s</i>" % s
        if a.get("underline"):
            s = "<u>%s</u>" % s
        if a.get("strikethrough"):
            s = "<strike>%s</strike>" % s
        href = t.get("href")
        if href:
            internal = HEX32_RE.search(href.replace("-", "")) if (
                href.startswith("/") or "notion.so" in href) else None
            if internal:
                s = link_placeholder(internal.group(1), plain)
            else:
                s = '<a href="%s">%s</a>' % (esc(href), s)
        out.append(s)
    return "".join(out)


class Exporter:
    """Walks the Notion tree and builds one HTML body per page."""

    def __init__(self, notion, root_id, only=None):
        self.notion = notion
        self.root_id = norm(root_id)
        self.only = [o.lower() for o in (only or [])]
        self.pages = {}  # id -> {title, parent, children, html}

    def should_crawl(self, parent_id, title):
        if parent_id == self.root_id and self.only:
            return title.lower() in self.only
        return True

    def crawl(self, page_id, title, parent_id=None):
        page_id = norm(page_id)
        if page_id in self.pages:
            return
        self.pages[page_id] = {"title": title, "parent": parent_id,
                               "children": [], "html": ""}
        depth = 0
        p = parent_id
        while p:
            depth += 1
            p = self.pages[p]["parent"]
        print("  " * depth + "- " + title)
        try:
            blocks = self.notion.children(page_id)
        except NotionError as e:
            print("  " * depth + "  ! skipped: " + str(e))
            self.pages[page_id]["html"] = "<div><i>Could not read this page from Notion.</i></div>"
            return
        self.pages[page_id]["html"] = self.render_blocks(blocks, page_id)

    def add_child(self, parent_id, child_id, title):
        """Crawl a sub-page and return the HTML that links to it."""
        if self.should_crawl(parent_id, title):
            self.pages[parent_id]["children"].append(norm(child_id))
            self.crawl(child_id, title, parent_id)
        return link_placeholder(child_id, title)

    def block_children(self, block):
        return self.notion.children(block["id"]) if block.get("has_children") else []

    def render_blocks(self, blocks, page_id):
        out, i = [], 0
        grouped = {"bulleted_list_item": "ul", "numbered_list_item": "ol",
                   "to_do": "ul", "child_page": "ul"}
        while i < len(blocks):
            kind = blocks[i]["type"]
            if kind in grouped:
                items = []
                while i < len(blocks) and blocks[i]["type"] == kind:
                    items.append(self.render_list_item(blocks[i], page_id))
                    i += 1
                out.append("<%s>%s</%s>" % (grouped[kind], "".join(items), grouped[kind]))
                continue
            out.append(self.render_block(blocks[i], page_id))
            i += 1
        return "".join(out)

    def render_list_item(self, block, page_id):
        kind = block["type"]
        if kind == "child_page":
            title = clean_title(block["child_page"]["title"])
            return "<li>%s</li>" % self.add_child(page_id, block["id"], title)
        data = block[kind]
        text = rich(data.get("rich_text"))
        if kind == "to_do":
            text = ("☑ " if data.get("checked") else "☐ ") + text
        nested = self.render_blocks(self.block_children(block), page_id)
        return "<li>%s%s</li>" % (text, nested)

    def render_block(self, block, page_id):
        kind = block["type"]
        data = block.get(kind, {})
        text = rich(data.get("rich_text")) if isinstance(data, dict) else ""
        kids = lambda: self.render_blocks(self.block_children(block), page_id)

        if kind == "paragraph":
            return "<div>%s</div>%s" % (text or "<br>", kids())
        if kind == "heading_1":
            return "<h2>%s</h2>%s" % (text, kids())
        if kind == "heading_2":
            return "<h3>%s</h3>%s" % (text, kids())
        if kind == "heading_3":
            return "<div><b>%s</b></div>%s" % (text, kids())
        if kind == "quote":
            return "<blockquote>%s</blockquote>%s" % (text, kids())
        if kind == "callout":
            icon = (data.get("icon") or {}).get("emoji", "")
            return "<div>%s %s</div>%s" % (icon, text, kids())
        if kind == "toggle":
            return "<div><b>▸ %s</b></div>%s" % (text, kids())
        if kind == "code":
            return "<div><tt>%s</tt></div>" % text
        if kind == "equation":
            return "<div><tt>%s</tt></div>" % esc(data.get("expression"))
        if kind == "divider":
            return "<div>—————</div>"
        if kind == "table":
            rows = []
            for row in self.block_children(block):
                cells = row.get("table_row", {}).get("cells", [])
                rows.append("<tr>%s</tr>" % "".join("<td>%s</td>" % rich(c) for c in cells))
            return "<div><table><tbody>%s</tbody></table></div>" % "".join(rows)
        if kind in ("column_list", "column"):
            return kids()
        if kind == "synced_block":
            source = (data.get("synced_from") or {}).get("block_id")
            if source:
                try:
                    return self.render_blocks(self.notion.children(source), page_id)
                except NotionError:
                    return ""
            return kids()
        if kind == "child_database":
            return self.render_database(block, page_id)
        if kind == "link_to_page":
            target = data.get("page_id")
            if not target:
                return ""
            try:
                title = self.notion.page_title(target)
            except NotionError:
                title = "Linked page"
            return "<div>→ %s</div>" % link_placeholder(target, title)
        if kind in ("image", "video", "file", "pdf", "audio"):
            label = rich(data.get("caption")) or kind.capitalize()
            if data.get("type") == "external":
                return '<div>[%s] <a href="%s">%s</a></div>' % (
                    kind.capitalize(), esc(data["external"]["url"]), label)
            return '<div>[%s: %s — see original <a href="%s">in Notion</a>]</div>' % (
                kind.capitalize(), label, notion_url(page_id))
        if kind in ("bookmark", "embed", "link_preview"):
            url = data.get("url", "")
            return '<div><a href="%s">%s</a></div>' % (esc(url), rich(data.get("caption")) or esc(url))
        # table_of_contents, breadcrumb, template, unsupported: nothing to copy
        return ""

    def render_database(self, block, page_id):
        title = clean_title(block["child_database"].get("title") or "Database")
        try:
            rows = self.notion.query_database(block["id"])
        except NotionError:
            return "<h3>%s</h3><div><i>(Linked database view — open in Notion.)</i></div>" % esc(title)
        items = []
        for row in rows:
            if row.get("object") != "page":
                continue
            items.append("<li>%s</li>" % self.add_child(page_id, row["id"], title_from_properties(row)))
        return "<h3>%s</h3><ul>%s</ul>" % (esc(title), "".join(items))


# --------------------------------------------------------------------------
# Apple Notes (AppleScript via osascript)
# --------------------------------------------------------------------------

AS_CREATE = '''
on run argv
    set acctName to item 1 of argv
    set folderName to item 2 of argv
    set htmlText to read (POSIX file (item 3 of argv)) as «class utf8»
    tell application "Notes"
        set acct to account acctName
        if not (exists folder folderName of acct) then
            make new folder at acct with properties {name:folderName}
        end if
        set n to make new note at folder folderName of acct with properties {body:htmlText}
        return id of n
    end tell
end run
'''

AS_UPDATE = '''
on run argv
    set htmlText to read (POSIX file (item 2 of argv)) as «class utf8»
    tell application "Notes" to set body of note id (item 1 of argv) to htmlText
end run
'''

AS_EXISTS = '''
on run argv
    tell application "Notes" to return (exists note id (item 1 of argv)) as text
end run
'''

AS_FIND = '''
on run argv
    set out to ""
    tell application "Notes"
        repeat with n in (notes of account (item 1 of argv) whose name is (item 2 of argv))
            set out to out & (id of n) & tab & ((count of attachments of n) as text) & tab & (name of container of n) & tab & ((modification date of n) as text) & tab & (length of (plaintext of n)) & linefeed
        end repeat
    end tell
    return out
end run
'''

AS_BY_ID = '''
on run argv
    tell application "Notes"
        set n to note id (item 1 of argv)
        return (id of n) & tab & ((count of attachments of n) as text) & tab & (name of container of n) & tab & ((modification date of n) as text) & tab & (length of (plaintext of n)) & linefeed
    end tell
end run
'''


def find_hub(args):
    """Return (note id, attachment count) for the hub note, or None. Notes in
    Recently Deleted are ignored; if several real notes share the name, list
    them and let the user pick one with --hub-id."""
    matched = args.hub
    if args.hub_id:
        rows = [osa(AS_BY_ID, args.hub_id)]
    else:
        rows = []
        names = [args.hub, "%s %s" % (args.marker, args.hub)]
        if not args.hub.lower().endswith("hub"):
            names += ["%s Hub" % args.hub, "%s %s Hub" % (args.marker, args.hub)]
        for name in names:
            rows = [r for r in osa(AS_FIND, args.account, name).splitlines() if r.strip()]
            if rows:
                matched = name
                break
    notes = [r.split("\t") for r in rows]
    live = [n for n in notes if n[2].strip().lower() != "recently deleted"]
    if len(live) == 1:
        return live[0][0], live[0][1]
    if not live:
        print('\n! Could not find your hub note "%s" in account "%s".' % (args.hub, args.account))
        print('  Rerun with --hub "Exact Note Name". Notes already created are just updated.')
        return None
    print('\n! %d notes are named "%s", so the script did not pick one:' % (len(live), matched))
    for i, (nid, att, folder, modified, length) in enumerate(live, 1):
        print("  %d) folder: %s | last edited: %s | %s characters | %s attachments"
              % (i, folder, modified, length, att))
        print("     --hub-id \"%s\"" % nid)
    print("  Open each in Notes to see which is your real hub, then rerun with its --hub-id line.")
    return None

AS_BODY = '''
on run argv
    tell application "Notes" to return body of note id (item 1 of argv)
end run
'''


AS_SAMPLE = '''
on run argv
    set sep to "<!--NOTE-BREAK-->"
    set out to ""
    tell application "Notes"
        set acct to account (item 1 of argv)
        set hubs to (notes of acct whose name contains (item 2 of argv))
        repeat with n in hubs
            set out to out & (body of n) & sep
        end repeat
        set ns to notes of acct
        set total to count of ns
        if total > 15 then set total to 15
        repeat with i from 1 to total
            set out to out & (body of item i of ns) & sep
        end repeat
    end tell
    return out
end run
'''

# Apple Notes' own body font. Used when your notes don't name a font, which is
# what Notes does for text typed in its default style.
SYSTEM_FONT = "-apple-system, '.AppleSystemUIFont', 'SF Pro Text', 'Helvetica Neue'"


def detect_font(args, note_ids=()):
    """Find the font family and size your existing notes use, so imported notes
    match them. Notes created by a script otherwise fall back to Helvetica."""
    try:
        sample = osa(AS_SAMPLE, args.account, args.hub.split()[0])
    except (RuntimeError, OSError) as e:
        print("  (Couldn't read your notes to match the font: %s)" % e)
        return SYSTEM_FONT, None
    ours = set(note_ids)
    families, sizes = {}, {}
    for body in sample.split("<!--NOTE-BREAK-->"):
        if not body.strip() or any(i in body for i in ours):
            continue
        for fam in re.findall(r"font-family:\s*([^;\"]+)", body) + re.findall(r'<font[^>]*face="([^"]+)"', body):
            fam = fam.strip().strip("'")
            if fam and "courier" not in fam.lower() and "menlo" not in fam.lower():
                families[fam] = families.get(fam, 0) + 1
        for size in re.findall(r"font-size:\s*(\d+(?:\.\d+)?)px", body):
            sizes[size] = sizes.get(size, 0) + 1
    family = max(families, key=families.get) if families else SYSTEM_FONT
    size = max(sizes, key=sizes.get) if sizes else None
    return family, size


def with_font(body, font):
    family, size = font
    style = "font-family: %s" % family
    if size:
        style += "; font-size: %spx" % size
    return '<div style="%s">%s</div>' % (esc(style), body)


def osa(script, *args, html_text=None):
    with tempfile.TemporaryDirectory() as tmp:
        script_path = os.path.join(tmp, "s.applescript")
        with open(script_path, "w", encoding="utf-8") as f:
            f.write(script)
        argv = list(args)
        if html_text is not None:
            html_path = os.path.join(tmp, "body.html")
            with open(html_path, "w", encoding="utf-8") as f:
                f.write(html_text)
            argv.append(html_path)
        r = subprocess.run(["osascript", script_path] + argv, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return r.stdout.strip()


def note_identifiers(coredata_ids):
    """Map Apple Notes AppleScript ids (x-coredata://…/ICNote/p123) to the note
    UUIDs used by note links. Needs Full Disk Access for Terminal."""
    wanted = {}
    for cid in coredata_ids:
        m = re.search(r"/p(\d+)$", cid)
        if m:
            wanted[int(m.group(1))] = cid
    if not wanted:
        return {}
    tmp = tempfile.mkdtemp()
    try:
        for suffix in ("", "-wal", "-shm"):
            if os.path.exists(NOTESTORE + suffix):
                shutil.copy2(NOTESTORE + suffix, os.path.join(tmp, "NoteStore.sqlite" + suffix))
        con = sqlite3.connect(os.path.join(tmp, "NoteStore.sqlite"))
        marks = ",".join("?" * len(wanted))
        rows = con.execute(
            "SELECT Z_PK, ZIDENTIFIER FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK IN (%s)" % marks,
            list(wanted)).fetchall()
        con.close()
        return {wanted[pk]: ident for pk, ident in rows if ident}
    except (OSError, sqlite3.Error) as e:
        print("\n! Could not read the Notes database for link ids (%s)." % e)
        print("  Give Terminal Full Disk Access (see README), then rerun to add links.")
        return None
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def link_url(uuid, style):
    if style == "notes":
        return "notes://showNote?identifier=" + uuid
    return "applenotes:note/" + uuid


# --------------------------------------------------------------------------
# Assemble
# --------------------------------------------------------------------------

def apply_forever_notes(exporter, marker):
    """Give the hub and collections the ✱ prefix and every other note a
    collection tag, following Forever ✱ Notes."""
    pages, root = exporter.pages, exporter.root_id
    collections = {root}
    for child in pages[root]["children"]:
        if pages[child]["children"]:
            collections.add(child)
    for pid, page in pages.items():
        top = pid
        while pages[top]["parent"] not in (None, root):
            top = pages[top]["parent"]
        if pid in collections:
            page["display"] = "%s %s" % (marker, page["title"]) if marker else page["title"]
            page["tag"] = None
        else:
            page["display"] = page["title"]
            page["tag"] = tag_name(pages[top]["title"] if top in collections else pages[root]["title"])


def tag_name(title):
    words = re.findall(r"[A-Za-z0-9]+", title.replace("'", "").replace("’", ""))
    tag = "".join(w[:1].upper() + w[1:] for w in words if w.lower() not in ("and", "the", "of"))
    return "#" + re.sub(r"Classes$", "Class", tag or "Note")


def resolve_links(body, pages, uuids, style):
    def sub(m):
        pid, fallback = m.group(1), m.group(2)
        title = esc(pages[pid]["display"]) if pid in pages else fallback
        cid = pages.get(pid, {}).get("note_id")
        uuid = (uuids or {}).get(cid)
        if uuid:
            return '<a href="%s">%s</a>' % (link_url(uuid, style), title)
        return title
    return LINK_RE.sub(sub, body)


def note_html(pid, page, pages):
    parts = ["<div><h1>%s</h1></div>" % esc(page["display"])]
    if page["parent"]:
        parts.append("<div>↑ %s</div><div><br></div>" % link_placeholder(
            page["parent"], pages[page["parent"]]["display"]))
    parts.append(page["html"])
    parts.append("<div><br></div>")
    if page.get("tag"):
        parts.append("<div>%s</div>" % page["tag"])
    parts.append('<div><i>Imported from <a href="%s">Notion</a></i></div>' % notion_url(pid))
    return "".join(parts)


def load_state():
    if os.path.exists(STATE_PATH):
        with open(STATE_PATH, encoding="utf-8") as f:
            return json.load(f)
    return {"notes": {}, "hub_done": False}


def save_state(state):
    with open(STATE_PATH, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)


def write_preview(exporter, bodies):
    out = os.path.join(HERE, "preview")
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    for pid, body in bodies.items():
        name = re.sub(r"[^\w\- ]+", "", exporter.pages[pid]["title"])[:80].strip() or pid
        with open(os.path.join(out, "%s-%s.html" % (name, pid[:6])), "w", encoding="utf-8") as f:
            f.write("<meta charset='utf-8'>" + resolve_links(body, exporter.pages, {}, "applenotes"))
    print("\nDry run: wrote %d previews to %s (nothing changed in Apple Notes)." % (len(bodies), out))


def update_hub(args, exporter, uuids, state, font):
    pages = exporter.pages
    root = pages[exporter.root_id]
    classes = [c for c in root["children"] if re.search(args.hub_match, pages[c]["title"], re.I)]
    if not classes:
        print("\nNo class pages matched for the hub; skipping hub.")
        return
    found = find_hub(args)
    if not found:
        return
    hub_id, attachments = found
    links = "".join("<li>%s</li>" % link_placeholder(c, pages[c]["display"]) for c in classes)
    section = with_font(resolve_links(
        "<div><br></div><h2>%s</h2><ul>%s</ul><div>All teaching: %s</div>" % (
            esc(args.hub_heading), links, link_placeholder(exporter.root_id, root["display"])),
        pages, uuids, args.link_style), font)
    if int(attachments or 0) > 0:
        # Rewriting a note's body through AppleScript drops attachments, so don't.
        print('\n! "%s" has attachments, so the script will not edit it. Paste this in by hand:'
              % args.hub)
        print("  %s:" % args.hub_heading)
        for c in classes:
            print("   - " + pages[c]["display"])
        return
    old = osa(AS_BODY, hub_id)
    backup = os.path.join(HERE, "hub-backup-%d.html" % int(time.time()))
    with open(backup, "w", encoding="utf-8") as f:
        f.write(old)
    osa(AS_UPDATE, hub_id, html_text=old + section)
    state["hub_done"] = True
    print('\nAdded "%s" section to your hub note (previous version saved to %s).'
          % (args.hub_heading, os.path.basename(backup)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=DEFAULT_ROOT, help="Notion page ID or URL to copy (default: Sermon Prep & Teaching)")
    ap.add_argument("--only", action="append", help='Only copy this sub-page of the root, e.g. --only "Sabbath Classes" (repeatable)')
    ap.add_argument("--account", default="iCloud", help="Apple Notes account (default: iCloud)")
    ap.add_argument("--folder", default="Notes", help="Apple Notes folder (Forever Notes keeps everything in Notes)")
    ap.add_argument("--marker", default="✱", help="Prefix for hub/collection note titles (default: ✱)")
    ap.add_argument("--hub", default="Ministry", help="Name of your hub note; ✱ prefix and ' Hub' are tried automatically")
    ap.add_argument("--hub-id", help="Exact note id of your hub, when several notes share its name")
    ap.add_argument("--hub-heading", default="Classes", help="Headline added to the hub note")
    ap.add_argument("--hub-match", default="class", help="Root sub-pages whose title matches this go under the hub headline")
    ap.add_argument("--no-hub", action="store_true", help="Don't touch the hub note")
    ap.add_argument("--link-style", choices=["applenotes", "notes"], default="applenotes",
                    help="URL style for note links (try 'notes' if links don't open)")
    ap.add_argument("--font", help="Font family to use (default: whatever your existing notes use)")
    ap.add_argument("--font-size", help="Body font size in px (default: whatever your existing notes use)")
    ap.add_argument("--dry-run", action="store_true", help="Read Notion and write HTML previews only")
    args = ap.parse_args()

    root_match = HEX32_RE.search(norm(args.root.split("?")[0]))
    if not root_match:
        sys.exit("--root must be a Notion page ID or URL")
    root_id = root_match.group(1)

    token = os.environ.get("NOTION_TOKEN") or getpass.getpass("Paste your Notion secret (it stays hidden) and press Enter: ")
    token = token.strip().strip("\"'“”‘’ ")
    if not token or "paste" in token.lower():
        sys.exit("No Notion secret given. Run `unset NOTION_TOKEN`, then run the script again and paste it when asked.")
    notion = Notion(token)

    print("Reading Notion…")
    try:
        root_title = notion.page_title(root_id)
    except NotionError as e:
        if " 401 " in str(e):
            sys.exit("Notion says the secret is invalid. Copy it again from notion.so/profile/integrations "
                     "(Internal Integration Secret → Show → Copy), run `unset NOTION_TOKEN`, then run the "
                     "script again and paste it when asked.")
        if " 404 " in str(e):
            sys.exit("Notion can't see Sermon Prep & Teaching. Open that page → ••• → Connections and add "
                     "your integration, then run again.")
        sys.exit(str(e))
    exporter = Exporter(notion, root_id, args.only)
    exporter.crawl(root_id, root_title)
    pages = exporter.pages
    apply_forever_notes(exporter, args.marker)
    bodies = {pid: note_html(pid, p, pages) for pid, p in pages.items()}
    print("\n%d pages read from Notion." % len(pages))

    if args.dry_run:
        write_preview(exporter, bodies)
        return

    state = load_state()
    family, size = detect_font(args, state["notes"].values())
    font = (args.font or family, args.font_size or size)
    print("\nFont: %s%s (matched to your existing notes)" % (
        "system default" if font[0] == SYSTEM_FONT else font[0],
        ", %spx" % font[1] if font[1] else ""))
    print('\nWriting to Apple Notes (account "%s", folder "%s")…' % (args.account, args.folder))
    for n, (pid, body) in enumerate(bodies.items(), 1):
        plain = with_font(resolve_links(body, pages, {}, args.link_style), font)
        existing = state["notes"].get(pid)
        if existing and osa(AS_EXISTS, existing) == "true":
            osa(AS_UPDATE, existing, html_text=plain)
            pages[pid]["note_id"] = existing
            verb = "updated"
        else:
            pages[pid]["note_id"] = osa(AS_CREATE, args.account, args.folder, html_text=plain)
            verb = "created"
        state["notes"][pid] = pages[pid]["note_id"]
        save_state(state)
        print("  [%d/%d] %s: %s" % (n, len(bodies), verb, pages[pid]["display"]))

    print("\nLinking notes…")
    note_ids = [p["note_id"] for p in pages.values()]
    uuids = None
    for _ in range(5):  # give Notes a moment to save new notes to its database
        uuids = note_identifiers(note_ids)
        if uuids is None or len(uuids) == len(note_ids):
            break
        time.sleep(2)
    if uuids:
        linked = [pid for pid, body in bodies.items() if LINK_RE.search(body)]
        for pid in linked:
            osa(AS_UPDATE, pages[pid]["note_id"],
                html_text=with_font(resolve_links(bodies[pid], pages, uuids, args.link_style), font))
        print("  Added links in %d notes." % len(linked))
        missing = len(note_ids) - len(uuids)
        if missing:
            print("  ! %d notes weren't in the Notes database yet; rerun to link them." % missing)

    if not args.no_hub and not state.get("hub_done"):
        update_hub(args, exporter, uuids, state, font)
    save_state(state)
    print("\nDone.")


if __name__ == "__main__":
    main()
