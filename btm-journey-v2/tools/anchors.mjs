// Second pass for scenes whose sentence pauses were too short to detect: retry with a lower threshold / shorter pause.
import { createRequire } from 'module';
import { readFileSync, writeFileSync } from 'fs';
import { spawnSync } from 'child_process';
const require = createRequire(import.meta.url);
const W = require('../script.js'), dur = JSON.parse(readFileSync('durations.json', 'utf8'));
for (const s of W.SCENES) {
  if (dur[s.id].sents) continue;
  const out = `assets/narr/${s.id}.wav`, total = dur[s.id].dur, hay = s.narr.toLowerCase(), sentences = []; const re = /[^.?!]+[.?!]+(\s+|$)/g; let m;
  while ((m = re.exec(hay))) sentences.push([m.index, m.index + m[0].trimEnd().length]);
  const S = sentences.length;
  for (const [noise, d] of [['-36dB', 0.1], ['-34dB', 0.08], ['-32dB', 0.06], ['-30dB', 0.05]]) {
    const r = spawnSync('ffmpeg', ['-v', 'info', '-i', out, '-af', `silencedetect=noise=${noise}:d=${d}`, '-f', 'null', '-'], { encoding: 'utf8' }).stderr;
    const st = [...r.matchAll(/silence_start: ([\d.]+)/g)].map((x) => +x[1]), en = [...r.matchAll(/silence_end: ([\d.]+)/g)].map((x) => +x[1]);
    const gaps = []; for (let i = 0; i < st.length; i++) gaps.push([st[i], en[i] != null ? en[i] : total]);
    const lead = gaps.length && gaps[0][0] < 0.05 ? gaps.shift() : null, trail = gaps.length && gaps[gaps.length - 1][1] >= total - 0.05 ? gaps.pop() : null;
    if (gaps.length < S - 1) continue;
    const t0 = lead ? lead[1] : 0, t1 = trail ? trail[0] : total, pick = [...gaps].sort((a, b) => (b[1] - b[0]) - (a[1] - a[0])).slice(0, S - 1).sort((a, b) => a[0] - b[0]);
    dur[s.id].sents = sentences.map((sn, k) => [sn[0], sn[1], k === 0 ? t0 : pick[k - 1][1], k === S - 1 ? t1 : pick[k][0]]);
    console.log(s.id, 'anchored with', noise, d, S, 'sentences'); break;
  }
  if (!dur[s.id].sents) console.log(s.id, 'still proportional');
}
writeFileSync('durations.json', JSON.stringify(dur, null, 1)); writeFileSync('durations.js', 'window.WT_DURS=' + JSON.stringify(dur) + ';');
