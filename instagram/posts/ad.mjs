// Renders the @bethemansystem paid ad creatives (Instagram + Facebook).
// Usage: node ad.mjs   (outputs to ./out)
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

const C = { ink: '#0B0B0C', amber: '#E18B1F', cream: '#F2EEE6', stone: '#BFBCB6', mute: '#8C877E' };

const base = (w, h) => `
<link rel="stylesheet" href="fonts.css">
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:${w}px;height:${h}px;background:${C.ink};color:${C.cream};font-family:'Inter',sans-serif;-webkit-font-smoothing:antialiased}
.frame{position:relative;width:${w}px;height:${h}px;overflow:hidden;background:radial-gradient(120% 80% at 50% 0%, #1b1a19 0%, ${C.ink} 60%)}
.pad{position:absolute;display:flex;flex-direction:column}
.brand{display:flex;align-items:center;gap:18px;font-family:'Oswald';font-weight:500;letter-spacing:.32em;font-size:26px;text-transform:uppercase}
.brand i{display:block;width:44px;height:3px;background:${C.amber}}
.h{font-family:'Oswald';font-weight:700;text-transform:uppercase;line-height:.98;color:${C.cream}}
.h em{font-style:normal;color:${C.amber}}
.serif{font-family:'Lora';font-style:italic;font-weight:500;color:${C.stone}}
.body{font-size:38px;line-height:1.4;color:${C.stone}}
.body b{color:${C.cream};font-weight:600}
.rule{width:96px;height:4px;background:${C.amber}}
.grow{flex:1}
.cta{display:inline-flex;background:${C.amber};color:${C.ink};font-family:'Oswald';font-weight:700;text-transform:uppercase;letter-spacing:.08em;font-size:40px;padding:28px 44px;border-radius:2px}
.handle{font-family:'Oswald';font-weight:500;letter-spacing:.12em;font-size:32px;color:${C.cream}}
</style>`;

const content = (hSize) => `
  <div class="brand"><i></i>Be The Man</div>
  <div class="grow"></div>
  <div class="serif" style="font-size:54px;line-height:1.35">New Year’s. Sunday morning.<br>The car after the argument.</div>
  <div class="h" style="font-size:${hSize}px;margin-top:44px">You meant it<br><em>every time.</em></div>
  <div class="rule" style="margin:44px 0 36px"></div>
  <div class="body">Discipline for husbands &amp; dads who’ve broken the promise before. <b>Follow for the system that holds.</b></div>
  <div style="margin-top:48px;display:flex;align-items:center;gap:28px"><span class="cta">Follow →</span><span class="handle">@bethemansystem</span></div>
  <div class="grow"></div>`;

const jobs = {
  // Feed (4:5): Instagram feed + Facebook feed
  'ad-feed-1080x1350': [1080, 1350, `<div class="frame"><div class="pad" style="inset:96px 96px 96px 96px">${content(150)}</div></div>`],
  // Stories/Reels (9:16): keep top ~250px and bottom ~340px free of text
  'ad-story-1080x1920': [1080, 1920, `<div class="frame"><div class="pad" style="inset:260px 90px 360px 90px">${content(140)}</div></div>`],
};

const browser = await chromium.launch();
for (const [name, [w, h, html]] of Object.entries(jobs)) {
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
