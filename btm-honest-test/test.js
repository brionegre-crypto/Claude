/* Be The Man — "The Low Seat Check" 60 s motion graphic: the shared model.
 * The page (index.html) draws from it and tools/make-audio.mjs reads the same numbers, so every sound sits on the frame of the thing it belongs to.
 * The wording, the scoring and the result texts below are copied from https://bethemansystem.com/humility/ (assets/humility-page-snapshot.html).
 * 100 BPM: one beat = 0.6 s, 60 s = 100 beats; scene landings sit on beats.
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.LS = factory();
})(this, function () {
  'use strict';
  const DUR = 60, FPS = 60, BEAT = 0.6;
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, t) => a + (b - a) * t;
  const sstep = (x) => { x = clamp(x); return x * x * (3 - 2 * x); };
  const eInOut = (x) => { x = clamp(x); return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; };
  const eOut = (x) => 1 - Math.pow(1 - clamp(x), 3);
  const eOut5 = (x) => 1 - Math.pow(1 - clamp(x), 5);
  const eInOutSine = (x) => -(Math.cos(Math.PI * clamp(x)) - 1) / 2;
  const snap = (t) => Math.round(t * FPS) / FPS;
  const rng = (seed) => () => { seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  function pchip(keys) {
    const n = keys.length, x = keys.map((k) => k[0]), y = keys.map((k) => k[1]), d = [], m = new Array(n);
    for (let i = 0; i < n - 1; i++) d.push((y[i + 1] - y[i]) / (x[i + 1] - x[i]));
    m[0] = d[0]; m[n - 1] = d[n - 2];
    for (let i = 1; i < n - 1; i++) m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
    for (let i = 0; i < n - 1; i++) {
      if (d[i] === 0) { m[i] = 0; m[i + 1] = 0; continue; }
      const a = m[i] / d[i], b = m[i + 1] / d[i], s = a * a + b * b;
      if (s > 9) { const tau = 3 / Math.sqrt(s); m[i] = tau * a * d[i]; m[i + 1] = tau * b * d[i]; }
    }
    return (t) => {
      if (t <= x[0]) return y[0];
      if (t >= x[n - 1]) return y[n - 1];
      let i = 0; while (t > x[i + 1]) i++;
      const hh = x[i + 1] - x[i], u = (t - x[i]) / hh, u2 = u * u, u3 = u2 * u;
      return (2 * u3 - 3 * u2 + 1) * y[i] + (u3 - 2 * u2 + u) * hh * m[i] + (-2 * u3 + 3 * u2) * y[i + 1] + (u3 - u2) * hh * m[i + 1];
    };
  }

  /* the new site's palette (assets/site-snapshot.css) */
  const COL = { bg: '#000000', tile: '#111113', tile2: '#1c1c1e', fg: '#f5f5f7', muted: '#a1a1a6', dim: '#7c7c82', accent: '#e18b1f', hi: '#f6b24f', onAccent: '#0b0b0c', room: '#0e0c0a' };

  /* ---------------- the test, verbatim from the page ---------------- */
  const P = [
    { k: 'teachable', name: 'Teachable', short: 'Correction lands', ref: 'Proverbs 12:1', why: 'A man who can’t be corrected stays the same man. Your answers say correction bounces off you more than it lands.', time: 'Your Sunday review, before you plan the week.', act: 'Ask your wife or a brother one question: “Where am I hard to correct?” Listen. Say thank you. Say nothing else.', test: 'If you asked them, they would say you didn’t defend yourself once.' },
    { k: 'owned', name: 'Owned', short: 'Misses get owned', ref: 'Proverbs 28:13', why: 'Explaining a miss feels like honesty. It’s usually a defense. Your answers say you explain more than you own.', time: 'Tonight, after the house goes down.', act: 'Pick the last miss you explained instead of owned. Go back to that person and name it in one sentence, with no “but”.', test: 'You said what you did, not how it was taken, and you didn’t ask for anything back.' },
    { k: 'unseen', name: 'Unseen', short: 'Service nobody sees', ref: 'Matthew 6:3–4', why: 'Service that needs an audience is a trade. Your answers say more of your good work gets noticed than goes unseen.', time: 'One evening this week. Put it on your Weekly Scorecard.', act: 'Do one job at home that nobody will see or thank you for. Tell no one, not even on Sunday.', test: 'The week ends and nobody knows. That’s the point.' },
    { k: 'credit', name: 'Credit', short: 'Credit flows out', ref: 'Philippians 2:3', why: 'A humble man lets the spotlight move. Your answers say it tends to drift back to you.', time: 'Every conversation, all week.', act: 'Before you tell your story, ask the other man a second question about his.', test: 'At least once this week, someone else’s win got your full attention and you didn’t mention yours.' },
    { k: 'dependent', name: 'Dependent', short: 'The bent knee', ref: 'James 4:10', why: 'Pride says it all depends on you. Your answers say you run your week as if God is a backup plan.', time: 'Before your next real decision, at home or at work.', act: 'Pray about it before you decide, not after. Write the time on your Weekly Scorecard like any other commitment.', test: 'The prayer came first, and you can say when it happened.' }
  ];
  const Q = [
    [0, 'When my wife or a friend corrects me, I can say “you’re right” without adding a “but”.'],
    [0, 'I ask someone I trust where I’m falling short, without waiting for a crisis.'],
    [0, 'When I’m corrected, my first move is to explain why it happened.', 1],
    [0, 'In the last year I changed my mind about something that mattered because someone showed me I was wrong.'],
    [1, 'When I miss something I committed to, I tell the person before they have to ask.'],
    [1, 'My apologies name what I did, not how it was taken.'],
    [1, 'When something goes wrong at home, I find a reason it wasn’t really my fault.', 1],
    [1, 'I apologize out loud to my kids, or to people who work under me.'],
    [2, 'I do work at home that nobody will notice or thank me for.'],
    [2, 'When I help, I make sure someone knows it was me.', 1],
    [2, 'I take the worst seat, the worst job or the last plate without being asked.'],
    [2, 'I give time to people who can do nothing for me.'],
    [3, 'When someone gets praised for something I helped with, it doesn’t bother me.'],
    [3, 'In conversation, I steer it back to my own story or my own wins.', 1],
    [3, 'I can honestly celebrate when another man succeeds at something I want.'],
    [3, 'I let someone else’s idea win without needing to improve it first.'],
    [4, 'I pray about decisions before I’ve already made them.'],
    [4, 'I run my week as if everything depends on me.', 1],
    [4, 'I ask for help before I’m out of options.'],
    [4, 'When things go well, I thank God before I credit myself.']
  ];
  const SCALE = ['Never', 'Rarely', 'Sometimes', 'Often', 'Almost always'];
  const BANDS = [
    [80, 'The low seat.', 'Humility shows up in what you do, not just in what you believe about yourself. Guard it: it’s the easiest thing to lose by noticing you have it.'],
    [60, 'Mostly low, with one high place.', 'You’re further along than most men, and there’s one place where pride still has a seat at your table. That’s normal. It’s also exactly where your wife is waiting for you to change.'],
    [40, 'Defended.', 'You probably think of yourself as humble, and in some places you are. But under pressure you protect yourself first. The good news: defenses are habits, and habits can be rebuilt.'],
    [0, 'Head of the table.', 'This is an honest result, and it took humility to give honest answers. Most men never look this squarely. Start with one posture this week, not five.']
  ];
  const value = (q, a) => (Q[q][2] ? 6 - a : a);
  const scores = (ans) => { const s = [0, 0, 0, 0, 0]; for (let q = 0; q < 20; q++) s[Q[q][0]] += value(q, ans[q]); return s.map((x) => Math.round((x - 4) / 16 * 100)); };
  const overall = (s) => Math.round(s.reduce((a, b) => a + b, 0) / s.length);

  /* one illustrative run: his answers, and the answers of the witness (his wife) */
  const HIS = [4, 4, 4, 3, 4, 3, 3, 3, 4, 3, 4, 3, 4, 4, 4, 4, 3, 5, 3, 2];
  const WIT = [3, 3, 4, 2, 3, 3, 4, 2, 3, 4, 3, 3, 3, 4, 3, 3, 3, 5, 2, 2];
  const S = scores(HIS), W = scores(WIT), SO = overall(S), WO = overall(W);
  const band = (n) => BANDS.filter((b) => n >= b[0])[0];
  const thinnest = S.indexOf(Math.min.apply(null, S));
  let gapN = 0, gapV = -1; P.forEach((p, n) => { if (S[n] - W[n] > gapV) { gapV = S[n] - W[n]; gapN = n; } });
  const cmpText = 'You scored yourself ' + SO + '. Your witness scored you ' + WO + '. ' + (Math.abs(SO - WO) < 8 ? 'That’s close. The two of you see the same man.' : (SO > WO ? 'The gap is the blind spot. It’s worth one honest conversation.' : 'You’re harder on yourself than your witness is. Listen to that too.'));

  const WORDS = {
    kicker: 'THE LOW SEAT CHECK  ·  FREE  ·  5 MINUTES', h1a: 'How humble are you', h1b: 'on a Tuesday?',
    lede: 'Every man thinks he’s humble. The people at his kitchen table know better. This check skips how humble you feel and asks what you actually do: when you’re corrected, when you miss, when nobody’s watching, when someone else gets the credit.',
    verse: '“When you are invited, go and sit in the lowest place.”', cite: 'Luke 14:10',
    how: 'Twenty statements. For each, choose how often it’s true of you in the last month, not on your best week.',
    get: 'A score across five postures, the one that’s thinnest, and one action for this week with a time on it.',
    start: 'Start the check', fine: 'Nothing is saved or sent anywhere.',
    wit1: 'Get a second witness', wit2: 'You can’t see your own blind spot. Someone at your table can.', witBtn: 'Send to a witness', copied: 'Link copied. Paste it in a text.',
    tagline: 'Faith should function.', url: 'BETHEMANSYSTEM.COM/HUMILITY', label: 'THE LOW SEAT CHECK  ·  FREE  ·  5 MINUTES', example: 'An illustrative run of The Low Seat Check.'
  };

  /* ---------------- the schedule (seconds) ---------------- */
  const SHOWN = [0, 2, 5, 13, 17];                      // the questions we sit with, in order
  const QSTART = [12.0, 16.2, 20.4, 24.6, 28.8];        // each lands on a beat
  const PICK_AT = [2.55, 3.05, 2.6, 2.7, 3.4];          // when he clicks, after the question appears
  const T = {
    h1: 0.9, lede: 2.4, verse: 5.4, scrollA: 7.2, scrollB: 9.0, hover: 10.2, click: 11.4,
    montageA: 33.0, montageB: 36.0, result: 36.0, count: [36.6, 38.4], bandT: 38.6, bars: [39.0, 41.4], thin: 42.0, ttt: [43.2, 44.4, 45.6],
    witness: 46.8, witHover: 48.4, witClick: 49.2, copied: 49.3, cmp: 50.4, cmpBars: [51.0, 52.8],
    end: 54.0, morphA: 54.0, morphB: 55.2
  };
  const PICK = QSTART.map((q, i) => snap(q + PICK_AT[i]));
  const ANS_SHOWN = SHOWN.map((q) => HIS[q]);

  /* the sting (logo scene), time-warped */
  const STING = { ts0: 2.3, tsClose: 4.35, tf0: T.morphB, closeFilm: snap(T.morphB + 1.8) };
  STING.speed = (STING.tsClose - STING.ts0) / (STING.closeFilm - STING.tf0);
  const tsOf = (tf) => STING.ts0 + (tf - STING.tf0) * STING.speed;
  const tfOf = (ts) => STING.tf0 + (ts - STING.ts0) / STING.speed;

  /* the camera: always moving, slowly; the shot opens wide on the room, then pushes into the screen */
  const cam = {
    dz: pchip([[0, -430], [3, -380], [8, -90], [12, -30], [33, -60], [36, -150], [42, -110], [46.8, -70], [50, -50], [54, 380], [55.2, 900], [60, 900]]),
    ry: pchip([[0, 7], [6, 3], [12, -2], [24, 2], [36, -3], [46.8, 2], [54, 0], [60, 0]]),
    rx: pchip([[0, 2], [8, 0], [24, 1.2], [40, -1], [54, 0], [60, 0]]),
    px: pchip([[0, 120], [8, 60], [20, 30], [36, 10], [46.8, 40], [54, 0], [60, 0]]),
    py: pchip([[0, -20], [8, -10], [24, -4], [36, 6], [54, 0], [60, 0]])
  };
  const camera = (t) => ({ dz: cam.dz(t), ry: cam.ry(t), rx: cam.rx(t), px: cam.px(t), py: cam.py(t) });

  /* the man: how far he leans in (0 back .. 1 forward), how far his head drops, when he exhales */
  const lean = pchip([[0, 0.1], [5, 0.35], [11, 0.7], [12, 0.85], [20, 0.9], [31.8, 0.95], [33.2, 0.7], [36, 0.8], [38.6, 0.25], [42, 0.2], [46.8, 0.6], [50, 0.8], [54, 1.0], [60, 1.0]]);
  const headDrop = pchip([[0, 0.0], [12, 0.25], [18.8, 0.25], [19.8, 0.55], [22, 0.3], [31.7, 0.3], [32.6, 0.75], [34, 0.3], [38.5, 0.0], [46, 0.15], [54, 0.3], [60, 0.3]]);

  /* the cursor: keyframes in the screen's design coordinates (1280 x 720), [t, x, y] */
  const optY = (i) => 384 + 66 * i;
  const cursorKeys = (function () {
    const k = [[0, 900, 520], [2.5, 960, 470], [6, 1000, 520], [8, 1040, 560], [9.6, 700, 600], [T.hover, 340, 636], [T.click, 336, 634], [11.9, 760, 470]];
    const optX = 600;
    const picks = [3, 3, 2, 3, 4];                       // option index (0-4) = answer - 1 for the five shown
    QSTART.forEach((q, i) => {
      const a = ANS_SHOWN[i] - 1, y = optY(a), pick = PICK[i];
      if (i === 1) { k.push([q + 1.2, 760, optY(1)], [q + 1.8, 700, optY(3)], [q + 2.3, 640, optY(4) - 8], [pick - 0.15, optX, y], [pick, optX, y]); }
      else if (i === 4) { k.push([q + 1.4, 760, optY(1)], [q + 2.0, 720, optY(2)], [q + 2.6, 690, optY(3)], [q + 3.0, optX, optY(4) - 4], [pick, optX, y]); }
      else { k.push([q + 1.3, 780, 470], [pick - 0.45, 700, y - 60], [pick - 0.12, optX, y], [pick, optX, y]); }
      k.push([q + 4.2 - 0.1, 760, 480]);
    });
    k.push([33.0, 700, 440], [36.0, 700, 440], [38.0, 900, 520], [46.0, 940, 560], [T.witHover, 330, 520], [T.witClick, 326, 518], [50.0, 700, 480], [54, 700, 480], [60, 700, 480]);
    return k.sort((a, b) => a[0] - b[0]).filter((v, i, a) => i === 0 || v[0] > a[i - 1][0]);
  })();
  const cursorX = pchip(cursorKeys.map((k) => [k[0], k[1]])), cursorY = pchip(cursorKeys.map((k) => [k[0], k[2]]));
  const clicks = [T.click].concat(PICK).concat([T.witClick]);
  /* the quick pass through the other fifteen statements */
  const MONTAGE = (function () { const out = [], rest = []; for (let q = 0; q < 20; q++) if (SHOWN.indexOf(q) < 0) rest.push(q); return rest; })();   // 15 questions
  const montageTimes = MONTAGE.map((q, i) => snap(T.montageA + 0.12 + i * (T.montageB - T.montageA - 0.5) / (MONTAGE.length - 1)));

  return {
    DUR, FPS, BEAT, COL, P, Q, SCALE, BANDS, HIS, WIT, S, W, SO, WO, band, thinnest, gapN, gapV, cmpText, WORDS, SHOWN, QSTART, PICK, ANS_SHOWN, T,
    STING, tsOf, tfOf, camera, lean, headDrop, cursorX, cursorY, clicks, MONTAGE, montageTimes, optY, scores, overall, value,
    clamp, lerp, sstep, eInOut, eOut, eOut5, eInOutSine, snap, rng, pchip
  };
});
