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
      execFileSync('npx', ['--yes', 'hyperframes@0.8.181', 'tts', `assets/narr/${s.id}.txt`, '-v', 'am_adam', '-s', '1.0', '-o', out, '--json'], { env: { ...process.env, HYPERFRAMES_PYTHON: PY }, stdio: ['ignore', 'pipe', 'inherit'] });
    }
    const total = parseFloat(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', out]).toString());
    // sentence boundaries from the pauses in the voice: the longest S-1 internal gaps are the sentence ends
    
    
    dur[s.id] = { dur: total, sents: null };
    try {
      const r = require('child_process').spawnSync('ffmpeg', ['-v', 'info', '-i', out, '-af', 'silencedetect=noise=-38dB:d=0.14', '-f', 'null', '-'], { encoding: 'utf8' }).stderr;
      const st = [...r.matchAll(/silence_start: ([\d.]+)/g)].map((m) => +m[1]), en = [...r.matchAll(/silence_end: ([\d.]+)/g)].map((m) => +m[1]);
      const gaps = []; for (let i = 0; i < st.length; i++) gaps.push([st[i], en[i] != null ? en[i] : total]);
      const lead = gaps.length && gaps[0][0] < 0.05 ? gaps.shift() : null, trail = gaps.length && gaps[gaps.length - 1][1] >= total - 0.05 ? gaps.pop() : null;
      const t0 = lead ? lead[1] : 0, t1 = trail ? trail[0] : total;
      const hay = s.narr.toLowerCase(), sentences = []; const re = /[^.?!]+[.?!]+(\s+|$)/g; let m;
      while ((m = re.exec(hay))) sentences.push([m.index, m.index + m[0].trimEnd().length]);
      const S = sentences.length;
      if (S >= 1 && gaps.length >= S - 1) {
        const pick = [...gaps].sort((a, b) => (b[1] - b[0]) - (a[1] - a[0])).slice(0, S - 1).sort((a, b) => a[0] - b[0]);
        dur[s.id].sents = sentences.map((sn, k) => [sn[0], sn[1], k === 0 ? t0 : pick[k - 1][1], k === S - 1 ? t1 : pick[k][0]]);
      }
    } catch (e) { /* proportional timing is used */ }
    console.log(s.id, dur[s.id].dur.toFixed(2), dur[s.id].sents ? dur[s.id].sents.length + ' sentences anchored' : 'proportional');
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
