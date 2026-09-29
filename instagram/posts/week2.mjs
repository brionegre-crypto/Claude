// Week 2 (Oct 12–18) posts + carousel. Same styles as build.mjs.
// Usage: node week2.mjs   (outputs to ./out)
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


const posts = {
  'w2-06-one-sentence': `
  <div class="frame"><div class="pad">
    ${brand}
    <div class="grow"></div>
    <div class="label">Your vision statement</div>
    <div class="h" style="font-size:118px;margin-top:28px">If you can’t say who you’re becoming in <em>one sentence,</em></div>
    <div class="serif" style="font-size:56px;line-height:1.3;margin-top:44px">you’ll become whoever the week needs you to be.</div>
    <div class="rule" style="margin:52px 0 40px"></div>
    <div class="body">Step 1 ends in that sentence. <b>Every step after it gets checked against it.</b></div>
    <div class="grow"></div>
    ${foot('Step 1 is free · link in bio')}
  </div></div>`,

  'w2-07-pray-when': `
  <div class="frame" style="background:radial-gradient(120% 80% at 50% 0%, #1d1c1b 0%, ${C.coal} 65%)"><div class="pad">
    ${brand}
    <div class="grow"></div>
    <div class="serif" style="font-size:62px;line-height:1.3">Most men pray<br>when they remember.</div>
    <div class="h" style="font-size:150px;margin-top:48px">Pick the<br><em>when.</em></div>
    <div class="rule" style="margin:52px 0 44px"></div>
    <ul class="list">
      <li><span><b>A time.</b> Not “in the morning.” 6:10.</span></li>
      <li><span><b>A place.</b> The same chair, every day.</span></li>
      <li><span><b>A trigger.</b> Coffee poured → before the first sip.</span></li>
    </ul>
    <div class="grow"></div>
    ${foot()}
  </div></div>`,

  'w2-08-conviction': `
  <div class="frame"><div class="pad">
    ${brand}
    <div class="grow"></div>
    <div class="h" style="font-size:132px;color:#5c5954">You don’t need<br>more conviction.</div>
    <div class="h" style="font-size:132px;margin-top:36px">You need a<br><em>starting point.</em></div>
    <div class="rule" style="margin:56px 0 40px"></div>
    <div class="body">Not a bigger goal. Not another promise. <b>A first step everything after it gets built on.</b></div>
    <div class="grow"></div>
    ${foot('Step 1 is free · link in bio')}
  </div></div>`,
};

const N = 7;
const slide = (i, inner) => `<div class="frame"><div class="pad">
  <div style="display:flex;justify-content:space-between;align-items:center">${brand}${dots(N, i)}</div>
  ${inner}
  <div class="foot"><span>${i < N - 1 ? 'Swipe →' : TAG}</span><span class="h2">${HANDLE}</span></div>
</div></div>`;
const step = (i, n, title, text) => slide(i, `
  <div class="grow"></div>
  <div class="num">${n}</div>
  <div class="h" style="font-size:100px;margin-top:40px">${title}</div>
  <div class="rule" style="margin:48px 0 40px"></div>
  <div class="body">${text}</div>
  <div class="grow"></div>`);

const carousel = {
  'w2-carousel-1-cover': slide(0, `
    <div class="grow"></div>
    <div class="label">Grab a pen · save this</div>
    <div class="h" style="font-size:124px;margin-top:28px">Write your<br>vision statement<br><em>in 20 minutes.</em></div>
    <div class="rule" style="margin:52px 0 40px"></div>
    <div class="body">One question: <b>what type of man do you want to be?</b></div>
    <div class="grow"></div>`),
  'w2-carousel-2': step(1, '01', 'List his <em>attributes.</em>', 'Not a feeling. Words you could check. <b>Patient. Present. Honest when it costs him.</b>'),
  'w2-carousel-3': step(2, '02', 'Picture an ordinary <em>Tuesday.</em>', 'For each attribute: what does it look like at 6 PM, when you’re tired and the kids are loud? <b>Write that down.</b>'),
  'w2-carousel-4': step(3, '03', 'Would your house <em>know?</em>', 'How would your wife and kids see it — <b>without you telling them?</b> If they couldn’t, rewrite it.'),
  'w2-carousel-5': step(4, '04', 'One <em>sentence.</em>', 'Say who he is in one line. <b>That’s your vision statement.</b> Short enough to remember in the car.'),
  'w2-carousel-6': step(5, '05', 'Check every <em>decision</em> against it.', 'Every step after this one gets measured by that sentence. <b>If it doesn’t serve him, it doesn’t get your Tuesday.</b>'),
  'w2-carousel-7-cta': slide(6, `
    <div class="grow"></div>
    <div class="serif" style="font-size:52px;line-height:1.35">Want the worksheet that walks you through it?</div>
    <div class="rule" style="margin:52px 0 48px"></div>
    <div class="h" style="font-size:108px">Step 1 is<br><em>free.</em></div>
    <div style="margin-top:56px"><span class="cta">Comment “STEP1” →</span></div>
    <div class="grow"></div>`),
};

const jobs = [...Object.entries(posts), ...Object.entries(carousel)].map(([k, v]) => [k, v, W, H]);
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
