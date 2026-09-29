// Renders training.html + out/timeline.json + out/narration.wav into out/be-the-man-training.mp4.
// Only frames where something changes are rendered; static stretches are held with ffmpeg's concat demuxer.
// Usage: node render.mjs            (run python3 tts.py first)
//        node render.mjs --stills   (one PNG per slide, fully built, for checking)
import { createRequire } from 'module';
import { execSync } from 'child_process';
import { mkdirSync, readFileSync, writeFileSync, rmSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const require = createRequire(import.meta.url);
const { chromium } = require(join(execSync('npm root -g').toString().trim(), 'playwright'));
const here = dirname(fileURLToPath(import.meta.url));
const OUT = join(here, 'out');
const FPS = 30, BEAT_T = 0.45, SLIDE_T = 0.8;
const FFMPEG = process.env.FFMPEG || execSync(`python3 -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())"`).toString().trim();
const { total, slides } = JSON.parse(readFileSync(join(OUT, 'timeline.json')));

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
await page.goto('file://' + join(here, 'training.html'));
await page.evaluate(() => window.ready);

if (process.argv.includes('--stills')) {
  for (let si = 0; si < slides.length; si++) {
    await page.evaluate(([si]) => render(si, 99, 1, 1, null, si / 14), [si]);
    await page.screenshot({ path: join(OUT, `still-${String(si).padStart(2, '0')}.png`) });
  }
  await browser.close(); process.exit(0);
}

const FR = join(OUT, 'frames');
rmSync(FR, { recursive: true, force: true }); mkdirSync(FR, { recursive: true });
let n = 0; const list = [];
async function shot(args, dur) {
  await page.evaluate(a => render(...a), args);
  const f = join(FR, `${String(n++).padStart(5, '0')}.jpg`);
  await page.screenshot({ path: f, type: 'jpeg', quality: 92 });
  list.push(`file '${f}'\nduration ${dur.toFixed(4)}`);
}

// flatten beats into events
const ev = [];
slides.forEach((s, si) => s.beats.forEach((b, bi) => ev.push({ si, bi, t: b.start })));
await shot([0, -1, 1, 1, null, 0], ev[0].t);                       // opening hold before the first line
for (let k = 0; k < ev.length; k++) {
  const { si, bi, t } = ev[k];
  const next = k + 1 < ev.length ? ev[k + 1].t : total;
  const prog = t / total;
  const T = bi === 0 && si > 0 ? SLIDE_T : BEAT_T;
  const nf = Math.round(T * FPS);
  for (let i = 0; i < nf; i++) {
    const q = (i + 1) / nf;
    if (bi === 0 && si > 0) {
      const prev = { si: si - 1, opacity: Math.max(0, 1 - 2 * q) };
      const r = Math.max(0, 2 * q - 1);
      await shot([si, 0, r, r, prev, prog], 1 / FPS);
    } else {
      await shot([si, bi, q, 1, null, prog], 1 / FPS);
    }
  }
  await shot([si, bi, 1, 1, null, prog], Math.max(1 / FPS, next - t - T));
  if (k % 10 === 0) console.log(`event ${k + 1}/${ev.length}`);
}
list.push(list[list.length - 1].split('\n')[0]);                   // concat demuxer needs the last file repeated
writeFileSync(join(OUT, 'frames.txt'), list.join('\n') + '\n');
await browser.close();

const mp4 = join(OUT, 'be-the-man-training.mp4');
execSync(`"${FFMPEG}" -y -loglevel error -f concat -safe 0 -i "${join(OUT, 'frames.txt')}" -i "${join(OUT, 'narration.wav')}" ` +
  `-vf "fps=${FPS},format=yuv420p" -c:v libx264 -preset medium -crf 20 -tune stillimage -c:a aac -ar 44100 -ac 2 -b:a 160k -shortest -movflags +faststart "${mp4}"`, { stdio: 'inherit' });
console.log('wrote', mp4, `(${n} frames rendered)`);
