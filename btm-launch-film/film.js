/* Be The Man — 20 s launch film: the shared model.
 * The page (index.html) draws from it and tools/make-audio.mjs reads the same numbers,
 * so every sound lands on the frame of the thing it belongs to.  Everything is a pure
 * function of time t (seconds).  100 BPM: one beat = 0.6 s; scene landings sit on beats.
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.Film = factory();
})(this, function () {
  'use strict';

  const DUR = 20, FPS = 60, BEAT = 0.6;
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, t) => a + (b - a) * t;
  const sstep = (x) => { x = clamp(x); return x * x * (3 - 2 * x); };
  const eInOut = (x) => { x = clamp(x); return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; };
  const eOut = (x) => 1 - Math.pow(1 - clamp(x), 3);
  const eOut5 = (x) => 1 - Math.pow(1 - clamp(x), 5);
  const eInOutSine = (x) => -(Math.cos(Math.PI * clamp(x)) - 1) / 2;
  const snap = (t) => Math.round(t * FPS) / FPS;           // every event sits on a frame

  /* brand */
  const COL = { cream: '#F2EEE6', ink: '#0B0B0C', amber: '#E18B1F', hot: '#FFB84D', charcoal: '#141416', stone: '#BFBCB6', mute: '#8C877E', paper: '#FBF9F4', ghost: '#E8E3D8' };

  /* seeded rng */
  const rng = (seed) => () => { seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };

  /* monotone cubic through keys [[t, v], ...] */
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
    return (t) => {
      if (t <= x[0]) return y[0] + m[0] * (t - x[0]) * 0;
      if (t >= x[n - 1]) return y[n - 1];
      let i = 0; while (t > x[i + 1]) i++;
      const hh = x[i + 1] - x[i], u = (t - x[i]) / hh, u2 = u * u, u3 = u2 * u;
      return (2 * u3 - 3 * u2 + 1) * y[i] + (u3 - 2 * u2 + u) * hh * m[i] + (-2 * u3 + 3 * u2) * y[i + 1] + (u3 - u2) * hh * m[i + 1];
    };
  }

  /* ------------------------------------------------------------------ */
  /* the script                                                          */
  /* ------------------------------------------------------------------ */
  const WORDS = {
    hook: 'YOU MEANT IT.', sub: 'Every time.',
    s2: 'WRITE IT DOWN.', s3: 'SCORE YOUR WEEK.', s4: 'IT COMES BACK.',
    question: 'What type of man do you want to be?',
    sentence: 'I’m a man who is home on time, and fully there when I am.',
    tagline: 'Break the cycle. Build the system. Be the man.',
    label: 'FREE STEP 1  ·  GO.BETHEMANSYSTEM.COM/FRAMEWORK'
  };

  /* scene landings, all on the beat */
  const L = { s2: 7 * BEAT, s3: 14 * BEAT, s4: 21 * BEAT, s5: 28 * BEAT };   // 4.2, 8.4, 12.6, 16.8

  const T = {
    dotIn: snap(0.30), go: snap(0.55), headDone: snap(1.75),
    subA: 2.0,                         // "Every time." is typed
    loopA: 2.4, loopB: 3.3,            // the line makes its loop (the cycle)
    openA: 3.3, openB: 4.2,            // the line opens into the window (lands on beat 7)
    sentA: 4.75,                       // the sentence is typed
    press: snap(7.3),                  // "Save my sentence" is pressed: the worksheet gives way to the scorecard
    scrollA: 7.5, scrollB: 8.4,        // the window scrolls from the worksheet to the scorecard (lands on beat 14)
    checks: [9.2, 10.0, 10.8],         // the thread reaches each habit
    flipA: 11.0, flipB: 12.6,         // the window turns over: the email
    emailA: 12.75,                     // the sentence comes back (focus pull)
    press2: snap(15.3),                // "Open this week's scorecard" is pressed
    weekFill: [snap(14.1), snap(14.5), snap(14.9)],   // 3 of 5 days, filled one by one
    collapseA: 15.8, collapseB: 16.4,
    darkA: 15.95, darkB: 16.8,
    morphA: 16.0, morphB: 16.8
  };

  /* band: the headline, letter by letter, flips into the next one */
  const BAND = [
    { t0: 3.5, to: WORDS.s2 }, { t0: 7.65, to: WORDS.s3 }, { t0: 11.85, to: WORDS.s4 }, { t0: 15.9, to: '' }
  ];
  const FLIP_STAG = 0.028, FLIP_DUR = 0.32;
  const bandStrings = [WORDS.hook, WORDS.s2, WORDS.s3, WORDS.s4, ''];

  /* typing: irregular, human, deterministic */
  function typeSchedule(start, text, cps, seed) {
    const r = rng(seed), out = []; let t = start;
    for (let i = 0; i < text.length; i++) {
      out.push(snap(t));
      let dt = (1 / cps) * (0.62 + 0.76 * r());
      const ch = text[i]; if (ch === ',') dt += 0.2; else if (ch === '.') dt += 0.26; else if (ch === ' ') dt *= 0.85;
      t += dt;
    }
    return out;
  }
  const SUB_T = typeSchedule(T.subA, WORDS.sub, 13, 5);
  const SENT_T = typeSchedule(T.sentA, WORDS.sentence, 21, 9);
  const typedCount = (times, t) => { let n = 0; while (n < times.length && times[n] <= t) n++; return n; };

  /* camera: always moving, slowly */
  const camKeys = {
    dz: pchip([[0, -140], [4.2, -60], [8.4, 10], [12.6, 60], [16.8, 120], [20, 170]]),
    ry: pchip([[0, -2.2], [4.2, 3.2], [8.4, -2.6], [12.6, 3.0], [16.8, -1.0], [20, 1.0]]),
    rx: pchip([[0, 1.5], [4.2, -2.0], [8.4, 2.2], [12.6, -1.4], [16.8, 0.5], [20, 0]]),
    px: pchip([[0, 40], [4.2, -30], [8.4, 20], [12.6, -26], [16.8, 0], [20, 0]]),
    py: pchip([[0, 8], [4.2, -14], [8.4, 12], [12.6, -8], [16.8, 0], [20, 0]])
  };
  const camera = (t) => ({ dz: camKeys.dz(t), ry: camKeys.ry(t), rx: camKeys.rx(t), px: camKeys.px(t), py: camKeys.py(t) });

  /* the window's own turn (degrees about Y) and tilt */
  const winYaw = pchip([[3.3, -17], [8.4, -5], [11.0, 9], [11.8, 60], [12.6, 171], [15.8, 179], [16.4, 180]]);
  const winPitch = pchip([[3.3, 6], [8.4, 3], [12.6, 5], [16.4, 0]]);
  const winOpen = (t) => eInOut((t - T.openA) / (T.openB - T.openA));
  const winCollapse = (t) => 1 - eInOut((t - T.collapseA) / (T.collapseB - T.collapseA));

  /* the line's routes and how it travels between them */
  const MORPHS = [
    { t0: T.loopA, t1: T.loopB, from: 'line', to: 'loop' },
    { t0: 3.3, t1: 4.2, from: 'loop', to: 'r2' },
    { t0: 7.5, t1: 8.4, from: 'r2', to: 'r3' },
    { t0: 12.1, t1: 12.75, from: 'r3', to: 'r4' },
    { t0: T.morphA, t1: T.morphB, from: 'r4', to: 'sting' }
  ];
  const headX = (t) => eOut(clamp((t - T.go) / (T.headDone - T.go)));       // 0..1 across the frame
  /* how hard the line is working, for the sound (0..1) */
  const lineActivity = (t) => {
    let a = 0;
    if (t > T.go && t < T.headDone + 0.1) { const u = (t - T.go) / (T.headDone - T.go); a = Math.max(a, Math.pow(1 - clamp(u), 1.6) * 0.9 + 0.1 * (u < 1 ? 1 : 0)); }
    MORPHS.forEach((m) => { const u = (t - m.t0) / (m.t1 - m.t0); if (u > 0 && u < 1) a = Math.max(a, 0.75 * Math.sin(Math.PI * u)); });
    return a;
  };

  /* the pulse that runs the connected thread: it reaches each habit in turn */
  const pulseTimes = [T.checks[0] - 0.55, T.checks[0], T.checks[1], T.checks[2]];

  /* the logo scene is the thread sting, time-warped */
  const STING = { ts0: 2.3, tsClose: 4.35, tf0: L.s5, closeFilm: snap(L.s5 + 1.65) };
  STING.speed = (STING.tsClose - STING.ts0) / (STING.closeFilm - STING.tf0);        // the sting runs a little fast; its loop closes on a frame
  const tsOf = (tf) => STING.ts0 + (tf - STING.tf0) * STING.speed;
  const tfOf = (ts) => STING.tf0 + (ts - STING.ts0) / STING.speed;

  return {
    DUR, FPS, BEAT, COL, WORDS, L, T, BAND, FLIP_STAG, FLIP_DUR, bandStrings, SUB_T, SENT_T, typedCount, typeSchedule,
    camera, winYaw, winPitch, winOpen, winCollapse, MORPHS, headX, lineActivity, pulseTimes, STING, tsOf, tfOf,
    clamp, lerp, sstep, eInOut, eOut, eOut5, eInOutSine, snap, rng, pchip
  };
});
