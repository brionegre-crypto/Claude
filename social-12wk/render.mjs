// Renders the 12-week Be The Man + Couples calendar: images, carousels, Reels, and
// Instagram / Facebook / Threads captions, one folder per post.
// Usage: node render.mjs [--only=<id-substring>] [--no-video]
//   needs: global playwright, and `pip install imageio-ffmpeg` for Reels.
import { createRequire } from 'module';
import { execSync, spawn } from 'child_process';
import { writeFileSync, mkdirSync, rmSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { items, CTA, TAGS, existing } from './content.mjs';

const require = createRequire(import.meta.url);
const { chromium } = require(join(execSync('npm root -g').toString().trim(), 'playwright'));
const here = dirname(fileURLToPath(import.meta.url));
const OUT = join(here, 'posts');
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const [k, v] = a.replace(/^--/, '').split('='); return [k, v ?? true]; }));
const FPS = 30;

// ---------- schedule ----------
const WEEK1_MONDAY = Date.UTC(2026, 9, 5); // Mon Oct 5, 2026
const DAY = { Mon: 0, Tue: 1, Wed: 2, Thu: 3, Fri: 4, Sat: 5, Sun: 6 };
const SLOTS = {
  btm: { r1: ['Mon', '7pm'], p1: ['Tue', '7pm'], c: ['Thu', '7pm'], p2: ['Sat', '9am'], r2: ['Sun', '7pm'] },
  cpl: { r1: ['Tue', '12pm'], p1: ['Wed', '12pm'], c: ['Fri', '12pm'], r2: ['Sat', '7pm'], p2: ['Sun', '4pm'] },
};
const dateOf = (week, day) => new Date(WEEK1_MONDAY + ((week - 1) * 7 + DAY[day]) * 864e5);
const iso = (d) => d.toISOString().slice(0, 10);

// ---------- theme ----------
const THEME = {
  btm: { bg: '#0B0B0C', glow: '#2a1d0e', ink: '#F2EEE6', em: '#E18B1F', soft: '#BFBCB6', mute: '#8C877E', btnInk: '#0B0B0C', btn: '#E18B1F', rule: '#E18B1F', mark: 'Be The Man', grain: 0.07, tag: 'Break the cycle. Build the system. Be the man.' },
  cpl: { bg: '#F2EEE6', glow: '#fffaf2', ink: '#161514', em: '#B8680F', soft: '#4a463f', mute: '#7d776d', btnInk: '#F2EEE6', btn: '#161514', rule: '#B8680F', mark: 'Be The Man · Couples', grain: 0.05, tag: 'Love on purpose. Not by accident.' },
};
const TAG = 'Break the cycle. Build the system. Be the man.';
const md = (s = '') => s.replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/\*(.+?)\*/g, '<em>$1</em>').replace(/\n/g, '<br>');

