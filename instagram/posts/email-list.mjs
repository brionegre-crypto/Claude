// Renders the "join the email list" post (lock-screen concept) to out/email-list.png
// Usage: node email-list.mjs
import { createRequire } from 'module';
import { execSync } from 'child_process';
import { writeFileSync, rmSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const require = createRequire(import.meta.url);
const { chromium } = require(join(execSync('npm root -g').toString().trim(), 'playwright'));
const here = dirname(fileURLToPath(import.meta.url));

const junk = [
  ['SHOP', 'FLASH SALE 🔥 48 hours only', 'Everything must go. Don’t miss out.', 'now'],
  ['NEWS', 'Breaking: you won’t believe what…', 'Tap to read the full story', '2m'],
  ['GURU', '10x your mornings with this 1 hack', 'Limited seats in the masterclass', '9m'],
  ['CART', 'Your cart misses you 🛒', 'Complete your order before it’s gone', '14m'],
];

const html = `<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="fonts.css">
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:1080px;height:1350px;background:#0B0B0C;font-family:'Inter',sans-serif;-webkit-font-smoothing:antialiased;color:#F2EEE6}
.f{position:relative;width:1080px;height:1350px;overflow:hidden;background:radial-gradient(90% 60% at 50% 62%, #2a1d0e 0%, #0B0B0C 70%)}
.f::after{content:"";position:absolute;inset:0;opacity:.07;pointer-events:none;
 background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E")}
.top{position:absolute;left:96px;right:96px;top:84px}
.brand{display:flex;align-items:center;gap:18px;font-family:'Oswald';font-weight:500;letter-spacing:.32em;font-size:24px;text-transform:uppercase}
.brand i{width:44px;height:3px;background:#E18B1F;display:block}
.pre{font-family:'Lora';font-style:italic;font-weight:500;color:#BFBCB6;font-size:50px;margin-top:56px;line-height:1.2}
.h{font-family:'Oswald';font-weight:700;text-transform:uppercase;font-size:112px;line-height:.98;margin-top:14px}
.h em{font-style:normal;color:#E18B1F}
.stack{position:absolute;left:96px;right:96px;top:560px}
.clock{font-family:'Inter';font-weight:300;text-align:center;color:#F2EEE6;opacity:.18;font-size:26px;letter-spacing:.3em;margin-bottom:22px}
.n{display:flex;gap:22px;align-items:center;padding:20px 26px;border-radius:26px;margin-bottom:12px;
   background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.06);filter:blur(1.2px) grayscale(1);opacity:.42}
.n .ic{flex:0 0 58px;height:58px;border-radius:14px;background:#3a3936;display:flex;align-items:center;justify-content:center;
   font-family:'Oswald';font-size:15px;letter-spacing:.08em;color:#8C877E}
.n .t{flex:1;min-width:0}
.n .a{display:flex;justify-content:space-between;font-size:22px;color:#BFBCB6}
.n .a b{font-weight:600;color:#F2EEE6}
.n .s{font-size:21px;color:#8C877E;margin-top:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.n.d1{transform:scale(.97);opacity:.32}.n.d2{transform:scale(.95);opacity:.24}.n.d3{transform:scale(.93);opacity:.16}
.hero{position:relative;display:flex;gap:26px;padding:30px 32px;border-radius:30px;margin:-4px -14px 0;
   background:linear-gradient(180deg,#1d1a16,#141312);border:2px solid #E18B1F;
   box-shadow:0 0 0 8px rgba(225,139,31,.08),0 30px 80px rgba(225,139,31,.22)}
.hero .ic{flex:0 0 76px;height:76px;border-radius:18px;background:#E18B1F;color:#0B0B0C;display:flex;align-items:center;justify-content:center;
   font-family:'Oswald';font-weight:700;font-size:28px;letter-spacing:.02em}
.hero .a{display:flex;justify-content:space-between;align-items:baseline;font-family:'Oswald';font-weight:500;letter-spacing:.18em;font-size:22px;color:#E18B1F;text-transform:uppercase}
.hero .a span{letter-spacing:.06em;color:#8C877E;font-family:'Inter';font-weight:500;text-transform:none;font-size:20px}
.hero .tt{font-weight:700;font-size:34px;margin-top:8px;color:#F2EEE6;line-height:1.2}
.hero .s{font-size:25px;line-height:1.45;color:#BFBCB6;margin-top:10px}
.bot{position:absolute;left:96px;right:96px;bottom:84px;display:flex;justify-content:space-between;align-items:flex-end}
.cta{background:#E18B1F;color:#0B0B0C;font-family:'Oswald';font-weight:700;text-transform:uppercase;letter-spacing:.08em;font-size:34px;padding:24px 36px;border-radius:2px}
.fine{font-size:22px;color:#8C877E;text-align:right;line-height:1.5}
.fine b{color:#F2EEE6;font-weight:600}
</style></head><body><div class="f">
  <div class="top">
    <div class="brand"><i></i>Be The Man</div>
    <div class="pre">Every other email wants your money.</div>
    <div class="h">This one wants<br>your <em>Tuesday.</em></div>
  </div>
  <div class="stack">
    <div class="clock">THURSDAY</div>
    <div class="hero">
      <div class="ic">BTM</div>
      <div style="flex:1">
        <div class="a">Be The Man <span>now</span></div>
        <div class="tt">This week: one decision, with a time attached.</div>
        <div class="s">Not a devotional. Not a pep talk. When, where, what trigger — and how you’d know it held.</div>
      </div>
    </div>
    <div style="height:18px"></div>
    <div style="height:230px;overflow:hidden;-webkit-mask-image:linear-gradient(#000 20%,transparent 95%)">${junk.map(([ic, t, s, m], i) => `<div class="n d${i}"><div class="ic">${ic}</div><div class="t"><div class="a"><b>${t}</b><span>${m}</span></div><div class="s">${s}</div></div></div>`).join('')}</div>
  </div>
  <div class="bot">
    <div class="cta">Get Thursday’s email →</div>
    <div class="fine"><b>Free. One email a week.</b><br>No card. Leave in one click.<br>Link in bio · @bethemansystem</div>
  </div>
</div></body></html>`;

const file = join(here, '.render-email-list.html');
writeFileSync(file, html);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1080, height: 1350 } });
await page.goto('file://' + file);
await page.evaluate(() => document.fonts.ready);
await page.screenshot({ path: join(here, 'out', 'email-list.png') });
await browser.close();
rmSync(file);
console.log('rendered out/email-list.png');
