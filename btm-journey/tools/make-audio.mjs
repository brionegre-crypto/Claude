// Music, sound effects and the narration, mixed in code.  node tools/make-audio.mjs <out.wav>
// Reads the same model as the picture (script.js, sting.js); the narration is assets/narration.f32 (laid on the timeline by narrate.mjs laid).
import { createRequire } from 'module';
import { writeFileSync, readFileSync } from 'fs';
const require = createRequire(import.meta.url);
const W = require('../script.js');
const M = require('../sting.js');
const out = process.argv[2] || 'assets/walkthrough-audio.wav';
const SR = 48000, DUR = W.DUR, N = Math.ceil(SR * DUR), BEAT = 0.6;
const sc = M.create('orbit', { targetW: 1500, comp0: 0.05 });
let seed = 29;
const rnd = () => { seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const noise = () => rnd() * 2 - 1;
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const onePole = (fc) => { let y = 0; const a = 1 - Math.exp(-2 * Math.PI * fc / SR); return (x) => (y += a * (x - y)); };
function svf() { let s1 = 0, s2 = 0; return (x, fc, q) => { const g = Math.tan(Math.PI * Math.min(fc, SR * 0.45) / SR), k = 1 / q, a1 = 1 / (1 + g * (g + k)), a2 = g * a1, a3 = g * a2, v3 = x - s2, v1 = a1 * s1 + a2 * v3, v2 = s2 + a2 * s1 + a3 * v3; s1 = 2 * v1 - s1; s2 = 2 * v2 - s2; return { lp: v2, bp: v1, hp: x - k * v1 - v2 }; }; }
const L = new Float32Array(N), R = new Float32Array(N), VO = new Float32Array(N);
const pan2 = (p) => [Math.cos((p + 1) * Math.PI / 4) * 1.4142, Math.sin((p + 1) * Math.PI / 4) * 1.4142];
const add = (i, v, p = 0) => { if (i < 0 || i >= N) return; const [l, r] = pan2(p); L[i] += v * l; R[i] += v * r; };
const idx = (t) => Math.round(t * SR);
const hz = (m) => 440 * Math.pow(2, (m - 69) / 12);

/* the voice, and how loud it is (the music ducks under it) */
{ const raw = readFileSync('assets/narration.f32'); const f = new Float32Array(raw.buffer, raw.byteOffset, raw.length / 4); for (let i = 0; i < N && i < f.length; i++) VO[i] = f[i]; }
const duck = new Float32Array(N); { const a = onePole(5), r = onePole(1.6); let y = 0; for (let i = 0; i < N; i++) { const v = Math.min(1, Math.abs(VO[i]) * 5); y = v > y ? y + (v - y) * 0.02 : y + (v - y) * 0.00035; duck[i] = y; } }

/* 1. music: warm and low, 100 BPM, a bar of each chord (2.4 s); it comes up between scenes and sits under the voice */
const CH = [[38, 45, 53, 57, 64], [34, 41, 50, 57, 62], [43, 50, 53, 58, 62], [45, 52, 55, 60, 64]];
const bars = Math.ceil(DUR / (4 * BEAT));
{
  const lp = svf(), lp2 = svf(), padL = new Float32Array(N), padR = new Float32Array(N);
  for (let b = 0; b < bars; b++) {
    const t0 = b * 4 * BEAT, chord = CH[b % 4], last = t0 + 4 * BEAT + 1.0;
    for (let n = 0; n < chord.length; n++) for (const det of [-0.08, 0.08]) {
      const f = hz(chord[n] + 12) * Math.pow(2, det / 12), ph = rnd() * 6.28, i0 = idx(t0), i1 = Math.min(N, idx(last));
      for (let i = i0; i < i1; i++) { const t = (i - i0) / SR, env = (1 - Math.exp(-t / 0.7)) * Math.exp(-Math.max(0, t - 4 * BEAT) / 0.4); const s = (Math.sin(2 * Math.PI * f * i / SR + ph) + 0.3 * Math.sin(4 * Math.PI * f * i / SR + ph * 2)) * env * 0.034; padL[i] += s * (0.8 + 0.2 * (n % 2)); padR[i] += s * (0.8 + 0.2 * ((n + 1) % 2)); }
    }
  }
  for (let i = 0; i < N; i++) { const g = 1 - 0.62 * duck[i]; L[i] += lp(padL[i], 650, 0.7).lp * g; R[i] += lp2(padR[i], 650, 0.7).lp * g; }
}
function bass(t, note, len = 1.3, amp = 0.15) { const f = hz(note), i0 = idx(t); for (let n = 0; n < SR * len; n++) { const tt = n / SR, env = (1 - Math.exp(-tt / 0.014)) * Math.exp(-tt / (len * 0.4)); add(i0 + n, (Math.sin(2 * Math.PI * f * tt) + 0.25 * Math.sin(4 * Math.PI * f * tt)) * env * amp * (1 - 0.6 * duck[Math.min(N - 1, i0 + n)]), 0); } }
for (let b = 0; b < bars; b++) { const t = b * 4 * BEAT; if (t > 1 && t < DUR - 6) bass(t, CH[b % 4][0], 1.5, 0.13); }
function pluck(t, note, amp = 0.05, p = 0) { const f = hz(note), i0 = idx(t); for (let n = 0; n < SR * 0.9; n++) { const tt = n / SR, env = Math.exp(-tt / 0.22) * (1 - Math.exp(-tt / 0.003)); add(i0 + n, (Math.sin(2 * Math.PI * f * tt) + 0.3 * Math.sin(6 * Math.PI * f * tt) * Math.exp(-tt / 0.05)) * env * amp * (1 - 0.7 * duck[Math.min(N - 1, i0 + n)]), p); } }
const PAT = [1, 0, 0, 1, 0, 1, 0, 0];
for (let b = 0; b < bars; b++) for (let e = 0; e < 8; e++) { const t = b * 4 * BEAT + e * BEAT / 2; if (t < 3 || t > W.T.morphA - 1 || !PAT[e]) continue; pluck(t, CH[b % 4][1 + ((b * 3 + e) % 4)] + 12 + (e % 2 ? 12 : 0), 0.05, ((b + e) % 2 ? 0.3 : -0.3)); }
{ const lp = svf(); for (let i = 0; i < N; i++) { const t = i / SR; add(i, lp(noise(), 380, 0.6).lp * 0.04 * (1 - clamp((t - W.T.morphB) / 2) * 0.7), 0); } }   // the room

/* 2. the screen: a page turn between scenes, a soft tick as every line lands */
const bpF = svf();
function key(t, amp = 1, p = 0) { const i0 = idx(t), f = 170 + rnd() * 70, c = 2400 + rnd() * 900; for (let n = 0; n < SR * 0.05; n++) { const tt = n / SR; add(i0 + n, (bpF(noise(), c, 1.6).bp * Math.exp(-tt / 0.004) * 0.16 + Math.sin(2 * Math.PI * f * tt) * Math.exp(-tt / 0.018) * 0.10) * amp, p); } }
function bell(t, f, amp = 0.08, p = 0) { const i0 = idx(t); for (let n = 0; n < SR * 1.4; n++) { const tt = n / SR; add(i0 + n, (Math.sin(2 * Math.PI * f * tt) + 0.35 * Math.sin(2 * Math.PI * f * 2.76 * tt) * Math.exp(-tt / 0.1)) * Math.exp(-tt / 0.4) * (1 - Math.exp(-tt / 0.002)) * amp, p); } }
function boom(t, f0 = 56, len = 1.2, amp = 0.26) { const i0 = idx(t); for (let n = 0; n < SR * len; n++) { const tt = n / SR, f = f0 * (1 + 0.5 * Math.exp(-tt / 0.07)); add(i0 + n, Math.sin(2 * Math.PI * f * tt) * Math.exp(-tt / (len * 0.3)) * (1 - Math.exp(-tt / 0.004)) * amp, 0); } }
function whoosh(t0, len = 0.8, amp = 0.1) { const bp = svf(), i0 = idx(t0), i1 = idx(t0 + len); for (let i = i0; i < i1; i++) { const u = (i - i0) / (i1 - i0); add(i, bp(noise(), 300 + 2600 * Math.sin(Math.PI * u) , 0.9).bp * Math.sin(Math.PI * u) * amp, 0.5 * (u - 0.5)); } }
const NOTES = [523, 587, 659, 740, 784, 880, 988];
W.SCENES.forEach((s, si) => {
  if (s.page.length === 0) return;
  whoosh(s.t0 - 0.5, 0.85, 0.1);
  let ni = 0;
  const pat = (t, big) => { const tt = W.snap(t); if (big) { bell(tt + 0.02, NOTES[ni++ % 7] * (si % 2 ? 1 : 0.5), 0.07, -0.25 + 0.5 * ((ni % 5) / 4)); } else key(tt, 0.35, -0.2); };
  s.page.forEach((b) => {
    const bc = W.cueTime(s, b.cue, s.t0 + 0.5), cues = [], bellish = ['route', 'kpis', 'cards', 'stat', 'map', 'stairs'].includes(b.t);
    (b.items || []).forEach((it, i) => cues.push(W.cueTime(s, it.cue || (b.cues && b.cues[i]), bc + i * 0.5)));
    (b.rows || []).forEach((r, i) => cues.push(W.cueTime(s, r.cue, bc + i * 0.5)));
    (b.lines || []).forEach((r, i) => cues.push(W.cueTime(s, r.cue, bc + i * 0.8)));
    (b.labels || []).forEach((r, i) => cues.push(W.cueTime(s, r.cue, bc + i)));
    if (b.t === 'hero' || b.t === 'text' || b.t === 'cta' || !cues.length) { pat(bc, 0); if (b.t === 'hero') { pat(bc + 0.25, 0); pat(bc + 0.75, 0); } }
    cues.forEach((c) => pat(c, bellish ? 1 : 0));
    if (b.t === 'stat') bell(W.snap(bc + 0.9), 392, 0.07, 0.3);
    if (b.t === 'cycle') { const bt = W.cueTime(s, b.breakCue, bc + 10); whoosh(bt - 0.4, 1.4, 0.13); }
    if (b.t === 'week') { const tA = W.cueTime(s, b.sweepA, bc + 4), tB = W.cueTime(s, b.sweepB, bc + 12); for (let d = 0; d < 7; d++) key(W.snap(tA + d * (tB - tA) / 7 + 0.1), 0.28, -0.4 + d * 0.13); }
  });
});
/* 3. the logo, as in the other films: the thread draws it, a click closes the loop, a low note holds under it */
boom(W.T.morphB, 52, 1.4, 0.28);
{
  const bpA = svf(), bpB = svf(), bpC = svf(), lpS = svf(), sm = onePole(40), smT = onePole(30), gLP = onePole(260), g2 = onePole(1400);
  const sp = W.STING.speed, i0 = idx(W.STING.tf0), i1 = Math.min(N, idx(DUR - 0.4));
  for (let i = i0; i < i1; i++) {
    const tf = i / SR, ts = W.tsOf(tf);
    const v = ts > M.T.go && ts < M.T.close + 0.05 ? sc.headV(ts) * sp : 0, ink = clamp((sc.headS(ts) - sc.Lsw) / 160);
    const tv = ts > M.T.tailA && ts < M.T.tailB ? Math.abs(sc.tailV(ts)) * sp : 0;
    const lv = sm(1 - Math.exp(-v / 2600)), lvT = smT(1 - Math.exp(-tv / 3000));
    if (lv < 1e-4 && lvT < 1e-4) continue;
    const nz = noise(), air = bpA(nz, 520 + 1500 * lv, 0.8).bp * 0.30 + lpS(nz, 260, 0.7).lp * 0.55;
    const g = 0.45 + 0.55 * Math.min(1, Math.abs(gLP(noise()) * 9)), pen = bpB(nz, 2300 + 1100 * lv, 1.6).bp * g * 0.55 + g2(nz) * 0.12 * g;
    add(i, ((1 - ink) * air * 1.05 + ink * pen * 0.30) * lv * 0.5 + bpC(noise(), 1500 + 2600 * lvT, 2.4).bp * lvT * 0.12, clamp((sc.penPos(ts).x - 960) / 1800, -0.5, 0.5));
  }
  { const ii = idx(W.STING.closeFilm), bp = svf(); for (let n = 0; n < SR * 0.25; n++) { const tt = n / SR; add(ii + n, bp(noise(), 3200, 1.1).bp * Math.exp(-tt / 0.0045) * 0.20 + Math.sin(2 * Math.PI * 1780 * tt) * Math.exp(-tt / 0.014) * 0.07 + Math.sin(2 * Math.PI * (150 - 40 * Math.min(1, tt / 0.05)) * tt) * Math.exp(-tt / 0.05) * 0.24, 0); } }
  sc.jumpSegs.forEach((j, k) => { const t = W.snap(W.tfOf(sc.relEnd(j))), ii = idx(t), bp = svf(); for (let n = 0; n < SR * 0.05; n++) { const tt = n / SR; add(ii + n, bp(noise(), 2600 + 120 * k, 1.5).bp * Math.exp(-tt / 0.006) * (0.05 + (k === 7 ? 0.03 : 0)), 0.1); } });
  { const ii = idx(W.snap(W.tfOf(M.T.note))), lp = svf(); for (let n = 0; ii + n < N; n++) { const t = n / SR, att = 1 - Math.exp(-t / 0.08), dec = Math.exp(-t / 1.1), end = 1 - clamp((t - (DUR - W.tfOf(M.T.note) - 0.5)) / 0.5); let s = 0; for (const [m, a, d] of [[1, 1, 0], [1, 0.55, 0.9], [2, 0.3, 0.4], [3, 0.1, -0.3], [0.5, 0.4, 0]]) s += Math.sin(2 * Math.PI * (98 * m + d) * t) * a; add(ii + n, lp(s, 620, 0.7).lp * att * (0.3 + 0.7 * dec) * Math.sin(Math.PI / 2 * end) * 0.28, 0); } }
  const t0 = W.tfOf(M.T.tagA), t1 = W.tfOf(M.T.tagB);
  for (let k = 0; k < 14; k++) key(W.snap(t0 + (t1 - t0) * k / 13), 0.45, 0);
  for (let k = 0; k < 14; k++) key(W.snap(t1 + 0.05 + 1.3 * k / 13), 0.3, 0);
}

/* master: the voice on top (a little warm, centred), everything normalised */
{ const hp = svf(), lpv = svf(); for (let i = 0; i < N; i++) { const v = VO[i]; const hv = hp(v, 85, 0.7).hp; const w = hv * 0.95 + lpv(hv, 3200, 0.7).lp * 0.12; L[i] += w; R[i] += w; } }
let pk = 0; for (let i = 0; i < N; i++) pk = Math.max(pk, Math.abs(L[i]), Math.abs(R[i]));
const g = 0.708 / (pk || 1), buf = Buffer.alloc(44 + N * 4);
buf.write('RIFF', 0); buf.writeUInt32LE(36 + N * 4, 4); buf.write('WAVEfmt ', 8); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22);
buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36); buf.writeUInt32LE(N * 4, 40);
const fadeOut = (i) => 1 - clamp((i / SR - (DUR - 0.45)) / 0.45), fadeIn = (i) => clamp(i / SR / 0.6);
for (let i = 0; i < N; i++) { buf.writeInt16LE(Math.round(Math.tanh(L[i] * g * 1.1) / Math.tanh(1.1) * 32000 * fadeOut(i) * fadeIn(i)), 44 + i * 4); buf.writeInt16LE(Math.round(Math.tanh(R[i] * g * 1.1) / Math.tanh(1.1) * 32000 * fadeOut(i) * fadeIn(i)), 46 + i * 4); }
writeFileSync(out, buf);
console.log('wrote', out, 'peak before norm', pk.toFixed(3), 'dur', DUR.toFixed(2));
