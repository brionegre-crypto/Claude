// Speaks every scene with the local Kokoro voice (am_michael), measures it, and writes durations.json.
// Then (phase 2, after durations exist) lays the voice on the timeline: assets/narration.wav + env.js (mouth-movement envelope per frame).
import { createRequire } from 'module';
import { execFileSync } from 'child_process';
import { existsSync, writeFileSync, readFileSync } from 'fs';
const require = createRequire(import.meta.url);
const phase = process.argv[2] || 'speak';
const PY = process.env.HYPERFRAMES_PYTHON || '/tmp/ttsenv/bin/python';
if (phase === 'speak') {
  const W = require('../script.js'), dur = {};
  for (const s of W.SCENES) {
    const out = `assets/narr/${s.id}.wav`;
    if (!existsSync(out)) {
      writeFileSync(`assets/narr/${s.id}.txt`, s.narr);
      execFileSync('npx', ['--yes', 'hyperframes@0.8.181', 'tts', `assets/narr/${s.id}.txt`, '-v', 'am_michael', '-s', '0.93', '-o', out, '--json'], { env: { ...process.env, HYPERFRAMES_PYTHON: PY }, stdio: ['ignore', 'pipe', 'inherit'] });
    }
    dur[s.id] = parseFloat(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', out]).toString());
    console.log(s.id, dur[s.id].toFixed(2));
  }
  writeFileSync('durations.json', JSON.stringify(dur, null, 1));
  writeFileSync('durations.js', 'window.WT_DURS=' + JSON.stringify(dur) + ';');
} else {
  const W = require('../script.js'), SR = 48000, N = Math.ceil(W.DUR * SR), buf = new Float32Array(N);
  for (const s of W.SCENES) {
    const raw = execFileSync('ffmpeg', ['-v', 'error', '-i', `assets/narr/${s.id}.wav`, '-ac', '1', '-ar', String(SR), '-f', 'f32le', '-'], { maxBuffer: 1 << 29 });
    const f = new Float32Array(raw.buffer, raw.byteOffset, raw.length / 4), i0 = Math.round(s.t0 * SR);
    for (let i = 0; i < f.length && i0 + i < N; i++) buf[i0 + i] += f[i];
  }
  let pk = 0; for (let i = 0; i < N; i++) pk = Math.max(pk, Math.abs(buf[i]));
  const g = 0.85 / (pk || 1); for (let i = 0; i < N; i++) buf[i] *= g;
  writeFileSync('assets/narration.f32', Buffer.from(buf.buffer));
  // mouth envelope: smoothed RMS per 60 fps frame, 0..255
  const F = Math.ceil(W.DUR * 60), env = new Array(F).fill(0), win = SR / 60;
  for (let k = 0; k < F; k++) { let a = 0, c = 0; for (let i = Math.floor((k - 0.5) * win); i < Math.floor((k + 1.5) * win); i++) if (i >= 0 && i < N) { a += buf[i] * buf[i]; c++; } env[k] = Math.sqrt(a / (c || 1)); }
  const m = Math.max(...env) || 1; let y = 0; const sm = env.map((v) => { y += (Math.min(1, v / (m * 0.55)) - y) * 0.45; return Math.round(y * 255); });
  writeFileSync('env.js', 'window.WT_ENV=' + JSON.stringify(sm) + ';');
  console.log('narration laid on timeline, frames', F);
}
