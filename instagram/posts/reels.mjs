// Renders the three faceless text Reels to out/reel-*.mp4 (1080x1920, 30fps, H.264 + silent AAC).
// Usage: node reels.mjs [name-filter]   (needs: pip install imageio-ffmpeg)
import { createRequire } from 'module';
import { execSync, spawn } from 'child_process';
import { writeFileSync, rmSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const require = createRequire(import.meta.url);
const { chromium } = require(join(execSync('npm root -g').toString().trim(), 'playwright'));
const FFMPEG = execSync(`python3 -c "import imageio_ffmpeg as i;print(i.get_ffmpeg_exe())"`).toString().trim();
const here = dirname(fileURLToPath(import.meta.url));
const FPS = 30;

// A scene is [start, end, html]. Elements with data-t="seconds" animate in at that time.
const endCard = (t) => `
  <div class="brand a" data-t="${t}"><i></i>Be The Man</div>
  <div class="h a" data-t="${t + 0.2}" style="font-size:118px;margin-top:40px">Break the cycle.<br>Build the system.<br><em>Be the man.</em></div>
  <div class="a" data-t="${t + 0.9}" style="margin-top:70px"><span class="cta">Free Step 1 → link in bio</span></div>
  <div class="small a" data-t="${t + 1.2}" style="margin-top:28px">@bethemansystem</div>`;

const reels = {
  'reel-1-weekly-review': { dur: 17, scenes: [
    [0, 3.2, `<div class="label a" data-t="0">Run your week like a business</div>
      <div class="h a" data-t="0.1" style="font-size:132px;margin-top:30px">Most men review their week <em>from memory.</em></div>`],
    [3.2, 6, `<div class="serif a" data-t="3.3" style="font-size:92px">Memory is a story.</div>
      <div class="h a" data-t="4.2" style="font-size:150px;margin-top:30px">Not <em>evidence.</em></div>`],
    [6, 8.4, `<div class="h a" data-t="6.1" style="font-size:140px">Sunday.<br>15 minutes.<br><em>A pen.</em></div>`],
    [8.4, 13.4, `<div class="label a" data-t="8.5">Three questions</div>
      <ol class="list">
        <li class="a" data-t="8.8"><b>01</b><span>What did I say I’d do — and <em>when?</em></span></li>
        <li class="a" data-t="10.0"><b>02</b><span>What actually happened?</span></li>
        <li class="a" data-t="11.2"><b>03</b><span>What counts as a <em>miss</em> next week?</span></li>
      </ol>`],
    [13.4, 17, endCard(13.5)],
  ]},
  'reel-2-5am': { dur: 17, scenes: [
    [0, 3, `<div class="h a" data-t="0" style="font-size:170px">5 AM isn’t <em>the secret.</em></div>`],
    [3, 6.2, `<div class="serif a" data-t="3.1" style="font-size:76px">Your morning keeps failing because</div>
      <div class="h a" data-t="4.1" style="font-size:132px;margin-top:30px">it gets decided <em>at 9 PM.</em></div>`],
    [6.2, 11.4, `<div class="label a" data-t="6.3">Tonight</div>
      <ul class="checks">
        <li class="a" data-t="6.6"><s></s><span>Phone out of the bedroom.</span></li>
        <li class="a" data-t="7.8"><s></s><span>Clothes laid out.</span></li>
        <li class="a" data-t="9.0"><s></s><span>Tomorrow’s one decision — written, <em>with a time.</em></span></li>
      </ul>`],
    [11.4, 14, `<div class="h a" data-t="11.5" style="font-size:140px">A goal says what.</div>
      <div class="h a" data-t="12.4" style="font-size:140px;margin-top:20px">A system says <em>when.</em></div>`],
    [14, 17, endCard(14.1)],
  ]},
  'reel-3-watching': { dur: 17, scenes: [
    [0, 3.2, `<div class="h a" data-t="0" style="font-size:150px">Your kids won’t do what you <em>say.</em></div>`],
    [3.2, 5.8, `<div class="h a" data-t="3.3" style="font-size:170px">They’ll do what you <em>do.</em></div>`],
    [5.8, 10.8, `<div class="serif a" data-t="5.9" style="font-size:72px">They’re watching how you handle</div>
      <ul class="big">
        <li class="a" data-t="6.8">the bad day.</li>
        <li class="a" data-t="7.8">the argument.</li>
        <li class="a" data-t="8.8"><em>the miss.</em></li>
      </ul>`],
    [10.8, 14, `<div class="h a" data-t="10.9" style="font-size:112px">Would your family be able to <em>tell</em></div>
      <div class="serif a" data-t="12" style="font-size:64px;margin-top:40px">— without you announcing it?</div>`],
    [14, 17, endCard(14.1)],
  ]},
};

const page = (r) => `<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="fonts.css"><style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:1080px;height:1920px;background:#0B0B0C;color:#F2EEE6;font-family:'Inter';-webkit-font-smoothing:antialiased;overflow:hidden}
#bg{position:absolute;inset:-60px;background:radial-gradient(80% 50% at 50% 45%, #2a1d0e 0%, #0B0B0C 70%)}
#grain{position:absolute;inset:0;opacity:.07;background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E")}
#bar{position:absolute;left:0;top:0;height:8px;background:#E18B1F}
.scene{position:absolute;left:96px;right:150px;top:0;bottom:0;display:flex;flex-direction:column;justify-content:center;padding:260px 0 420px}
.a{opacity:0}
.brand{display:flex;align-items:center;gap:18px;font-family:'Oswald';font-weight:500;letter-spacing:.32em;font-size:30px;text-transform:uppercase}
.brand i{width:56px;height:4px;background:#E18B1F;display:block}
.label{font-family:'Oswald';font-weight:500;letter-spacing:.24em;font-size:36px;color:#E18B1F;text-transform:uppercase}
.h{font-family:'Oswald';font-weight:700;text-transform:uppercase;line-height:.98}
em{font-style:normal;color:#E18B1F}
.serif{font-family:'Lora';font-style:italic;font-weight:500;color:#BFBCB6;line-height:1.25}
.small{font-size:30px;color:#8C877E}
.cta{display:inline-block;background:#E18B1F;color:#0B0B0C;font-family:'Oswald';font-weight:700;text-transform:uppercase;letter-spacing:.08em;font-size:46px;padding:28px 44px;border-radius:2px}
.list{list-style:none;margin-top:50px;display:flex;flex-direction:column;gap:54px}
.list li{display:flex;gap:34px;align-items:baseline;font-size:62px;font-weight:600;line-height:1.2}
.list b{font-family:'Oswald';color:#E18B1F;font-size:64px}
.checks{list-style:none;margin-top:50px;display:flex;flex-direction:column;gap:50px}
.checks li{display:flex;gap:34px;font-size:62px;font-weight:600;line-height:1.2}
.checks s{flex:0 0 54px;height:54px;border:5px solid #E18B1F;margin-top:6px;position:relative}
.checks s::after{content:"";position:absolute;left:12px;top:2px;width:16px;height:30px;border:solid #E18B1F;border-width:0 7px 7px 0;transform:rotate(45deg)}
.big{list-style:none;margin-top:40px;font-family:'Oswald';font-weight:700;text-transform:uppercase;font-size:130px;line-height:1.05}
</style></head><body>
<div id="bg"></div>
${r.scenes.map(([s, e, h], i) => `<div class="scene" id="s${i}" data-s="${s}" data-e="${e}">${h}</div>`).join('')}
<div id="grain"></div><div id="bar"></div>
<script>
const DUR=${r.dur};
const ease=x=>1-Math.pow(1-Math.min(Math.max(x,0),1),3);
window.render=t=>{
  document.getElementById('bar').style.width=(t/DUR*100)+'%';
  document.getElementById('bg').style.transform='scale('+(1+t*0.004)+')';
  document.querySelectorAll('.scene').forEach(sc=>{
    const s=+sc.dataset.s,e=+sc.dataset.e,last=e>=DUR;
    const vis=t>=s&&t<e;
    sc.style.display=vis?'flex':'none';
    if(!vis)return;
    const out=last?1:1-ease((t-(e-0.3))/0.3);
    sc.style.opacity=out;
    sc.querySelectorAll('.a').forEach(el=>{
      const p=ease((t-(+el.dataset.t))/0.45);
      el.style.opacity=p;el.style.transform='translateY('+((1-p)*50)+'px)';
    });
  });
};
</script></body></html>`;

const browser = await chromium.launch();
const only = process.argv[2];
for (const [name, r] of Object.entries(reels)) {
  if (only && !name.includes(only)) continue;
  const file = join(here, `.render-${name}.html`);
  writeFileSync(file, page(r));
  const p = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
  await p.goto('file://' + file);
  await p.evaluate(() => document.fonts.ready);
  const out = join(here, 'out', `${name}.mp4`);
  const ff = spawn(FFMPEG, ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-',
    '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo', '-shortest',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-preset', 'medium', '-crf', '18', '-r', String(FPS),
    '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  const frames = Math.round(r.dur * FPS);
  for (let f = 0; f < frames; f++) {
    await p.evaluate((t) => window.render(t), f / FPS);
    const buf = await p.screenshot({ type: 'jpeg', quality: 92 });
    if (!ff.stdin.write(buf)) await new Promise((res) => ff.stdin.once('drain', res));
  }
  ff.stdin.end();
  await new Promise((res, rej) => ff.on('close', (c) => (c === 0 ? res() : rej(new Error('ffmpeg ' + c)))));
  // cover frame: the hook, fully in
  await p.evaluate(() => window.render(2.4));
  await p.screenshot({ path: join(here, 'out', `${name}-cover.png`) });
  await p.close();
  rmSync(file);
  console.log('rendered', name);
}
await browser.close();
