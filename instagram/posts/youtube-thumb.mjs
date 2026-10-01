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
.glow{position:absolute;right:-60px;top:-40px;width:900px;height:900px;border-radius:50%;background:radial-gradient(closest-side, rgba(225,139,31,.85) 0%, rgba(225,139,31,.30) 55%, rgba(225,139,31,0) 100%)}
.man{position:absolute;right:-70px;bottom:-80px;height:840px;filter:brightness(1.1) contrast(1.08) saturate(1.1) drop-shadow(0 0 3px rgba(225,139,31,.9)) drop-shadow(0 0 30px rgba(0,0,0,.6))}
.fade{position:absolute;inset:0;background:linear-gradient(90deg, rgba(11,11,12,.7) 0%, rgba(11,11,12,0) 50%)}
.pad{position:absolute;left:64px;top:44px;bottom:36px;display:flex;flex-direction:column}
.brand{display:flex;align-items:center;gap:14px;font-family:'Oswald';font-weight:500;letter-spacing:.3em;font-size:22px;text-transform:uppercase}
.brand i{display:block;width:40px;height:3px;background:${C.amber}}
.row{display:flex;align-items:center;gap:22px;margin-top:34px}
.pill{font-family:'Oswald';font-weight:700;letter-spacing:.14em;font-size:38px;background:${C.amber};color:${C.ink};padding:6px 20px;text-transform:uppercase}
.h{font-family:'Oswald';font-weight:700;text-transform:uppercase;line-height:.9;text-shadow:0 6px 28px rgba(0,0,0,.6)}
.why{font-size:130px;color:${C.cream}}
.big{font-size:240px;color:${C.cream}}
.fail{font-size:240px;color:${C.amber}}
</style>
<div class="frame">
  <div class="glow"></div>
  <img class="man" src="photos/cut-thinking.png">
  <div class="fade"></div>
  <div class="pad">
    <div class="brand"><i></i>Be The Man</div>
    <div class="row"><div class="h why">Why</div><div class="pill">Step 2</div></div>
    <div class="h big" style="margin-top:6px">Goals</div>
    <div class="h fail">Fail</div>
  </div>
</div>`;

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
