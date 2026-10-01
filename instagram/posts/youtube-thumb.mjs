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
.glow{position:absolute;right:-40px;top:40px;width:820px;height:820px;border-radius:50%;background:radial-gradient(closest-side, rgba(225,139,31,.7) 0%, rgba(225,139,31,.18) 55%, rgba(225,139,31,0) 100%)}
.man{position:absolute;right:-30px;bottom:-30px;height:760px;filter:drop-shadow(0 0 28px rgba(0,0,0,.55))}
.fade{position:absolute;inset:0;background:linear-gradient(90deg, rgba(11,11,12,.55) 0%, rgba(11,11,12,0) 48%)}
.pad{position:absolute;inset:56px 0 48px 80px;display:flex;flex-direction:column}
.brand{display:flex;align-items:center;gap:16px;font-family:'Oswald';font-weight:500;letter-spacing:.32em;font-size:24px;text-transform:uppercase}
.brand i{display:block;width:44px;height:3px;background:${C.amber}}
.label{font-family:'Oswald';font-weight:500;letter-spacing:.24em;font-size:34px;color:${C.amber};text-transform:uppercase}
.h{font-family:'Oswald';font-weight:700;text-transform:uppercase;line-height:.98;color:${C.cream};font-size:152px;text-shadow:0 4px 24px rgba(0,0,0,.5)}
.h em{font-style:normal;color:${C.amber}}
.rule{width:120px;height:6px;background:${C.amber};margin:34px 0 0}
.serif{font-family:'Lora';font-style:italic;font-weight:500;color:${C.stone};font-size:34px;line-height:1.25}
.grow{flex:1}
</style>
<div class="frame">
  <div class="glow"></div>
  <img class="man" src="photos/cut-thinking.png">
  <div class="fade"></div>
  <div class="pad">
    <div class="brand"><i></i>Be The Man</div>
    <div class="grow"></div>
    <div class="label">Step 2 of 7</div>
    <div class="h" style="margin-top:14px">What are<br>your<br><em>goals?</em></div>
    <div class="rule"></div>
    <div style="height:24px"></div>
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
