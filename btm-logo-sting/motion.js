/* loop — logo + motion model.
 * One file, two consumers: the composition (index.html) draws with it, and
 * tools/make-audio.mjs reads the same timing so every sound lands on the frame
 * of the thing it belongs to.  Pure functions of time: same t -> same pixels.
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.Motion = factory();
})(this, function () {
  'use strict';

  const TAU = Math.PI * 2;
  const W = 1920, H = 1080, CX = 960, CY = 540;
  const FPS = 60, DUR = 6;

  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, t) => a + (b - a) * t;
  const sstep = (x) => { x = clamp(x); return x * x * (3 - 2 * x); };
  const eOutCubic = (x) => 1 - Math.pow(1 - clamp(x), 3);
  const eOutQuart = (x) => 1 - Math.pow(1 - clamp(x), 4);
  const eOutQuint = (x) => 1 - Math.pow(1 - clamp(x), 5);
  const eOutExpo = (x) => { x = clamp(x); return x >= 1 ? 1 : 1 - Math.pow(2, -10 * x); };
  const eInOutCubic = (x) => { x = clamp(x); return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; };
  const eInOutSine = (x) => -(Math.cos(Math.PI * clamp(x)) - 1) / 2;
  const eOutBack = (x, c = 1.4) => { x = clamp(x); const c3 = c + 1; return 1 + c3 * Math.pow(x - 1, 3) + c * Math.pow(x - 1, 2); };

  /* ------------------------------------------------------------------ */
  /* palette — straight from the Be The Man brand (build.mjs / render.mjs) */
  /* ------------------------------------------------------------------ */
  const COL = {
    bg: '#0B0B0C', glow: '#2A1D0E', cream: '#F2EEE6', amber: '#E18B1F',
    stone: '#BFBCB6', mute: '#8C877E'
  };
  const hex = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
  const mixHex = (a, b, t) => {
    const A = hex(a), B = hex(b);
    return 'rgb(' + A.map((v, i) => Math.round(lerp(v, B[i], t))).join(',') + ')';
  };

  /* ------------------------------------------------------------------ */
  /* THE LOGO — BE THE MAN: heavy condensed caps (Oswald 700, the brand  */
  /* face) over one straight amber rule.  The rule is the sweeping line,  */
  /* pulled taut: the cycle, broken into a foundation.                   */
  /* ------------------------------------------------------------------ */
  const S = 16;                     // the line / rule weight
  const RS = 72, K = 2.2, D = K * RS;   // seed curve: a closed loop (the "cycle")
  const LETTER_COUNT = 8;           // B E T H E M A N
  const STUB = 34;

  /* the seed curve: one closed line (two arcs + two straight tangents) that
   * starts and ends at its own crossing; local coords, crossing at (0,0) */
  function buildLoop(ds) {
    const R = RS, th = Math.acos(R / (D / 2)), CX1 = -D / 2, CX2 = D / 2;
    const xs = [], ys = [], ss = [];
    let s = 0;
    const push = (x, y) => { xs.push(x); ys.push(y); ss.push(s); };
    const T2a = [CX2 + R * Math.cos(Math.PI + th), R * Math.sin(Math.PI + th)];
    const T2b = [CX2 + R * Math.cos(Math.PI - th), R * Math.sin(Math.PI - th)];
    const T1a = [CX1 + R * Math.cos(-th), R * Math.sin(-th)];
    const T1b = [CX1 + R * Math.cos(th), R * Math.sin(th)];
    const sweep = TAU - 2 * th;
    const segs = [
      { k: 'line', a: [0, 0], b: T2a },
      { k: 'arc', c: [CX2, 0], a0: Math.PI + th, da: sweep },
      { k: 'line', a: T2b, b: T1a },
      { k: 'arc', c: [CX1, 0], a0: -th, da: -sweep },
      { k: 'line', a: T1b, b: [0, 0] }
    ];
    s = 0; push(0, 0);
    for (const sg of segs) {
      if (sg.k === 'line') {
        const len = Math.hypot(sg.b[0] - sg.a[0], sg.b[1] - sg.a[1]), n = Math.max(1, Math.round(len / ds)), s0 = s;
        for (let i = 1; i <= n; i++) { const f = i / n; s = s0 + len * f; push(lerp(sg.a[0], sg.b[0], f), lerp(sg.a[1], sg.b[1], f)); }
      } else {
        const len = Math.abs(sg.da) * R, n = Math.max(2, Math.round(len / ds)), s0 = s;
        for (let i = 1; i <= n; i++) { const f = i / n, a = sg.a0 + sg.da * f; s = s0 + len * f; push(sg.c[0] + R * Math.cos(a), sg.c[1] + R * Math.sin(a)); }
      }
    }
    const total = s;
    const dx = T2a[0], dy = T2a[1], dl = Math.hypot(dx, dy), ux = dx / dl, uy = dy / dl;
    const sx = [], sy = [], sS = [], nStub = Math.round(STUB / ds);
    for (let i = nStub; i >= 1; i--) { const v = -(i / nStub) * STUB; sx.push(ux * v); sy.push(uy * v); sS.push(v); }
    return { x: Float64Array.from(sx.concat(xs)), y: Float64Array.from(sy.concat(ys)), s: Float64Array.from(sS.concat(ss)), total };
  }
  const LOOP_HALF = D / 2 + RS;

  /* the journeys: the same closed curve, warped huge; the reel-in pulls it
   * taut into the rule.  shift = where the big crossing sits (frame centre = 0,0) */
  const VARIANTS = {
    lasso:   { kxR: 5.1, kxL: 4.7, kyR: 4.0, kyL: 3.5, tilt: -0.22, shift: { x: 20, y: -6 }, twist: 0, wave: null },
    horizon: { kxR: 7.2, kxL: 2.3, kyR: 3.1, kyL: 2.2, tilt: 0.06, shift: { x: -420, y: 60 }, twist: 0, wave: { amp: 70, freq: 0.0042, phase: 0.6 } },
    swirl:   { kxR: 3.3, kxL: 3.3, kyR: 2.45, kyL: 2.45, tilt: 0.1, shift: { x: 0, y: 0 }, twist: 1.6, twistR: 440, wave: null }
  };

  const T = {
    dotIn: 0.2, dotInDur: 0.12,
    driftA: 0.3, driftB: 0.9,
    launch: 1.0, peak: 1.3,
    close: 3.5,
    reel0: 2.4, reel1: 2.95,
    letA: 3.62, letStep: 0.06, letRise: 0.34,
    dryDelay: 0.08, dryLen: 0.24,
    settleA: 3.5, settleB: 5.0,
    done: 4.5,
    tagA: 4.5, tagB: 5.0,
    still: 5.0
  };
  const ZETA = 0.84;
  const OFF0 = { x: 0, y: 28 };

  /* layout = measured by the page from the real font: ink width W, cap height Hc, gap G between caps and rule */
  function create(name, layout) {
    const V = VARIANTS[name] || VARIANTS.lasso;
    const LY = Object.assign({ W: 1100, Hc: 128, G: 36 }, layout || {});
    const totH = LY.Hc + LY.G + S;
    const BASE_Y = -totH / 2 + LY.Hc;                 // baseline of the caps
    const RULE_Y = BASE_Y + LY.G + S / 2;             // centre-line of the rule
    const RULE_TOP = RULE_Y - S / 2;
    const FX = (LY.W / 2 - S / 2) / LOOP_HALF;        // loop -> rule: stretch x, flatten y
    const F = buildLoop(1.25);
    const n = F.s.length;

    const big = (px, py) => {                          // the fully warped (huge) curve
      const side = sstep((px + 20) / 40);
      const kx = lerp(V.kxL, V.kxR, side), ky = lerp(V.kyL, V.kyR, side);
      let x = px * kx, y = py * ky;
      if (V.wave) y += V.wave.amp * Math.sin(x * V.wave.freq + V.wave.phase);
      let ang = V.tilt;
      if (V.twist) ang += V.twist * Math.min(1, Math.hypot(x, y) / V.twistR);
      const c = Math.cos(ang), s = Math.sin(ang);
      return [x * c - y * s + V.shift.x, x * s + y * c + V.shift.y];
    };
    function warp(px, py, ws) {                        // ws 1 = huge curve, 0 = the rule
      const w = Math.max(0, ws), o = Math.max(0, -ws);   // a negative ws is the tiny overshoot: rule snaps 3% shorter
      const b = big(px, py);
      const fx = px * FX * (1 - o), fy = RULE_Y;
      return [lerp(fx, b[0], w), lerp(fy, b[1], w)];
    }
    function reel(un, t) {
      const ts = lerp(T.reel0, T.reel1, un);
      if (t <= ts) return 0;
      if (t >= T.close + 1.2) return 1;
      const tau = t - ts, tauC = T.close - ts;
      const wd = (Math.PI - Math.acos(ZETA)) / tauC, w = wd / Math.sqrt(1 - ZETA * ZETA);
      return 1 - Math.exp(-ZETA * w * tau) * (Math.cos(wd * tau) + (ZETA * w / wd) * Math.sin(wd * tau));
    }
    const wsAt = (un, t) => 1 - reel(un, t);

    const Lb = new Float64Array(n);
    let i0 = 0;
    for (let i = 0; i < n; i++) if (F.s[i] >= 0) { i0 = i; break; }
    for (let i = 1; i < n; i++) {
      const a = warp(F.x[i - 1], F.y[i - 1], 1), b = warp(F.x[i], F.y[i], 1);
      Lb[i] = Lb[i - 1] + Math.hypot(b[0] - a[0], b[1] - a[1]);
    }
    const off = Lb[i0];
    for (let i = 0; i < n; i++) Lb[i] -= off;
    const LB0 = Lb[0], LB1 = Lb[n - 1];

    const NG = 2400, gCum = new Float64Array(NG + 1);
    const gSpeed = (t) => {
      if (t <= T.launch || t >= T.close) return 0;
      if (t < T.peak) return Math.sin((t - T.launch) / (T.peak - T.launch) * Math.PI / 2);
      const y = (t - T.peak) / (T.close - T.peak);
      return (1 + Math.cos(Math.PI * Math.pow(y, 0.6))) / 2;
    };
    for (let i = 1; i <= NG; i++) {
      const t = T.launch + (T.close - T.launch) * (i / NG), t0 = T.launch + (T.close - T.launch) * ((i - 1) / NG);
      gCum[i] = gCum[i - 1] + 0.5 * (gSpeed(t) + gSpeed(t0)) * (T.close - T.launch) / NG;
    }
    const gTot = gCum[NG];
    const sbAt = (t) => {
      if (t <= T.launch) return LB0;
      if (t >= T.close) return LB1;
      const f = (t - T.launch) / (T.close - T.launch) * NG, i = Math.floor(f);
      return LB0 + (LB1 - LB0) * lerp(gCum[i], gCum[Math.min(NG, i + 1)], f - i) / gTot;
    };
    const sfFromSb = (sb) => {
      if (sb <= LB0) return F.s[0];
      if (sb >= LB1) return F.s[n - 1];
      let lo = 0, hi = n - 1;
      while (hi - lo > 1) { const m = (lo + hi) >> 1; if (Lb[m] <= sb) lo = m; else hi = m; }
      return lerp(F.s[lo], F.s[hi], (sb - Lb[lo]) / Math.max(1e-9, Lb[hi] - Lb[lo]));
    };
    const idxAtS = (sv) => {
      let lo = 0, hi = n - 1;
      if (sv <= F.s[0]) return [0, 0];
      if (sv >= F.s[n - 1]) return [n - 2, 1];
      while (hi - lo > 1) { const m = (lo + hi) >> 1; if (F.s[m] <= sv) lo = m; else hi = m; }
      return [lo, (sv - F.s[lo]) / (F.s[hi] - F.s[lo])];
    };
    const pointAtS = (sv, t) => {
      const [i, f] = idxAtS(sv);
      return warp(lerp(F.x[i], F.x[i + 1], f), lerp(F.y[i], F.y[i + 1], f), wsAt(clamp(sv / F.total), t));
    };
    const offset = (t) => {
      const e = eOutQuint((t - T.settleA) / (T.settleB - T.settleA));
      return { x: OFF0.x * (1 - e), y: OFF0.y * (1 - e) };
    };
    const penS = (t) => {
      if (t < T.launch) return -STUB * eInOutSine((t - T.driftA) / (T.driftB - T.driftA));
      return sfFromSb(sbAt(t));
    };

    /* the caps rise out of the rule, left to right, born amber, cooling to cream */
    const letterState = (li, t) => {
      const t0 = T.letA + li * T.letStep;
      return { p: eOutCubic((t - t0) / T.letRise), dry: sstep((t - (t0 + T.dryDelay)) / T.dryLen) };
    };

    const inkLen = (t) => {
      let letters = 0;
      for (let i = 0; i < LETTER_COUNT; i++) letters += letterState(i, t).p * LY.Hc;
      return { main: t >= T.launch ? sbAt(t) - LB0 : 0, letters };
    };
    const speeds = (t) => {
      const h = 1 / 240, a = inkLen(t - h), b = inkLen(t + h);
      return { main: (b.main - a.main) / (2 * h), letters: (b.letters - a.letters) / (2 * h) };
    };
    const penPos = (t) => {
      const o = offset(t);
      if (t < T.close) { const p = pointAtS(penS(t), t); return { x: CX + o.x + p[0], y: CY + o.y + p[1] }; }
      const li = clamp(Math.floor((t - T.letA) / T.letStep), 0, LETTER_COUNT - 1);
      return { x: CX + o.x + (li / (LETTER_COUNT - 1) - 0.5) * LY.W * 0.8, y: CY + o.y + RULE_Y };
    };

    /* the line itself: dot -> sweeping stroke -> rule */
    function drawScene(ctx, t) {
      const o = offset(t);
      ctx.save();
      ctx.translate(CX + o.x, CY + o.y);
      ctx.lineCap = 'square'; ctx.lineJoin = 'round'; ctx.lineWidth = S;
      ctx.strokeStyle = COL.amber; ctx.fillStyle = COL.amber;
      if (t >= T.dotIn) {
        const sHead = penS(t), p0 = pointAtS(sHead, t);
        if (t < T.launch) {
          const k = eOutBack((t - T.dotIn) / T.dotInDur, 2.2), h = Math.max(0, S * 0.65 * k);
          ctx.fillRect(p0[0] - h, p0[1] - h, 2 * h, 2 * h);        // the pen tip: a square, not a bubble
        } else {
          ctx.beginPath();
          const [ih] = idxAtS(sHead);
          ctx.moveTo(...pointAtS(F.s[0], t));
          for (let i = 1; i <= ih; i++) {
            const p = warp(F.x[i], F.y[i], wsAt(clamp(F.s[i] / F.total), t));
            ctx.lineTo(p[0], p[1]);
          }
          ctx.lineTo(p0[0], p0[1]);
          ctx.stroke();
          if (ih < 1) { const h = S * 0.65; ctx.fillRect(p0[0] - h, p0[1] - h, 2 * h, 2 * h); }
        }
      }
      ctx.restore();
    }

    return { name, V, LY, BASE_Y, RULE_Y, RULE_TOP, totH, F, warp, wsAt, reel, sbAt, penS, pointAtS, offset, speeds, penPos,
      drawScene, letterState, lengths: { big: LB1 - LB0, loop: F.total } };
  }

  return { create, mix: mixHex, VARIANTS, T, COL, W, H, CX, CY, FPS, DUR, TAU,
    LETTER_COUNT, S, ease: { clamp, lerp, sstep, eOutCubic, eOutQuart, eOutQuint, eOutExpo, eInOutCubic, eInOutSine, eOutBack } };
});
