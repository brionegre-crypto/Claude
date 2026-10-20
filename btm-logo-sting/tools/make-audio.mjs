// Every sound in code, no samples. Reads the same motion model the picture uses,
// so the pen hiss follows the pen's real speed and the click / note sit on the
// exact frame of what they belong to.
//   node tools/make-audio.mjs <variant> <out.wav>
import { createRequire } from 'module';
import { writeFileSync } from 'fs';
const require = createRequire(import.meta.url);
const Motion = require('../motion.js');

const variant = process.argv[2] || 'lasso';
const out = process.argv[3] || 'assets/loop-sfx.wav';
const SR = 48000, DUR = 6, N = SR * DUR;
const T = Motion.T;
const scene = Motion.create(variant);

// ---------- helpers ----------
let seed = 7;
const rnd = () => { seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const gauss = () => (rnd() + rnd() + rnd() + rnd() - 2) * 1.7;
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const frame = (t) => Math.round(t * SR);

// TPT state-variable filter (stable with a per-sample cutoff)
function svf() {
  let s1 = 0, s2 = 0;
  return (x, fc, q) => {
    const g = Math.tan(Math.PI * Math.min(fc, SR * 0.45) / SR), k = 1 / q;
    const a1 = 1 / (1 + g * (g + k)), a2 = g * a1, a3 = g * a2;
    const v3 = x - s2, v1 = a1 * s1 + a2 * v3, v2 = s2 + a2 * s1 + a3 * v3;
    s1 = 2 * v1 - s1; s2 = 2 * v2 - s2;
    return { lp: v2, bp: v1, hp: x - k * v1 - v2 };
  };
}
const onePole = (fc) => { let y = 0; const a = 1 - Math.exp(-2 * Math.PI * fc / SR); return (x) => (y += a * (x - y)); };

// ---------- pen activity, sampled at 1 kHz from the picture's own motion ----------
const CR = 1000, nCtl = DUR * CR + 2;
const ctl = { main: new Float64Array(nCtl), stems: new Float64Array(nCtl), bowl: new Float64Array(nCtl), pan: new Float64Array(nCtl) };  // stems = letters
for (let i = 0; i < nCtl; i++) {
  const t = i / CR;
  const sp = scene.speeds(t);
  ctl.main[i] = Math.abs(sp.main); ctl.stems[i] = Math.abs(sp.letters); ctl.bowl[i] = 0;
  ctl.pan[i] = clamp((scene.penPos(t).x - 960) / 900, -1, 1);
}
const at = (arr, t) => { const f = t * CR, i = Math.floor(f); return arr[i] + (arr[Math.min(nCtl - 1, i + 1)] - arr[i]) * (f - i); };

// ---------- 1. pen on paper ----------
const penL = new Float32Array(N), penR = new Float32Array(N);
{
  const bpA = svf(), bpB = svf(), hpC = svf(), bodyF = svf();
  const smooth = onePole(38), smoothSp = onePole(60);
  const grainLP = onePole(170);
  let grain = 0;
  for (let i = 0; i < N; i++) {
    const t = i / SR;
    const m = at(ctl.main, t), st = at(ctl.stems, t), bw = at(ctl.bowl, t);
    // one number: how hard is the pen working right now (0..1)
    const raw = 1 - Math.exp(-(m / 3200 + 0.9 * st / 3000 + 0.9 * bw / 2600));
    const lvl = smooth(raw);
    const sp = smoothSp(clamp(m / 4200 + st / 6000 + bw / 3000));
    const w = gauss();
    // fibres: slowly wandering gain makes the hiss crawl like paper grain
    grain = grainLP(gauss()) * 5.5;
    const gmod = clamp(0.62 + 0.38 * grain, 0.1, 1.4);
    const fc = 1900 + 3600 * sp;
    const a = bpA(w, fc, 0.9).bp, b = bpB(w, fc * 0.55, 1.2).bp;
    const body = bodyF(w, 420 + 500 * sp, 1.4).bp;
    // sparse tiny ticks where the nib catches the grain
    let tick = 0;
    if (rnd() < (260 + 1500 * lvl) / SR) tick = (rnd() - 0.5) * 2.2;
    const hp = hpC(tick + 0.0, 2600, 0.8).hp;
    const sig = (a * 1.0 + b * 0.55 + body * 0.35) * gmod + hp * 0.9;
    const amp = Math.pow(lvl, 1.25) * 0.5;
    const s = sig * amp;
    const pan = at(ctl.pan, t) * 0.55, gl = Math.cos((pan + 1) * Math.PI / 4), gr = Math.sin((pan + 1) * Math.PI / 4);
    penL[i] = s * gl * 1.41; penR[i] = s * gr * 1.41;
  }
}

// ---------- 2. the click: loop closes ----------
const clkL = new Float32Array(N), clkR = new Float32Array(N);
{
  const n0 = frame(T.close);
  const lp = onePole(6500);
  for (let i = 0; i < SR * 0.5; i++) {
    const t = i / SR;
    let s = 0;
    s += 0.55 * Math.sin(2 * Math.PI * 1650 * t) * Math.exp(-t / 0.011);
    s += 0.30 * Math.sin(2 * Math.PI * 2480 * t) * Math.exp(-t / 0.006);
    s += 0.55 * Math.sin(2 * Math.PI * 880 * t) * Math.exp(-t / 0.020);
    s += 0.50 * Math.sin(2 * Math.PI * 196 * t) * Math.exp(-t / 0.045);
    s += (i < 90 ? gauss() * 0.35 * (1 - i / 90) : 0);
    s = lp(s);
    clkL[n0 + i] = s * 0.62; clkR[n0 + i] = s * 0.62;
  }
}

// ---------- 3. one warm low note under the finished logo ----------
const noteL = new Float32Array(N), noteR = new Float32Array(N);
{
  const n0 = frame(T.done), f0 = 110;           // A2
  const lp = onePole(1500), lp2 = onePole(1500);
  const partials = [[1, 1.0], [2, 0.62], [3, 0.30], [4, 0.14], [5, 0.06], [0.5, 0.22]];
  for (let i = 0; n0 + i < N; i++) {
    const t = i / SR, abs = n0 / SR + t;
    const att = 0.5 - 0.5 * Math.cos(Math.PI * clamp(t / 0.022));
    const dec = Math.exp(-t / 1.25);
    const tail = abs > 5.6 ? 0.5 + 0.5 * Math.cos(Math.PI * clamp((abs - 5.6) / 0.4)) : 1;
    let l = 0, r = 0;
    for (const [h, a] of partials) {
      const f = f0 * h;
      l += a * Math.sin(2 * Math.PI * f * 1.0007 * t + 0.3 * h);
      r += a * Math.sin(2 * Math.PI * f * 0.9993 * t + 0.9 * h);
    }
    // a touch of warmth from soft saturation, then roll the top off
    l = lp(Math.tanh(l * 0.85)); r = lp2(Math.tanh(r * 0.85));
    const e = att * dec * tail * 0.42;
    noteL[n0 + i] = l * e; noteR[n0 + i] = r * e;
  }
}

// ---------- tiny room for click + note (not the pen) ----------
function reverb(inp) {
  const combs = [1557, 1617, 1491, 1422].map((d) => ({ d, buf: new Float32Array(d), p: 0, lp: 0 }));
  const aps = [225, 556].map((d) => ({ d, buf: new Float32Array(d), p: 0 }));
  const out = new Float32Array(inp.length);
  for (let i = 0; i < inp.length; i++) {
    let s = 0;
    for (const c of combs) {
      const y = c.buf[c.p]; c.lp = y * 0.62 + c.lp * 0.38;
      c.buf[c.p] = inp[i] + c.lp * 0.80; c.p = (c.p + 1) % c.d; s += y;
    }
    for (const a of aps) {
      const y = a.buf[a.p]; const v = s + y * 0.5; a.buf[a.p] = v; s = y - v * 0.5; a.p = (a.p + 1) % a.d;
    }
    out[i] = s * 0.25;
  }
  return out;
}
const sendL = new Float32Array(N), sendR = new Float32Array(N);
for (let i = 0; i < N; i++) { sendL[i] = clkL[i] * 0.9 + noteL[i] * 0.5; sendR[i] = clkR[i] * 0.9 + noteR[i] * 0.5; }
const wetL = reverb(sendL), wetR = reverb(sendR.map((v, i) => v));

// ---------- mix, polish, write ----------
const L = new Float64Array(N), Rr = new Float64Array(N);
const hpL = svf(), hpR = svf();
for (let i = 0; i < N; i++) {
  const l = penL[i] * 1.0 + clkL[i] + noteL[i] + wetL[i] * 0.22;
  const r = penR[i] * 1.0 + clkR[i] + noteR[i] + wetR[i] * 0.22;
  L[i] = hpL(l, 38, 0.7).hp; Rr[i] = hpR(r, 38, 0.7).hp;
}
// fade the very first/last samples so nothing ever clicks at the edges
for (let i = 0; i < 96; i++) { const g = i / 96; L[i] *= g; Rr[i] *= g; L[N - 1 - i] *= g; Rr[N - 1 - i] *= g; }
let peak = 0;
for (let i = 0; i < N; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(Rr[i]));
const target = 0.56;   // about -5 dBFS peak: soft and premium, not loud
const g = target / Math.max(1e-6, peak);
const pcm = Buffer.alloc(N * 4);
for (let i = 0; i < N; i++) {
  pcm.writeInt16LE(Math.round(clamp(Math.tanh(L[i] * g * 1.0), -1, 1) * 32767), i * 4);
  pcm.writeInt16LE(Math.round(clamp(Math.tanh(Rr[i] * g * 1.0), -1, 1) * 32767), i * 4 + 2);
}
const hdr = Buffer.alloc(44);
hdr.write('RIFF', 0); hdr.writeUInt32LE(36 + pcm.length, 4); hdr.write('WAVE', 8); hdr.write('fmt ', 12);
hdr.writeUInt32LE(16, 16); hdr.writeUInt16LE(1, 20); hdr.writeUInt16LE(2, 22); hdr.writeUInt32LE(SR, 24);
hdr.writeUInt32LE(SR * 4, 28); hdr.writeUInt16LE(4, 32); hdr.writeUInt16LE(16, 34); hdr.write('data', 36); hdr.writeUInt32LE(pcm.length, 40);
writeFileSync(out, Buffer.concat([hdr, pcm]));
console.log(`wrote ${out}  (${variant})  raw peak ${peak.toFixed(3)}  gain ${g.toFixed(2)}  click@${frame(T.close)}  note@${frame(T.done)}`);
