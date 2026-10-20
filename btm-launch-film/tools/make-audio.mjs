// The film's music and every sound effect, made in code (no samples).  Reads the same model as the picture (film.js, sting.js),
// so each sound sits on the frame of the thing it belongs to.   node tools/make-audio.mjs <out.wav>
import { createRequire } from 'module';
import { writeFileSync } from 'fs';
const require = createRequire(import.meta.url);
const F = require('../film.js');
const M = require('../sting.js');
const out = process.argv[2] || 'assets/film-audio.wav';
const SR = 48000, DUR = 20, N = SR * DUR, BEAT = 0.6;
const T = F.T, sc = M.create('orbit', { targetW: 1500, comp0: 0.05 });

let seed = 3;
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

/* ---------------- 1. music: soft, warm, minimal, 100 BPM ---------------- */
// Cmaj7 | Am7 | Fmaj7 | G6   (each chord = 4 beats = one bar, 2.4 s)
const CH = [[48, 55, 59, 64, 67], [45, 52, 55, 60, 64], [41, 48, 52, 57, 60], [43, 50, 55, 59, 64]];
const bars = Math.ceil(DUR / (4 * BEAT));
{
  const lp = svf(), lp2 = svf();
  const padL = new Float32Array(N), padR = new Float32Array(N);
  for (let b = 0; b < bars; b++) {
    const t0 = b * 4 * BEAT, chord = CH[b % 4], last = t0 + 4 * BEAT + 0.9;
    for (let n = 0; n < chord.length; n++) {
      for (const det of [-0.07, 0.07]) {
        const f = hz(chord[n] + 12) * Math.pow(2, det / 12), ph = rnd() * 6.28;
        const i0 = idx(t0), i1 = Math.min(N, idx(last));
        for (let i = i0; i < i1; i++) {
          const t = (i - i0) / SR, env = (1 - Math.exp(-t / 0.55)) * Math.exp(-Math.max(0, t - 4 * BEAT) / 0.35);
          const s = (Math.sin(2 * Math.PI * f * (i / SR) + ph) + 0.35 * Math.sin(4 * Math.PI * f * (i / SR) + ph * 2)) * env * 0.030;
          padL[i] += s * (0.8 + 0.2 * (n % 2)); padR[i] += s * (0.8 + 0.2 * ((n + 1) % 2));
        }
      }
    }
  }
  for (let i = 0; i < N; i++) { const a = lp(padL[i], 900, 0.7).lp, b2 = lp2(padR[i], 900, 0.7).lp; L[i] += a; R[i] += b2; }
}
// bass: root, soft, on beats 1 and 3 (and on each landing)
function bass(t, note, len = 1.0, amp = 0.16) {
  const f = hz(note), i0 = idx(t);
  for (let n = 0; n < SR * len; n++) { const tt = n / SR, env = (1 - Math.exp(-tt / 0.012)) * Math.exp(-tt / (len * 0.38)); const s = (Math.sin(2 * Math.PI * f * tt) + 0.25 * Math.sin(4 * Math.PI * f * tt)) * env * amp; add(i0 + n, s, 0); }
}
for (let b = 0; b < bars; b++) { const r = CH[b % 4][0] - 12; bass(b * 4 * BEAT, r, 1.3); if (b * 4 * BEAT + 2 * BEAT < DUR - 1) bass(b * 4 * BEAT + 2 * BEAT, r, 0.9, 0.1); }
// plucks: a quiet pattern of chord tones on the eighth notes from the first landing; sparse before that
function pluck(t, note, amp = 0.07, p = 0) {
  const f = hz(note), i0 = idx(t);
  for (let n = 0; n < SR * 0.9; n++) { const tt = n / SR, env = Math.exp(-tt / 0.22) * (1 - Math.exp(-tt / 0.003)); const s = (Math.sin(2 * Math.PI * f * tt) + 0.3 * Math.sin(6 * Math.PI * f * tt) * Math.exp(-tt / 0.05)) * env * amp; add(i0 + n, s, p); }
}
const PAT = [1, 0, 0, 1, 0, 1, 0, 0];
for (let b = 0; b < bars; b++) {
  const chord = CH[b % 4];
  for (let e = 0; e < 8; e++) {
    const t = b * 4 * BEAT + e * BEAT / 2;
    if (t < 1.2 || t > 19.4) continue;
    const on = t < F.L.s2 ? (e === 3 || e === 6) : PAT[e];
    if (!on) continue;
    pluck(t, chord[1 + ((b * 3 + e) % 4)] + 12 + (e % 2 ? 12 : 0), t < F.L.s2 ? 0.045 : 0.065, ((b + e) % 2 ? 0.3 : -0.3));
  }
}
// a barely-there shaker on the off-beats once the story starts
{
  const hp = svf();
  for (let t = F.L.s2 + BEAT / 2; t < 18.6; t += BEAT) { const i0 = idx(t); for (let n = 0; n < SR * 0.06; n++) { const tt = n / SR; add(i0 + n, hp(noise(), 6500, 0.9).hp * Math.exp(-tt / 0.012) * 0.014, 0.2); } }
}

