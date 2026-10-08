"""Build POSTING-GUIDE.md (every post, every platform, in date order) and
two-week zip packs under 30 MB from posts/ + calendar.csv.
Usage: python3 make_packs.py
"""
import csv, os, zipfile, datetime
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
POSTS = os.path.join(HERE, 'posts')
PACKS = os.path.join(HERE, 'packs-boost' if '--boost' in __import__('sys').argv else 'packs')
rows = list(csv.DictReader(open(os.path.join(HERE, 'calendar.csv'))))
HOURS = {'8am': 8, '9am': 9, '12pm': 12, '2pm': 14, '4pm': 16, '7pm': 19, '9pm': 21}
rows.sort(key=lambda r: (r['date'], HOURS[r['time']]))
import sys
BOOST = '--boost' in sys.argv
rows = [r for r in rows if ('_b-' in r['folder']) == BOOST]

def read(folder, name):
    p = os.path.join(POSTS, folder, name)
    return open(p).read().strip() if os.path.exists(p) else ''

def block(d):
    """Two-week block index from Mon Oct 5."""
    start = datetime.date(2026, 10, 9) if BOOST else datetime.date(2026, 10, 5)
    return (datetime.date.fromisoformat(d) - start).days // 14

TIME = {'8am': '8:00 AM', '9am': '9:00 AM', '12pm': '12:00 PM', '2pm': '2:00 PM', '4pm': '4:00 PM', '7pm': '7:00 PM', '9pm': '9:00 PM'}
TYPE = {'post': 'Post', 'carousel': 'Carousel', 'reel': 'Reel'}

def guide(rs, title):
    out = [f'# {title}\n',
           'Each post has its own folder (same name as below) holding the media plus `instagram.txt`, `facebook.txt` and `threads.txt`. '
           'Times are your local time. Post the **same media** on all three platforms; only the caption changes.\n',
           '**Instagram:** paste `instagram.txt`. Carousels: add images in file-number order. Reels: set the cover to the `-cover.jpg`.  ',
           '**Facebook:** paste `facebook.txt` (it has clickable links).  ',
           '**Threads:** paste `threads.txt` and attach the same image(s) or video. It is under 500 characters.\n',
           '| Date | Time | Brand | Type | Title |', '|---|---|---|---|---|']
    for r in rs:
        out.append(f"| {r['day']} {r['date'][5:]} | {TIME.get(r['time'], r['time'])} | {r['brand']} | {TYPE[r['type']]} | {r['title']} |")
    out.append('\n---\n')
    for i, r in enumerate(rs, 1):
        f = r['folder']
        media = sorted(x for x in os.listdir(os.path.join(POSTS, f)) if not x.endswith('.txt'))
        out.append(f"## {i}. {r['day']} {r['date']} · {TIME.get(r['time'], r['time'])} · {r['brand']} · {TYPE[r['type']]}\n")
        out.append(f"**{r['title']}**  \n- [ ] Instagram  - [ ] Facebook  - [ ] Threads  \n**Folder:** `{f}/`  \n**Files:** " + ', '.join(f'`{m}`' for m in media) + '\n')
        for label, name in (('Instagram', 'instagram.txt'), ('Facebook', 'facebook.txt'), ('Threads', 'threads.txt')):
            out.append(f'**{label}:**\n```\n{read(f, name)}\n```\n')
        out.append('---\n')
    return '\n'.join(out)

os.makedirs(PACKS, exist_ok=True)
open(os.path.join(HERE, 'POSTING-GUIDE-BOOST.md' if BOOST else 'POSTING-GUIDE.md'), 'w').write(guide(rows, '30-day boost: 3 extra posts a day (Oct 9 – Nov 7, 2026)' if BOOST else 'Be The Man + Couples: 12-week posting guide (Oct 6 – Dec 27, 2026)'))

groups = defaultdict(list)
for r in rows:
    groups[block(r['date'])].append(r)
for b, rs in sorted(groups.items()):
    first, last = rs[0]['date'], rs[-1]['date']
    name = f'pack-B{b + 1}_{first}_to_{last}' if BOOST else f'pack-{b + 1:02d}_{first}_to_{last}'
    g = guide(rs, f'Posting guide: {first} to {last}')
    # split further if a block would exceed ~28 MB
    parts, cur, size = [], [], 0
    for r in rs:
        s = sum(os.path.getsize(os.path.join(POSTS, r['folder'], x)) for x in os.listdir(os.path.join(POSTS, r['folder'])))
        if cur and size + s > 28e6:
            parts.append(cur); cur, size = [], 0
        cur.append(r); size += s
    parts.append(cur)
    for k, part in enumerate(parts):
        zname = name + (f'_part{k + 1}' if len(parts) > 1 else '') + '.zip'
        with zipfile.ZipFile(os.path.join(PACKS, zname), 'w', zipfile.ZIP_STORED) as z:
            z.writestr('POSTING-GUIDE.md', guide(part, f'Posting guide: {part[0]["date"]} to {part[-1]["date"]}'))
            for r in part:
                for x in sorted(os.listdir(os.path.join(POSTS, r['folder']))):
                    z.write(os.path.join(POSTS, r['folder'], x), f"{r['folder']}/{x}")
        print(zname, round(os.path.getsize(os.path.join(PACKS, zname)) / 1e6, 1), 'MB', len(part), 'posts')
