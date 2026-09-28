// Renders reel-club-portal.html to an MP4 (1080x1920, 30 fps) with headless Chromium + ffmpeg.
// Usage: node reel.mjs [--yt]            -> out/reel-club-portal.mp4 (9:16) or out/youtube-club-portal.mp4 (16:9)
//        node reel.mjs [--yt] 1.5 12 30  -> PNG stills at those seconds (out/<name>-frame-<t>.png), for checking
import { createRequire } from 'module';
import { execSync, spawn } from 'child_process';
import { mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const require = createRequire(import.meta.url);
const { chromium } = require(join(execSync('npm root -g').toString().trim(), 'playwright'));
const here = dirname(fileURLToPath(import.meta.url));
const OUT = join(here, 'out');
mkdirSync(OUT, { recursive: true });
const FPS = 30;
const FFMPEG = process.env.FFMPEG || execSync(`python3 -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())"`).toString().trim();

const args = process.argv.slice(2);
const YT = args.includes('--yt');
const NAME = YT ? 'youtube-club-portal' : 'reel-club-portal';
const [W, H] = YT ? [1920, 1080] : [1080, 1920];
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: H } });
await page.goto('file://' + join(here, 'reel-club-portal.html') + (YT ? '#yt' : ''));
await page.evaluate(() => window.ready);
const total = await page.evaluate(() => TOTAL);

const stills = args.filter(a => a !== '--yt').map(Number);
if (stills.length) {
  for (const t of stills) {
    await page.evaluate(t => render(t), t);
    await page.screenshot({ path: join(OUT, `${NAME}-frame-${t}.png`) });
  }
} else {
  const out = join(OUT, NAME + '.mp4');
  const ff = spawn(FFMPEG, ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-preset', 'slow', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  const n = Math.round(total * FPS);
  for (let i = 0; i < n; i++) {
    await page.evaluate(t => render(t), i / FPS);
    const buf = await page.screenshot({ type: 'jpeg', quality: 95 });
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if (i % 150 === 0) console.log(`frame ${i}/${n}`);
  }
  ff.stdin.end();
  await new Promise(r => ff.on('close', r));
  console.log('wrote', out);
}
await browser.close();
