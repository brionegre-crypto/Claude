// Every sound in code, no samples. Reads the same motion model the picture uses, so the pen
// follows the pen's real speed and the click / note sit on the exact frame of what they belong to.
//   node tools/make-audio.mjs <variant> <out.wav>
import { createRequire } from 'module';
import { writeFileSync } from 'fs';
const require = createRequire(import.meta.url);
const Motion = require('../motion.js');

const variant = process.argv[2] || 'orbit';
const out = process.argv[3] || 'assets/btm-sfx.wav';
const SR = 48000, DUR = 6, N = SR * DUR;
const T = Motion.T;
const sc = Motion.create(variant);

let seed = 11;
const rnd = () => { seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const noise = () => rnd() * 2 - 1;
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const onePole = (fc) => { let y = 0; const a = 1 - Math.exp(-2 * Math.PI * fc / SR); return (x) => (y += a * (x - y)); };
function svf() {                                    // state-variable filter, stable with moving cutoff
  let s1 = 0, s2 = 0;
  return (x, fc, q) => {
    const g = Math.tan(Math.PI * Math.min(fc, SR * 0.45) / SR), k = 1 / q;
    const a1 = 1 / (1 + g * (g + k)), a2 = g * a1, a3 = g * a2;
    const v3 = x - s2, v1 = a1 * s1 + a2 * v3, v2 = s2 + a2 * s1 + a3 * v3;
    s1 = 2 * v1 - s1; s2 = 2 * v2 - s2;
    return { lp: v2, bp: v1, hp: x - k * v1 - v2 };
  };
}

const L = new Float32Array(N), R = new Float32Array(N);
const add = (i, l, r) => { if (i >= 0 && i < N) { L[i] += l; R[i] += r; } };

// ---------- control signals from the picture's own motion (1 kHz) ----------
const CR = 1000, nC = DUR * CR + 2;
const head = new Float64Array(nC), onInk = new Float64Array(nC), tail = new Float64Array(nC), pan = new Float64Array(nC);
for (let i = 0; i < nC; i++) {
  const t = i / CR;
  head[i] = t > T.go && t < T.close + 0.05 ? sc.headV(t) : 0;
  const s = sc.headS(t);
  onInk[i] = clamp((s - sc.Lsw) / 160);                        // 0 while circling, 1 once the head is writing letters
  tail[i] = t > T.tailA && t < T.tailB ? Math.abs(sc.tailV(t)) : 0;
  pan[i] = clamp((sc.penPos(t).x - 960) / 1800, -0.5, 0.5);
}
const at = (a, t) => { const f = t * CR, i = Math.floor(f); return a[i] + (a[Math.min(nC - 1, i + 1)] - a[i]) * (f - i); };

// ---------- 1. the pen: soft air while the line circles, fine paper grain while it writes ----------
{
  const bpA = svf(), bpB = svf(), bpC = svf(), lpS = svf();
  const sm = onePole(40), smT = onePole(30), grainLP = onePole(260), grain2 = onePole(1400);
  for (let i = 0; i < N; i++) {
    const t = i / SR;
    const v = at(head, t), ink = at(onInk, t), tv = at(tail, t), pn = at(pan, t);
    const lvl = sm(1 - Math.exp(-v / 2600));
    const lvlT = smT(1 - Math.exp(-tv / 3000));
    if (lvl < 1e-4 && lvlT < 1e-4) continue;
    const nz = noise();
    // circling: a low, soft pass of air -- lower and rounder the slower it goes
    const air = bpA(nz, 520 + 1500 * lvl, 0.8).bp * 0.30 + lpS(nz, 260, 0.7).lp * 0.55;
    // writing: pen on paper -- narrow band + grain that flickers at the stroke rate
    const g = 0.45 + 0.55 * Math.min(1, Math.abs(grainLP(noise()) * 9));
    const pen = bpB(nz, 2300 + 1100 * lvl, 1.6).bp * g * 0.55 + grain2(nz) * 0.12 * g;
    const body = ((1 - ink) * air * 1.05 + ink * pen * 0.30) * lvl * 0.62;
    // the circle being reeled in: a thin, bright zip, rising with its speed
    const zip = bpC(noise(), 1500 + 2600 * lvlT, 2.4).bp * lvlT * 0.12;
    const s = body + zip;
    const pl = Math.cos((pn + 1) * Math.PI / 4), pr = Math.sin((pn + 1) * Math.PI / 4);
    L[i] += s * pl * 1.4142; R[i] += s * pr * 1.4142;
  }
}

// ---------- 2. the click: the loop closes (exactly on T.close) ----------
{
  const i0 = Math.round(T.close * SR), bp = svf();
  for (let n = 0; n < SR * 0.25; n++) {
    const t = n / SR;
    const tick = bp(noise(), 3200, 1.1).bp * Math.exp(-t / 0.0045) * 0.20;      // the nick of the latch
    const ping = Math.sin(2 * Math.PI * 1780 * t) * Math.exp(-t / 0.014) * 0.07;  // a hint of metal
    const thump = Math.sin(2 * Math.PI * (150 - 40 * Math.min(1, t / 0.05)) * t) * Math.exp(-t / 0.05) * 0.24;  // soft body
    const s = tick + ping + thump;
    add(i0 + n, s, s);
  }
}

// ---------- 3. the thread is reeled out of the word: eight small, quiet ticks, each on the frame its stitch disappears ----------
sc.jumpSegs.forEach((j, k) => {
  const i0 = Math.round(sc.relEnd(j) * SR), bp = svf();
  const amp = 0.05 + (k === sc.jumpSegs.length - 1 ? 0.03 : 0);
  for (let n = 0; n < SR * 0.05; n++) {
    const t = n / SR, s = bp(noise(), 2600 + 120 * k, 1.5).bp * Math.exp(-t / 0.006) * amp;
    add(i0 + n, s * 0.9, s * 0.9);
  }
});

// ---------- 4. one warm low note under the final logo ----------
{
  const i0 = Math.round(T.note * SR), f0 = 98;                // G2
  const lp = svf();
  for (let n = 0; i0 + n < N; n++) {
    const t = n / SR;
    const att = 1 - Math.exp(-t / 0.07), dec = Math.exp(-t / 0.95);
    const end = 1 - clamp((t - (DUR - T.note - 0.35)) / 0.35);
    const env = att * (0.28 + 0.72 * dec) * Math.sin(Math.PI / 2 * end);
    let s = 0;
    for (const [mult, amp, det] of [[1, 1.0, 0], [1, 0.55, 0.9], [2, 0.32, 0.4], [3, 0.12, -0.3], [0.5, 0.40, 0]]) {
      s += Math.sin(2 * Math.PI * (f0 * mult + det) * t) * amp;
    }
    s = lp(s, 620, 0.7).lp * env * 0.30;
    add(i0 + n, s, s);
  }
}

// ---------- master: gentle limit, normalise to -3 dBFS, 16-bit stereo WAV ----------
let pk = 0; for (let i = 0; i < N; i++) pk = Math.max(pk, Math.abs(L[i]), Math.abs(R[i]));
const g = 0.708 / (pk || 1);
const buf = Buffer.alloc(44 + N * 4);
buf.write('RIFF', 0); buf.writeUInt32LE(36 + N * 4, 4); buf.write('WAVEfmt ', 8); buf.writeUInt32LE(16, 16);
buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22); buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28);
buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36); buf.writeUInt32LE(N * 4, 40);
for (let i = 0; i < N; i++) {
  buf.writeInt16LE(Math.round(Math.tanh(L[i] * g * 1.1) / Math.tanh(1.1) * 32000), 44 + i * 4);
  buf.writeInt16LE(Math.round(Math.tanh(R[i] * g * 1.1) / Math.tanh(1.1) * 32000), 46 + i * 4);
}
writeFileSync(out, buf);
console.log('wrote', out, 'peak before norm', pk.toFixed(3));
