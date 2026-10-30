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
    { id: 'welcome', url: 'bethemansystem.com', cam: 'wide',
      narr: 'Welcome. I’m Brian Greene, and this is the Be The Man System. For the next few minutes I’m going to walk you through the whole site, page by page: what’s free, what costs money, and where I’d tell you to start. Be The Man is a consistency system for Black Christian men. The promise is simple: do what you said. Every week.',
      page: [
        { t: 'hero', cue: 'Welcome', kicker: 'The Be The Man System, for Black Christian men', title: 'Do what you said.\nEvery week.', sub: 'You start strong, then it stalls, and you start over. Seven steps make follow-through repeatable.' },
        { t: 'cta', cue: 'The promise is simple', label: 'Get Step 1, free', note: 'Free. No card. Step 1 arrives in about two minutes, then one email a week. Leave in one click.' }
      ] },
    { id: 'pattern', url: 'bethemansystem.com', cam: 'push',
      narr: 'Most of us know the pattern. You start strong, then it stalls, and you start over. You meant it every time, and nothing changed. The system makes follow-through repeatable with three things: one sentence about the man you’re becoming, goals with dates, and a weekly scorecard that shows you the result.',
      page: [
        { t: 'text', cue: 'Most of us know the pattern', kicker: 'The pattern', big: 'You start strong, then it stalls, and you start over.' },
        { t: 'rows', cue: 'one sentence', items: [
          { label: 'One sentence', value: 'the man you’re becoming', cue: 'one sentence about' },
          { label: 'Goals with dates', value: 'a when for every goal', cue: 'goals with dates' },
          { label: 'A weekly scorecard', value: 'shows you the result', cue: 'a weekly scorecard' } ] }
      ] },
    { id: 'scorecard', url: 'bethemansystem.com', cam: 'push',
      narr: 'This is the scorecard on the home page, week six, an example. The man I’m becoming: present, steady, keeps his word. Three commitments, each with a time. Phone in the drawer at seven forty P M. Scripture before screens at six fifteen A M. Train Monday, Wednesday, Friday. Thirteen of fifteen kept this week. By Sunday night, you can see whether you kept your word.',
      page: [
        { t: 'card', cue: 'This is the scorecard', kicker: 'Weekly scorecard · Week 6 · Example', quote: 'The man I’m becoming: present, steady, keeps his word.', quoteCue: 'The man I’m becoming',
          rows: [ { label: 'Phone in the drawer', time: '7:40 PM', days: [1,1,1,1,1,0,1], cue: 'Phone in the drawer' }, { label: 'Scripture before screens', time: '6:15 AM', days: [1,1,1,1,0,1,1], cue: 'Scripture before screens' }, { label: 'Train Mon · Wed · Fri', time: '', days: [1,0,1,0,1,0,0], cue: 'Train Monday' } ],
          total: '13 of 15 kept this week', totalCue: 'Thirteen of fifteen' }
      ] },
    { id: 'seven', url: 'bethemansystem.com/#how', cam: 'push',
      narr: 'Here are the seven steps. Step one: what type of man do you want to be? Two: what are your goals? Three: what has stopped you so far? Four: the laws of a system that holds. Five: the four pillars. Six: why you need a system. And seven: God at the center. Each step answers to the one before it, and each ends in something you do, and can check.',
      page: [
        { t: 'hero', cue: 'Here are the seven steps', kicker: 'How it works', title: 'Seven steps. One system.', sub: 'Each step answers to the one before it, starting with a single sentence about the man you want to be.' },
        { t: 'steps', cue: 'Step one', items: [
          { n: 1, name: 'What type of man do you want to be?', tag: 'Free', cue: 'Step one' }, { n: 2, name: 'What are your goals?', cue: 'Two:' }, { n: 3, name: 'What has stopped you so far?', cue: 'Three:' },
          { n: 4, name: 'The laws of a system that holds', cue: 'Four:' }, { n: 5, name: 'The four pillars', cue: 'Five:' }, { n: 6, name: 'Why you need a system', cue: 'Six:' }, { n: 7, name: 'God at the center', cue: 'seven: God' } ] }
      ] },
    { id: 'why', url: 'bethemansystem.com', cam: 'push',
      narr: 'Why a system, instead of more motivation? A goal says, I’ll be more present. A system says, Thursday, seven forty P M, phone in the drawer: when, where, and on what trigger, written down so it can be checked. In one study, ninety-one percent of people who wrote down when and where they would act followed through, against thirty-eight percent who didn’t. Across ninety-four studies, the pattern held. And the center isn’t you. The standard is scripture, not mood.',
      page: [
        { t: 'cols', cue: 'Why a system', title: 'Why you need a system.', a: { head: 'A goal', line: 'I’ll be more present.', cue: 'A goal says' }, b: { head: 'A system', line: 'Thursday, 7:40 PM, phone in the drawer.', cue: 'A system says' } },
        { t: 'stat', cue: 'In one study', a: { label: 'Wrote down when and where', v: 91 }, b: { label: 'Didn’t', v: 38 }, note: 'Across 94 studies, the pattern held.', noteCue: 'Across ninety-four' },
        { t: 'text', cue: 'And the center', big: 'The center isn’t you. The standard is scripture, not mood.' }
      ] },
    { id: 'step1', url: 'bethemansystem.com/step-1', cam: 'wide',
      narr: 'Start here. Step one is free. No card. It’s a worksheet: twenty minutes, a pen, and one sentence that names the man you want to be. You enter your first name and email, and Step one arrives in about two minutes. Then you get one short email a week, and you can leave in one click.',
      page: [
        { t: 'hero', cue: 'Start here', kicker: 'Step 1 · Free', title: 'Stop starting over.\nFinish what you start.', sub: 'A worksheet: the man you want to be, and one sentence that says so. 20 minutes. A pen. No card.' },
        { t: 'rows', cue: 'In twenty minutes', items: [
          { label: 'Five qualities', value: 'of the man you are becoming', cue: 'twenty minutes' }, { label: 'What each looks like', value: 'in real life', cue: 'a pen' }, { label: 'One sentence', value: 'that names him', cue: 'one sentence that names' } ] },
        { t: 'cta', cue: 'You enter your first name', label: 'Send me Step 1, free', note: 'In your inbox in about two minutes, then one short email a week. Leave in one click.' }
      ] },
    { id: 'challenge', url: 'bethemansystem.com/7-week-challenge', cam: 'push',
      narr: 'If you’d rather ease in, there’s the seven week challenge. It’s free: one email every Tuesday, and you can join any week, with no need to catch up. Forward it to one man you trust, and once a week, text each other one word: done, or missed. That’s the whole accountability.',
      page: [
        { t: 'hero', cue: 'there’s the seven week challenge', kicker: 'Free · One email a week', title: 'The 7-week challenge.', sub: 'One email every Tuesday. Join any week. No need to catch up.' },
        { t: 'chips', cue: 'text each other', label: 'Once a week, text each other one word', items: ['done', 'missed'], cues: ['done', 'or missed'] }
      ] },
    { id: 'training', url: 'bethemansystem.com/training', cam: 'push',
      narr: 'There’s also a free six minute training, on why good men keep breaking the same promise, the three places every promise dies, and the one test more honest than any habit tracker. And if you’d rather talk, book a free fifteen minute call with me, Monday to Thursday evenings, Central time. No pitch you didn’t ask for.',
      page: [
        { t: 'hero', cue: 'free six minute training', kicker: 'A free training · 6 minutes', title: 'You meant it every time.', sub: 'Why good men keep breaking the same promise, the three places every promise dies, and the first step that makes a system hold.' },
        { t: 'cta', cue: 'book a free fifteen minute call', label: 'Book my call', note: 'Free · 15 minutes · Monday to Thursday evenings, Central time. Where are you stuck?' }
      ] },
    { id: 'humility', url: 'bethemansystem.com/humility', cam: 'wide',
      narr: 'One of my favorite free tools is the Low Seat Check. How humble are you, on a Tuesday? It’s twenty statements about what you actually do at home, across five postures of humility: teachable, owned, unseen, credit, and dependent. In five minutes you get a score, your thinnest posture, and one action for this week. Then you send it to your wife, or a brother, and see how they score you. The gap is the blind spot.',
      page: [
        { t: 'hero', cue: 'One of my favorite', kicker: 'The Low Seat Check · Free · 5 minutes', title: 'How humble are you\non a Tuesday?', sub: '“When you are invited, go and sit in the lowest place.” Luke 14:10' },
        { t: 'chips', cue: 'five postures', label: 'Five postures of humility', items: ['Teachable', 'Owned', 'Unseen', 'Credit', 'Dependent'], cues: ['teachable', 'owned', 'unseen', 'credit', 'dependent'] },
        { t: 'rows', cue: 'you get a score', items: [
          { label: 'A score', value: 'out of 100', cue: 'a score' }, { label: 'Your thinnest posture', value: 'and one action, with a time', cue: 'thinnest posture' }, { label: 'A second witness', value: 'your wife or a brother scores you', cue: 'send it to your wife' } ] }
      ] },
    { id: 'club', url: 'bethemansystem.com/the-club', cam: 'push',
      narr: 'If you want the whole thing, join the Be The Man Club. Nineteen dollars a month, or a hundred and forty-nine dollars a year, with everything unlocked on day one. You get the framework and the Weekly Scorecard the day you join, then a new set of tools every month, until you have all eleven by month six. Plus one more tool every month that never goes in the store. And once a month, the room opens: one live hour on Google Meet, the second Tuesday, seven to eight P M Central. Members only, never recorded. Bring your scorecard, say your number, and work on the miss that keeps coming back.',
      page: [
        { t: 'hero', cue: 'join the Be The Man Club', kicker: 'The Club', title: 'The Be The Man Club.\n$19 a month.', sub: 'Or $149 a year, everything today. Step 1 and the weekly email stay free to everyone.' },
        { t: 'rows', cue: 'You get the framework', items: [
          { label: 'Day one', value: 'the framework and the Weekly Scorecard', cue: 'You get the framework' }, { label: 'Months 1 to 6', value: 'a new set of tools, all eleven by month six', cue: 'a new set of tools' }, { label: 'Every month', value: 'one more tool, Club only', cue: 'Plus one more tool' }, { label: 'The monthly call', value: '2nd Tuesday · 7–8 PM Central · never recorded', cue: 'once a month' } ] },
        { t: 'text', cue: 'Bring your scorecard', big: 'Bring your Scorecard, say your number, and work on the miss that keeps coming back.' }
      ] },
    { id: 'workshop', url: 'bethemansystem.com/workshop', cam: 'push',
      narr: 'Want help in the middle of the week? Fix Your Wednesday is a live one-hour workshop, every other Wednesday, seven to eight P M Central, for twenty-seven dollars. You leave with one sentence naming the man you’re becoming, one goal with a date and a time, and your first weekly scorecard. Every ticket includes the recording.',
      page: [
        { t: 'hero', cue: 'Want help in the middle', kicker: '$27 · Live on Google Meet', title: 'Fix Your Wednesday.', sub: 'Every other Wednesday, 7:00 to 8:00 PM Central. Most men start Monday strong and lose the week by Wednesday.' },
        { t: 'rows', cue: 'You leave with', items: [
          { label: 'One sentence', value: 'naming the man you are becoming', cue: 'one sentence naming' }, { label: 'One goal', value: 'with a date and a time', cue: 'one goal' }, { label: 'Your first Scorecard', value: 'weekly', cue: 'first weekly scorecard' }, { label: 'The recording', value: 'included with every ticket', cue: 'includes the recording' } ] }
      ] },
    { id: 'group', url: 'bethemansystem.com/group', cam: 'push',
      narr: 'The six-week group is for husbands and fathers who keep making the same promise. Four men, six Sundays, seven to eight P M Central on Google Meet. Each Sunday builds a step: who you’re building, goals with a when, what has stopped you, the laws of a system that holds, the four pillars, and God at the center. The founding price is a hundred and forty-seven dollars for the four founding seats, and it includes the Complete Library. The test: by December twentieth, could someone in your house tell something changed, without you telling them?',
      page: [
        { t: 'hero', cue: 'The six-week group', kicker: 'Four seats · Founding price $147', title: 'Six Sundays to build what keeps the promise.', sub: 'A live group for husbands and fathers. Sundays, 7:00 to 8:00 PM Central, on Google Meet. November 15 to December 20.' },
        { t: 'steps', cue: 'Each Sunday builds a step', plain: true, items: [
          { n: 'Nov 15', name: 'Who are you building?', cue: 'who you’re building' }, { n: 'Nov 22', name: 'Goals with a when', cue: 'goals with a when' }, { n: 'Nov 29', name: 'What has stopped you so far', cue: 'what has stopped you' },
          { n: 'Dec 6', name: 'The laws of a system that holds', cue: 'the laws of a system' }, { n: 'Dec 13', name: 'The four pillars', cue: 'the four pillars' }, { n: 'Dec 20', name: 'God at the center', cue: 'God at the center.' } ] },
        { t: 'text', cue: 'The test', big: 'By December 20, could someone in your house tell something changed, without you telling them?' }
      ] },
    { id: 'inner', url: 'bethemansystem.com/inner-circle', cam: 'push',
      narr: 'The Inner Circle is by application. Ten men at most. A private weekly class with me every Thursday, a monthly one-on-one, a weekly review of your scorecard, a direct line on weekdays, and a quarterly half-day intensive. The founding circle is a hundred and ninety-seven dollars a month for the first eight men, kept for as long as you stay. Come to four Thursdays and send four scorecards. If after thirty days it isn’t worth it, I refund you in full. You start with a free fifteen minute application call.',
      page: [
        { t: 'hero', cue: 'The Inner Circle is by application', kicker: 'The Inner Circle · By application', title: 'Ten men. A weekly class with Brian.', sub: 'For men in the Club who want a small private room, and someone checking your number.' },
        { t: 'rows', cue: 'A private weekly class', items: [
          { label: 'Every Thursday', value: 'a private weekly class, 7–8 PM Central', cue: 'A private weekly class' }, { label: 'Every month', value: 'a one-on-one with Brian', cue: 'a monthly one-on-one' }, { label: 'Every week', value: 'Brian reviews your Scorecard', cue: 'a weekly review' }, { label: 'Weekdays', value: 'a direct line', cue: 'a direct line' }, { label: 'Every quarter', value: 'a half-day intensive', cue: 'quarterly half-day' } ] },
        { t: 'kpis', cue: 'The founding circle', items: [ { big: '$197', small: 'a month, first 8 men', cue: 'a hundred and ninety-seven' }, { big: '30 days', small: 'full refund if it isn’t worth it', cue: 'thirty days' } ] },
        { t: 'cta', cue: 'You start with', label: 'Book my application call', note: 'Free, 15 minutes.' }
      ] },
    { id: 'store', url: 'bethemansystem.com/products', cam: 'push',
      narr: 'The store is where you can buy tools one at a time. The Complete Be The Man System is ninety-seven dollars: all seven step worksheets and all eleven tools. The Weekly Scorecard is seven dollars. Forty Cards for Men is nine. There are field guides and workbooks for your marriage, for fatherhood, and for your faith, and three kits: the Husband Kit for thirty-nine dollars, the Father Kit for twenty-nine, and the Faith Kit for twenty-nine.',
      page: [
        { t: 'hero', cue: 'The store is where', kicker: 'The Store · Best value', title: 'The Complete Be The Man System.\n$97.', sub: 'All seven step worksheets and all eleven tools.' },
        { t: 'cards', cue: 'The Weekly Scorecard', items: [
          { name: 'The Weekly Scorecard', price: '$7', desc: 'Tracking on paper, shared with someone.', cue: 'The Weekly Scorecard' }, { name: 'Forty Cards for Men', price: '$9', desc: 'Forty cards, one action a day.', cue: 'Forty Cards' } ] },
        { t: 'cards', cue: 'three kits', items: [
          { name: 'Husband Kit', price: '$39', desc: 'For your marriage.', cue: 'the Husband Kit' }, { name: 'Father Kit', price: '$29', desc: 'For fatherhood.', cue: 'the Father Kit' }, { name: 'Faith Kit', price: '$29', desc: 'For your faith.', cue: 'the Faith Kit' } ] }
      ] },
    { id: 'couples', url: 'bethemansystem.com/couples', cam: 'wide',
      narr: 'Couples. This is certified marriage counseling for engaged and married couples, with me. You each take a validated relationship assessment online, separately, on your own time. Then we meet for three sessions to go through your results together and choose what to work on. It’s three hundred dollars for three sessions, and the thirty-five dollar assessment fee is paid directly to the assessment provider. Couples who did premarital education were about thirty percent less likely to divorce. Send an inquiry, and I reply within twenty-four hours.',
      page: [
        { t: 'hero', cue: 'Couples', kicker: 'For couples', title: 'Certified marriage counseling for engaged and married couples.', sub: 'With Brian Greene, pastor and certified marriage counselor.' },
        { t: 'steps', cue: 'You each take', items: [
          { n: 1, name: 'Send an inquiry — Brian replies within 24 hours', cue: 'Send an inquiry, and' }, { n: 2, name: 'Each of you takes a validated assessment, separately', cue: 'You each take' }, { n: 3, name: 'Three sessions together, built on your results', cue: 'three sessions to go' } ] },
        { t: 'kpis', cue: 'three hundred dollars', items: [ { big: '$300', small: 'three sessions', cue: 'three hundred dollars' }, { big: '~30%', small: 'less likely to divorce after premarital education', cue: 'thirty percent' } ] }
      ] },
    { id: 'church', url: 'bethemansystem.com/ministry-kit', cam: 'push',
      narr: 'For churches, there’s the men’s ministry kit: one licence for your whole men’s ministry, a hundred and ninety-nine dollars. Seven weeks, one night a week, seventy-five minutes, with a leader guide, timed plans, printable worksheets and the scorecard. You don’t need to be a teacher. And you can book me to speak: men’s nights, retreats, conferences and workshops, on the framework, the first ten minutes home, and the low seat.',
      page: [
        { t: 'hero', cue: 'For churches', kicker: '$199 · One licence for your whole men’s ministry', title: 'The men’s ministry kit.', sub: 'Seven weeks, one night a week, 75 minutes. Every man leaves with one written commitment, a time to do it, and a partner who asks about it.' },
        { t: 'rows', cue: 'with a leader guide', items: [
          { label: 'Leader guide', value: 'seven sessions, online', cue: 'a leader guide' }, { label: 'Timed plans', value: 'for every 75-minute night', cue: 'timed plans' }, { label: 'Worksheets + Scorecard', value: 'printable', cue: 'printable worksheets' } ] },
        { t: 'chips', cue: 'book me to speak', label: 'Book Brian to speak', items: ['The framework', 'The first ten minutes home', 'The low seat'], cues: ['the framework', 'first ten minutes', 'low seat'] }
      ] },
    { id: 'about', url: 'bethemansystem.com/about', cam: 'wide',
      narr: 'Who’s teaching this? I grew up without a father in the house, so I learned the hard way how a man keeps his word on a Tuesday when nobody’s watching. Today I’m a husband of eleven years, a father of three, a pastor of ten years, and a certified marriage counselor, and I still have weeks where something slips. This is the system I wish someone had handed me at twenty-five. And the site lists six laws I hold myself to, written before anything was published.',
      page: [
        { t: 'hero', cue: 'Who’s teaching this', kicker: 'About', title: 'I’m Brian Greene.', sub: 'I grew up without a father in the house. Nobody showed me how a man keeps his word on a Tuesday when nobody’s watching.' },
        { t: 'kpis', cue: 'a husband of eleven years', items: [ { big: '11', small: 'years a husband', cue: 'husband of eleven' }, { big: '3', small: 'children', cue: 'father of three' }, { big: '10', small: 'years a pastor', cue: 'pastor of ten' } ] },
        { t: 'chips', cue: 'six laws', label: 'Six laws, written before anything was published', items: ['Clock', 'Source', 'Failure', 'Proximity', 'Evidence', 'Protection'], cues: ['six laws', 'six laws', 'six laws', 'six laws', 'six laws', 'six laws'] }
      ] },
    { id: 'start', url: 'bethemansystem.com', cam: 'wide',
      narr: 'So where do you start? Start with Step one. It’s free. If one worksheet doesn’t change anything in a week, nineteen dollars a month won’t either. Then take the Low Seat Check, and send it to someone at your table. When you’re ready, join the Club.',
      page: [
        { t: 'steps', cue: 'So where do you start', plain: true, items: [
          { n: 1, name: 'Get Step 1, free', cue: 'Start with Step one' }, { n: 2, name: 'Take the Low Seat Check, then send it to someone at your table', cue: 'Low Seat Check' }, { n: 3, name: 'When you’re ready, join the Club', cue: 'join the Club' } ] }
      ] },
    { id: 'outro', url: 'bethemansystem.com', cam: 'logo',
      narr: 'Faith should function. Be The Man. Be The Man System dot com.',
      page: [] }
  ];

  /* ---------------------------------------------------------------- the timeline ---------------------------------------------------------------- */
  let DURS = null;
  try { DURS = isNode ? JSON.parse(require('fs').readFileSync(require('path').join(__dirname, 'durations.json'), 'utf8')) : (typeof window !== 'undefined' ? window.WT_DURS : null); } catch (e) { DURS = null; }
  const LEAD = 1.6, GAP = 0.9, TAILPAD = 0.35;
  let cursor = LEAD;
  SCENES.forEach((s, i) => {
    s.n = s.narr.split(/\s+/).length;
    s.nd = DURS && DURS[s.id] ? DURS[s.id] : s.n / 2.9;          // narration seconds (measured when assets/narr exists)
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

  /* a cue phrase -> a time inside its scene (proportional to where it falls in the narration) */
  function cueTime(scene, phrase, fallback) {
    if (phrase == null) return fallback;
    const hay = scene.narr.toLowerCase(), i = hay.indexOf(String(phrase).toLowerCase());
    if (i < 0) return fallback;
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
