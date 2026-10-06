#!/usr/bin/env python3
"""
Upload the Be The Man 12-week posts into Sprout Social as scheduled drafts.

Runs on your Mac (Python 3 standard library only, nothing to install). It reads the
post folders that install-social-posts.command put in your Be The Man System folder,
uploads each image/video straight to Sprout (no public links), and creates one draft
per network (Instagram, Facebook, Threads) with that network's caption and the
post's date/time. Sprout's API can only create drafts, so you finish by opening each
draft in Sprout and clicking Schedule. The time is already filled in.

Usage (in Terminal):
  python3 ~/Downloads/sprout_upload.py --test   # one post only, to check it in Sprout
  python3 ~/Downloads/sprout_upload.py          # everything still in the future

Your API token: Sprout → Settings → Global Features → API → generate a token.
The script asks for it (it is not saved anywhere), or reads SPROUT_API_TOKEN.
"""
import argparse, datetime, getpass, glob, json, mimetypes, os, re, sys, time, uuid
import urllib.error, urllib.request
from zoneinfo import ZoneInfo

API = os.environ.get('SPROUT_API_BASE', 'https://api.sproutsocial.com')
TZ = ZoneInfo('America/Chicago')
HOURS = {'9am': 9, '12pm': 12, '4pm': 16, '7pm': 19}
NETWORKS = [('instagram', 'instagram.txt'), ('facebook', 'facebook.txt'), ('threads', 'threads.txt')]
STATE = os.path.expanduser('~/.bethemansystem-sprout-uploaded.json')

# ---------------- HTTP ----------------
class Sprout:
    def __init__(self, token):
        self.token = token; self.last = 0.0; self.customer = None

    def _req(self, method, path, body=None, headers=None):
        # Sprout allows 60 requests/minute; stay under it.
        wait = 1.1 - (time.time() - self.last)
        if wait > 0: time.sleep(wait)
        self.last = time.time()
        h = {'Authorization': f'Bearer {self.token}', 'Accept': 'application/json'}
        h.update(headers or {})
        req = urllib.request.Request(API + path, data=body, method=method, headers=h)
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req, timeout=180) as r:
                    raw = r.read(); return r.status, (json.loads(raw) if raw else {})
            except urllib.error.HTTPError as e:
                txt = e.read().decode(errors='replace')
                if e.code == 429 or e.code >= 500:
                    time.sleep(5 * (attempt + 1)); continue
                return e.code, {'error': txt}
            except urllib.error.URLError as e:
                time.sleep(5 * (attempt + 1))
        return 0, {'error': 'network error, gave up after retries'}

    def get(self, path): return self._req('GET', path)

    def post_json(self, path, obj):
        return self._req('POST', path, json.dumps(obj).encode(), {'Content-Type': 'application/json'})

    def post_file(self, path, field, filename):
        boundary = uuid.uuid4().hex
        ctype = mimetypes.guess_type(filename)[0] or 'application/octet-stream'
        with open(filename, 'rb') as f: data = f.read()
        body = (f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"; filename="{os.path.basename(filename)}"\r\n'
                f'Content-Type: {ctype}\r\n\r\n').encode() + data + f'\r\n--{boundary}--\r\n'.encode()
        return self._req('POST', path, body, {'Content-Type': f'multipart/form-data; boundary={boundary}'})

    # -------- Sprout calls --------
    def setup(self):
        s, d = self.get('/v1/metadata/client')
        if s != 200: sys.exit(f'Could not read your Sprout account (HTTP {s}). Check the token.\n{d}')
        self.customer = d['data'][0]['customer_id']
        s, d = self.get(f'/v1/{self.customer}/metadata/customer')
        if s != 200: sys.exit(f'Could not list your Sprout profiles (HTTP {s}).\n{d}')
        return d['data']

    media_field = None
    def upload(self, path):
        fields = [self.media_field] if self.media_field else ['media', 'file']
        for field in fields:
            s, d = self.post_file(f'/v1/{self.customer}/media/', field, path)
            if s in (200, 201, 202):
                m = (d.get('data') or [d])[0]
                if m.get('media_id'):
                    self.media_field = field
                    return m['media_id']
            err = (s, d)
        sys.exit(f'Media upload failed for {os.path.basename(path)} (HTTP {err[0]}):\n{err[1]}\n'
                 'Nothing else was uploaded after this. Send me this message and I\'ll adjust the script.')

# ---------------- posts ----------------
def find_root(arg):
    if arg: return os.path.expanduser(arg)
    for d in glob.glob(os.path.expanduser('~/Desktop/*/')):
        if os.path.basename(d.rstrip('/')).lower() == 'be the man system':
            p = os.path.join(d, 'Social Media - Oct to Dec 2026')
            if os.path.isdir(p): return p
    sys.exit('Could not find "Be The Man System/Social Media - Oct to Dec 2026" on your Desktop.\n'
             'Run install-social-posts.command first, or pass the folder path: --folder "/path/to/folder"')

FOLDER = re.compile(r'^(\d{4}-\d{2}-\d{2})_\w{3}_(\d{1,2}(?:am|pm))_(BTM|COUPLES)_(POST|CAROUSEL|REEL)_(.+)$')

