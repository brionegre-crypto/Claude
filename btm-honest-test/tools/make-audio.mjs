// The Low Seat Check video: music and every sound, made in code.  Reads the same model as the picture (test.js, sting.js).
// node tools/make-audio.mjs <out.wav>
import { createRequire } from 'module';
import { writeFileSync } from 'fs';
const require = createRequire(import.meta.url);
const F = require('../test.js');
const M = require('../sting.js');
const out = process.argv[2] || 'assets/test-audio.wav';
const SR = 48000, DUR = 60, N = SR * DUR, BEAT = 0.6;
const T = F.T, sc = M.create('orbit', { targetW: 1500, comp0: 0.05 });
let seed = 11;
const rnd = () => { seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const noise = () => rnd() * 2 - 1;
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const onePole = (fc) => { let y = 0; const a = 1 - Math.exp(-2 * Math.PI * fc / SR); return (x) => (y += a * (x - y)); };
function svf() { let s1 = 0, s2 = 0; return (x, fc, q) => { const g = Math.tan(Math.PI * Math.min(fc, SR * 0.45) / SR), k = 1 / q, a1 = 1 / (1 + g * (g + k)), a2 = g * a1, a3 = g * a2, v3 = x - s2, v1 = a1 * s1 + a2 * v3, v2 = s2 + a2 * s1 + a3 * v3; s1 = 2 * v1 - s1; s2 = 2 * v2 - s2; return { lp: v2, bp: v1, hp: x - k * v1 - v2 }; }; }
const L = new Float32Array(N), R = new Float32Array(N);
const pan2 = (p) => [Math.cos((p + 1) * Math.PI / 4) * 1.4142, Math.sin((p + 1) * Math.PI / 4) * 1.4142];
const add = (i, v, p = 0) => { if (i < 0 || i >= N) return; const [l, r] = pan2(p); L[i] += v * l; R[i] += v * r; };
const idx = (t) => Math.round(t * SR);
const hz = (m) => 440 * Math.pow(2, (m - 69) / 12);

/* 1. music: warm, low, patient; 100 BPM.  Dm9 | Bbmaj7 | Gm7 | A7sus (a bar each, 2.4 s) -- it opens dark and lifts as the result lands */
const CH = [[38, 45, 53, 57, 64], [34, 41, 50, 57, 62], [43, 50, 53, 58, 62], [45, 52, 55, 60, 64]];
const bars = Math.ceil(DUR / (4 * BEAT));
const lvl = (t) => clamp(0.35 + 0.35 * F.sstep((t - 10) / 3) + 0.35 * F.sstep((t - 36) / 2) - 0.25 * F.sstep((t - 33) / 0.5) * (1 - F.sstep((t - 36) / 0.5)), 0, 1);
{
  const lp = svf(), lp2 = svf(), padL = new Float32Array(N), padR = new Float32Array(N);
  for (let b = 0; b < bars; b++) {
    const t0 = b * 4 * BEAT, chord = CH[b % 4], last = t0 + 4 * BEAT + 1.0;
    for (let n = 0; n < chord.length; n++) for (const det of [-0.08, 0.08]) {
      const f = hz(chord[n] + 12) * Math.pow(2, det / 12), ph = rnd() * 6.28, i0 = idx(t0), i1 = Math.min(N, idx(last));
      for (let i = i0; i < i1; i++) {
        const t = (i - i0) / SR, env = (1 - Math.exp(-t / 0.7)) * Math.exp(-Math.max(0, t - 4 * BEAT) / 0.4);
        const s = (Math.sin(2 * Math.PI * f * i / SR + ph) + 0.3 * Math.sin(4 * Math.PI * f * i / SR + ph * 2)) * env * 0.030 * lvl(i / SR);
        padL[i] += s * (0.8 + 0.2 * (n % 2)); padR[i] += s * (0.8 + 0.2 * ((n + 1) % 2));
      }
    }
  }
  for (let i = 0; i < N; i++) { const t = i / SR, fc = 500 + 900 * F.sstep((t - 33) / 4); L[i] += lp(padL[i], fc, 0.7).lp; R[i] += lp2(padR[i], fc, 0.7).lp; }
}
function bass(t, note, len = 1.2, amp = 0.15) { const f = hz(note), i0 = idx(t); for (let n = 0; n < SR * len; n++) { const tt = n / SR, env = (1 - Math.exp(-tt / 0.014)) * Math.exp(-tt / (len * 0.4)); add(i0 + n, (Math.sin(2 * Math.PI * f * tt) + 0.25 * Math.sin(4 * Math.PI * f * tt)) * env * amp * (0.6 + 0.4 * lvl(t)), 0); } }
for (let b = 0; b < bars; b++) { const r = CH[b % 4][0] - 12 + 12, t = b * 4 * BEAT; if (t > 1 && t < 57) { bass(t, r, 1.4); if (t > 12 && t < 54) bass(t + 2 * BEAT, r, 0.9, 0.09); } }
function pluck(t, note, amp = 0.06, p = 0) { const f = hz(note), i0 = idx(t); for (let n = 0; n < SR * 0.9; n++) { const tt = n / SR, env = Math.exp(-tt / 0.22) * (1 - Math.exp(-tt / 0.003)); add(i0 + n, (Math.sin(2 * Math.PI * f * tt) + 0.3 * Math.sin(6 * Math.PI * f * tt) * Math.exp(-tt / 0.05)) * env * amp, p); } }
const PAT = [1, 0, 0, 1, 0, 1, 0, 0];
for (let b = 0; b < bars; b++) for (let e = 0; e < 8; e++) {
  const t = b * 4 * BEAT + e * BEAT / 2;
  if (t < 12 || t > 53 || (t > 32.6 && t < 36.0)) continue;
  if (!PAT[e]) continue;
  pluck(t, CH[b % 4][1 + ((b * 3 + e) % 4)] + 12 + (e % 2 ? 12 : 0), t < 36 ? 0.045 : 0.062, ((b + e) % 2 ? 0.3 : -0.3));
}
// a quiet pulse while he sits with the questions: a heartbeat, not a drum
function thump(t, amp = 0.16) { const i0 = idx(t); for (let n = 0; n < SR * 0.5; n++) { const tt = n / SR, f = 52 * (1 + 0.6 * Math.exp(-tt / 0.05)); add(i0 + n, Math.sin(2 * Math.PI * f * tt) * Math.exp(-tt / 0.11) * (1 - Math.exp(-tt / 0.004)) * amp, 0); } }
for (let t = 12.0; t < 32.4; t += BEAT * 2) { thump(t, 0.12); thump(t + 0.27, 0.07); }
// the room: a low tone and a little air
{ const lp = svf(); for (let i = 0; i < N; i++) { const t = i / SR; const a = lp(noise(), 380, 0.6).lp * 0.045 * (1 - F.sstep((t - 54) / 1.5) * 0.6); add(i, a, 0); } }

/* 2. the mouse: every click and the soft taps between */
const bpK = svf(), bpF = svf();
function click(t, amp = 1, p = 0) { const i0 = idx(t); for (let n = 0; n < SR * 0.06; n++) { const tt = n / SR; add(i0 + n, (bpK(noise(), 3200, 1.4).bp * Math.exp(-tt / 0.003) * 0.20 + Math.sin(2 * Math.PI * 210 * tt) * Math.exp(-tt / 0.02) * 0.14) * amp, p); } }
function key(t, amp = 1, p = 0) { const i0 = idx(t), f = 170 + rnd() * 70, c = 2400 + rnd() * 900; for (let n = 0; n < SR * 0.05; n++) { const tt = n / SR; add(i0 + n, (bpF(noise(), c, 1.6).bp * Math.exp(-tt / 0.004) * 0.16 + Math.sin(2 * Math.PI * f * tt) * Math.exp(-tt / 0.018) * 0.10) * amp, p); } }
F.clicks.forEach((t, i) => click(F.snap(t), 1, -0.1));
// the page is written in: soft ticks under each wipe of text
[0.5, F.T.h1, F.T.h1 + 0.7].forEach((t) => { for (let k = 0; k < 7; k++) key(F.snap(t + 0.12 * k), 0.35, -0.2 + 0.07 * k); });
for (let k = 0; k < 16; k++) key(F.snap(F.T.lede + 0.14 * k), 0.28, 0.1);
// the verse: one low, held note
{ const i0 = idx(F.T.verse); const lp = svf(); for (let n = 0; n < SR * 2.4; n++) { const t = n / SR, e = (1 - Math.exp(-t / 0.2)) * Math.exp(-t / 1.1); let s = 0; for (const [m, a] of [[1, 1], [2, 0.3], [3, 0.1]]) s += Math.sin(2 * Math.PI * 110 * m * t) * a; add(i0 + n, lp(s, 700, 0.7).lp * e * 0.12, 0); } }
// the answer picked: a soft amber note that climbs with the answer
F.PICK.forEach((t, i) => { const a = F.ANS_SHOWN[i]; pluck(F.snap(t) + 0.04, [62, 66, 69, 73, 76][a - 1] + 12, 0.1, 0.2); });
// each new question slides in
F.QSTART.forEach((t) => { const bp = svf(), i0 = idx(t), i1 = idx(t + 0.5); for (let i = i0; i < i1; i++) { const u = (i - i0) / (i1 - i0); add(i, bp(noise(), 400 + 2200 * u, 0.9).bp * Math.sin(Math.PI * u) * 0.09, 0.3 * (u - 0.5)); } });
// the fast pass: the other fifteen, each a small tick, climbing
F.montageTimes.forEach((t, i) => { const tt = F.snap(t); key(tt, 0.7, -0.4 + 0.8 * (i / 14)); pluck(tt, 64 + (i % 5) * 2 + Math.floor(i / 5) * 7 + 12, 0.045, -0.3 + 0.6 * (i / 14)); });
// the cut to the result: a breath out and a low hit
function boom(t, f0 = 58, len = 1.1, amp = 0.3) { const i0 = idx(t); for (let n = 0; n < SR * len; n++) { const tt = n / SR, f = f0 * (1 + 0.5 * Math.exp(-tt / 0.07)); add(i0 + n, Math.sin(2 * Math.PI * f * tt) * Math.exp(-tt / (len * 0.3)) * (1 - Math.exp(-tt / 0.004)) * amp, 0); } }
function riser(t0, t1, amp = 0.09) { const bp = svf(), i0 = idx(t0), i1 = idx(t1); for (let i = i0; i < i1; i++) { const u = (i - i0) / (i1 - i0); add(i, bp(noise(), 400 + 5200 * u * u, 1.2).bp * Math.pow(u, 2.2) * amp, (u - 0.5) * 0.5); } }
riser(F.T.montageB - 0.9, F.T.montageB, 0.10); boom(F.T.result, 56, 1.3, 0.3);
// the score counts up: a tick per whole point, climbing
{ const a = idx(F.T.count[0]), b = idx(F.T.count[1]); let last = 0; for (let i = a; i < b; i++) { const u = F.eOut((i / SR - F.T.count[0]) / (F.T.count[1] - F.T.count[0])), v = Math.round(F.SO * u); if (v !== last) { last = v; const bp = svf(); for (let n = 0; n < 900; n++) add(i + n, bp(noise(), 2800 + 20 * v, 1.6).bp * Math.exp(-n / SR / 0.004) * 0.05, 0); } } }
// the band is named ("Defended."): one low note
{ const i0 = idx(F.T.bandT), lp = svf(); for (let n = 0; n < SR * 1.6; n++) { const t = n / SR, e = (1 - Math.exp(-t / 0.03)) * Math.exp(-t / 0.7); let s = 0; for (const [m, a] of [[1, 1], [2, 0.4], [3, 0.15]]) s += Math.sin(2 * Math.PI * 98 * m * t) * a; add(i0 + n, lp(s, 900, 0.7).lp * e * 0.18, 0); } }
// five bars fill, one note each
function bell(t, f, amp = 0.1, p = 0) { const i0 = idx(t); for (let n = 0; n < SR * 1.4; n++) { const tt = n / SR; add(i0 + n, (Math.sin(2 * Math.PI * f * tt) + 0.35 * Math.sin(2 * Math.PI * f * 2.76 * tt) * Math.exp(-tt / 0.1)) * Math.exp(-tt / 0.4) * (1 - Math.exp(-tt / 0.002)) * amp, p); } }
F.S.forEach((v, b) => { bell(F.snap(F.T.bars[0] + b * 0.4) + 0.1, [523, 587, 659, 740, 784][b] * (v < 40 ? 0.5 : 1), 0.08, -0.5 + 0.25 * b); });
// the thinnest posture is named: the lowest note yet
bell(F.snap(F.T.thin) + 0.05, 220, 0.16, 0);
// time, action, test: three small landings
F.T.ttt.forEach((t, i) => { const tt = F.snap(t); thump(tt, 0.14); bell(tt + 0.02, [659, 784, 988][i], 0.08, -0.3 + 0.3 * i); });
// "Send to a witness": the link is copied
bell(F.snap(F.T.copied) + 0.08, 1047, 0.1, 0.2); bell(F.snap(F.T.copied) + 0.14, 1568, 0.06, -0.2);
// the comparison: two sets of bars, the gap opens
riser(F.T.cmp - 0.4, F.T.cmp + 0.3, 0.07);
F.W.forEach((v, b) => bell(F.snap(F.T.cmpBars[0] + 0.5 + b * 0.3), [440, 494, 554, 587, 659][b] * 0.5, 0.06, 0.4 - 0.2 * b));
// the screen goes dark, the line goes
{ const bp = svf(), i0 = idx(F.T.morphA), i1 = idx(F.T.morphB); for (let i = i0; i < i1; i++) { const u = (i - i0) / (i1 - i0); add(i, bp(noise(), 300 + 2400 * u * u, 0.9).bp * Math.sin(Math.PI * Math.min(1, u * 1.2)) * 0.11, 0.3 * (u - 0.5)); } }
boom(F.T.morphB, 52, 1.4, 0.3);

/* 3. the logo: the sting, time-warped */
{
  const bpA = svf(), bpB = svf(), bpC = svf(), lpS = svf(), sm = onePole(40), smT = onePole(30), gLP = onePole(260), g2 = onePole(1400);
  const sp = F.STING.speed, i0 = idx(F.STING.tf0), i1 = idx(59.6);
  for (let i = i0; i < i1; i++) {
    const tf = i / SR, ts = F.tsOf(tf);
    const v = ts > M.T.go && ts < M.T.close + 0.05 ? sc.headV(ts) * sp : 0, ink = clamp((sc.headS(ts) - sc.Lsw) / 160);
    const tv = ts > M.T.tailA && ts < M.T.tailB ? Math.abs(sc.tailV(ts)) * sp : 0;
    const lv = sm(1 - Math.exp(-v / 2600)), lvT = smT(1 - Math.exp(-tv / 3000));
    if (lv < 1e-4 && lvT < 1e-4) continue;
    const nz = noise(), air = bpA(nz, 520 + 1500 * lv, 0.8).bp * 0.30 + lpS(nz, 260, 0.7).lp * 0.55;
    const g = 0.45 + 0.55 * Math.min(1, Math.abs(gLP(noise()) * 9)), pen = bpB(nz, 2300 + 1100 * lv, 1.6).bp * g * 0.55 + g2(nz) * 0.12 * g;
    const body = ((1 - ink) * air * 1.05 + ink * pen * 0.30) * lv * 0.5, zip = bpC(noise(), 1500 + 2600 * lvT, 2.4).bp * lvT * 0.12;
    add(i, body + zip, clamp((sc.penPos(ts).x - 960) / 1800, -0.5, 0.5));
  }
  { const ii = idx(F.STING.closeFilm), bp = svf(); for (let n = 0; n < SR * 0.25; n++) { const tt = n / SR; add(ii + n, bp(noise(), 3200, 1.1).bp * Math.exp(-tt / 0.0045) * 0.20 + Math.sin(2 * Math.PI * 1780 * tt) * Math.exp(-tt / 0.014) * 0.07 + Math.sin(2 * Math.PI * (150 - 40 * Math.min(1, tt / 0.05)) * tt) * Math.exp(-tt / 0.05) * 0.24, 0); } }
  sc.jumpSegs.forEach((j, k) => { const t = F.snap(F.tfOf(sc.relEnd(j))), ii = idx(t), bp = svf(); for (let n = 0; n < SR * 0.05; n++) { const tt = n / SR; add(ii + n, bp(noise(), 2600 + 120 * k, 1.5).bp * Math.exp(-tt / 0.006) * (0.05 + (k === 7 ? 0.03 : 0)), 0.1); } });
  { const ii = idx(F.snap(F.tfOf(M.T.note))), lp = svf(); for (let n = 0; ii + n < N; n++) { const t = n / SR, att = 1 - Math.exp(-t / 0.08), dec = Math.exp(-t / 1.1), end = 1 - clamp((t - (DUR - F.tfOf(M.T.note) - 0.45)) / 0.45); let s = 0; for (const [m, a, d] of [[1, 1, 0], [1, 0.55, 0.9], [2, 0.3, 0.4], [3, 0.1, -0.3], [0.5, 0.4, 0]]) s += Math.sin(2 * Math.PI * (98 * m + d) * t) * a; add(ii + n, lp(s, 620, 0.7).lp * att * (0.3 + 0.7 * dec) * Math.sin(Math.PI / 2 * end) * 0.30, 0); } }
  const t0 = F.tfOf(M.T.tagA), t1 = F.tfOf(M.T.tagB);
  for (let k = 0; k < 14; k++) key(F.snap(t0 + (t1 - t0) * k / 13), 0.5, 0);
  for (let k = 0; k < 10; k++) key(F.snap(t1 + 0.05 + 0.6 * k / 9), 0.35, 0);
}

/* master */
let pk = 0; for (let i = 0; i < N; i++) pk = Math.max(pk, Math.abs(L[i]), Math.abs(R[i]));
const g = 0.708 / (pk || 1), buf = Buffer.alloc(44 + N * 4);
buf.write('RIFF', 0); buf.writeUInt32LE(36 + N * 4, 4); buf.write('WAVEfmt ', 8); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22);
buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36); buf.writeUInt32LE(N * 4, 40);
const fadeOut = (i) => 1 - clamp((i / SR - (DUR - 0.4)) / 0.4), fadeIn = (i) => clamp(i / SR / 0.5);
for (let i = 0; i < N; i++) {
  buf.writeInt16LE(Math.round(Math.tanh(L[i] * g * 1.1) / Math.tanh(1.1) * 32000 * fadeOut(i) * fadeIn(i)), 44 + i * 4);
  buf.writeInt16LE(Math.round(Math.tanh(R[i] * g * 1.1) / Math.tanh(1.1) * 32000 * fadeOut(i) * fadeIn(i)), 46 + i * 4);
}
writeFileSync(out, buf);
console.log('wrote', out, 'peak before norm', pk.toFixed(3));