const css = (t, w, h) => `
<link rel="stylesheet" href="fonts.css"><style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:${w}px;height:${h}px;background:${t.bg};color:${t.ink};font-family:'Inter',sans-serif;-webkit-font-smoothing:antialiased;overflow:hidden}
.frame{position:relative;width:${w}px;height:${h}px;overflow:hidden;background:radial-gradient(110% 70% at 50% 8%, ${t.glow} 0%, ${t.bg} 62%)}
.grain{position:absolute;inset:0;pointer-events:none;opacity:${t.grain};background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E")}
.pad{position:absolute;inset:96px 96px 88px 96px;display:flex;flex-direction:column}
.brand{display:flex;align-items:center;gap:18px;font-family:'Oswald';font-weight:500;letter-spacing:.32em;font-size:24px;text-transform:uppercase;color:${t.ink}}
.brand i{display:block;width:44px;height:3px;background:${t.rule}}
.label{font-family:'Oswald';font-weight:500;letter-spacing:.24em;font-size:28px;color:${t.em};text-transform:uppercase;margin-bottom:26px}
.h{font-family:'Oswald';font-weight:700;text-transform:uppercase;line-height:.98;color:${t.ink}}
em{font-style:normal;color:${t.em}}
.serif{font-family:'Lora';font-style:italic;font-weight:500;color:${t.soft};line-height:1.3}
.body{font-size:36px;line-height:1.45;color:${t.soft}} .body b,.list b{color:${t.ink};font-weight:600}
.rule{width:96px;height:4px;background:${t.rule};margin:46px 0 40px}
.grow{flex:1}
.foot{display:flex;justify-content:space-between;align-items:flex-end;gap:30px;font-size:24px;color:${t.mute}}
.foot .r{color:${t.ink};font-weight:600;text-align:right}
.btn{display:inline-block;background:${t.btn};color:${t.btnInk};font-family:'Oswald';font-weight:700;text-transform:uppercase;letter-spacing:.08em;font-size:36px;padding:24px 38px;border-radius:2px;margin-top:48px}
.list{list-style:none;display:flex;flex-direction:column;gap:24px;margin-top:6px}
.list li{display:flex;gap:26px;font-size:36px;line-height:1.35;color:${t.soft}}
.list li::before{content:"";flex:0 0 14px;height:14px;margin-top:17px;background:${t.em}}
.num{font-family:'Oswald';font-weight:700;color:${t.em};font-size:190px;line-height:.8;margin-bottom:36px}
.dots{display:flex;gap:10px}.dots span{width:30px;height:4px;background:${t.mute};opacity:.35}.dots span.on{background:${t.em};opacity:1}
/* reels */
.scene{position:absolute;left:96px;right:150px;top:0;bottom:0;display:flex;flex-direction:column;justify-content:center;padding:260px 0 420px}
.scene .h{line-height:.98}
.rl{font-size:58px;font-weight:600;line-height:1.25;display:flex;gap:30px;color:${t.ink};margin-top:40px}
.rl::before{content:"";flex:0 0 18px;height:18px;margin-top:26px;background:${t.em}}
.rt{font-size:52px;line-height:1.35;color:${t.soft};margin-top:34px} .rt b{color:${t.ink}}
.a{opacity:0}
#bar{position:absolute;left:0;top:0;height:8px;background:${t.em}}
</style>`;

const brandRow = (t, right = '') => `<div style="display:flex;justify-content:space-between;align-items:center"><div class="brand"><i></i>${t.mark}</div>${right}</div>`;
const autoH = (s) => { const n = s.replace(/[*\n]/g, '').length; return n <= 16 ? 170 : n <= 28 ? 150 : n <= 44 ? 130 : n <= 64 ? 112 : n <= 90 ? 98 : 86; };

// ---------- static post ----------
function postHTML(it, t) {
  const p = it.post;
  return `<div class="frame"><div class="grain"></div><div class="pad" id="fit">
    ${brandRow(t)}
    <div class="grow"></div>
    ${p.label ? `<div class="label">${md(p.label)}</div>` : ''}
    ${p.pre ? `<div class="serif" style="font-size:${p.preSize || 58}px;margin-bottom:40px">${md(p.pre)}</div>` : ''}
    <div class="h" style="font-size:${p.hs || autoH(p.h)}px">${md(p.h)}</div>
    ${p.sub ? `<div class="serif" style="font-size:${p.subSize || 50}px;margin-top:40px">${md(p.sub)}</div>` : ''}
    ${p.body || p.items ? '<div class="rule"></div>' : ''}
    ${p.body ? `<div class="body">${md(p.body)}</div>` : ''}
    ${p.items ? `<ul class="list" ${p.body ? 'style="margin-top:34px"' : ''}>${p.items.map((x) => `<li><span>${md(x)}</span></li>`).join('')}</ul>` : ''}
    ${p.btn ? `<div><span class="btn">${md(p.btn)}</span></div>` : ''}
    <div class="grow"></div>
    <div class="foot"><span>${t.tag}</span><span class="r">${CTA[it.cta].foot}</span></div>
  </div></div>`;
}

// ---------- carousel ----------
function slidesHTML(it, t) {
  const c = it.carousel, N = c.slides.length + 2;
  const wrap = (i, inner) => `<div class="frame"><div class="grain"></div><div class="pad" id="fit">
    ${brandRow(t, `<div class="dots">${Array.from({ length: N }, (_, k) => `<span class="${k === i ? 'on' : ''}"></span>`).join('')}</div>`)}
    ${inner}
    <div class="foot"><span>${i < N - 1 ? 'Swipe →' : t.tag}</span><span class="r">${i < N - 1 ? '@bethemansystem' : CTA[it.cta].foot}</span></div></div></div>`;
  const out = [wrap(0, `<div class="grow"></div>${c.label ? `<div class="label">${md(c.label)}</div>` : ''}
    <div class="h" style="font-size:${c.hs || autoH(c.h)}px">${md(c.h)}</div>
    ${c.body ? `<div class="rule"></div><div class="body">${md(c.body)}</div>` : ''}<div class="grow"></div>`)];
  c.slides.forEach(([title, text], i) => out.push(wrap(i + 1, `<div class="grow"></div>
    <div class="num">${String(i + 1).padStart(2, '0')}</div>
    <div class="h" style="font-size:${autoH(title) * 0.78}px">${md(title)}</div>
    <div class="rule"></div><div class="body">${md(text)}</div><div class="grow"></div>`)));
  out.push(wrap(N - 1, `<div class="grow"></div>
    ${c.end.pre ? `<div class="serif" style="font-size:52px;margin-bottom:46px">${md(c.end.pre)}</div>` : ''}
    <div class="h" style="font-size:${autoH(c.end.h) * 0.85}px">${md(c.end.h)}</div>
    <div><span class="btn">${md(c.end.btn || CTA[it.cta].btn)}</span></div><div class="grow"></div>`));
  return out;
}

