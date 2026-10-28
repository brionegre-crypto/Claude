"""The Truth Ledger guide page (single HTML file, brand styles inline)."""
import html
from content import *
from build import TONIGHT

e = html.escape
def hm(t): h, m = t; return f"{(h - 1) % 12 + 1}:{m:02d} {'AM' if h < 12 else 'PM'}"

SCRIPTS = [
    ("When the urge hits", "“Give me a second. I want to answer that honestly.”"),
    ("When you don't know", "“I don't know.” / “I'm not sure. Let me check and tell you.”"),
    ("When you didn't do it", "“I didn't do it yet. I'll have it done by ___.”"),
    ("When you failed", "“I messed that up. Here's what I'm doing about it.”"),
    ("When it already slipped out", "“Actually, that's not true. The truth is ___.”"),
    ("When you're ashamed", "“I'm embarrassed to tell you this, but…”"),
    ("When she asks and you need time", "“I'll answer that fully. Give me until tonight.” Then answer it tonight."),
]

def build(path):
    weeks = []
    for w in WEEKS:
        days = []
        for i in range((w['n'] - 1) * 7, w['n'] * 7):
            t, f, q = DAYS[i]; d = i + 1; k = DAY_SCI[d]
            days.append(f'''<article class="day" id="day-{d}" data-day="{d}">
  <label class="check"><input type="checkbox" data-day="{d}"><span></span></label>
  <div><p class="dnum">Day {d}{' · Review' if d % 7 == 0 else ''}</p><h4>{e(t)}</h4>
  <p><b>Morning.</b> {e(f)}</p><p><b>Tonight.</b> {e(q)}</p>
  <div class="nums"><label>Told <input type="number" min="0" inputmode="numeric" id="n-{d}-t" data-n="t" data-day="{d}"></label><label>Caught <input type="number" min="0" inputmode="numeric" id="n-{d}-c" data-n="c" data-day="{d}"></label><label>Corrected <input type="number" min="0" inputmode="numeric" id="n-{d}-x" data-n="x" data-day="{d}"></label></div>
  <p class="why"><a href="#sci-{k}">Why it works: {e(SCIENCE[k]['title'])}</a></p></div></article>''')
        weeks.append(f'''<section class="week" id="week-{w['n']}">
  <p class="label">Week {w['n']}</p><h3>{e(w['name'])}</h3><p class="serif big">{e(w['line'])}</p>
  <p>{e(w['why'])}</p><p class="tot" data-week="{w['n']}"></p><blockquote>“{e(w['verse'])}” <cite>{e(w['ref'])}</cite></blockquote>
  {''.join(days)}</section>''')

    order = ["curtis", "selfhelp", "prolific", "selfpres", "escalate", "track", "ifthen", "hrt", "pause", "exposure", "shame",
             "compassion", "lapse", "affirm", "secrets", "expressive", "sleep", "kelly", "trust"]
    assert sorted(order) == sorted(SCIENCE)
    cards = ''.join(f'''<article class="sci" id="sci-{k}"><p class="badge b-{SCIENCE[k]['strength'].lower()}">{SCIENCE[k]['strength']} evidence</p>
  <h4>{e(SCIENCE[k]['title'])}</h4><p>{e(SCIENCE[k]['finding'])}</p>
  <p><b>In your system:</b> {e(SCIENCE[k]['use'])}</p>
  <p class="src"><a href="{e(SCIENCE[k]['url'])}" target="_blank" rel="noopener">{e(SCIENCE[k]['source'])}</a> · Used on Days {', '.join(str(d) for d in sorted(DAY_SCI) if DAY_SCI[d] == k)}</p></article>''' for k in order)
    tonight = TONIGHT.split('\n')
    page = f'''<title>The Truth Ledger</title>
<meta charset="utf-8"><meta name="claude:viewport-fit-sides" content="cover">
<link href="https://fonts.googleapis.com/css2?family=Oswald:wght@500;700&family=Lora:ital,wght@1,500&family=Inter:wght@400;600&display=swap" rel="stylesheet">
<style>
:root{{--bg:#0B0B0C;--panel:#141416;--ink:#F2EEE6;--em:#E18B1F;--soft:#BFBCB6;--mute:#8C877E;--rule:#2a2925;color-scheme:dark}}
*{{box-sizing:border-box}}html{{scroll-behavior:smooth}}
body{{margin:0;background:var(--bg);color:var(--ink);font:17px/1.6 Inter,system-ui,sans-serif}}
.wrap{{max-width:760px;margin:0 auto;padding-block:0 80px;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px))}}
body::before{{content:"";position:fixed;inset:0 0 auto;height:env(safe-area-inset-top,0px);z-index:10;background:var(--bg)}}
.brand{{font:500 13px Oswald;letter-spacing:.32em;text-transform:uppercase;color:var(--soft);padding:28px 0 0}}
.brand b{{color:var(--em)}}
.hero{{padding:56px 0 40px;border-bottom:2px solid var(--em)}}
h1,h2,h3,h4{{font-family:Oswald;text-transform:uppercase;line-height:1;margin:0}}
h1{{font-size:clamp(48px,12vw,88px);font-weight:700}}h2{{font-size:34px;margin:56px 0 16px}}h3{{font-size:40px;margin:4px 0 8px}}h4{{font-size:20px;margin:2px 0 8px;letter-spacing:.02em}}
.label,.dnum{{font:500 13px Oswald;letter-spacing:.24em;text-transform:uppercase;color:var(--em);margin:0}}
.serif{{font-family:Lora;font-style:italic;color:var(--soft)}}.big{{font-size:22px;margin:0 0 12px}}
.hero .serif{{font-size:24px;margin:18px 0 0}}
.note{{background:var(--panel);border-left:3px solid var(--em);padding:16px 20px;margin:24px 0;color:var(--soft);font-size:15px}}
.note b{{color:var(--ink)}}
ol,ul{{padding-left:22px}}li{{margin:6px 0}}
.lines{{display:grid;gap:12px;counter-reset:l;padding:0;list-style:none}}
.lines li{{background:var(--panel);padding:16px 18px 16px 64px;position:relative;margin:0}}
.lines li:before{{counter-increment:l;content:counter(l);position:absolute;left:18px;top:8px;font:700 38px Oswald;color:var(--em)}}
.rhythm{{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px}}
.rhythm div{{background:var(--panel);padding:16px}}.rhythm strong{{display:block;font:700 22px Oswald;color:var(--em)}}
.rhythm span{{font-size:14px;color:var(--soft)}}
table{{width:100%;border-collapse:collapse;font-size:15px}}td{{padding:10px 8px;border-bottom:1px solid var(--rule);vertical-align:top}}
td:first-child{{color:var(--mute);width:38%}}
pre{{background:var(--panel);padding:16px;white-space:pre-wrap;font:14px/1.6 'IBM Plex Mono',ui-monospace,monospace;color:var(--soft)}}
blockquote{{margin:16px 0 24px;padding:0 0 0 16px;border-left:2px solid var(--rule);font-family:Lora;font-style:italic;color:var(--soft)}}
cite{{display:block;font:500 12px Oswald;letter-spacing:.2em;text-transform:uppercase;color:var(--mute);margin-top:6px;font-style:normal}}
.day,.week{{scroll-margin-top:100px}}
.week{{border-top:1px solid var(--rule);padding-top:40px;margin-top:40px}}
.day{{display:flex;gap:14px;padding:16px;margin:10px 0;background:var(--panel);border:1px solid transparent}}
.day p{{margin:4px 0;font-size:15.5px}}.day b{{color:var(--em);font-weight:600}}
.day.today{{border-color:var(--em)}}.day.done{{opacity:.55}}
.nums{{display:flex;flex-wrap:wrap;gap:8px 14px;margin:10px 0 2px;font-size:13px;color:var(--mute)}}.nums label{{display:flex;align-items:center;gap:6px}}
.nums input{{width:58px;background:var(--bg);color:var(--ink);border:1px solid var(--rule);padding:4px 6px;font:inherit;font-size:15px;font-variant-numeric:tabular-nums}}
.nums input:focus-visible{{outline:2px solid var(--em)}}
.tot{{font:500 13px Oswald;letter-spacing:.14em;text-transform:uppercase;color:var(--em);font-variant-numeric:tabular-nums}}.tot:empty{{display:none}}
.check input{{position:absolute;opacity:0}}.check span{{display:block;width:24px;height:24px;border:2px solid var(--mute);margin-top:2px;cursor:pointer}}
.check input:checked+span{{background:var(--em);border-color:var(--em)}}.check input:focus-visible+span{{outline:2px solid var(--ink)}}
.bar{{position:sticky;top:env(safe-area-inset-top,0px);z-index:5;background:rgba(11,11,12,.94);border-bottom:1px solid var(--rule);padding-block:8px;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));display:flex;gap:6px 12px;align-items:center;flex-wrap:wrap;font-size:13px;color:var(--soft)}}
.bar input{{background:var(--panel);color:var(--ink);border:1px solid var(--rule);padding:6px 8px;font:inherit}}
.bar a,.btn{{background:var(--em);color:var(--bg);font:700 13px Oswald;letter-spacing:.08em;text-transform:uppercase;padding:6px 12px;text-decoration:none}}
#status{{color:var(--ink)}}
.toc{{display:flex;flex-wrap:wrap;gap:8px;margin:28px 0 0}}.toc a{{font:500 12px Oswald;letter-spacing:.14em;text-transform:uppercase;color:var(--soft);border:1px solid var(--rule);padding:6px 10px;text-decoration:none}}
.why{{margin-top:8px!important}}.why a{{color:var(--soft);font-size:14px;text-decoration:none;border-bottom:1px solid var(--rule)}}
.sci{{background:var(--panel);padding:18px;margin:12px 0;scroll-margin-top:100px}}.sci p{{margin:6px 0;font-size:15.5px}}.sci b{{color:var(--em);font-weight:600}}
.src{{font-size:13.5px!important;color:var(--mute)}}.src a{{color:var(--soft)}}
.badge{{display:inline-block;font:500 11px Oswald;letter-spacing:.18em;text-transform:uppercase;padding:3px 8px;margin:0}}
.b-strong{{background:var(--em);color:var(--bg)}}.b-moderate{{border:1px solid var(--em);color:var(--em)}}.b-early{{border:1px solid var(--mute);color:var(--soft)}}
.sci .badge{{margin-bottom:10px}}
.h3s{{font-size:22px;margin:28px 0 8px;color:var(--em)}}
.legend{{font-size:14px;color:var(--soft);line-height:2.2}}
footer{{margin-top:64px;padding-top:24px;border-top:2px solid var(--em);color:var(--mute);font-size:14px}}
@media print{{.bar{{display:none}}body{{background:#fff;color:#000}}.day,.note,.lines li,.rhythm div,pre{{background:#f4f1ea}}}}
</style>
<div class="bar"><label>Day 1 is <input type="date" id="start"></label><span id="status"></span><a href="#" id="jump">Go to today</a></div>
<div class="wrap">
<p class="brand"><b>■</b> Be The Man</p>
<header class="hero"><p class="label">A Be The Man daily system</p><h1>The Truth<br>Ledger</h1>
<p class="serif">49 days to become a man whose word holds.</p></header>

<nav class="toc"><a href="#tonight">Tonight</a><a href="#rhythm">Daily rhythm</a><a href="#science">The science</a><a href="#home">At home</a><a href="#week-1">The 49 days</a><a href="#relapse">If you lie</a><a href="#setup">Reminders</a></nav>

<div class="note"><b>Read this first.</b> This is a program one man does on his own, for one goal: to stop lying. Researchers who study pathological lying say no proven treatment exists yet, and they point to cognitive behavioral therapy (CBT) as the best place to start. Self-guided CBT, done with no therapist, has solid evidence behind it, and the men who keep doing the work every day get the most from it. So this guide gives you the CBT methods with the strongest evidence (tracking, if-then plans, habit reversal, exposure and relapse prevention) in 49 short days. Every day links to the study behind it, rated honestly as Strong, Moderate or Early. If you ever feel hopeless or think about harming yourself, call or text <b>988</b> (Suicide &amp; Crisis Lifeline, US).</div>

<h2 id="tonight">Tonight: Day 0</h2>
<p>Don't wait for Monday. Do these five things alone, before you sleep.</p>
<ol>{''.join(f"<li>{e(x[3:])}</li>" for x in tonight[1:6])}</ol>
<p class="serif">{e(tonight[6])}</p>

<h2>The three lines</h2>
<ol class="lines">
<li><b>No new lies.</b> When the alarm goes off in your body, pause. Three seconds and one breath, then a true sentence.</li>
<li><b>Correct it fast.</b> If one gets out, fix it within 60 seconds, or the same day at the latest: “Actually, that's not true.”</li>
<li><b>Log every one, every night.</b> Being honest with the ledger is the first honesty. A ledger with a lie in it is worthless.</li>
</ol>

<h2 id="rhythm">The daily rhythm</h2>
<div class="rhythm">
<div><strong>{hm(TIMES['morning'])}</strong>Morning · 2 min<br><span>Read your sentence and today's focus. Write one if-then plan: \u201cIf ___ happens, then I'll say ___.\u201d</span></div>
<div><strong>{hm(TIMES['midday'])}</strong>Midday · 60 sec<br><span>Anything to correct since morning? Fix it before 5 PM.</span></div>
<div><strong>{hm(TIMES['evening'])}</strong>Evening Ledger · 10 min<br><span>Fill in the ledger and answer tonight's question.</span></div>
<div><strong>Every 7th day</strong>{hm(TIMES['review'])} · 20 min<br><span>Add up the week and compare it with the last one. Write a new if-then for the situation that beat you.</span></div>
</div>

<h2>The pause: true sentences to use</h2>
<p>A lie fills a silence. Have true sentences ready so you have something else to say.</p>
<table>{''.join(f"<tr><td>{e(a)}</td><td>{e(b)}</td></tr>" for a, b in SCRIPTS)}</table>

<h2>The evening ledger</h2>
<p>Use the Notes app or a paper notebook, one page per night, and enter your three numbers on that day below. Numbers matter. Over 49 days you should see lies told go down while lies caught and corrections go up.</p>
<pre>{e(LEDGER)}</pre>

<h2 id="home">At home</h2>
<p>Home is where lying usually costs the most. These rules keep you from adding to the damage while you learn.</p>
<ul>
<li><b>No new lies.</b> If you're asked something directly, don't lie. If you need a moment: \u201cGive me a second. I want to answer that honestly.\u201d</li>
<li><b>No covering lies.</b> When an old lie comes up, never tell a new one to protect it. If you aren't ready to correct it yet, say nothing rather than add a layer.</li>
<li><b>Answer the whole question the first time.</b> A half-answer is a lie with better manners.</li>
<li><b>Private is not a lie, but secrets about her life are different.</b> You can decline to talk about something. You can't hide things that affect her.</li>
<li><b>Don't trickle the truth.</b> When you correct old lies, correct each one completely. A little more truth each time you're caught breaks trust again every time.</li>
</ul>

<h2 id="science">The science behind the system</h2>
<p>What researchers know about lying, habits, shame and trust, and exactly where each finding shows up in your 49 days.</p>
<p class="legend"><span class="badge b-strong">Strong</span> reviews of many experiments &nbsp; <span class="badge b-moderate">Moderate</span> solid studies, or a proven method borrowed from a related problem &nbsp; <span class="badge b-early">Early</span> small, mixed or unpublished evidence</p>
{cards}



{''.join(weeks)}

<h2 id="relapse">If you lie (and on some day you will)</h2>
<p>A slip isn't a relapse. Hiding the slip is the relapse. Research on relapse shows that the \u201cI've blown it, what's the use\u201d thought after one slip is what turns it into a full return to the old pattern.</p>
<ol><li>Correct it the same day.</li><li>Log it honestly tonight.</li><li>Write yourself two honest, kind sentences. Don't tear yourself down: shame makes men hide.</li><li>Reread your if-then plans and fix the one that failed.</li><li>Start the next day where you are. Don't go back to Day 1.</li></ol>

<h2 id="setup">Set up the reminders</h2>
<ol>
<li>Save <b>install-truth-ledger.command</b> from your Claude chat to your Mac's Downloads folder.</li>
<li>Open Terminal and run: <code>bash ~/Downloads/install-truth-ledger.command</code> (add <code>today</code> at the end to make today Day 1).</li>
<li>Allow Terminal to control Reminders when your Mac asks.</li>
<li>Check that the list syncs to your iPhone: Settings &rarr; your name &rarr; iCloud &rarr; Reminders is on.</li>
</ol>
<p>No Mac nearby? Open <b>Truth-Ledger.ics</b> on your iPhone to add the same schedule to Calendar, with alerts.</p>

<footer><p class="serif">{e(TAGLINE)}</p><p>The Truth Ledger · a Be The Man daily system · bethemansystem.com</p></footer>
</div>
<script>
(function(){{
  var S={{get:function(k){{try{{return localStorage.getItem(k)}}catch(e){{return null}}}},set:function(k,v){{try{{localStorage.setItem(k,v)}}catch(e){{}}}}}};
  var start=document.getElementById('start'),status=document.getElementById('status'),jump=document.getElementById('jump');
  var iso=function(d){{return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0')}};
  var t=new Date();t.setDate(t.getDate()+1);
  start.value=S.get('tl-start')||iso(t);
  function today(){{var p=start.value.split('-');var d0=new Date(p[0],p[1]-1,p[2]);var n=new Date();n.setHours(0,0,0,0);return Math.round((n-d0)/864e5)+1}}
  function paint(){{var n=today();document.querySelectorAll('.day').forEach(function(el){{el.classList.toggle('today',+el.dataset.day===n)}});
    var done=document.querySelectorAll('.day input:checked').length;
    status.textContent=(n<1?'Starts in '+(1-n)+' day'+(n===0?'':'s')+'. Tonight is Day 0.':n>49?'49 days complete.':'Today is Day '+n+'.')+' '+done+'/49 done';}}
  document.querySelectorAll('.day input').forEach(function(c){{c.checked=S.get('tl-d'+c.dataset.day)==='1';c.closest('.day').classList.toggle('done',c.checked);
    c.addEventListener('change',function(){{S.set('tl-d'+c.dataset.day,c.checked?'1':'0');c.closest('.day').classList.toggle('done',c.checked);paint()}})}});
  function totals(){{for(var w=1;w<=7;w++){{var t={{t:0,c:0,x:0}},any=false;
    for(var d=(w-1)*7+1;d<=w*7;d++){{['t','c','x'].forEach(function(k){{var v=S.get('tl-n'+d+k);if(v!==null&&v!==''){{t[k]+=+v;any=true}}}})}}
    var el=document.querySelector('.tot[data-week="'+w+'"]');if(el)el.textContent=any?'Your week: '+t.t+' told \u00b7 '+t.c+' caught \u00b7 '+t.x+' corrected':''}}}}
  document.querySelectorAll('.nums input').forEach(function(i){{var v=S.get('tl-n'+i.dataset.day+i.dataset.n);if(v!==null)i.value=v;
    i.addEventListener('input',function(){{S.set('tl-n'+i.dataset.day+i.dataset.n,i.value);totals()}})}});
  totals();
  start.addEventListener('change',function(){{S.set('tl-start',start.value);paint()}});
  jump.addEventListener('click',function(ev){{ev.preventDefault();var n=Math.min(Math.max(today(),1),49);document.getElementById('day-'+n).scrollIntoView({{block:'center'}})}});
  paint();
}})();
</script>'''
    open(path, 'w').write(page)