/* ---------------- 2. landings: every scene change lands on the beat ---------------- */
function boom(t, f0 = 62, len = 1.1, amp = 0.34) { const i0 = idx(t); for (let n = 0; n < SR * len; n++) { const tt = n / SR, f = f0 * (1 + 0.5 * Math.exp(-tt / 0.07)); add(i0 + n, Math.sin(2 * Math.PI * f * tt) * Math.exp(-tt / (len * 0.3)) * (1 - Math.exp(-tt / 0.004)) * amp, 0); } }
function riser(t0, t1, amp = 0.09) {
  const bp = svf(), i0 = idx(t0), i1 = idx(t1);
  for (let i = i0; i < i1; i++) { const u = (i - i0) / (i1 - i0), v = bp(noise(), 400 + 5200 * u * u, 1.2).bp * Math.pow(u, 2.2) * amp; add(i, v, (u - 0.5) * 0.5); }
}
const LANDS = [F.L.s2, F.L.s3, F.L.s4, F.L.s5];
LANDS.forEach((t, k) => {
  riser(t - 0.9, t, 0.10); boom(t, 58, 1.0, k === 3 ? 0.30 : 0.24);
  const chord = CH[(Math.round(t / (4 * BEAT)) % 4)]; pluck(t, chord[2] + 12, 0.09, -0.2); pluck(t + 0.01, chord[3] + 12, 0.07, 0.2);
});

/* ---------------- 3. the line ---------------- */
{
  const bpA = svf(), lpS = svf(), sm = onePole(30);
  for (let i = 0; i < idx(16.9); i++) {
    const t = i / SR, a = sm(F.lineActivity(t));
    if (a < 1e-3) continue;
    const nz = noise(), p = t < F.T.headDone + 0.1 ? clamp((F.headX(t) - 0.5) * 1.1, -0.6, 0.6) : 0;
    const v = (bpA(nz, 700 + 2300 * a, 0.9).bp * 0.5 + lpS(nz, 240, 0.7).lp * 0.45) * Math.pow(a, 1.15) * 0.34;
    add(i, v, p);
  }
}
// the dot appears
{ const i0 = idx(T.dotIn); for (let n = 0; n < SR * 0.25; n++) { const tt = n / SR; add(i0 + n, Math.sin(2 * Math.PI * 1318 * tt) * Math.exp(-tt / 0.05) * 0.05 + Math.sin(2 * Math.PI * 659 * tt) * Math.exp(-tt / 0.12) * 0.03, -0.5); } }