// ---------- reel ----------
function reelPlan(it) {
  // scenes: arrays of lines "B:" big, "S:" serif, "L:" label, "I:" list item, "T:" text
  let t = 0; const scenes = [];
  for (const lines of it.reel) {
    let lt = t + 0.1; const parsed = [];
    for (const raw of lines) { const [k, ...r] = raw.split(':'); parsed.push({ k, s: r.join(':'), at: lt }); lt += k === 'I' ? 1.1 : 0.85; }
    const chars = lines.join('').length;
    const end = lt + Math.max(1.3, Math.min(3.2, chars / 26));
    scenes.push({ start: t, end, lines: parsed }); t = end;
  }
  scenes.push({ start: t, end: t + 3.2, lines: null }); // end card
  return { scenes, dur: t + 3.2 };
}
function reelHTML(it, t, plan) {
  const bigSize = (lines) => { const n = lines.filter((l) => l.k === 'B').map((l) => l.s).join(' '); return autoH(n) * 1.08; };
  const line = (l, big) => {
    const a = `class="a" data-t="${l.at.toFixed(2)}"`;
    if (l.k === 'B') return `<div ${a}><div class="h" style="font-size:${big}px;margin-top:18px">${md(l.s)}</div></div>`;
    if (l.k === 'S') return `<div ${a}><div class="serif" style="font-size:72px;margin-top:20px">${md(l.s)}</div></div>`;
    if (l.k === 'L') return `<div ${a}><div class="label" style="font-size:36px">${md(l.s)}</div></div>`;
    if (l.k === 'I') return `<div ${a}><div class="rl"><span>${md(l.s)}</span></div></div>`;
    return `<div ${a}><div class="rt">${md(l.s)}</div></div>`;
  };
  const endT = plan.scenes.at(-1).start + 0.1;
  const end = `<div class="a" data-t="${endT}"><div class="brand" style="font-size:30px"><i style="width:56px;height:4px"></i>${t.mark}</div></div>
    <div class="a" data-t="${endT + 0.25}"><div class="h" style="font-size:${it.theme === 'btm' ? 112 : 104}px;margin-top:40px">${md(it.endH || (it.theme === 'btm' ? 'Break the cycle.\nBuild the system.\n*Be the man.*' : 'Love on purpose.\n*Not by accident.*'))}</div></div>
    <div class="a" data-t="${endT + 0.9}"><span class="btn" style="font-size:44px;margin-top:64px">${md(CTA[it.cta].btn)}</span></div>
    <div class="a" data-t="${endT + 1.2}"><div style="font-size:30px;color:${t.mute};margin-top:28px">@bethemansystem</div></div>`;
  return `<div class="frame" style="width:1080px;height:1920px"><div id="bg" style="position:absolute;inset:-60px;background:radial-gradient(80% 50% at 50% 45%, ${t.glow} 0%, ${t.bg} 70%)"></div>
  ${plan.scenes.map((s, i) => `<div class="scene" data-s="${s.start}" data-e="${s.end}">${s.lines ? s.lines.map((l) => line(l, bigSize(s.lines))).join('') : end}</div>`).join('')}
  <div class="grain"></div><div id="bar"></div></div>
  <script>
  const DUR=${plan.dur};const ease=x=>1-Math.pow(1-Math.min(Math.max(x,0),1),3);
  window.render=t=>{document.getElementById('bar').style.width=(t/DUR*100)+'%';document.getElementById('bg').style.transform='scale('+(1+t*0.004)+')';
   document.querySelectorAll('.scene').forEach(sc=>{const s=+sc.dataset.s,e=+sc.dataset.e,last=e>=DUR-0.01,vis=t>=s&&t<e;sc.style.display=vis?'flex':'none';if(!vis)return;
    sc.style.opacity=last?1:1-ease((t-(e-0.3))/0.3);
    sc.querySelectorAll('.a').forEach(el=>{const p=ease((t-(+el.dataset.t))/0.45);el.style.opacity=p;el.style.transform='translateY('+((1-p)*50)+'px)';});});};
  window.fitScenes=()=>{let bad=0;document.querySelectorAll('.scene').forEach(sc=>{sc.style.display='flex';sc.querySelectorAll('.a').forEach(e=>e.style.opacity=1);
    for(let i=0;i<14;i++){const over=sc.scrollHeight>sc.clientHeight+2||[...sc.querySelectorAll('.h,.serif,.rl,.rt')].some(e=>e.scrollWidth>e.clientWidth+2);if(!over)break;
     sc.querySelectorAll('.h,.serif,.rl,.rt').forEach(e=>{e.style.fontSize=(parseFloat(getComputedStyle(e).fontSize)*0.93)+'px'});if(i==13)bad++;}
    sc.style.display='none';});return bad;};
  </script>`;
}

