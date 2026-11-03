/* Be The Man — "the thread" logo sting: motion model.
 * One file, two consumers: the composition (index.html) draws with it, and
 * tools/make-audio.mjs reads the same timing, so every sound lands on the frame
 * of the thing it belongs to.  Pure functions of time: same t -> same pixels.
 *
 * THE IDEA.  One amber thread leaves a dot, circles the frame, breaks out of the
 * circle and drops straight down into the stem of the B.  It writes BE THE MAN as
 * one unbroken line (cooling from amber to cream as it goes), runs home to the
 * point it started from and closes the loop: that point becomes the full stop.
 * The connecting thread is then pulled out of the word, and the letters, which
 * were held tight by it, relax into their final spacing.
 *
 * THE LOGO.  A custom monoline wordmark: every stroke the same weight, square
 * ends, one cut-corner (chamfer) detail, cream on near-black, one amber full stop.
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.Motion = factory();
})(this, function () {
  'use strict';

  const W = 1920, HH = 1080, CX = 960, CY = 540, FPS = 60, DUR = 6;
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, t) => a + (b - a) * t;
  const sstep = (x) => { x = clamp(x); return x * x * (3 - 2 * x); };
  const eInOutSine = (x) => -(Math.cos(Math.PI * clamp(x)) - 1) / 2;
  const eInOutCubic = (x) => { x = clamp(x); return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; };
  const eOutCubic = (x) => 1 - Math.pow(1 - clamp(x), 3);
  const eOutQuint = (x) => 1 - Math.pow(1 - clamp(x), 5);

  /* palette: straight from the Be The Man brand */
  const COL = {
    bg: '#0B0B0C', charcoal: '#141416', amber: '#E18B1F', hot: '#FFB84D', white: '#FFE3B8',
    cream: '#F2EEE6', stone: '#BFBCB6', mute: '#8C877E'
  };
  const hex = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
  const rgba = (h, a) => { const c = hex(h); return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')'; };

  /* ------------------------------------------------------------------ */
  /* timing (seconds).  Every sound and every picture event reads this.  */
  /* ------------------------------------------------------------------ */
  const T = {
    dotIn: 0.25,            // the dot appears
    go: 0.70,               // it starts to move
    tailA: 2.30, tailB: 3.95,   // the circle is reeled in behind the head
    close: 4.35,            // the head lands on the starting point: loop closed
    release: 4.35,          // the connecting thread is pulled out (click)
    note: 4.50,             // warm low note under the finished logo
    tagA: 271 / 60, tagB: 299 / 60, // tagline written (frames 271-299)
    still: 5.0              // from here the picture is one fixed frame
  };

  /* ------------------------------------------------------------------ */
  /* THE LOGO — glyph strokes in base units (cap height 200, stroke 36)  */
  /* Each glyph is ONE polyline the pen can trace without lifting; free   */
  /* ends sit on the outer edge, corners on the stroke centre line.       */
  /* ------------------------------------------------------------------ */
  const BH = 200, BW = 44, BC = 22;          // cap height, stroke weight, chamfer
  const GAP = 46, WORDGAP = 120, DOTGAP = 54; // letter gap, word gap, gap before the full stop
  const h = BW / 2, tt = h, bb = BH - h, mm = BH / 2;

  const GLYPHS = {
    B: (gw) => {
      const l = h, r = gw - h, c = BC;
      return [[l, 0], [l, mm], [l, tt], [r - c, tt], [r, tt + c], [r, mm - c], [r - c, mm], [l, mm], [l, bb],
        [r - c, bb], [r, bb - c], [r, mm + c], [r - c, mm]];
    },
    E: (gw) => {
      const l = h, r = gw - h, rm = gw - 16;
      return [[l, mm], [rm, mm], [l, mm], [l, tt], [gw, tt], [l, tt], [l, bb], [gw, bb], [gw - h, bb]];
    },
    T: (gw) => [[h, tt], [0, tt], [gw, tt], [gw / 2, tt], [gw / 2, BH], [gw / 2, bb]],
    H: (gw) => { const l = h, r = gw - h; return [[l, bb], [l, BH], [l, 0], [l, mm], [r, mm], [r, 0], [r, BH], [r, bb]]; },
    M: (gw) => {
      const l = h, r = gw - h, cx = gw / 2, vy = tt + 0.58 * (bb - tt);
      return [[l, bb], [l, BH], [l, tt], [cx, vy], [r, tt], [r, BH], [r, bb]];
    },
    A: (gw) => {
      const cx = gw / 2, ax1 = cx - 22, ax2 = cx + 22, yc = 152;
      const ext = 24;                                   // legs run past the baseline; the glyph clip cuts them flat
      const xf = h * 1.09;                              // foot centre so the outer edge lands on the glyph edge
      const lx = (y) => lerp(xf, ax1, (BH - y) / (BH - tt));
      const rx = (y) => lerp(gw - xf, ax2, (BH - y) / (BH - tt));
      const yE = BH + ext, kx = ext / (BH - tt);
      return [[lx(bb), bb], [xf - (ax1 - xf) * kx, yE], [ax1, tt], [ax2, tt], [rx(yc), yc], [lx(yc), yc], [rx(yc), yc],
        [gw - xf + (gw - xf - ax2) * kx, yE], [rx(bb), bb]];
    },
    N: (gw) => { const l = h, r = gw - h; return [[l, bb], [l, BH], [l, tt], [r, bb], [r, 0], [r, tt]]; }
  };
  const WORD = [
    { ch: 'B', gw: 138, gap: GAP }, { ch: 'E', gw: 104, gap: WORDGAP },
    { ch: 'T', gw: 132, gap: GAP }, { ch: 'H', gw: 140, gap: GAP }, { ch: 'E', gw: 104, gap: WORDGAP },
    { ch: 'M', gw: 172, gap: GAP }, { ch: 'A', gw: 174, gap: GAP }, { ch: 'N', gw: 144, gap: DOTGAP }
  ];

  /* ------------------------------------------------------------------ */
  /* the circling part: a rounded-corner polyline, sampled               */
  /* ------------------------------------------------------------------ */
  function roundedPath(pts, radii, step) {
    const out = [pts[0].slice()];
    for (let i = 1; i < pts.length - 1; i++) {
      const p = pts[i], a = pts[i - 1], b = pts[i + 1], R = radii[i] || 0;
      const d1 = [p[0] - a[0], p[1] - a[1]], d2 = [b[0] - p[0], b[1] - p[1]];
      const l1 = Math.hypot(d1[0], d1[1]), l2 = Math.hypot(d2[0], d2[1]);
      d1[0] /= l1; d1[1] /= l1; d2[0] /= l2; d2[1] /= l2;
      if (R <= 0) { out.push(p.slice()); continue; }
      const t1 = [p[0] - d1[0] * R, p[1] - d1[1] * R], t2 = [p[0] + d2[0] * R, p[1] + d2[1] * R];
      const c = [t1[0] + d2[0] * R, t1[1] + d2[1] * R];
      let a0 = Math.atan2(t1[1] - c[1], t1[0] - c[0]), a1 = Math.atan2(t2[1] - c[1], t2[0] - c[0]);
      let da = a1 - a0; while (da > Math.PI) da -= 2 * Math.PI; while (da < -Math.PI) da += 2 * Math.PI;
      const n = Math.max(2, Math.ceil(Math.abs(da) * R / step));
      for (let k = 0; k <= n; k++) { const a = a0 + da * k / n; out.push([c[0] + R * Math.cos(a), c[1] + R * Math.sin(a)]); }
    }
    out.push(pts[pts.length - 1].slice());
    return out;
  }

  /* the journeys.  Each ends dropping straight down into the stem of the B. */
  const JOURNEYS = {
    /* orbit: once round the whole frame, tightening inward, then the break and the drop */
    orbit: (p0, bx, top) => ({
      pts: [p0, [p0[0], 970], [80, 975], [80, 105], [1840, 105], [1840, 300], [bx, 300], [bx, top]],
      radii: [0, 150, 150, 150, 92, 92, 92, 0],
      keys: [[0.70, 0], [0.80, 0.05], [0.95, 0.30], [1.15, 0.80], [1.35, 1.0], [1.9, 0.86], [2.4, 0.92], [2.75, 0.9], [3.5, 0.9], [4.05, 0.81], [4.35, 0]]
    }),
    /* wrap: down, along the floor, up the left edge, across and down into the B */
    wrap: (p0, bx, top) => ({
      pts: [p0, [p0[0], 960], [70, 960], [70, 120], [bx, 120], [bx, top]],
      radii: [0, 170, 170, Math.floor((bx - 70) / 2) - 1, Math.floor((bx - 70) / 2) - 1, 0],
      keys: [[0.70, 0], [0.80, 0.05], [0.95, 0.30], [1.15, 0.85], [1.35, 1.0], [1.9, 0.72], [2.4, 0.56], [2.75, 0.52], [3.5, 0.56], [4.05, 0.50], [4.35, 0]]
    }),
    /* gantry: up, along the roof, a long rectangular loop back round the top, then the drop */
    gantry: (p0, bx, top) => ({
      pts: [p0, [p0[0], 110], [1840, 110], [1840, 960], [70, 960], [70, 270], [bx, 270], [bx, top]],
      radii: [0, 70, 70, 160, 160, Math.floor((bx - 70) / 2) - 1, Math.floor((bx - 70) / 2) - 1, 0],
      keys: [[0.70, 0], [0.80, 0.05], [0.95, 0.30], [1.15, 0.85], [1.35, 1.0], [1.9, 0.86], [2.45, 0.66], [2.8, 0.58], [3.5, 0.56], [4.05, 0.50], [4.35, 0]]
    })
  };

  /* monotone cubic through (t, v) keys */
  function pchip(keys) {
    const n = keys.length, x = keys.map((k) => k[0]), y = keys.map((k) => k[1]);
    const d = [], m = new Array(n);
    for (let i = 0; i < n - 1; i++) d.push((y[i + 1] - y[i]) / (x[i + 1] - x[i]));
    m[0] = d[0]; m[n - 1] = d[n - 2];
    for (let i = 1; i < n - 1; i++) m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
    for (let i = 0; i < n - 1; i++) {
      if (d[i] === 0) { m[i] = 0; m[i + 1] = 0; continue; }
      const a = m[i] / d[i], b = m[i + 1] / d[i], s = a * a + b * b;
      if (s > 9) { const tau = 3 / Math.sqrt(s); m[i] = tau * a * d[i]; m[i + 1] = tau * b * d[i]; }
    }
    m[0] = 0; m[n - 1] = 0;
    return (t) => {
      if (t <= x[0]) return y[0];
      if (t >= x[n - 1]) return y[n - 1];
      let i = 0; while (t > x[i + 1]) i++;
      const hh = x[i + 1] - x[i], u = (t - x[i]) / hh, u2 = u * u, u3 = u2 * u;
      return (2 * u3 - 3 * u2 + 1) * y[i] + (u3 - 2 * u2 + u) * hh * m[i] + (-2 * u3 + 3 * u2) * y[i + 1] + (u3 - u2) * hh * m[i + 1];
    };
  }

  /* ------------------------------------------------------------------ */
  function create(name, opts) {
    const o = Object.assign({ targetW: 1580, comp0: 0.05 }, opts || {});
    const jr = JOURNEYS[name] || JOURNEYS.orbit;

    /* ---- layout: scale the base word so word + full stop is o.targetW wide, centred ---- */
    let totalW = BW;                                   // the full stop
    WORD.forEach((g) => { totalW += g.gw + g.gap; });
    const k = o.targetW / totalW;
    const Hc = BH * k, w = BW * k;
    const left = CX - o.targetW / 2, top = CY - Hc / 2, bottom = top + Hc;
    const glyphs = [];
    let x = left;
    WORD.forEach((g, i) => {
      const loc = GLYPHS[g.ch](g.gw).map((p) => [x + p[0] * k, top + p[1] * k]);
      glyphs.push({ ch: g.ch, x0: x, gw: g.gw * k, pts: loc, cx: x + g.gw * k / 2 });
      x += (g.gw + g.gap) * k;
    });
    const dotC = [left + o.targetW - w / 2, bottom - w / 2];   // centre of the full stop = where the thread began
    const wordC = (glyphs[0].x0 + glyphs[glyphs.length - 1].x0 + glyphs[glyphs.length - 1].gw) / 2;
    const compOff = (i, comp) => (wordC - glyphs[i].cx) * comp;   // tension: letters held toward the middle

    /* ---- the one path: circling part, then glyph / jump / glyph ... / jump home ---- */
    const bStart = glyphs[0].pts[0];                   // (stem x, cap line) of the B
    // the drop lands on the B's stem as it is held under tension
    const bxHeld = bStart[0] + compOff(0, o.comp0);
    const J = jr(dotC, bxHeld, top);
    const sweep = roundedPath(J.pts, J.radii, 5);
    const V = [];      // vertices: {x, y, g}  g = glyph index (offset owner) or -1
    const SEG = [];    // segment j runs V[j] -> V[j+1]: {type, g}
    sweep.forEach((p) => V.push({ x: p[0], y: p[1], g: -1 }));
    for (let i = 1; i < V.length; i++) SEG.push({ type: 'sweep', g: -1 });
    const nSweepV = V.length;                          // V[nSweepV-1] is the B's first ink point
    glyphs.forEach((g, gi) => {
      g.pts.forEach((p, pi) => {
        const q = { x: p[0] + compOff(gi, o.comp0), y: p[1], g: gi };
        if (gi === 0 && pi === 0) { V[V.length - 1].g = 0; V[V.length - 1].x = q.x; return; }
        SEG.push({ type: pi === 0 ? 'jump' : 'ink', g: pi === 0 ? gi - 1 : gi });
        V.push(q);
      });
    });
    SEG.push({ type: 'jump', g: glyphs.length - 1 });   // N -> home
    V.push({ x: dotC[0], y: dotC[1], g: -1 });
    const n = V.length;
    const S = new Float64Array(n);
    for (let i = 1; i < n; i++) S[i] = S[i - 1] + Math.hypot(V[i].x - V[i - 1].x, V[i].y - V[i - 1].y);
    const L = S[n - 1], Lsw = S[nSweepV - 1];
    const segLen = (j) => S[j + 1] - S[j];
    // index ranges
    const inkRanges = [];       // per glyph: [firstSeg, lastSeg] (inclusive)
    const jumpSegs = [];        // segment indices of jumps in order
    SEG.forEach((sg, j) => {
      if (sg.type === 'ink') { const r = inkRanges[sg.g]; if (r) r[1] = j; else inkRanges[sg.g] = [j, j]; }
      if (sg.type === 'jump') jumpSegs.push(j);
    });
    // B's first ink segment follows the sweep directly
    const sweepSegs = [0, nSweepV - 2];

    /* ---- kinematics: head speed from the journey's key shape, scaled so the whole path is drawn by T.close ---- */
    const shape = pchip(J.keys);
    const t0 = J.keys[0][0], t1 = J.keys[J.keys.length - 1][0];
    const NT = Math.round((t1 - t0) * 2000);
    const cum = new Float64Array(NT + 1);
    for (let i = 1; i <= NT; i++) cum[i] = cum[i - 1] + 0.5 * (shape(t0 + (i - 1) / 2000) + shape(t0 + i / 2000)) / 2000;
    const lam = L / cum[NT];
    const headS = (t) => {
      if (t <= t0) return 0;
      if (t >= t1) return L;
      const f = (t - t0) * 2000, i = Math.floor(f);
      return lam * lerp(cum[i], cum[Math.min(NT, i + 1)], f - i);
    };
    const headV = (t) => lam * shape(clamp(t, t0, t1));
    // time at which the head passes arclength s
    const tOfS = (s) => {
      if (s <= 0) return t0;
      if (s >= L) return t1;
      let lo = 0, hi = NT;
      while (hi - lo > 1) { const m = (lo + hi) >> 1; if (lam * cum[m] <= s) lo = m; else hi = m; }
      return t0 + (lo + (s - lam * cum[lo]) / Math.max(1e-9, lam * (cum[hi] - cum[lo]))) / 2000;
    };
    const tailS = (t) => Lsw * eInOutSine((t - T.tailA) / (T.tailB - T.tailA));
    const tailV = (t) => { const e = 1 / 480; return (tailS(t + e) - tailS(t - e)) / (2 * e); };

    /* ---- state at time t ---- */
    // 0 -> 1 with a tiny (6%) overshoot, and EXACTLY 1 from u = 1 on, so the last second is truly still
    const settle = (u) => { if (u <= 0) return 0; if (u >= 1) return 1; const c = 1.3, v = u - 1; return 1 + (c + 1) * v * v * v + c * v * v; };
    const comp = (t) => o.comp0 * (1 - settle((t - T.release) / 0.6));
    const REL_STEP = 2 / 60, REL_DUR = 12 / 60;                       // frame-exact: every stitch starts and ends on a frame
    const relT = (j) => T.release + REL_STEP * jumpSegs.indexOf(j);   // the thread is reeled out left to right, tail first
    const relEnd = (j) => relT(j) + REL_DUR;
    const relFrac = (j, t) => eInOutSine((t - relT(j)) / REL_DUR);

    const pos = (i, c) => ({ x: V[i].x - (V[i].g >= 0 && V[i].g < glyphs.length ? compOff(V[i].g, o.comp0) - compOff(V[i].g, c) : 0), y: V[i].y });
    const ptAt = (s, c) => {
      s = clamp(s, 0, L);
      let lo = 0, hi = n - 1;
      while (hi - lo > 1) { const m = (lo + hi) >> 1; if (S[m] <= s) lo = m; else hi = m; }
      const f = (s - S[lo]) / Math.max(1e-9, S[hi] - S[lo]), a = pos(lo, c), b = pos(hi, c);
      return { x: lerp(a.x, b.x, f), y: lerp(a.y, b.y, f), dx: b.x - a.x, dy: b.y - a.y, seg: lo };
    };
    // one frame's pen position (for the sound's pan)
    const penPos = (t) => ptAt(headS(t), comp(t));

    return {
      name, k, Hc, w, left, top, bottom, glyphs, dotC, L, Lsw, V, S, SEG, n, nSweepV, inkRanges, jumpSegs, sweepSegs,
      lam, headS, headV, tOfS, tailS, tailV, comp, relT, relEnd, relFrac, pos, ptAt, penPos, wordC, compOff, comp0: o.comp0, totalW
    };
  }

  /* ------------------------------------------------------------------ */
  /* drawing                                                             */
  /* ------------------------------------------------------------------ */
  const THREAD = 0.32;     // the connecting thread is thinner than the stroke it is pulled out of
  const COOL = 0.34;       // seconds an ink stroke takes to cool from amber to cream
  const CHUNK = 14;

  function octagon(ctx, cx, cy, s, c) {
    const a = s / 2, ch = s * 0.22;
    ctx.beginPath();
    ctx.moveTo(cx - a + ch, cy - a); ctx.lineTo(cx + a - ch, cy - a); ctx.lineTo(cx + a, cy - a + ch);
    ctx.lineTo(cx + a, cy + a - ch); ctx.lineTo(cx + a - ch, cy + a); ctx.lineTo(cx - a + ch, cy + a);
    ctx.lineTo(cx - a, cy + a - ch); ctx.lineTo(cx - a, cy - a + ch); ctx.closePath();
    ctx.fillStyle = c; ctx.fill();
  }

  function glow(ctx, x, y, r, a, c) {
    const g = ctx.createRadialGradient(x, y, 0, x, y, r);
    for (let i = 0; i <= 10; i++) {                  // gaussian falloff: no visible ring at the edge
      const q = i / 10, f = Math.exp(-5 * q * q) * (1 - sstep((q - 0.8) / 0.2));
      g.addColorStop(q, rgba(c, a * f));
    }
    ctx.save(); ctx.globalCompositeOperation = 'screen'; ctx.fillStyle = g;
    ctx.fillRect(x - r, y - r, 2 * r, 2 * r); ctx.restore();
  }

  /* trace arclength [sa, sb] of segments jA..jB onto the current path (uses current positions) */
  function trace(sc, ctx, jA, jB, sa, sb, c) {
    let started = false;
    jA = Math.max(0, jA); jB = Math.min(sc.SEG.length - 1, jB);
    for (let j = jA; j <= jB; j++) {
      const s0 = sc.S[j], s1 = sc.S[j + 1];
      if (s1 <= sa || s0 >= sb) continue;
      const a = sc.pos(j, c), b = sc.pos(j + 1, c), len = Math.max(1e-9, s1 - s0);
      const fa = clamp((sa - s0) / len), fb = clamp((sb - s0) / len);
      const ax = lerp(a.x, b.x, fa), ay = lerp(a.y, b.y, fa), bx = lerp(a.x, b.x, fb), by = lerp(a.y, b.y, fb);
      if (!started) { ctx.moveTo(ax, ay); started = true; }
      ctx.lineTo(bx, by);
    }
    return started;
  }

  function drawScene(sc, ctx, t, opts) {
    const o = opts || {};
    const w = sc.w, c = sc.comp(t);
    const b = Math.min(sc.L, sc.headS(t)), a = Math.min(sc.Lsw, sc.tailS(t));
    const moving = t >= T.go;
    ctx.save();
    ctx.lineJoin = 'miter'; ctx.miterLimit = 40; ctx.lineCap = 'butt'; ctx.lineWidth = w;

    if (t >= T.dotIn) {
      /* ---- 1. thread (jumps): amber and thin, drawn first so the ink sits over its ends ---- */
      ctx.strokeStyle = COL.amber; ctx.lineWidth = w * THREAD;
      sc.jumpSegs.forEach((j) => {
        const len = sc.S[j + 1] - sc.S[j];
        const r = t >= T.close ? sc.relFrac(j, t) : 0;
        if (r >= 1) return;
        const sa = sc.S[j] + len * r, sb = Math.min(b, sc.S[j + 1]);
        if (sb <= sa) return;
        ctx.beginPath(); if (trace(sc, ctx, j, j, sa, sb, c)) ctx.stroke();
      });

      /* ---- 2. the circling part ---- */
      ctx.lineWidth = w;
      if (a < sc.Lsw) {
        ctx.strokeStyle = COL.amber;
        ctx.beginPath(); if (trace(sc, ctx, sc.sweepSegs[0], sc.sweepSegs[1], Math.max(0, a), Math.min(b, sc.Lsw), c)) ctx.stroke();
      }

      /* ---- 3. ink: each glyph clipped to its cap-height box so mitres land flat ---- */
      sc.glyphs.forEach((g, gi) => {
        const r = sc.inkRanges[gi]; if (!r) return;
        // the B's first segment is the stem; its first point is the end of the circling part
        if (b <= sc.S[r[0]]) return;
        ctx.save();
        ctx.beginPath(); ctx.rect(g.x0 + sc.compOff(gi, c) - 60, sc.top, g.gw + 120, sc.Hc); ctx.clip();
        const sa = sc.S[r[0]], sb = Math.min(b, sc.S[r[1] + 1]);
        ctx.strokeStyle = COL.cream;
        ctx.beginPath(); if (trace(sc, ctx, r[0], r[1], sa, sb, c)) ctx.stroke();
        // hot wake: amber while the stroke is fresh
        const tNow = t;
        for (let s = sa; s < sb; s += CHUNK) {
          const sm = Math.min(sb, s + CHUNK), age = tNow - sc.tOfS((s + sm) / 2), cool = sstep(age / COOL);
          if (cool > 0.985) continue;
          ctx.strokeStyle = mixCol(COL.amber, COL.cream, cool);
          ctx.beginPath(); if (trace(sc, ctx, r[0], r[1], s - 1.2, Math.min(sb, sm + 1.2), c)) ctx.stroke();
        }
        ctx.restore();
      });

      /* ---- 4. the hot tip: a short bright wake behind the head ---- */
      if (moving && b < sc.L && b > 0) {
        const tipL = 150;
        for (let s = Math.max(0, b - tipL); s < b; s += CHUNK) {
          const sm = Math.min(b, s + CHUNK), al = 0.95 * Math.pow(1 - (b - (s + sm) / 2) / tipL, 2.2);
          if (al < 0.03) continue;
          ctx.strokeStyle = mixCol(COL.amber, COL.hot, al);
          // the tip is drawn over whatever is under it; clip glyph strokes the same way
          const seg = sc.ptAt((s + sm) / 2, c).seg;
          if (sc.SEG[seg].type === 'ink') {
            const gi = sc.SEG[seg].g, g = sc.glyphs[gi];
            ctx.save(); ctx.beginPath(); ctx.rect(g.x0 + sc.compOff(gi, c) - 60, sc.top, g.gw + 120, sc.Hc); ctx.clip();
            ctx.beginPath(); if (trace(sc, ctx, seg - 4 < 0 ? 0 : seg - 4, seg + 4, s - 1.2, sm + 1.2, c)) ctx.stroke();
            ctx.restore();
          } else {
            ctx.lineWidth = sc.SEG[seg].type === 'jump' ? w * THREAD : w;
            ctx.beginPath(); if (trace(sc, ctx, 0, sc.SEG.length - 1, s - 1.2, sm + 1.2, c)) ctx.stroke();
            ctx.lineWidth = w;
          }
        }
      }
    }

    /* ---- 5. the two ends: tail (the dot we started from) and head ---- */
    if (t >= T.dotIn) {
      const flash = Math.exp(-(t - T.dotIn) / 0.16);
      const tp = sc.ptAt(a, c);
      if (a < sc.Lsw - w) {                                  // tail cap rides the line until it is reeled into the B
        glow(ctx, tp.x, tp.y, 70, 0.26 + 0.7 * flash, COL.amber);
        octagon(ctx, tp.x, tp.y, w, COL.amber);
      }
      if (b < sc.L && t >= T.go) {                           // head
        const hp = sc.ptAt(b, c);
        glow(ctx, hp.x, hp.y, 90, 0.36, COL.hot);
        octagon(ctx, hp.x, hp.y, w * 1.02, COL.hot);
      }
      if (t >= T.close) {                                    // the full stop: where the thread began
        const u = clamp((t - T.close) / 0.2);
        const os = 5 * Math.sin(Math.PI * u) * (1 - u);          // tiny overshoot along the line it arrived by
        const hp = sc.ptAt(sc.L - 0.5, c), dl = Math.hypot(hp.dx, hp.dy) || 1;
        const cool = sstep((t - T.close) / 0.45);
        const col = cool >= 1 ? COL.amber : mixCol(COL.hot, COL.amber, cool);
        const gl = 0.38 * Math.exp(-(t - T.close) / 0.22) * (1 - sstep((t - T.close) / 0.5));
        if (gl > 0.01) glow(ctx, sc.dotC[0], sc.dotC[1], 110, gl, COL.hot);
        octagon(ctx, sc.dotC[0] + hp.dx / dl * os, sc.dotC[1] + hp.dy / dl * os, w, col);
      } else if (t < T.go) {
        /* dot at rest: already drawn as the tail cap */
      }
    }
    ctx.restore();
  }

  function mixCol(a, b, t) {
    const A = hex(a), B = hex(b);
    return 'rgb(' + A.map((v, i) => Math.round(lerp(v, B[i], t))).join(',') + ')';
  }

  return { W, H: HH, CX, CY, FPS, DUR, T, COL, create, drawScene, JOURNEYS, lerp, clamp, sstep, eInOutSine, eInOutCubic, eOutCubic, eOutQuint, rgba };
});