/* ---------------- 4. typing, flips, presses, checks ---------------- */
const bpK = svf(), bpF = svf();
function key(t, amp = 1, p = 0) {
  const i0 = idx(t), f = 170 + rnd() * 70, c = 2400 + rnd() * 900;
  for (let n = 0; n < SR * 0.05; n++) { const tt = n / SR; add(i0 + n, (bpK(noise(), c, 1.6).bp * Math.exp(-tt / 0.004) * 0.16 + Math.sin(2 * Math.PI * f * tt) * Math.exp(-tt / 0.018) * 0.10) * amp, p); }
}
F.SUB_T.forEach((t) => key(t, 0.8, -0.1));
F.SENT_T.forEach((t, i) => key(t, 0.75 + 0.3 * rnd(), 0.1));
function clack(t, p, amp = 1) { const i0 = idx(t), f = 800 + rnd() * 500; for (let n = 0; n < SR * 0.03; n++) { const tt = n / SR; add(i0 + n, (bpF(noise(), 1800 + rnd() * 300, 1.4).bp * Math.exp(-tt / 0.0035) * 0.10 + Math.sin(2 * Math.PI * f * tt) * Math.exp(-tt / 0.01) * 0.05) * amp, p); } }
F.BAND.forEach((tr, k) => {
  const A = F.bandStrings[k], B = F.bandStrings[k + 1], n = Math.max(A.length, B.length);
  for (let i = 0; i < n; i++) { if (A[i] === B[i]) continue; clack(F.snap(tr.t0 + i * F.FLIP_STAG + F.FLIP_DUR / 2), clamp((i / 16) * 1.2 - 0.6, -0.6, 0.6), 0.9); }
});
for (let i = 0; i < F.WORDS.sub.length; i++) clack(F.snap(3.3 + i * F.FLIP_STAG + F.FLIP_DUR / 2), 0, 0.7);
// "Save my sentence" is pressed
{ const i0 = idx(T.press); for (let n = 0; n < SR * 0.14; n++) { const tt = n / SR; add(i0 + n, Math.sin(2 * Math.PI * 190 * tt) * Math.exp(-tt / 0.03) * 0.22 + bpK(noise(), 3000, 1.3).bp * Math.exp(-tt / 0.005) * 0.12, -0.15); } }
{ const i0 = idx(T.press2); for (let n = 0; n < SR * 0.14; n++) { const tt = n / SR; add(i0 + n, Math.sin(2 * Math.PI * 190 * tt) * Math.exp(-tt / 0.03) * 0.22 + bpK(noise(), 3000, 1.3).bp * Math.exp(-tt / 0.005) * 0.12, -0.15); } }
// the thread reaches each habit: a soft bell
function bell(t, f, amp = 0.12, p = 0) { const i0 = idx(t); for (let n = 0; n < SR * 1.4; n++) { const tt = n / SR; add(i0 + n, (Math.sin(2 * Math.PI * f * tt) + 0.35 * Math.sin(2 * Math.PI * f * 2.76 * tt) * Math.exp(-tt / 0.1)) * Math.exp(-tt / 0.4) * (1 - Math.exp(-tt / 0.002)) * amp, p); } }
T.checks.forEach((t, i) => { bell(t, [784, 988, 1175][i], 0.11, -0.3 + 0.3 * i); key(t, 1.2, -0.3 + 0.3 * i); });
// the sentence comes back: a soft, wide chime as the focus is pulled
bell(F.snap(T.emailA + 0.6), 1046.5, 0.10, -0.2); bell(F.snap(T.emailA + 0.6) + 0.04, 1568, 0.06, 0.25);
T.weekFill.forEach((t, i) => bell(t, [880, 988, 1175][i], 0.09, 0.2 - 0.2 * i));
// the window turns over / collapses
{ const bp = svf(); const i0 = idx(T.flipA), i1 = idx(F.L.s4); for (let i = i0; i < i1; i++) { const u = (i - i0) / (i1 - i0); add(i, bp(noise(), 300 + 1800 * Math.sin(Math.PI * u), 0.9).bp * Math.sin(Math.PI * u) * 0.10, 0.4 * Math.sin(Math.PI * u)); } }
{ const bp = svf(); const i0 = idx(T.collapseA), i1 = idx(T.collapseB); for (let i = i0; i < i1; i++) { const u = (i - i0) / (i1 - i0); add(i, bp(noise(), 2400 - 1900 * u, 0.9).bp * Math.sin(Math.PI * u) * 0.10, 0); } }