// fit a static slide: shrink type until nothing overflows
const fitStatic = () => {
  const pad = document.getElementById('fit'); let i = 0;
  const over = () => pad.scrollHeight > pad.clientHeight + 2 || [...pad.querySelectorAll('.h,.body,.serif,.list li')].some((e) => e.scrollWidth > e.clientWidth + 2);
  while (over() && i < 16) { pad.querySelectorAll('.h,.body,.serif,.list li,.num').forEach((e) => { e.style.fontSize = parseFloat(getComputedStyle(e).fontSize) * (e.classList.contains('h') ? 0.93 : 0.97) + 'px'; }); i++; }
  return over() ? -1 : i;
};

// ---------- captions ----------
function captions(it) {
  const c = CTA[it.cta];
  const pool = TAGS[it.theme];
  const seed = [...it.id].reduce((a, ch) => a + ch.charCodeAt(0), 0);
  const tags = [...new Set([...(it.tags || []), ...[0, 1, 2, 3].map((k) => pool[(seed + k * 3) % pool.length]), '#bethemansystem'])].slice(0, 5);
  const ig = `${it.cap.trim()}\n\n${c.ig}\n\n${tags.join(' ')}`;
  const fb = `${it.cap.trim()}\n\n${c.fb}\n\n${tags.slice(0, 2).join(' ')}`;
  const th = `${(it.th || it.cap).trim()}\n\n${c.th}`;
  return { ig, fb, th };
}

// ---------- main ----------
const ffmpeg = () => execSync(`python3 -c "import imageio_ffmpeg as i;print(i.get_ffmpeg_exe())"`).toString().trim();
mkdirSync(OUT, { recursive: true });
const browser = await chromium.launch();
const rows = []; const problems = [];

async function shot(html, w, h, file, fit = true) {
  const tmp = join(here, `.tmp-${process.pid}.html`);
  writeFileSync(tmp, `<!doctype html><html><head><meta charset="utf-8">${html.css}</head><body>${html.body}</body></html>`);
  const page = await browser.newPage({ viewport: { width: w, height: h } });
  await page.goto('file://' + tmp); await page.evaluate(() => document.fonts.ready);
  const r = fit ? await page.evaluate(fitStatic) : 0;
  await page.screenshot({ path: file, type: 'jpeg', quality: 92 });
  await page.close(); rmSync(tmp);
  return r;
}

