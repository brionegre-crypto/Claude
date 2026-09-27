// Renders the "receipt" email-list post to out/email-receipt.png
// Usage: node receipt.mjs
import { createRequire } from 'module';
import { execSync } from 'child_process';
import { writeFileSync, rmSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const require = createRequire(import.meta.url);
const { chromium } = require(join(execSync('npm root -g').toString().trim(), 'playwright'));
const here = dirname(fileURLToPath(import.meta.url));

const items = [
  ['1 × Email, every Thursday', '$0.00', ''],
  ['    A time, a trigger, a way', '', 'sub'],
  ['    to tell if it held', '', 'sub'],
  ['1 × Step 1 worksheet', '$0.00', ''],
  ['Replies reach a real man', '$0.00', ''],
];
const removed = ['Hype', 'Group chat', 'Guilt trip', 'Excuses'];

// barcode: deterministic widths
const bars = Array.from({ length: 58 }, (_, i) => [1, 3, 2, 1, 4, 1, 2, 3][(i * 7 + (i % 5)) % 8]);

const row = ([l, r, cls]) => `<div class="row ${cls}"><span>${l.replace(/ /g, '&nbsp;')}</span><span>${r}</span></div>`;

const html = `<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="fonts.css">
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:1080px;height:1350px;background:#0B0B0C;-webkit-font-smoothing:antialiased}
.f{position:relative;width:1080px;height:1350px;overflow:hidden;
  background:radial-gradient(70% 55% at 50% 55%, #2a1d0e 0%, #0B0B0C 72%)}
.f::after{content:"";position:absolute;inset:0;opacity:.07;pointer-events:none;
 background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E")}
.head{position:absolute;left:0;right:0;top:70px;text-align:center}
.head .k{font-family:'Oswald';font-weight:500;letter-spacing:.32em;font-size:24px;color:#E18B1F;text-transform:uppercase}
.head .h{font-family:'Oswald';font-weight:700;text-transform:uppercase;font-size:76px;line-height:1;color:#F2EEE6;margin-top:14px}
.head .h em{font-style:normal;color:#E18B1F}

.wrap{position:absolute;left:50%;top:262px;width:620px;transform:translateX(-50%) rotate(-2.2deg);
  filter:drop-shadow(0 40px 60px rgba(0,0,0,.6)) drop-shadow(0 0 60px rgba(225,139,31,.12))}
.r{position:relative;background:#F2EEE6;color:#1a1918;font-family:'IBM Plex Mono',monospace;font-size:20px;line-height:1.42;
  padding:36px 42px 30px;
  background-image:linear-gradient(180deg,rgba(0,0,0,0) 0%,rgba(0,0,0,.035) 100%),
    repeating-linear-gradient(0deg,rgba(0,0,0,.012) 0 2px,transparent 2px 5px);
  -webkit-mask:
    conic-gradient(from -45deg at bottom,#0000,#000 1deg 89deg,#0000 90deg) bottom/22px 51% repeat-x,
    conic-gradient(from 135deg at top,#0000,#000 1deg 89deg,#0000 90deg) top/22px 51% repeat-x;}
.c{text-align:center}
.logo{font-family:'Oswald';font-weight:700;font-size:40px;letter-spacing:.14em;text-transform:uppercase}
.small{font-size:17px;color:#5c5954}
.dash{border-top:2px dashed #9b968d;margin:13px 0}
.row{display:flex;justify-content:space-between;white-space:nowrap}
.row.sub{color:#6d6962;font-size:18px}
.x{display:flex;justify-content:space-between;color:#8a857c}
.x s{text-decoration-thickness:2px;text-decoration-color:#E18B1F}
.tot{display:flex;justify-content:space-between;font-weight:700;font-size:30px;margin-top:4px}
.stamp{position:absolute;right:-6px;top:34px;transform:rotate(-14deg);border:5px solid #E18B1F;color:#E18B1F;
  font-family:'Oswald';font-weight:700;font-size:34px;letter-spacing:.12em;padding:4px 16px;border-radius:6px;opacity:.9;text-transform:uppercase;
  mix-blend-mode:multiply}
.bars{display:flex;justify-content:center;align-items:stretch;height:52px;gap:3px;margin-top:6px}
.bars i{display:block;background:#1a1918}

.cta{position:absolute;left:0;right:0;bottom:58px;text-align:center}
.cta .b{display:inline-block;background:#E18B1F;color:#0B0B0C;font-family:'Oswald';font-weight:700;text-transform:uppercase;letter-spacing:.08em;font-size:34px;padding:22px 40px;border-radius:2px}
.cta .t{font-family:'Inter';font-size:22px;color:#8C877E;margin-top:18px}
.cta .t b{color:#F2EEE6;font-weight:600}
</style></head><body><div class="f">
  <div class="head">
    <div class="k">The weekly email</div>
    <div class="h">Here’s what it <em>costs.</em></div>
  </div>

  <div class="wrap"><div class="r">
    <div class="c logo">Be The Man</div>
    <div class="c small">Huntsville, AL · go.bethemansystem.com</div>
    <div class="c small">ORDER #0001 · THURSDAY</div>
    <div class="dash"></div>
    ${items.map(row).join('')}
    <div class="dash"></div>
    <div style="position:relative"><div class="small" style="margin-bottom:2px">NOT INCLUDED:</div>
    ${removed.map(r => `<div class="x"><s>${r}</s><span></span></div>`).join('')}<div class="stamp">Paid in full</div></div>
    <div class="dash"></div>
    <div class="tot"><span>TOTAL</span><span>$0.00</span></div>
    <div class="row small"><span>Card required</span><span>NO</span></div>
    <div class="row small"><span>To leave</span><span>1 CLICK</span></div>
    <div class="dash"></div>
    <div class="c" style="font-weight:600">Break the cycle.<br>Build the system. Be the man.</div>
    <div class="bars">${bars.map(w => `<i style="width:${w * 2}px"></i>`).join('')}</div>
    <div class="c small">THANK YOU · COME BACK THURSDAY</div>
  </div></div>

  <div class="cta">
    <div class="b">Join the email → link in bio</div>
    <div class="t"><b>Free. One email a week.</b> Comes with Step 1.</div>
  </div>
</div></body></html>`;

const file = join(here, '.render-receipt.html');
writeFileSync(file, html);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1080, height: 1350 } });
await page.goto('file://' + file);
await page.evaluate(() => document.fonts.ready);
await page.screenshot({ path: join(here, 'out', 'email-receipt.png') });
await browser.close();
rmSync(file);
console.log('rendered out/email-receipt.png');