/* ---------------- 5. the logo: the sting, time-warped ---------------- */
{
  const bpA = svf(), bpB = svf(), bpC = svf(), lpS = svf(), sm = onePole(40), smT = onePole(30), gLP = onePole(260), g2 = onePole(1400);
  const sp = F.STING.speed, i0 = idx(F.STING.tf0), i1 = idx(19.6);
  for (let i = i0; i < i1; i++) {
    const tf = i / SR, ts = F.tsOf(tf);
    const v = ts > M.T.go && ts < M.T.close + 0.05 ? sc.headV(ts) * sp : 0, ink = clamp((sc.headS(ts) - sc.Lsw) / 160);
    const tv = ts > M.T.tailA && ts < M.T.tailB ? Math.abs(sc.tailV(ts)) * sp : 0;
    const lvl = sm(1 - Math.exp(-v / 2600)), lvlT = smT(1 - Math.exp(-tv / 3000));
    if (lvl < 1e-4 && lvlT < 1e-4) continue;
    const nz = noise(), air = bpA(nz, 520 + 1500 * lvl, 0.8).bp * 0.30 + lpS(nz, 260, 0.7).lp * 0.55;
    const g = 0.45 + 0.55 * Math.min(1, Math.abs(gLP(noise()) * 9)), pen = bpB(nz, 2300 + 1100 * lvl, 1.6).bp * g * 0.55 + g2(nz) * 0.12 * g;
    const body = ((1 - ink) * air * 1.05 + ink * pen * 0.30) * lvl * 0.5, zip = bpC(noise(), 1500 + 2600 * lvlT, 2.4).bp * lvlT * 0.12;
    add(i, body + zip, clamp((sc.penPos(ts).x - 960) / 1800, -0.5, 0.5));
  }
  // the click: the loop closes
  { const t0 = F.STING.closeFilm, ii = idx(t0), bp = svf(); for (let n = 0; n < SR * 0.25; n++) { const tt = n / SR; add(ii + n, bp(noise(), 3200, 1.1).bp * Math.exp(-tt / 0.0045) * 0.20 + Math.sin(2 * Math.PI * 1780 * tt) * Math.exp(-tt / 0.014) * 0.07 + Math.sin(2 * Math.PI * (150 - 40 * Math.min(1, tt / 0.05)) * tt) * Math.exp(-tt / 0.05) * 0.24, 0); } }
  // the thread is reeled out: small ticks, each on the frame its stitch disappears
  sc.jumpSegs.forEach((j, k) => { const t = F.snap(F.tfOf(sc.relEnd(j))), ii = idx(t), bp = svf(); for (let n = 0; n < SR * 0.05; n++) { const tt = n / SR; add(ii + n, bp(noise(), 2600 + 120 * k, 1.5).bp * Math.exp(-tt / 0.006) * (0.05 + (k === 7 ? 0.03 : 0)), 0.1); } });
  // one warm low note under the finished logo (G2) and its octave
  { const ii = idx(F.snap(F.tfOf(M.T.note))), lp = svf(); for (let n = 0; ii + n < N; n++) { const t = n / SR, att = 1 - Math.exp(-t / 0.08), dec = Math.exp(-t / 1.0), end = 1 - clamp((t - (DUR - F.tfOf(M.T.note) - 0.45)) / 0.45); let s = 0; for (const [m, a, d] of [[1, 1, 0], [1, 0.55, 0.9], [2, 0.3, 0.4], [3, 0.1, -0.3], [0.5, 0.4, 0]]) s += Math.sin(2 * Math.PI * (98 * m + d) * t) * a; add(ii + n, lp(s, 620, 0.7).lp * att * (0.3 + 0.7 * dec) * Math.sin(Math.PI / 2 * end) * 0.30, 0); } }
  // the tagline and the label are written
  const tagT0 = F.tfOf(M.T.tagA), tagT1 = F.tfOf(M.T.tagB);
  for (let k = 0; k < 14; k++) key(F.snap(tagT0 + (tagT1 - tagT0) * k / 13), 0.5, 0);
  for (let k = 0; k < 8; k++) key(F.snap(tagT1 + 0.05 + 0.45 * k / 7), 0.35, 0);
}

/* ---------------- master ---------------- */
let pk = 0; for (let i = 0; i < N; i++) pk = Math.max(pk, Math.abs(L[i]), Math.abs(R[i]));
const g = 0.708 / (pk || 1), buf = Buffer.alloc(44 + N * 4);
buf.write('RIFF', 0); buf.writeUInt32LE(36 + N * 4, 4); buf.write('WAVEfmt ', 8); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22);
buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36); buf.writeUInt32LE(N * 4, 40);
const fadeOut = (i) => 1 - clamp((i / SR - (DUR - 0.35)) / 0.35);
for (let i = 0; i < N; i++) {
  buf.writeInt16LE(Math.round(Math.tanh(L[i] * g * 1.1) / Math.tanh(1.1) * 32000 * fadeOut(i)), 44 + i * 4);
  buf.writeInt16LE(Math.round(Math.tanh(R[i] * g * 1.1) / Math.tanh(1.1) * 32000 * fadeOut(i)), 46 + i * 4);
}
writeFileSync(out, buf);
console.log('wrote', out, 'peak before norm', pk.toFixed(3));
