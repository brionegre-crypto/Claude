/* Be The Man — site walkthrough (about 7 minutes): the shared model.
 * index.html draws from it; tools/*.mjs read the same numbers, so every sound and caption sits on the frame it belongs to.
 * Every fact, price and date below is taken from https://bethemansystem.com (pages fetched 30 Oct 2026; text in assets/site/).
 * The narration is written as it is spoken (numbers and times in words).
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(true);
  else root.WT = factory(false);
})(this, function (isNode) {
  'use strict';
  const FPS = 60;
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const lerp = (a, b, t) => a + (b - a) * t;
  const sstep = (x) => { x = clamp(x); return x * x * (3 - 2 * x); };
  const eInOut = (x) => { x = clamp(x); return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; };
  const eOut = (x) => 1 - Math.pow(1 - clamp(x), 3);
  const eInOutSine = (x) => -(Math.cos(Math.PI * clamp(x)) - 1) / 2;
  const snap = (t) => Math.round(t * FPS) / FPS;
  const rng = (seed) => () => { seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  function pchip(keys) {
    const n = keys.length, x = keys.map((k) => k[0]), y = keys.map((k) => k[1]), d = [], m = new Array(n);
    if (n === 1) return () => y[0];
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
      let lo = 0, hi = n - 1; while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (x[mid] <= t) lo = mid; else hi = mid; }
      const hh = x[lo + 1] - x[lo], u = (t - x[lo]) / hh, u2 = u * u, u3 = u2 * u;
      return (2 * u3 - 3 * u2 + 1) * y[lo] + (u3 - 2 * u2 + u) * hh * m[lo] + (-2 * u3 + 3 * u2) * y[lo + 1] + (u3 - u2) * hh * m[lo + 1];
    };
  }

  /* brand: amber #E18B1F on near-black, cream type (site tokens: assets/site/site.css) */
  const COL = { bg: '#000000', tile: '#111113', tile2: '#1c1c1e', fg: '#f5f5f7', cream: '#F2EEE6', muted: '#a1a1a6', dim: '#9a9aa3', accent: '#e18b1f', hi: '#f6b24f', onAccent: '#0b0b0c', room: '#0e0c0a' };

  const TAGLINE = 'Faith should function.', URL = 'BETHEMANSYSTEM.COM', LABEL = 'THE BE THE MAN SYSTEM  ·  FOR BLACK CHRISTIAN MEN';

  /* ---------------------------------------------------------------- the script ---------------------------------------------------------------- */
  // page blocks: hero / text / steps / cards / rows / stat / card (scorecard) / cta / chips / quote / kpis.   cue = a phrase in the narration the element appears on.
  const SCENES = [
    { id: 'hook', url: '', cam: 'wide',
      narr: 'You meant it. Every single time. Monday, you were all in. By Wednesday? Gone. And you started over. Again. Here’s the good news: that’s not a character flaw. It’s a missing system. Be The Man is a consistency system for Black Christian men, and it does one thing: it helps you do what you said. Every week.',
      page: [
        { t: 'cycle', theme: 'dark', cue: 'You meant it', breakCue: 'Here’s the good news',
          lines: [ { txt: 'You meant it.', cue: 'You meant it' }, { txt: 'Every time.', cue: 'Every single time' } ],
          labels: [ { txt: 'Monday: all in', cue: 'Monday', pos: 'top' }, { txt: 'Wednesday: gone', cue: 'Wednesday', pos: 'right' }, { txt: 'Start over', cue: 'And you started over', pos: 'left' } ] },
        { t: 'hero', theme: 'amber', cue: 'Here’s the good news', kicker: 'Not a character flaw. A missing system.', title: 'Do what you said.\nEvery week.', sub: 'The Be The Man System · a consistency system for Black Christian men.' }
      ] },
    { id: 'system', url: '', cam: 'wide',
      narr: 'So how does it work? Three things. One sentence about the man you’re becoming. Goals with dates. And a weekly scorecard. Let’s look at one week. Phone in the drawer at seven forty P M. Scripture before screens at six fifteen A M. Train Monday, Wednesday, Friday. Come Sunday night? Thirteen of fifteen. You don’t wonder if you kept your word. You see it.',
      page: [
        { t: 'rows', theme: 'cream', cue: 'So how does it work', head: 'Three things', items: [
          { label: 'One sentence', value: 'the man you’re becoming', cue: 'One sentence about' },
          { label: 'Goals with dates', value: 'a when for every goal', cue: 'Goals with dates' },
          { label: 'A weekly scorecard', value: 'shows you the result', cue: 'a weekly scorecard' } ] },
        { t: 'week', theme: 'dark', cue: 'Let’s look at one week', kicker: 'Weekly scorecard · Week 6 · Example', quote: 'The man I’m becoming: present, steady, keeps his word.',
          rows: [ { label: 'Phone in the drawer', time: '7:40 PM', days: [1,1,1,1,1,0,1], cue: 'Phone in the drawer' }, { label: 'Scripture before screens', time: '6:15 AM', days: [1,1,1,1,0,1,1], cue: 'Scripture before screens' }, { label: 'Train Mon · Wed · Fri', time: '', days: [1,0,1,0,1,0,0], cue: 'Train Monday' } ],
          sweepA: 'Phone in the drawer', sweepB: 'Come Sunday night', total: '13 of 15 kept this week', totalCue: 'Thirteen of fifteen' }
      ] },
    { id: 'steps', url: '', cam: 'wide',
      narr: 'It builds in seven steps, and each one answers to the one before it. What type of man do you want to be? What are your goals? What has stopped you so far? The laws of a system that holds. The four pillars. Why you need a system. And at the center? God. The standard is scripture, not mood.',
      page: [
        { t: 'stairs', theme: 'cream', cue: 'It builds in seven steps', items: [
          { n: 1, name: 'What type of man do you want to be?', tag: 'Free', cue: 'What type of man' }, { n: 2, name: 'What are your goals?', cue: 'What are your goals' }, { n: 3, name: 'What has stopped you so far?', cue: 'What has stopped you' },
          { n: 4, name: 'The laws of a system that holds', cue: 'The laws of a system' }, { n: 5, name: 'The four pillars', cue: 'The four pillars' }, { n: 6, name: 'Why you need a system', cue: 'Why you need a system' }, { n: 7, name: 'God at the center', cue: 'God. The standard' } ] },
        { t: 'text', theme: 'amber', cue: 'The standard is scripture', big: 'The standard is scripture, not mood.' }
      ] },
    { id: 'proof', url: '', cam: 'wide',
      narr: 'Does writing it down really work? Here’s the proof. Ninety-one percent of people who wrote down when and where they’d act followed through. Only thirty-eight percent of the people who didn’t. Ninety-four studies. Same pattern. A goal says, I’ll be more present. A system says, Thursday, seven forty P M, phone in the drawer. See the difference?',
      page: [
        { t: 'stat', theme: 'dark', cue: 'Does writing it down really work', a: { label: 'Wrote down when and where', v: 91 }, b: { label: 'Didn’t', v: 38 }, note: 'Across 94 studies, the pattern held.', noteCue: 'Ninety-four studies' },
        { t: 'cols', theme: 'cream', cue: 'A goal says', title: 'A goal says what. A system says when.', a: { head: 'A goal', line: 'I’ll be more present.', cue: 'A goal says' }, b: { head: 'A system', line: 'Thursday, 7:40 PM, phone in the drawer.', cue: 'A system says' } }
      ] },
    { id: 'map', url: '', cam: 'wide',
      narr: 'So where are you right now? There are five roads in. Pick the one that sounds like you. Just starting. Want to see yourself honestly. Need other men. Want a stronger marriage. Or lead men at your church.',
      page: [
        { t: 'map', theme: 'dark', cue: 'So where are you right now', origin: 'You are here', items: [
          { label: 'I’m just starting', sub: 'Step 1 · Free', cue: 'Just starting' }, { label: 'I want to see myself honestly', sub: 'The Low Seat Check', cue: 'see yourself honestly' }, { label: 'I need other men', sub: 'Club · Workshop · Group · Inner Circle', cue: 'Need other men' },
          { label: 'I want a stronger marriage', sub: 'Couples counseling', cue: 'stronger marriage' }, { label: 'I lead men at church', sub: 'Ministry kit · Speaking', cue: 'your church' } ] }
      ] },
    { id: 'start', url: '', cam: 'wide',
      narr: 'Just starting? Perfect. Begin with Step one. It’s free. Twenty minutes, a pen, and one sentence that names the man you want to be. Drop in your name and email, and it lands in about two minutes. After that? One short email a week. Want to ease in? The seven week challenge is free too. One email every Tuesday, and you can join any week. There’s a free six minute training. Or book a free fifteen minute call, and tell Brian where you’re stuck.',
      page: [
        { t: 'route', theme: 'cream', cue: 'Just starting', label: 'Road 1 · I’m just starting', items: [
          { name: 'Step 1', tag: 'Free', desc: '20 minutes, a pen, one sentence.', cue: 'Begin with Step one' },
          { name: '7-week challenge', tag: 'Free', desc: 'One email every Tuesday. Join any week.', cue: 'seven week challenge' },
          { name: 'Free training', tag: '6 minutes', desc: 'Why good men break the same promise.', cue: 'free six minute training' },
          { name: 'A call with Brian', tag: 'Free · 15 min', desc: 'Where are you stuck?', cue: 'book a free fifteen' } ] }
      ] },
    { id: 'honest', url: '', cam: 'wide',
      narr: 'Want to see yourself honestly? Take the Low Seat Check. How humble are you, on a Tuesday? Twenty statements about what you actually do at home. Five postures: teachable, owned, unseen, credit, and dependent. Five minutes. Free. You get a score, your thinnest posture, and one action for this week. Then send it to your wife, or a brother, and see how they score you. That gap? That’s your blind spot.',
      page: [
        { t: 'route', theme: 'dark', cue: 'Want to see yourself honestly', label: 'Road 2 · The Low Seat Check · Free · 5 minutes', items: [
          { name: '20 statements', tag: 'What you do at home', desc: 'Not how humble you feel.', cue: 'Twenty statements' },
          { name: '5 postures', tag: 'From scripture', desc: 'Teachable · Owned · Unseen · Credit · Dependent', cue: 'Five postures' },
          { name: 'Your result', tag: 'A score', desc: 'Your thinnest posture, and one action with a time.', cue: 'You get a score' },
          { name: 'A second witness', tag: 'Your wife or a brother', desc: 'The gap is the blind spot.', cue: 'send it to your wife' } ] }
      ] },
    { id: 'ladder1', url: '', cam: 'wide',
      narr: 'Need other men? Climb the ladder. Start with the Club: nineteen dollars a month, or a hundred and forty-nine a year. You get the framework, the scorecard, new tools every month, and a live call on the second Tuesday. Members only, never recorded. Want something this week? Fix Your Wednesday. One live hour, twenty-seven dollars, every other Wednesday. Recording included.',
      page: [
        { t: 'route', theme: 'cream', rise: true, cue: 'Need other men', label: 'Road 3 · I need other men', items: [
          { name: 'The Club', tag: '$19 a month', desc: 'Or $149 a year. New tools monthly, a live call on the 2nd Tuesday.', cue: 'Start with the Club' },
          { name: 'Fix Your Wednesday', tag: '$27', desc: 'One live hour, every other Wednesday. Recording included.', cue: 'Fix Your Wednesday' } ] }
      ] },
    { id: 'ladder2', url: '', cam: 'wide',
      narr: 'Ready for more? The six-week group is four men, six Sundays, a hundred and forty-seven dollars at the founding price. The test: by December twentieth, could someone in your house tell something changed, without you telling them? And at the top, the Inner Circle. Ten men. A weekly class every Thursday. A monthly one-on-one. Your scorecard reviewed every week. A hundred and ninety-seven dollars a month, by application. Come to four Thursdays, and if it isn’t worth it after thirty days, you get a full refund.',
      page: [
        { t: 'route', theme: 'dark', rise: true, cue: 'Ready for more', label: 'Road 3 · I need other men', items: [
          { name: 'The 6-week group', tag: '$147 founding', desc: 'Four men. Six Sundays, Nov 15 to Dec 20. The test: could someone in your house tell something changed, without you telling them?', cue: 'The six-week group' },
          { name: 'The Inner Circle', tag: '$197 a month', desc: 'Ten men. A weekly class with Brian. By application. 30-day refund.', cue: 'at the top, the Inner Circle' } ] }
      ] },
    { id: 'couples', url: '', cam: 'wide',
      narr: 'Want a stronger marriage? There’s couples counseling, for engaged or married couples. You each take a validated relationship assessment online, separately, on your own time. Then you meet for three sessions to go through your results together, and choose what to work on first. Three hundred dollars for the three sessions. Couples who did premarital education were about thirty percent less likely to divorce. Send an inquiry, and you’ll hear back within twenty-four hours.',
      page: [
        { t: 'route', theme: 'cream', cue: 'Want a stronger marriage', label: 'Road 4 · Couples counseling · Engaged or married', items: [
          { name: 'Send an inquiry', tag: 'Reply in 24 hours', desc: 'Leave your names and the best way to reach you.', cue: 'Send an inquiry' },
          { name: 'The assessment', tag: 'Each of you', desc: 'Validated, online, separately, on your own time.', cue: 'You each take' },
          { name: 'Three sessions', tag: '$300', desc: 'Your results, together. What to work on first.', cue: 'three sessions to go' } ] },
        { t: 'kpis', theme: 'amber', cue: 'Three hundred dollars', items: [ { big: '$300', small: 'three sessions', cue: 'Three hundred dollars' }, { big: '~30%', small: 'less likely to divorce after premarital education', cue: 'thirty percent' } ] }
      ] },
    { id: 'church', url: '', cam: 'wide',
      narr: 'Lead men at your church? The men’s ministry kit is one licence for your whole ministry: a hundred and ninety-nine dollars. Seven weeks, one night a week, seventy-five minutes. A leader guide, timed plans, printable worksheets, and the scorecard. You don’t need to be a teacher. Want a speaker? Book Brian for men’s nights, retreats, conferences, and workshops.',
      page: [
        { t: 'route', theme: 'dark', cue: 'Lead men at your church', label: 'Road 5 · I lead men at church', items: [
          { name: 'Ministry kit', tag: '$199 · one licence', desc: 'Seven weeks, one night a week, 75 minutes. A leader guide, timed plans, worksheets, the scorecard.', cue: 'men’s ministry kit' },
          { name: 'Book Brian to speak', tag: 'Men’s nights · retreats · conferences', desc: 'The framework. The first ten minutes home. The low seat.', cue: 'Want a speaker' } ] }
      ] },
    { id: 'store', url: '', cam: 'wide',
      narr: 'Just want the tools? The store has them. The Complete Be The Man System is ninety-seven dollars: all seven step worksheets and all eleven tools. The Weekly Scorecard, seven dollars. Forty Cards for Men, nine. Then three kits: Husband, thirty-nine dollars. Father, twenty-nine. Faith, twenty-nine.',
      page: [
        { t: 'hero', theme: 'amber', cue: 'Just want the tools', kicker: 'The Store · Best value', title: 'The Complete System.\n$97.', sub: 'All seven step worksheets and all eleven tools.' },
        { t: 'cards', theme: 'cream', cue: 'The Weekly Scorecard, seven', lead: 'Tools', items: [
          { name: 'The Weekly Scorecard', price: '$7', desc: 'Tracking on paper, shared with someone.', cue: 'The Weekly Scorecard' }, { name: 'Forty Cards for Men', price: '$9', desc: 'Forty cards, one action a day.', cue: 'Forty Cards' } ] },
        { t: 'cards', theme: 'dark', cue: 'three kits', lead: 'Kits', items: [
          { name: 'Husband Kit', price: '$39', desc: 'For your marriage.', cue: 'Husband, thirty' }, { name: 'Father Kit', price: '$29', desc: 'For fatherhood.', cue: 'Father, twenty' }, { name: 'Faith Kit', price: '$29', desc: 'For your faith.', cue: 'Faith, twenty' } ] }
      ] },
    { id: 'recap', url: '', cam: 'wide',
      narr: 'Quick recap. Free: Step one, the seven week challenge, the training, the call, and the Low Seat Check. Then nineteen dollars a month for the Club. Twenty-seven dollars for a workshop. A hundred and forty-seven for the group. A hundred and ninety-seven a month for the Inner Circle. Start free. Climb when you’re ready.',
      page: [
        { t: 'route', theme: 'cream', rise: true, cue: 'Quick recap', label: 'Start free. Climb when you’re ready.', items: [
          { name: 'Free', tag: 'Start here', desc: 'Step 1 · challenge · training · call · Low Seat Check', cue: 'Free: Step one' },
          { name: 'The Club', tag: '$19 a month', desc: 'Tools and a monthly call.', cue: 'Club' },
          { name: 'Workshop', tag: '$27', desc: 'Fix Your Wednesday.', cue: 'workshop' },
          { name: 'The group', tag: '$147', desc: 'Four men, six Sundays.', cue: 'for the group' },
          { name: 'Inner Circle', tag: '$197 a month', desc: 'By application.', cue: 'for the Inner Circle' } ] }
      ] },
    { id: 'faq', url: '', cam: 'wide',
      narr: 'Three questions men ask first. Is it a devotional? No. The weekly emails teach the mechanism: when, where, what trigger, and how you’d know it worked. Is it connected to a church? No. It’s for any Black Christian man who wants his faith to show up in how he keeps his word. And why a system, instead of motivation? Because intentions rarely change a week. A plan you can check does.',
      page: [
        { t: 'rows', theme: 'dark', cue: 'Three questions', head: 'Questions men ask first', items: [
          { label: 'Is it a devotional?', value: 'No. It teaches the mechanism.', cue: 'Is it a devotional' },
          { label: 'Is it run by a church?', value: 'No. Any Black Christian man.', cue: 'Is it connected' },
          { label: 'Why a system, not motivation?', value: 'A plan you can check changes a week.', cue: 'why a system' } ] }
      ] },
    { id: 'about', url: '', cam: 'wide',
      narr: 'So who’s behind this? I grew up without a father in the house. Nobody showed me how a man keeps his word on a Tuesday when nobody’s watching, so I learned the hard way. Today I’m a husband of eleven years, a father of three, a pastor of ten years, and a certified marriage counselor. And I still have weeks where something slips. This is the system I wish someone had handed me at twenty-five. I hold myself to six laws, written before anything was published.',
      page: [
        { t: 'hero', theme: 'dark', cue: 'So who’s behind this', kicker: 'About', title: 'Who’s behind this.', sub: 'I grew up without a father in the house. Nobody showed me how a man keeps his word on a Tuesday when nobody’s watching.' },
        { t: 'kpis', theme: 'amber', cue: 'husband of eleven years', items: [ { big: '11', small: 'years a husband', cue: 'husband of eleven' }, { big: '3', small: 'children', cue: 'father of three' }, { big: '10', small: 'years a pastor', cue: 'pastor of ten' } ] },
        { t: 'chips', theme: 'cream', cue: 'six laws', label: 'Six laws, written before anything was published', items: ['Clock', 'Source', 'Failure', 'Proximity', 'Evidence', 'Protection'], cues: ['six laws', 'six laws', 'six laws', 'six laws', 'six laws', 'six laws'] }
      ] },
    { id: 'close', url: '', cam: 'wide',
      narr: 'So here’s your next step. Don’t buy anything yet. Get Step one. It’s free. If one worksheet doesn’t change anything in a week, nineteen dollars a month won’t either. Then take the Low Seat Check, and send it to someone at your table. And when you’re ready? Join the Club.',
      page: [
        { t: 'hero', theme: 'amber', cue: 'So here’s your next step', kicker: 'Your next step', title: 'Get Step 1.\nIt’s free.', sub: 'No card. Twenty minutes and a pen. One sentence that names the man you want to be.' },
        { t: 'cta', theme: 'dark', cue: 'Then take the Low Seat Check', label: 'bethemansystem.com', note: 'Step 1 · The Low Seat Check · The Club' }
      ] },
    { id: 'outro', url: '', cam: 'logo',
      narr: 'Faith should function. Be The Man. Be The Man System dot com.',
      page: [] }
  ];

  /* ---------------------------------------------------------------- the timeline ---------------------------------------------------------------- */
  let DURS = null;
  try { DURS = isNode ? JSON.parse(require('fs').readFileSync(require('path').join(__dirname, 'durations.json'), 'utf8')) : (typeof window !== 'undefined' ? window.WT_DURS : null); } catch (e) { DURS = null; }
  const LEAD = 0.8, GAP = 0.85, TAILPAD = 0.3;
  let cursor = LEAD;
  SCENES.forEach((s, i) => {
    s.n = s.narr.split(/\s+/).length;
    s.nd = DURS && DURS[s.id] ? (DURS[s.id].dur || DURS[s.id]) : s.n / 3.1; s.sents = DURS && DURS[s.id] && DURS[s.id].sents ? DURS[s.id].sents : null;          // narration seconds (measured when assets/narr exists)
    s.t0 = snap(cursor);                                          // the scene (and its narration) starts
    s.t1 = snap(s.t0 + s.nd + TAILPAD);                           // end of speech
    cursor = s.t1 + GAP;
  });
  const last = SCENES[SCENES.length - 1];
  /* the logo scene: the line starts as the final words are spoken; the sting plays out after */
  const T = { morphA: snap(last.t0 - 0.2), morphB: snap(last.t0 + 1.0) };
  const STING = { ts0: 2.3, tsClose: 4.35, tf0: T.morphB, closeFilm: snap(T.morphB + 1.8) };
  STING.speed = (STING.tsClose - STING.ts0) / (STING.closeFilm - STING.tf0);
  const tsOf = (tf) => STING.ts0 + (tf - STING.tf0) * STING.speed;
  const tfOf = (ts) => STING.tf0 + (ts - STING.ts0) / STING.speed;
  const DUR = Math.ceil((T.morphB + 5.6) * 60) / 60;
  const WORDS = { tagline: TAGLINE, url: URL, label: LABEL, note: 'bethemansystem.com' };

  /* a cue phrase -> a time inside its scene.  Uses the measured sentence boundaries of the narration when they exist (assets/narr/*.wav), else proportional */
  function cueTime(scene, phrase, fallback) {
    if (phrase == null) return fallback;
    const hay = scene.narr.toLowerCase(), i = hay.indexOf(String(phrase).toLowerCase());
    if (i < 0) return fallback;
    const sents = scene.sents;
    if (sents) for (const sn of sents) if (i >= sn[0] && i <= sn[1]) return scene.t0 + sn[2] + (sn[3] - sn[2]) * ((i - sn[0]) / Math.max(1, sn[1] - sn[0])) - 0.1;
    return scene.t0 + (i / hay.length) * scene.nd - 0.12;
  }

  /* camera: wide (the man in view, the screen a little back) or push (the screen fills more of the frame) */
  const camKey = { wide: { dz: -250, ry: 5, rx: 1.5, px: 90, py: -14 }, push: { dz: 150, ry: -2.5, rx: 0.5, px: 20, py: 0 }, logo: { dz: 420, ry: 0, rx: 0, px: 0, py: 0 } };
  const camKeys = (function () {
    const k = { dz: [], ry: [], rx: [], px: [], py: [] };
    const put = (t, c) => { Object.keys(k).forEach((n) => k[n].push([t, c[n]])); };
    put(0, camKey.wide);
    SCENES.forEach((s, i) => {
      const c = camKey[s.cam], hold = s.t1 - 0.6;
      const d = (i % 2 ? 1 : -1) * 18;                            // a slow drift inside every shot
      put(s.t0 - 0.2, { dz: c.dz, ry: c.ry - d * 0.1, rx: c.rx, px: c.px - d, py: c.py });
      put(Math.max(s.t0 + 0.6, hold), { dz: c.dz + (s.cam === 'push' ? 40 : 26), ry: c.ry + d * 0.1, rx: c.rx, px: c.px + d, py: c.py + 4 });
    });
    put(T.morphA, camKey.push); put(T.morphB + 1.2, camKey.logo); put(DUR, camKey.logo);
    const keys = {}; Object.keys(k).forEach((n) => { const arr = k[n].filter((v, i, a) => i === 0 || v[0] > a[i - 1][0]); keys[n] = pchip(arr); });
    return keys;
  })();
  const camera = (t) => ({ dz: camKeys.dz(t), ry: camKeys.ry(t), rx: camKeys.rx(t), px: camKeys.px(t), py: camKeys.py(t) });
  const sceneAt = (t) => { let r = SCENES[0]; for (const s of SCENES) if (t >= s.t0 - 0.3) r = s; return r; };

  return { FPS, DUR, COL, WORDS, SCENES, T, STING, tsOf, tfOf, camera, sceneAt, cueTime, LEAD, GAP,
    clamp, lerp, sstep, eInOut, eOut, eInOutSine, snap, rng, pchip };
});
