// Renders the YouTube thumbnail for Step 2 (1280x720) in the same style as the Instagram posts.
// Usage: node youtube-thumb.mjs   (outputs to ./out/youtube-step-2-thumbnail.png)
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
const W = 1280, H = 720;

const html = `
<link rel="stylesheet" href="fonts.css">
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:${W}px;height:${H}px;background:${C.ink};color:${C.cream};font-family:'Inter',sans-serif;-webkit-font-smoothing:antialiased}
.frame{position:relative;width:${W}px;height:${H}px;overflow:hidden;background:radial-gradient(120% 90% at 50% 0%, #1b1a19 0%, ${C.ink} 60%)}
.pad{position:absolute;inset:56px 80px 48px 80px;display:flex;flex-direction:column}
.brand{display:flex;align-items:center;gap:16px;font-family:'Oswald';font-weight:500;letter-spacing:.32em;font-size:24px;text-transform:uppercase}
.brand i{display:block;width:44px;height:3px;background:${C.amber}}
.label{font-family:'Oswald';font-weight:500;letter-spacing:.24em;font-size:34px;color:${C.amber};text-transform:uppercase}
.h{font-family:'Oswald';font-weight:700;text-transform:uppercase;line-height:.98;color:${C.cream};font-size:150px}
.h em{font-style:normal;color:${C.amber}}
.rule{width:96px;height:4px;background:${C.amber};margin:34px 0 26px}
.serif{font-family:'Lora';font-style:italic;font-weight:500;color:${C.stone};font-size:36px}
.grow{flex:1}
.foot{display:flex;justify-content:space-between;font-size:22px;color:${C.mute}}
.foot b{color:${C.cream};font-weight:600}
</style>
<div class="frame"><div class="pad">
  <div class="brand"><i></i>Be The Man</div>
  <div class="grow"></div>
  <div class="label" style="margin-top:0">Step 2 of 7</div>
  <div class="h" style="margin-top:18px">What are<br>your <em>goals?</em></div>
  <div class="rule"></div>
  <div class="serif">A goal says what. A system says when.</div>
  <div class="grow"></div>
  <div class="foot"><span>Break the cycle. Build the system. Be the man.</span><b>@bethemansystem</b></div>
</div></div>`;

const file = join(here, '_yt-thumb.html');
writeFileSync(file, html);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: H } });
await page.goto('file://' + file);
await page.evaluate(() => document.fonts.ready);
await page.screenshot({ path: join(OUT, 'youtube-step-2-thumbnail.png') });
await browser.close();
import('fs').then(fs => fs.unlinkSync(file));
console.log('wrote out/youtube-step-2-thumbnail.png');