def load_posts(root):
    posts = []
    for d in sorted(glob.glob(os.path.join(root, '*', '*/'))):
        m = FOLDER.match(os.path.basename(d.rstrip('/')))
        if not m: continue
        date, tm, brand, kind, pid = m.groups()
        y, mo, da = map(int, date.split('-'))
        when = datetime.datetime(y, mo, da, HOURS[tm], tzinfo=TZ)
        files = sorted(os.listdir(d))
        if kind == 'REEL':
            media = [os.path.join(d, f) for f in files if f.endswith('.mp4')]; mtype = 'VIDEO'
        else:
            media = [os.path.join(d, f) for f in files if f.lower().endswith(('.jpg', '.png')) and '-cover' not in f]; mtype = 'PHOTO'
        caps = {net: open(os.path.join(d, fn)).read().strip() for net, fn in NETWORKS if os.path.exists(os.path.join(d, fn))}
        posts.append(dict(key=os.path.basename(d.rstrip('/')), when=when, kind=kind, brand=brand, media=media, mtype=mtype, caps=caps))
    posts.sort(key=lambda p: p['when'])
    return posts

def pick_profiles(profiles):
    chosen = {}
    for net, _ in NETWORKS:
        env = os.environ.get(f'SPROUT_PROFILE_{net.upper()}')
        if env:
            chosen[net] = next((p for p in profiles if str(p['customer_profile_id']) == env), None); continue
        cands = [p for p in profiles if net in str(p.get('network_type', '')).lower()]
        if net == 'facebook':
            cands = [p for p in cands if 'instagram' not in str(p.get('network_type', '')).lower()]
        if len(cands) == 1: chosen[net] = cands[0]
        elif len(cands) > 1:
            print(f'\nMore than one {net} profile in Sprout:')
            for i, p in enumerate(cands, 1): print(f'  {i}. {p.get("name")} ({p.get("native_name", "")})')
            k = input(f'Which number is @bethemansystem on {net}? ').strip()
            chosen[net] = cands[int(k) - 1]
        else:
            chosen[net] = None
    return chosen

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--folder'); ap.add_argument('--test', action='store_true')
    ap.add_argument('--only', help='only folders containing this text')
    a = ap.parse_args()

    root = find_root(a.folder)
    posts = [p for p in load_posts(root) if p['when'] > datetime.datetime.now(TZ) + datetime.timedelta(minutes=20)]
    if a.only: posts = [p for p in posts if a.only in p['key']]
    done = json.load(open(STATE)) if os.path.exists(STATE) else {}
    if not posts: sys.exit('No future posts found.')

    token = os.environ.get('SPROUT_API_TOKEN') or getpass.getpass('Paste your Sprout API token (hidden), then Return: ').strip()
    sp = Sprout(token)
    profiles = sp.setup()
    chosen = pick_profiles(profiles)
    print('\nPosting to:')
    for net, p in chosen.items():
        print(f'  {net:9} → ' + (f'{p.get("name")} (id {p["customer_profile_id"]})' if p else 'NOT FOUND in Sprout, skipped'))
    if not any(chosen.values()): sys.exit('No Instagram, Facebook or Threads profile found in Sprout.')

    if a.test: posts = posts[:1]
    todo = [(p, net) for p in posts for net, _ in NETWORKS if chosen.get(net) and net in p['caps'] and done.get(f"{p['key']}|{net}") is None]
    print(f'\n{len(posts)} posts, {len(todo)} drafts to create (already done: {len(done)}).')
    print(f'First: {posts[0]["key"]} at {posts[0]["when"]:%a %b %d %I:%M %p} Central')
    if input('Type YES to start: ').strip() != 'YES': sys.exit('Stopped. Nothing was uploaded.')

    for i, p in enumerate(posts, 1):
        nets = [net for net, _ in NETWORKS if chosen.get(net) and net in p['caps'] and done.get(f"{p['key']}|{net}") is None]
        if not nets: continue
        media_ids = [sp.upload(f) for f in p['media']]  # uploaded once, reused for each network
        for net in nets:
            prof = chosen[net]
            group = (prof.get('groups') or [None])[0]
            body = {
                'group_id': group, 'customer_profile_ids': [prof['customer_profile_id']], 'is_draft': True,
                'text': p['caps'][net],
                'media': [{'media_id': m, 'media_type': p['mtype']} for m in media_ids],
                'delivery': {'type': 'SCHEDULED', 'scheduled_times': [p['when'].astimezone(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')]},
            }
            s, d = sp.post_json(f'/v1/{sp.customer}/publishing/posts', body)
            if s not in (200, 201, 202):
                json.dump(done, open(STATE, 'w'), indent=1)
                sys.exit(f'\nCreating the {net} draft for {p["key"]} failed (HTTP {s}):\n{d}\n'
                         f'Everything before this is saved. Fix the issue (or send me this message), then run the script again; it skips what is done.')
            done[f"{p['key']}|{net}"] = (d.get('data') or [{}])[0].get('id', 'ok')
            json.dump(done, open(STATE, 'w'), indent=1)
        print(f'[{i}/{len(posts)}] ✓ {p["key"]}  ({", ".join(nets)})')

    print('\nDone. In Sprout, open Publishing → Drafts (or the calendar), check each draft, and click Schedule.')
    print('Reels: set the cover in Sprout if you want; the cover image is the "-cover.jpg" in each Reel folder.')

if __name__ == '__main__':
    main()
