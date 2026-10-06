// Be The Man posts already made for Oct 6–18 (weeks 1–2). Media is copied from
// ../instagram/posts/out; this adds Facebook + Threads versions and refreshed CTAs.
const O = '../instagram/posts/out/';
export const existing = [
  {
    id: 'system-when', theme: 'btm', type: 'post', week: 1, date: '2026-10-06', time: '7pm', cta: 'challenge',
    title: 'A goal says what. A system says when.', media: [O + '03-system-when.png'],
    cap: `How to stay disciplined when motivation runs out: stop adding goals. Add a "when."

A promise with no time attached isn't a plan. It's a feeling with a deadline you never set.

Every decision needs three things written down before the week starts:
→ When it happens
→ What counts as a miss
→ How you'd know it held

💾 Save this. Do it Sunday.`,
    th: `A goal says what. A system says when.

A promise with no time attached isn't a plan. It's a feeling with a deadline you never set.

Write three things before the week starts: when it happens, what counts as a miss, how you'd know it held.`,
  },
  {
    id: 'email-receipt', theme: 'btm', type: 'post', week: 1, date: '2026-10-07', time: '7pm', cta: 'challenge',
    title: 'Receipt: what the weekly email costs', media: [O + 'email-receipt.png'],
    cap: `Here's the receipt.

1 × Email, every week: $0.00
1 × Step 1 worksheet: $0.00
Replies that reach a real man: $0.00

Not included: hype, a group chat, guilt trips, or another pep talk you'll forget by Tuesday.

One email. One decision with a time attached. No card. Leave in one click.

The only thing it costs is the excuse.`,
    th: `Here's the receipt for my weekly email.

Email, every week: $0.00
Step 1 worksheet: $0.00
Hype, guilt trips, group chats: not included

One decision with a time attached. No card. Leave in one click. The only thing it costs is the excuse.`,
  },
  {
    id: 'wife-test', theme: 'btm', type: 'post', week: 1, date: '2026-10-08', time: '7pm', cta: 'challenge',
    title: 'Would your wife be able to tell?', media: [O + '04-wife-test.png'],
    cap: `Would your wife be able to tell? That's the whole test.

Not because you announced it. Because it showed up at dinner, at bedtime, and on an ordinary Tuesday.

The best change in a man is the one his house notices before he says a word.

📤 Send this to a man who's ready.`,
    th: `Would your wife be able to tell?

Not because you announced it. Because it showed up at dinner, at bedtime, on an ordinary Tuesday.

The best change in a man is the one his house notices before he says a word.`,
  },
  {
    id: 'club', theme: 'btm', type: 'post', week: 1, date: '2026-10-10', time: '9am', cta: 'club',
    title: 'The Be The Man Club, $19 a month', media: [O + '05-club.png'],
    cap: `The Be The Man Club. $19 a month.

→ The tools in the store, free the day you join
→ A new tool every month
→ One email a week: a time, a trigger, and a way to tell if it held

No group chat. No badges. Cancel anytime; the files are yours to keep.

If you haven't done Step 1 yet, start there. It's free.`,
    th: `The Be The Man Club. $19 a month.

The tools, a new one every month, and one email a week with a time and a trigger.

No group chat. No badges. Cancel anytime, keep the files.`,
  },
  {
    id: 'promise', theme: 'btm', type: 'reel', week: 2, date: '2026-10-12', time: '7pm', cta: 'challenge',
    title: 'Reel: You\'ve made this promise before', media: [O + 'reel-4-promise.mp4', O + 'reel-4-promise-cover.png'],
    cap: `You've made this promise before.

New Year's. Sunday morning. The car after the argument.

You meant it every time.

Men don't lack conviction. What we never had was a first step that comes before the promise.`,
    th: `You've made this promise before.

New Year's. Sunday morning. The car after the argument. You meant it every time.

What you never had was a first step that comes before the promise.`,
  },
  {
    id: 'one-sentence', theme: 'btm', type: 'post', week: 2, date: '2026-10-13', time: '7pm', cta: 'challenge',
    title: 'Who you\'re becoming in one sentence', media: [O + 'w2-06-one-sentence.png'],
    cap: `If you can't say who you're becoming in one sentence, you'll become whoever the week needs you to be.

The boss's version. The tired version. The phone-in-hand version.

Week 1 of the free 7-week challenge is exactly this: one sentence about the man you're becoming. Every step after it gets checked against it.

💾 Save this for tonight.`,
    th: `If you can't say who you're becoming in one sentence, you'll become whoever the week needs you to be.

The boss's version. The tired version. The phone-in-hand version.`,
  },
  {
    id: 'bad-day', theme: 'btm', type: 'reel', week: 2, date: '2026-10-14', time: '7pm', cta: 'challenge',
    title: 'Reel: One bad day shouldn\'t cost you a month', media: [O + 'reel-6-bad-day.mp4', O + 'reel-6-bad-day-cover.png'],
    cap: `You missed one day. So you quit the whole month.

One bad day shouldn't cost you a month.

Before the week starts, write down what counts as a miss. Then missing once isn't failure, and you know exactly what is.

💾 Save this for Sunday.`,
    th: `You missed one day. So you quit the whole month.

One bad day shouldn't cost you a month. Write down what counts as a miss before the week starts. Then missing once isn't failure.`,
  },
  {
    id: 'vision-carousel', theme: 'btm', type: 'carousel', week: 2, date: '2026-10-15', time: '7pm', cta: 'step1',
    title: 'Carousel: Write your vision statement in 20 minutes',
    media: ['1-cover', '2', '3', '4', '5', '6', '7-cta'].map((x) => O + `w2-carousel-${x}.png`),
    cap: `Write your vision statement in 20 minutes. Grab a pen. 💾 Save this.

1. List his attributes. Words you could check, not feelings.
2. Picture an ordinary Tuesday. What does each one look like at 6 PM when you're tired?
3. Would your house know it without you telling them?
4. Say who he is in one sentence.
5. Check every decision against it.`,
    th: `Write your vision statement in 20 minutes:

1. List his attributes
2. Picture an ordinary Tuesday
3. Would your house know without being told?
4. Say who he is in one sentence
5. Check every decision against it`,
  },
  {
    id: 'pray-when', theme: 'btm', type: 'post', week: 2, date: '2026-10-16', time: '7pm', cta: 'challenge',
    title: 'Most men pray when they remember', media: [O + 'w2-07-pray-when.png'],
    cap: `Most men pray when they remember.

That's not a prayer life. That's a mood.

Pick three things:
→ A time. Not "morning." 6:10.
→ A place. The same chair, every day.
→ A trigger. Coffee poured, then pray before the first sip.

A mechanism, not a mood.

📤 Send this to a brother who's been meaning to.`,
    th: `Most men pray when they remember. That's not a prayer life. That's a mood.

Pick a time (6:10, not "morning"), a place (the same chair), and a trigger (coffee poured, pray before the first sip).`,
  },
  {
    id: 'conviction', theme: 'btm', type: 'post', week: 2, date: '2026-10-17', time: '9am', cta: 'challenge',
    title: 'You don\'t need more conviction', media: [O + 'w2-08-conviction.png'],
    cap: `You don't need more conviction. You've had plenty.

You need a starting point.

Not a bigger goal. Not another promise. A first step that everything after it gets built on.

The free 7-week challenge starts Tuesday. Bring a brother.`,
    th: `You don't need more conviction. You've had plenty.

You need a starting point. Not a bigger goal. Not another promise. A first step everything after it gets built on.`,
  },
  {
    id: 'pray-reel', theme: 'btm', type: 'reel', week: 2, date: '2026-10-18', time: '7pm', cta: 'challenge',
    title: 'Reel: Pray with a time attached', media: [O + 'reel-5-pray.mp4', O + 'reel-5-pray-cover.png'],
    cap: `Most men pray when they remember.

That's not a prayer life. It's a mood.

Give it a time. Give it a place. Give it a trigger. Coffee poured, pray before the first sip. Same chair. Same time. Every day.

A mechanism, not a mood.`,
    th: `Most men pray when they remember. That's a mood, not a prayer life.

Give it a time, a place and a trigger. Coffee poured, pray before the first sip. Same chair, every day.`,
  },
];
