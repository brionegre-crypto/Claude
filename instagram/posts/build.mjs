// Renders the @bethemansystem Instagram posts to PNG with headless Chromium.
// Usage: node build.mjs   (outputs to ./out)
import { createRequire } from 'module';
import { execSync } from 'child_process';
import { writeFileSync, mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const require = createRequire(import.meta.url);
const { chromium } = require(join(execSync('npm root -g').toString().trim(), 'playwright'));

const here = dirname(fileURLToPath(import.meta.url));
const OUT = join(here, 'out');
mkdirSync(OUT, { recursive: true });

const C = { ink: '#0B0B0C', coal: '#141416', slab: '#1F1F1F', amber: '#E18B1F', cream: '#F2EEE6', stone: '#BFBCB6', mute: '#8C877E' };
const HANDLE = '@bethemansystem';
const TAG = 'Break the cycle. Build the system. Be the man.';

const base = (w, h) => `
<link rel="stylesheet" href="fonts.css">
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:${w}px;height:${h}px;background:${C.ink};color:${C.cream};font-family:'Inter',sans-serif;-webkit-font-smoothing:antialiased}
.frame{position:relative;width:${w}px;height:${h}px;overflow:hidden;
  background:radial-gradient(120% 80% at 50% 0%, #1b1a19 0%, ${C.ink} 60%);}
.frame::after{content:"";position:absolute;inset:0;pointer-events:none;opacity:.07;
  background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");}
.pad{position:absolute;inset:96px 96px 88px 96px;display:flex;flex-direction:column}
.brand{display:flex;align-items:center;gap:18px;font-family:'Oswald';font-weight:500;letter-spacing:.32em;font-size:24px;color:${C.cream};text-transform:uppercase}
.brand i{display:block;width:44px;height:3px;background:${C.amber}}
.label{font-family:'Oswald';font-weight:500;letter-spacing:.24em;font-size:28px;color:${C.amber};text-transform:uppercase}
.h{font-family:'Oswald';font-weight:700;text-transform:uppercase;line-height:.98;letter-spacing:-.005em;color:${C.cream}}
.h em{font-style:normal;color:${C.amber}}
.serif{font-family:'Lora';font-style:italic;font-weight:500;color:${C.stone}}
.body{font-size:36px;line-height:1.45;color:${C.stone}}
.body b{color:${C.cream};font-weight:600}
.rule{width:96px;height:4px;background:${C.amber}}
.grow{flex:1}
.foot{display:flex;justify-content:space-between;align-items:flex-end;font-size:24px;color:${C.mute};letter-spacing:.02em}
.foot .h2{color:${C.cream};font-weight:600}
.cta{display:inline-flex;align-items:center;gap:18px;background:${C.amber};color:${C.ink};font-family:'Oswald';font-weight:700;
  text-transform:uppercase;letter-spacing:.08em;font-size:36px;padding:26px 40px;border-radius:2px}
.list{list-style:none;display:flex;flex-direction:column;gap:26px}
.list li{display:flex;gap:26px;font-size:36px;line-height:1.35;color:${C.stone}}
.list li::before{content:"";flex:0 0 14px;height:14px;margin-top:17px;background:${C.amber}}
.list li b{color:${C.cream};font-weight:600}
.num{font-family:'Oswald';font-weight:700;color:${C.amber};font-size:200px;line-height:.8}
.dots{display:flex;gap:10px}.dots span{width:34px;height:4px;background:#3a3936}.dots span.on{background:${C.amber}}
</style>`;

const brand = `<div class="brand"><i></i>Be The Man</div>`;
const foot = (right = HANDLE) => `<div class="foot"><span>${TAG}</span><span class="h2">${right}</span></div>`;
const dots = (n, i) => `<div class="dots">${Array.from({ length: n }, (_, k) => `<span class="${k === i ? 'on' : ''}"></span>`).join('')}</div>`;

const W = 1080, H = 1350, SH = 1920;

// ---------- Feed posts (1080x1350) ----------
const posts = {
  '01-step-1': `
  <div class="frame"><div class="pad">
    ${brand}
    <div class="grow"></div>
    <div class="label">Step 1 of 7 · Free</div>
    <div class="h" style="font-size:132px;margin-top:28px">What type<br>of man do you<br><em>want to be?</em></div>
    <div class="rule" style="margin:48px 0 40px"></div>
    <div class="body">One question. One worksheet. It ends in one sentence that says who he is. <b>Twenty minutes, a pen — not your phone.</b></div>
    <div style="margin-top:56px"><span class="cta">Comment “STEP1” →</span></div>
    <div class="grow"></div>
    ${foot()}
  </div></div>`,

  '02-meant-it': `
  <div class="frame"><div class="pad">
    ${brand}
    <div class="grow"></div>
    <div class="serif" style="font-size:60px;line-height:1.35">New Year’s.<br>Sunday morning.<br>The car after the argument.</div>
    <div class="h" style="font-size:150px;margin-top:56px">You meant it<br><em>every time.</em></div>
    <div class="rule" style="margin:52px 0 40px"></div>
    <div class="body">What you never had was <b>a first step that comes before the promise.</b></div>
    <div class="grow"></div>
    ${foot('Step 1 is free · link in bio')}
  </div></div>`,

  '03-system-when': `
  <div class="frame"><div class="pad">
    ${brand}
    <div class="grow"></div>
    <div class="h" style="font-size:170px">A goal<br>says what.</div>
    <div class="h" style="font-size:170px;margin-top:18px">A system<br>says <em>when.</em></div>
    <div class="rule" style="margin:60px 0 40px"></div>
    <div class="serif" style="font-size:44px;line-height:1.4">A promise with no time attached isn’t a plan. It’s a feeling with a deadline you never set.</div>
    <div class="grow"></div>
    ${foot()}
  </div></div>`,

  '04-wife-test': `
  <div class="frame" style="background:radial-gradient(120% 80% at 50% 0%, #1d1c1b 0%, ${C.coal} 65%)"><div class="pad">
    ${brand}
    <div class="grow"></div>
    <div class="label">The whole test</div>
    <div class="h" style="font-size:138px;margin-top:28px">Would your<br>wife be able<br>to <em>tell?</em></div>
    <div class="rule" style="margin:52px 0 44px"></div>
    <div class="body" style="margin-bottom:40px">Not because you announced it. Because it showed up on an ordinary Tuesday.</div>
    <ul class="list">
      <li><span><b>At dinner.</b></span></li>
      <li><span><b>At bedtime.</b></span></li>
      <li><span><b>When you name the miss</b> before she has to.</span></li>
    </ul>
    <div class="grow"></div>
    ${foot()}
  </div></div>`,

  '05-club': `
  <div class="frame"><div class="pad">
    ${brand}
    <div class="grow"></div>
    <div class="h" style="font-size:112px">The Be The Man Club.</div>
    <div class="h" style="font-size:112px;color:${C.amber};margin-top:6px">$17 a month.</div>
    <div class="rule" style="margin:48px 0 48px"></div>
    <ul class="list">
      <li><span><b>All 11 tools in the store</b> — free the day you join</span></li>
      <li><span><b>Steps 1–7,</b> every worksheet, in order</span></li>
      <li><span><b>The monthly tool</b> — Club-only, not sold anywhere</span></li>
      <li><span><b>One email a week:</b> a time, a trigger, a way to tell if it held</span></li>
    </ul>
    <div class="serif" style="font-size:36px;margin-top:48px">No group chat. No badges. Cancel anytime — the files are yours to keep.</div>
    <div class="grow"></div>
    ${foot('Link in bio')}
  </div></div>`,
};

// ---------- Carousel: "When motivation runs out" (1080x1350, 6 slides) ----------
const N = 6;
const slide = (i, inner) => `<div class="frame"><div class="pad">
  <div style="display:flex;justify-content:space-between;align-items:center">${brand}${dots(N, i)}</div>
  ${inner}
  <div class="foot"><span>${i < N - 1 ? 'Swipe →' : TAG}</span><span class="h2">${HANDLE}</span></div>
</div></div>`;
const step = (i, n, title, text) => slide(i, `
  <div class="grow"></div>
  <div class="num">${n}</div>
  <div class="h" style="font-size:112px;margin-top:40px">${title}</div>
  <div class="rule" style="margin:48px 0 40px"></div>
  <div class="body">${text}</div>
  <div class="grow"></div>`);

const carousel = {
  'carousel-1-cover': slide(0, `
    <div class="grow"></div>
    <div class="label">Save this for Sunday</div>
    <div class="h" style="font-size:128px;margin-top:28px">How to stay<br>disciplined when<br><em>motivation<br>runs out.</em></div>
    <div class="rule" style="margin:52px 0 40px"></div>
    <div class="body">Stop adding goals. <b>Add a when.</b></div>
    <div class="grow"></div>`),
  'carousel-2': step(1, '01', 'Write the <em>when.</em>', 'Every decision gets a time and a place before the week starts. <b>“This week” is not a time.</b>'),
  'carousel-3': step(2, '02', 'Define the <em>miss.</em>', 'Write what counts as a miss in advance — so a bad week is <b>defined before, not argued about after.</b>'),
  'carousel-4': step(3, '03', 'Log it <em>that day.</em>', 'Fill it in on the day it happens. Sunday-night memory is <b>a story, not evidence.</b>'),
  'carousel-5': step(4, '04', 'Run the <em>wife test.</em>', 'Could the people in your house see it <b>without you announcing it?</b> If not, it didn’t hold.'),
  'carousel-6-cta': slide(5, `
    <div class="grow"></div>
    <div class="serif" style="font-size:52px;line-height:1.35">Missing once is not failure.<br>One bad day shouldn’t cost you a month.</div>
    <div class="rule" style="margin:52px 0 48px"></div>
    <div class="h" style="font-size:108px">Start with<br><em>Step 1.</em> It’s free.</div>
    <div style="margin-top:56px"><span class="cta">Comment “STEP1” →</span></div>
    <div class="grow"></div>`),
};

// ---------- Story (1080x1920) ----------
const stories = {
  'story-step-1': `
  <div class="frame"><div class="pad" style="inset:180px 96px 140px 96px">
    ${brand}
    <div style="height:140px"></div>
    <div class="label">Free · Step 1 of 7</div>
    <div class="h" style="font-size:150px;margin-top:32px">What type<br>of man do<br>you <em>want<br>to be?</em></div>
    <div class="rule" style="margin:60px 0 44px"></div>
    <div class="body" style="font-size:40px">The worksheet walks you through it — then one sentence that says who he is. <b>Your vision statement.</b></div>
    <div class="grow"></div>
    <div style="text-align:center;font-family:'Oswald';letter-spacing:.2em;text-transform:uppercase;color:${C.amber};font-size:32px">↓ Tap the link · it lands tonight ↓</div>
    <div style="height:260px;margin-top:28px"></div>
  </div></div>`,
};

// ---------- Highlight covers (1080x1920, icon sits in the centre circle) ----------
const hl = (word, glyph) => `
  <div class="frame" style="background:${C.ink}"><div style="position:absolute;inset:0;display:flex;align-items:center;justify-content:center">
    <div style="width:620px;height:620px;border-radius:50%;border:6px solid ${C.amber};display:flex;flex-direction:column;align-items:center;justify-content:center;gap:28px">
      <div style="font-family:'Oswald';font-weight:700;color:${C.amber};font-size:150px;line-height:1">${glyph}</div>
      <div style="font-family:'Oswald';font-weight:500;letter-spacing:.22em;color:${C.cream};font-size:58px;text-transform:uppercase">${word}</div>
    </div></div></div>`;
const highlights = {
  'highlight-start': hl('Start', '01'),
  'highlight-free': hl('Free', '→'),
  'highlight-system': hl('System', '■'),
  'highlight-home': hl('Home', '⌂'),
  'highlight-club': hl('Club', '$17'),
  'highlight-faith': hl('Faith', '✝'),
};

const jobs = [
  ...Object.entries(posts).map(([k, v]) => [k, v, W, H]),
  ...Object.entries(carousel).map(([k, v]) => [k, v, W, H]),
  ...Object.entries(stories).map(([k, v]) => [k, v, W, SH]),
  ...Object.entries(highlights).map(([k, v]) => [k, v, W, SH]),
];

const browser = await chromium.launch();
for (const [name, html, w, h] of jobs) {
  const file = join(here, `.render-${name}.html`);
  writeFileSync(file, `<!doctype html><html><head><meta charset="utf-8">${base(w, h)}</head><body>${html}</body></html>`);
  const page = await browser.newPage({ viewport: { width: w, height: h } });
  await page.goto('file://' + file);
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: join(OUT, `${name}.png`) });
  await page.close();
  execSync(`rm -f "${file}"`);
  console.log('rendered', name);
}
await browser.close();
