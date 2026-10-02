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
// ---------- 6-week group ad (Facebook + Instagram) ----------
const details = `
  <div style="display:flex;gap:0;border-top:2px solid #2b2a28;border-bottom:2px solid #2b2a28">
    ${[['When','Sundays · 7 PM CT'],['Where','Google Meet'],['Dates','Nov 15 – Dec 20']].map(([k,v],i)=>`
    <div style="flex:${[1.35,1,1.15][i]};padding:28px 0 28px ${i?'28px':'0'};${i?'border-left:2px solid #2b2a28':''}">
      <div class="label" style="font-size:22px">${k}</div>
      <div style="font-size:30px;color:${C.cream};font-weight:600;margin-top:10px;white-space:nowrap">${v}</div>
    </div>`).join('')}
  </div>`;

const price = `<div style="display:flex;align-items:baseline;gap:22px">
  <span style="font-family:'Oswald';font-size:44px;color:${C.mute};text-decoration:line-through">$297</span>
  <span style="font-family:'Oswald';font-weight:700;font-size:76px;color:${C.amber}">$147</span>
  <span style="font-size:26px;color:${C.stone};line-height:1.25">founding group<br>4 seats</span></div>`;

const ads = {
  'ad-6-week-group-feed': [W, H, `
  <div class="frame"><div class="pad">
    ${brand}
    <div class="grow"></div>
    <div class="label" style="font-size:24px">A 6-week live group for husbands &amp; fathers</div>
    <div class="h" style="font-size:100px;margin-top:22px">The promise<br>you keep making.<br><em>Six Sundays</em><br><em>to keep it.</em></div>
    <div style="margin:36px 0 30px">${details}</div>
    <div style="display:flex;justify-content:space-between;align-items:center">${price}<span class="cta" style="font-size:30px;padding:22px 32px">Reserve a seat →</span></div>
    <div class="grow"></div>
    ${foot('bethemansystem.com')}
  </div></div>`],
  'ad-6-week-group-story': [W, SH, `
  <div class="frame"><div class="pad" style="inset:180px 96px 300px 96px">
    ${brand}
    <div class="grow"></div>
    <div class="label" style="font-size:24px">A 6-week live group for husbands &amp; fathers</div>
    <div class="h" style="font-size:132px;margin-top:32px">The promise<br>you keep making.<br><em>Six Sundays</em><br><em>to keep it.</em></div>
    <div class="body" style="margin-top:44px">Four men. One step a week. A scorecard that shows what held.</div>
    <div style="margin:52px 0 44px">${details}</div>
    ${price}
    <div style="margin-top:52px"><span class="cta">Reserve a seat →</span></div>
    <div class="body" style="margin-top:28px;font-size:28px">bethemansystem.com</div>
    <div class="grow"></div>
  </div></div>`],
};

const browser = await chromium.launch();
const page = await browser.newPage();
for (const [name, [w, h, html]] of Object.entries(ads)) {
  await page.setViewportSize({ width: w, height: h });
  const file = join(here, `.tmp-${name}.html`);
  writeFileSync(file, base(w, h) + html);
  await page.goto('file://' + file);
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: join(OUT, name + '.png') });
  execSync(`rm -f "${file}"`);
  console.log('wrote', name);
}
await browser.close();