const all = args.reverse ? [...existing, ...items].reverse() : [...existing, ...items];
for (const it of all) {
  const [day, time] = it.slot ? SLOTS[it.theme][it.slot] : [it.day, it.time];
  const d = it.date ? new Date(it.date) : dateOf(it.week, day);
  const dayName = d.toUTCString().slice(0, 3);
  const tm = it.time || time;
  const folder = `${iso(d)}_${dayName}_${tm}_${it.theme === 'btm' ? 'BTM' : 'COUPLES'}_${it.type.toUpperCase()}_${it.id}`;
  const dir = join(OUT, folder);
  rows.push({ date: iso(d), day: dayName, time: tm, brand: it.theme === 'btm' ? 'Be The Man' : 'Couples', type: it.type, title: it.title, folder, cta: it.cta, week: it.week });
  if (args.only && !it.id.includes(args.only)) continue;
  if (args.match && !new RegExp(args.match).test(it.id)) continue;
  mkdirSync(dir, { recursive: true });
  const t = THEME[it.theme];
  const cap = captions(it);
  if (cap.th.length > 500) problems.push(`${it.id}: Threads text ${cap.th.length} chars (>500)`);
  writeFileSync(join(dir, 'instagram.txt'), cap.ig + '\n');
  writeFileSync(join(dir, 'facebook.txt'), cap.fb + '\n');
  writeFileSync(join(dir, 'threads.txt'), cap.th + '\n');
  if (it.media) { for (const m of it.media) execSync(`cp "${join(here, m)}" "${dir}/"`); console.log('copied', folder); continue; }

  const done = it.type === 'post' ? existsSync(join(dir, `${it.id}.jpg`))
    : it.type === 'carousel' ? existsSync(join(dir, `01-${it.id}.jpg`))
    : existsSync(join(dir, `${it.id}.mp4`)) || (args['no-video'] && existsSync(join(dir, `${it.id}-cover.jpg`)));
  if (done && !args.force) { console.log('skip', folder); continue; }
  if (it.type === 'post') {
    const r = await shot({ css: css(t, 1080, 1350), body: postHTML(it, t) }, 1080, 1350, join(dir, `${it.id}.jpg`));
    if (r < 0) problems.push(`${it.id}: post still overflows`);
  } else if (it.type === 'carousel') {
    const sl = slidesHTML(it, t);
    for (let i = 0; i < sl.length; i++) {
      const r = await shot({ css: css(t, 1080, 1350), body: sl[i] }, 1080, 1350, join(dir, `${String(i + 1).padStart(2, '0')}-${it.id}.jpg`));
      if (r < 0) problems.push(`${it.id} slide ${i + 1}: overflows`);
    }
  } else if (it.type === 'reel') {
    const plan = reelPlan(it);
    const tmp = join(here, `.tmp-${process.pid}.html`);
    writeFileSync(tmp, `<!doctype html><html><head><meta charset="utf-8">${css(t, 1080, 1920)}</head><body>${reelHTML(it, t, plan)}</body></html>`);
    const page = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
    await page.goto('file://' + tmp); await page.evaluate(() => document.fonts.ready);
    const bad = await page.evaluate(() => window.fitScenes());
    if (bad) problems.push(`${it.id}: ${bad} reel scene(s) overflow`);
    await page.evaluate(() => window.render(Math.min(2.6, 1.5)));
    const firstEnd = plan.scenes[0].end - 0.35;
    await page.evaluate((x) => window.render(x), firstEnd);
    await page.screenshot({ path: join(dir, `${it.id}-cover.jpg`), type: 'jpeg', quality: 90 });
    if (!args['no-video']) {
      const outf = join(dir, `${it.id}.mp4`);
      const ff = spawn(ffmpeg(), ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-', '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo', '-shortest',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-preset', 'medium', '-crf', '23', '-r', String(FPS), '-c:a', 'aac', '-b:a', '64k', '-movflags', '+faststart', outf], { stdio: ['pipe', 'inherit', 'inherit'] });
      for (let f = 0; f < Math.round(plan.dur * FPS); f++) {
        await page.evaluate((x) => window.render(x), f / FPS);
        const buf = await page.screenshot({ type: 'jpeg', quality: 88 });
        if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once('drain', r));
      }
      ff.stdin.end();
      await new Promise((res, rej) => ff.on('close', (c) => (c === 0 ? res() : rej(new Error('ffmpeg ' + c)))));
    }
    await page.close(); rmSync(tmp);
  }
  console.log('done', folder);
}
await browser.close();

// ---------- calendar ----------
rows.sort((a, b) => (a.date + a.time.padStart(4, '0')).localeCompare(b.date + b.time.padStart(4, '0')));
if (!args.match) writeFileSync(join(here, 'calendar.csv'), 'date,day,time,brand,type,title,cta,folder\n' + rows.map((r) => [r.date, r.day, r.time, r.brand, r.type, `"${r.title.replace(/"/g, "'")}"`, r.cta, r.folder].join(',')).join('\n') + '\n');
writeFileSync(join(here, 'problems.txt'), problems.join('\n') + '\n');
console.log(problems.length ? 'PROBLEMS:\n' + problems.join('\n') : 'no problems');
