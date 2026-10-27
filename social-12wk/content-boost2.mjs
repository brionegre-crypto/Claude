// Boost 2: 3 extra posts per day, Nov 8 – Dec 7, 2026, Reels WITH music.
// 8am Reel (views) · 2pm carousel/quote (saves & shares) · 9pm CTA / comment post.
// Never collides with the main calendar (9am/12pm/4pm/7pm) or Boost 1 (ended Nov 7).
const R = (date, theme, id, cta, title, reel, cap, th, extra = {}) => ({ id: 'b2-' + id, theme, type: 'reel', date, time: '8am', cta, title: 'Reel: ' + title, reel, cap, th, ...extra });
const P = (date, time, theme, id, cta, title, post, cap, th) => ({ id: 'b2-' + id, theme, type: 'post', date, time, cta, title, post, cap, th });
const K = (date, theme, id, cta, title, carousel, cap, th) => ({ id: 'b2-' + id, theme, type: 'carousel', date, time: '2pm', cta, title: 'Carousel: ' + title, carousel, cap, th });
const B = 'btm', C = 'cpl';

export const boost2 = [
  // ───── Sun Nov 8 ─────
  R('2026-11-08', B, 'seven-days', 'group', 'Seven days until six Sundays',
    [['L:7 days', 'B:until six Sundays that *carry you through December.*'], ['S:Four men.', 'S:One hour.', 'B:*Same faces* every week.'], ['B:The holidays won’t *wait.*']],
    `Seven days until the 6-week group starts.

Four men. One hour every Sunday, 7–8 PM Central. The same faces every week, right through the holidays, so your system doesn't die in December.`,
    `Seven days until the 6-week group. Four men, one hour every Sunday, the same faces every week, right through the holidays.`),
  K('2026-11-08', C, 'sunday-reset', 'save', 'A 10-minute Sunday reset for couples',
    { label: 'Tonight · 10 minutes', h: 'A 10-minute Sunday reset *for couples.*', body: 'Before the week **runs you.**',
      slides: [['*Look back.*', 'One thing that went well last week. Each of you.'], ['*Look ahead.*', 'The three busiest days. **No surprises by Wednesday.**'], ['*Plan one date.*', 'Even if it’s 20 minutes on the porch.'], ['*Name one need.*', '“This week, I need ___ from you.”'], ['*Pray.*', 'Hands held. One sentence each.']],
      end: { pre: 'Ten minutes on Sunday.', h: 'A calmer\n*Wednesday.*' } },
    `A 10-minute Sunday reset for couples:

1. Look back: one thing that went well, each of you.
2. Look ahead: the three busiest days.
3. Plan one date, even 20 minutes on the porch.
4. Name one need: "This week, I need ___ from you."
5. Pray, hands held, one sentence each.`,
    `A 10-minute Sunday reset for couples: one win each, the three busiest days, one date, one need, one prayer. Ten minutes on Sunday buys a calmer Wednesday.`),
  P('2026-11-08', '9pm', B, 'humble-tuesday', 'lowSeat', 'How humble are you on a Tuesday?',
    { label: 'Free · 5 minutes', h: 'Every man thinks he’s humble.\n*His kitchen table knows better.*', body: 'Twenty statements about **what you actually do.** One action for this week.', btn: 'Take the check → link in bio' },
    `Every man thinks he's humble. The people at his kitchen table know better.

The Low Seat Check skips how humble you feel and asks what you actually do: when you're corrected, when you miss, when nobody's watching, when someone else gets the credit.

"When you are invited, go and sit in the lowest place." Luke 14:10`,
    `Every man thinks he's humble. The people at his kitchen table know better. The Low Seat Check asks what you actually do when you're corrected.`),

  // ───── Mon Nov 9 ─────
  R('2026-11-09', C, 'check-in-text', 'share', 'The 2 PM text that changes the evening',
    [['L:Send at 2 PM', 'B:“How’s your day *really* going?”'], ['S:Not “what’s for dinner.”', 'S:Not “did you call them.”'], ['B:Ask about *them.*']],
    `Send this at 2 PM today: "How's your day really going?"

Not "what's for dinner." Not "did you call the insurance." Ask about them.

It changes the whole evening.`,
    `Send this at 2 PM: "How's your day really going?" Not "what's for dinner." Ask about them. It changes the whole evening.`),
  P('2026-11-09', '2pm', B, 'quote-first', 'step1', 'Quote: decide who first',
    { h: 'Decide *who* you are before you decide *what* to do.' },
    `Decide who you are before you decide what to do.

Every goal you've broken was built on a sentence you never wrote.`,
    `Decide who you are before you decide what to do. Every goal you've broken was built on a sentence you never wrote.`),
  P('2026-11-09', '9pm', B, 'last-seats', 'group', 'Group: last seats this week',
    { label: 'Starts Sunday · Nov 15', h: 'Four seats.\n*Six Sundays.*\nStarts this week.', body: 'Sundays 7–8 PM Central, **Nov 15 – Dec 20**, on Google Meet. Founding price $147.', btn: 'Reserve a seat → link in bio' },
    `The 6-week group starts this Sunday.

Four seats. Six Sundays, 7–8 PM Central, Nov 15 to Dec 20, on Google Meet. Founding price $147.

If you've been meaning to, this is the week.`,
    `The 6-week group starts this Sunday. Four seats, six Sundays, Nov 15 to Dec 20. If you've been meaning to, this is the week.`),

  // ───── Tue Nov 10 ─────
  R('2026-11-10', B, 'calendar-it', 'challengeOn', 'Put it on the calendar like a meeting',
    [['S:You never skip', 'B:a meeting with *your boss.*'], ['B:So put your goal on the calendar *like one.*'], ['B:Day. Time. Place.\n*In ink.*']],
    `You never skip a meeting with your boss. So put your goal on the calendar like one.

Day. Time. Place. In ink. This week's challenge step: give one goal a day and a time.`,
    `You never skip a meeting with your boss. Put your goal on the calendar like one: day, time, place, in ink.`),
  K('2026-11-10', C, 'respect-ways', 'save', '5 ways to show respect at home',
    { label: 'For husbands and wives', h: '5 ways to show *respect* at home.', body: 'Love says “I care.” **Respect says “I trust you.”**',
      slides: [['Ask their *opinion* first.', 'Before you decide. Not after.'], ['Defend them *in public.*', 'Disagree in private.'], ['Keep *small* promises.', '“I’ll call at lunch.” Then call.'], ['Don’t *correct* in front of kids.', 'Talk about it later, together.'], ['Say *“you were right.”*', 'Out loud. It costs nothing.']],
      end: { pre: 'Respect is built on Tuesdays.', h: 'Love on purpose.\n*Not by accident.*' } },
    `5 ways to show respect at home:

1. Ask their opinion first, before you decide.
2. Defend them in public. Disagree in private.
3. Keep small promises.
4. Don't correct them in front of the kids.
5. Say "you were right," out loud.

Love says "I care." Respect says "I trust you."`,
    `5 ways to show respect at home: ask their opinion first, defend in public, keep small promises, don't correct in front of the kids, say "you were right."`),
  P('2026-11-10', '9pm', B, 'time-poll', 'comment', 'What time is your goal?',
    { label: 'Challenge · week 4', h: 'What *day and time* did you give your goal?', body: 'Write it below. **“Tue/Thu, 6:10 AM, garage.”** Saying it out loud makes it real.', btn: 'Answer below ↓' },
    `This week's challenge step: give one goal a day and a time.

Write yours below: "Tue/Thu, 6:10 AM, garage."

Saying it out loud in front of other men makes it real.`,
    `What day and time did you give your goal this week? "Tue/Thu, 6:10 AM, garage." Saying it out loud makes it real.`),

  // ───── Wed Nov 11 ─────
  R('2026-11-11', C, 'veterans', 'share', 'Service starts at home',
    [['S:Today we honor those who', 'B:*served.*'], ['B:Service starts at *home.*'], ['B:Serve each other\n*first.*']],
    `Today we honor everyone who served. Thank you.

And a reminder for the rest of us: service starts at home. Serve each other first, today, in one small way.`,
    `Today we honor everyone who served. Thank you. And a reminder: service starts at home. Serve each other first today.`, { music: 'btm-resolve' }),
  P('2026-11-11', '2pm', B, 'quote-wednesday', 'workshopWed', 'Quote: Wednesday is where promises go',
    { h: 'Wednesday is where *promises* go to die.', sub: 'Unless Monday gave them a time.' },
    `Wednesday is where promises go to die, unless Monday gave them a time.

Fix Your Wednesday is live again Nov 18, 7 PM Central.`,
    `Wednesday is where promises go to die, unless Monday gave them a time.`),
  P('2026-11-11', '9pm', C, 'gratitude-one', 'comment', 'One thing you’re grateful for about your spouse',
    { label: 'Couples', h: 'One thing you’re grateful for *about your spouse.*', body: 'Be specific. **Then screenshot it and send it to them.**', btn: 'Answer below ↓' },
    `One thing you're grateful for about your spouse. Be specific.

Then screenshot your comment and send it to them. 😊`,
    `One thing you're grateful for about your spouse. Be specific. Then send it to them.`),

  // ───── Thu Nov 12 ─────
  R('2026-11-12', B, 'show-up', 'group', 'Show up six Sundays',
    [['S:You don’t need', 'B:a *new year.*'], ['B:You need *six Sundays*\nand four men.'], ['B:Starts *this Sunday.*']],
    `You don't need a new year. You need six Sundays and four men who notice when you go quiet.

The 6-week group starts this Sunday, Nov 15.`,
    `You don't need a new year. You need six Sundays and four men who notice when you go quiet. Starts this Sunday.`),
  K('2026-11-12', B, 'habit-stack', 'step1', 'Attach the new habit to an old one',
    { label: 'Save this', h: 'Attach the new habit to *one you already have.*', body: 'Don’t find time. **Borrow a trigger.**',
      slides: [['Coffee poured →', '*pray* before the first sip.'], ['Car in park →', 'two minutes of quiet *before you walk in.*'], ['Kids in bed →', '*ten minutes* with your wife, phones away.'], ['Shoes off →', 'phone on the *kitchen counter.*'], ['Sunday dinner done →', '15 minutes to *plan the week.*']],
      end: { pre: 'The sentence comes first.', h: 'Step 1 is\n*free.*' } },
    `Don't find time for a new habit. Borrow a trigger:

Coffee poured → pray before the first sip.
Car in park → two minutes of quiet before you walk in.
Kids in bed → ten minutes with your wife, phones away.
Shoes off → phone on the kitchen counter.
Sunday dinner done → plan the week.`,
    `Don't find time for a new habit. Borrow a trigger. Coffee poured, pray. Car in park, two minutes of quiet. Kids in bed, ten minutes with your wife.`),
  P('2026-11-12', '9pm', B, 'kw-step1', 'step1', 'Comment STEP1: the sentence first',
    { label: 'Free · 20 minutes', h: 'Every system starts with *one sentence.*', body: 'Who you’re becoming, **on paper.** Then everything gets checked against it.', btn: 'Comment “STEP1” →' },
    `Every system starts with one sentence: who you're becoming, on paper. Then everything after it gets checked against it.

Twenty minutes and a pen.`,
    `Every system starts with one sentence: who you're becoming, on paper. Twenty minutes and a pen.`),

  // ───── Fri Nov 13 ─────
  R('2026-11-13', C, 'friday-no-phones', 'save', 'Friday night, no phones',
    [['B:Friday.', 'S:No phones after 8.'], ['B:Just *you two*\nand a deck of cards.'], ['B:Old-school.\n*On purpose.*']],
    `Friday night. No phones after 8. Just you two and a deck of cards, a puzzle, or the old photo albums.

Old-school, on purpose. Tag your spouse so it happens.`,
    `Friday night, no phones after 8. Just you two and a deck of cards. Old-school, on purpose.`),
  P('2026-11-13', '2pm', B, 'quote-seat', 'lowSeat', 'Quote: take the lowest seat',
    { label: 'Luke 14:10', h: '“Go and sit in *the lowest place.*”', sub: 'Humility isn’t thinking less of yourself. It’s thinking of yourself less.' },
    `"When you are invited, go and sit in the lowest place." Luke 14:10

Humility isn't thinking less of yourself. It's thinking of yourself less.`,
    `"Go and sit in the lowest place." Luke 14:10. Humility isn't thinking less of yourself. It's thinking of yourself less.`),
  P('2026-11-13', '9pm', C, 'kw-couples', 'couples', 'Comment COUPLES: holidays ahead',
    { label: 'Before Thanksgiving', h: 'The holidays test *every marriage.*', body: 'Go in knowing where you’re strong and where you’re stretched. **Three sessions, built on your results.**', btn: 'Comment “COUPLES” →' },
    `The holidays test every marriage: family, money, travel, tired.

Go in knowing where you're strong and where you're stretched. A validated assessment, then three sessions built on your results.`,
    `The holidays test every marriage. Go in knowing where you're strong and where you're stretched.`),

  // ───── Sat Nov 14 ─────
  R('2026-11-14', B, 'tomorrow-group', 'group', 'Tomorrow night: six Sundays begin',
    [['L:Tomorrow · 7 PM Central', 'B:Six Sundays *begin.*'], ['S:Four men.', 'S:One tool a week.', 'B:Home by *8.*'], ['B:Last call for *a seat.*']],
    `Tomorrow night, 7 PM Central, six Sundays begin.

Four men. One tool a week. Home by 8. This is the last call for a seat.`,
    `Tomorrow night, six Sundays begin. Four men, one tool a week, home by 8. Last call.`),
  K('2026-11-14', C, 'saturday-chores', 'share', 'Split Saturday, don’t fight about it',
    { label: 'Saturday', h: 'How to split Saturday *without a fight.*', body: 'Decide it **Friday night.**',
      slides: [['List *everything.*', 'Errands, chores, kids’ events, rest.'], ['Each picks *what they hate least.*', 'Seriously. It works.'], ['Trade *one* thing.', '“I’ll take the grocery run if you take bath time.”'], ['Protect *two hours.*', 'For each of you, alone. **Rest is not lazy.**'], ['End with *something fun.*', 'Together. Even just dessert.']],
      end: { pre: 'Same team.', h: 'Love on purpose.\n*Not by accident.*' } },
    `How to split Saturday without a fight (decide it Friday night):

1. List everything.
2. Each picks what they hate least.
3. Trade one thing.
4. Protect two hours alone for each of you.
5. End with something fun together.`,
    `Split Saturday without a fight: list everything, each picks what they hate least, trade one thing, protect two hours of rest each, end with something fun.`),
  P('2026-11-14', '9pm', B, 'one-promise', 'comment', 'The promise you’re keeping this month',
    { label: 'Say it here', h: 'What’s the *one promise* you’re keeping in November?', body: 'Write it below. **Come back Dec 1 and tell us if it held.**', btn: 'Answer below ↓' },
    `What's the one promise you're keeping this November?

Write it below. Come back on Dec 1 and tell us whether it held. We'll be watching. 👀`,
    `What's the one promise you're keeping this November? Write it. Come back Dec 1 and tell us if it held.`),

  // ───── Sun Nov 15 ─────
  R('2026-11-15', C, 'sunday-pray', 'share', 'Pray before church, not after',
    [['B:Pray *before* church.', 'S:Not after the fight in the car.'], ['B:60 seconds.\nHands held.'], ['B:Walk in *together.*']],
    `Pray before church, not after the fight in the car.

Sixty seconds, hands held, before you leave the house. Walk in together.`,
    `Pray before church, not after the fight in the car. Sixty seconds, hands held, before you leave the house.`),
  P('2026-11-15', '2pm', B, 'quote-sunday', 'step1', 'Quote: Sunday decides Wednesday',
    { h: 'Sunday night decides *Wednesday afternoon.*' },
    `Sunday night decides Wednesday afternoon.

Fifteen minutes tonight: what did I say I'd do, what actually happened, and what's the one thing this week?`,
    `Sunday night decides Wednesday afternoon. Fifteen minutes tonight.`),
  P('2026-11-15', '9pm', B, 'workshop-18', 'workshopWed', 'Fix Your Wednesday: Nov 18',
    { label: 'Wed Nov 18 · 7 PM Central · $27', h: 'Lose the week by Wednesday?\n*Fix it on Wednesday.*', items: ['Your **one sentence**', '**One goal** with a date and a time', 'Your first **Scorecard**'], btn: 'Reserve → link in bio' },
    `Most men start Monday strong and lose the week by Wednesday. So we meet on Wednesday.

Fix Your Wednesday, live, Nov 18, 7–8 PM Central. You leave with your sentence, one goal with a date and a time, and your first Scorecard. Recording included.`,
    `Lose the week by Wednesday? Fix it on Wednesday. Live Nov 18, 7 PM Central. $27, recording included.`),

  // ───── Mon Nov 16 ─────
  R('2026-11-16', B, 'miss-defined', 'challengeOn', 'Decide the miss before Monday ends',
    [['B:Write down what counts as *a miss.*'], ['S:Before the week', 'B:argues with *you.*'], ['I:One miss: normal', 'I:Two: change the time', 'I:Three: tell a brother']],
    `This week's challenge step: write down what counts as a miss, before the week argues with you.

One miss: normal. Two in a row: change the time. Three: tell a brother.`,
    `Write down what counts as a miss before the week argues with you. One: normal. Two: change the time. Three: tell a brother.`),
  K('2026-11-16', C, 'thanksgiving-plan', 'couples', 'Your Thanksgiving game plan',
    { label: '10 days out', h: 'Your Thanksgiving *game plan*, as a couple.', body: 'Decided **this week**, not in the driveway.',
      slides: [['*Where* and *how long.*', 'Agree on a leave time. **Then leave.**'], ['*Who* cooks what.', 'Divide it now. No martyrs.'], ['The *hard* relative.', 'Who handles them? **Their own child.**'], ['The *signal.*', 'One word means “I need you.” Honor it.'], ['The *drive home.*', 'One good thing first. Save the rest.']],
      end: { pre: 'Want help getting on the same page?', h: 'Certified marriage\n*counseling.*' } },
    `Your Thanksgiving game plan, decided this week, not in the driveway:

1. Where and how long. Then leave on time.
2. Who cooks what. No martyrs.
3. The hard relative: their own child handles them.
4. A signal that means "I need you."
5. On the drive home, one good thing first.`,
    `Thanksgiving game plan for couples: where and how long, who cooks what, who handles the hard relative, a signal for "I need you," and one good thing on the drive home.`),
  P('2026-11-16', '9pm', B, 'miss-poll', 'comment', 'What’s your miss?',
    { label: 'Challenge · week 5', h: 'Finish this: *“It counts as a miss when…”*', body: 'Make it specific enough that **you can’t argue with it.**', btn: 'Answer below ↓' },
    `Finish this sentence below: "It counts as a miss when…"

Make it specific enough that you can't argue with it on Wednesday. "Not done by 7:00 AM" beats "I didn't really do it."`,
    `Finish this: "It counts as a miss when…" Make it specific enough that you can't argue with it on Wednesday.`),

  // ───── Tue Nov 17 ─────
  R('2026-11-17', C, 'not-tonight', 'share', '“Not tonight” is a full sentence',
    [['S:“Can we talk about it', 'B:*tomorrow at 7?*”'], ['B:That’s not avoiding.', 'B:That’s *protecting* the conversation.'], ['B:Then show up *at 7.*']],
    `"Can we talk about it tomorrow at 7?"

That's not avoiding. That's protecting the conversation from two tired people at 11 PM. Then show up at 7.`,
    `"Can we talk about it tomorrow at 7?" That's not avoiding. That's protecting the conversation. Then show up at 7.`),
  P('2026-11-17', '2pm', B, 'quote-verdict', 'challengeOn', 'Quote: information, not a verdict',
    { h: 'A miss is *information.*\nQuitting is *a verdict.*' },
    `A miss is information. Quitting is a verdict.

Missed it twice? The time is wrong, not you. Change the time.`,
    `A miss is information. Quitting is a verdict. Missed it twice? Change the time, not the goal.`),
  P('2026-11-17', '9pm', B, 'workshop-tomorrow', 'workshopWed', 'Tomorrow night: Fix Your Wednesday',
    { label: 'Tomorrow · 7 PM Central', h: 'One hour in the middle of the week to *get it back.*', body: 'Live on Google Meet. **$27, recording included.**', btn: 'Reserve → link in bio' },
    `Tomorrow night: Fix Your Wednesday, live, 7 PM Central.

One hour in the middle of the week to get it back. Bring a pen. Recording included if you can't make it live.`,
    `Tomorrow 7 PM Central: Fix Your Wednesday. One hour in the middle of the week to get it back.`),

  // ───── Wed Nov 18 ─────
  R('2026-11-18', B, 'tonight-wed', 'workshopWed', 'Tonight: fix your Wednesday',
    [['L:Tonight · 7 PM Central', 'B:It’s Wednesday.\n*Let’s fix it.*'], ['S:One hour.', 'S:A pen.', 'B:Three things *written down.*'], ['B:See you *tonight.*']],
    `It's Wednesday. Let's fix it, tonight at 7 PM Central.

One hour, a pen, and three things written down: your sentence, one goal with a date and a time, and your first Scorecard.`,
    `It's Wednesday. Let's fix it tonight, 7 PM Central. One hour, a pen, three things written down.`),
  K('2026-11-18', C, 'grateful-prompts', 'save', 'Thanksgiving table questions',
    { label: 'Save for next week', h: '5 questions for the *Thanksgiving table.*', body: 'Better than **“so, how’s work?”**',
      slides: [['“What’s one thing that went *right* this year?”', 'Go around the table.'], ['“Who *helped* you this year?”', 'Then text them before dessert.'], ['“What are you *looking forward* to?”', 'Kids love this one.'], ['“What’s a *family story* we should never forget?”', 'Let the elders talk.'], ['“What are you *thankful* to God for?”', 'End with a prayer.']],
      end: { pre: 'Gratitude out loud.', h: 'Love on purpose.\n*Not by accident.*' } },
    `5 questions for the Thanksgiving table:

1. "What's one thing that went right this year?"
2. "Who helped you this year?"
3. "What are you looking forward to?"
4. "What's a family story we should never forget?"
5. "What are you thankful to God for?"

Save this for next week.`,
    `5 Thanksgiving table questions: what went right this year, who helped you, what are you looking forward to, what family story should we never forget, what are you thankful to God for?`),
  P('2026-11-18', '9pm', B, 'inner-circle', 'innerCircle', 'The Inner Circle',
    { label: 'By application · ten men', h: 'For the man who wants someone *checking his number.*', items: ['**Every Thursday:** a private class with me', '**Every month:** a one-on-one', '**Every week:** your Scorecard reviewed'], btn: 'Apply → link in bio' },
    `The Inner Circle is for the man who wants more than a system: someone checking his number.

Every Thursday: a private class with me, ten men at most.
Every month: a one-on-one.
Every week: your Scorecard reviewed.

By application. The first step is a free 15-minute call.`,
    `The Inner Circle: ten men, a weekly class with me, a monthly one-on-one, your Scorecard reviewed every week. By application.`),

  // ───── Thu Nov 19 ─────
  R('2026-11-19', C, 'phones-dinner', 'share', 'Phones off the dinner table',
    [['B:One basket.', 'S:By the front door.'], ['B:Every phone goes in *at dinner.*'], ['S:Yours too.', 'B:*Especially* yours.']],
    `One basket by the front door. Every phone goes in at dinner. Yours too. Especially yours.

The kids will complain for a week. Then they'll start talking.`,
    `One basket by the door. Every phone goes in at dinner. Yours too. Especially yours.`),
  P('2026-11-19', '2pm', B, 'quote-kitchen', 'lowSeat', 'Quote: the kitchen table knows',
    { h: 'You’re only as humble as *your kitchen table* says you are.' },
    `You're only as humble as your kitchen table says you are.

Want an honest read? The Low Seat Check is free and takes five minutes. You can even ask your wife to answer it about you.`,
    `You're only as humble as your kitchen table says you are.`),
  P('2026-11-19', '9pm', C, 'love-language', 'comment', 'How do you feel most loved?',
    { label: 'Couples poll', h: 'You feel most loved when they…', body: '**A** say it · **B** do something · **C** spend time · **D** hug you · **E** give a gift. Comment yours.', btn: 'Comment A–E ↓' },
    `You feel most loved when your spouse…

A. Says it
B. Does something for you
C. Spends time with you
D. Hugs you
E. Gives you something

Comment your letter. Then ask your spouse for theirs. You might be surprised.`,
    `You feel most loved when your spouse: A says it, B does something, C spends time, D hugs you, E gives a gift. Which one? Ask them too.`),

  // ───── Fri Nov 20 ─────
  R('2026-11-20', B, 'friday-count', 'challengeOn', 'Count it honestly this weekend',
    [['B:How many times did it *actually happen?*'], ['S:Not how you feel about it.', 'B:*The number.*'], ['B:The number doesn’t *lie.*\nOr judge.']],
    `This weekend, count it honestly. Not how you feel about the month: how many times it actually happened.

The number doesn't lie, and it doesn't judge. It just tells you where to start.`,
    `Count it honestly this weekend: not how you feel, how many times it actually happened. The number doesn't lie or judge.`),
  K('2026-11-20', B, 'black-friday', 'step1', 'What you actually need before Black Friday',
    { label: 'Before you shop', h: 'Things your family needs more than *what’s on sale.*', body: 'None of them cost **anything.**',
      slides: [['A *calm* father.', 'Not a perfect one.'], ['Your *attention.*', 'Phone down. Eyes up.'], ['Your *word, kept.*', 'Home when you said.'], ['Your *prayers.*', 'Out loud, by name.'], ['Your *presence.*', 'On the floor, not just in the room.']],
      end: { pre: 'Start with who you’re becoming.', h: 'Step 1 is\n*free.*' } },
    `Things your family needs more than what's on sale:

A calm father, not a perfect one.
Your attention: phone down, eyes up.
Your word, kept.
Your prayers, out loud, by name.
Your presence: on the floor, not just in the room.

None of them cost anything.`,
    `What your family needs more than what's on sale: a calm father, your attention, your word kept, your prayers by name, your presence. None of it costs anything.`),
  P('2026-11-20', '9pm', B, 'tag-dad', 'comment', 'Tag a father who shows up',
    { label: 'Honor him', h: 'Tag a father who *shows up.*', body: 'Not perfect. **Present.** Let him know somebody noticed.', btn: 'Tag him below ↓' },
    `Tag a father who shows up. Not a perfect one. A present one.

Let him know somebody noticed. Men rarely hear it.`,
    `Tag a father who shows up. Not perfect. Present. Men rarely hear that somebody noticed.`),

  // ───── Sat Nov 21 ─────
  R('2026-11-21', C, 'saturday-breakfast', 'save', 'Saturday breakfast before the kids wake',
    [['S:Saturday.', 'B:Up *30 minutes* before the kids.'], ['B:Coffee.\nBlanket.\n*Porch.*'], ['B:The best date costs *nothing.*']],
    `Saturday: get up 30 minutes before the kids. Coffee, blanket, porch.

The best date of the week costs nothing and lasts half an hour.`,
    `Saturday: up 30 minutes before the kids. Coffee, blanket, porch. The best date costs nothing.`),
  P('2026-11-21', '2pm', C, 'quote-thanks', 'share', 'Quote: gratitude out loud',
    { h: 'Gratitude you don’t say is just *a nice thought you kept.*' },
    `Gratitude you don't say is just a nice thought you kept.

Say it out loud to your spouse today. Specifically.`,
    `Gratitude you don't say is just a nice thought you kept. Say it out loud today.`),
  P('2026-11-21', '9pm', B, 'club-week', 'club', 'The Club: tools that keep you going',
    { label: 'The Be The Man Club · $19 a month', h: 'A new habit takes *66 days.*\nMost men quit at *14.*', body: 'The Club gives you **a new tool every month** so you keep going past month one.', btn: 'Join the Club → link in bio' },
    `A new habit takes about 66 days to stick. Most men quit around day 14.

The Club keeps you going past month one: the framework and the Weekly Scorecard the day you join, then a new set of tools every month. $19 a month, cancel anytime.`,
    `A new habit takes about 66 days to stick. Most men quit around day 14. The Club keeps you going past month one.`),

  // ───── Sun Nov 22 ─────
  R('2026-11-22', B, 'thankful-week', 'challengeOn', 'Thanksgiving week: count and thank',
    [['L:Thanksgiving week', 'B:Count it.\n*Then thank God for it.*'], ['S:14 of 20 mornings', 'B:is 14 mornings you *showed up.*'], ['B:That’s *grace*, not failure.']],
    `Thanksgiving week. Count it honestly, then thank God for every one.

14 of 20 mornings isn't failure. It's 14 mornings you showed up that you'd have forgotten. That's grace.`,
    `Thanksgiving week: count it honestly, then thank God for every one. 14 of 20 mornings is 14 mornings you showed up.`),
  K('2026-11-22', C, 'host-peace', 'couples', 'Hosting Thanksgiving without the fight',
    { label: 'Hosting this year?', h: 'Hosting Thanksgiving *without the fight.*', body: 'Most hosting fights happen **before anyone arrives.**',
      slides: [['Make the *list* together.', 'Monday night. Both of you.'], ['*Split* the day.', 'One cooks, one handles house and kids. **Switch at noon.**'], ['Set the *budget.*', 'One number for the whole day.'], ['Plan a *break.*', 'Ten minutes alone together mid-afternoon.'], ['Thank each other *first.*', 'Before the guests do.']],
      end: { pre: 'Engaged or married?', h: 'Certified marriage\n*counseling.*' } },
    `Hosting Thanksgiving without the fight:

1. Make the list together, Monday night.
2. Split the day: one cooks, one handles the house and kids.
3. One budget number.
4. Plan a ten-minute break together mid-afternoon.
5. Thank each other first, before the guests do.`,
    `Hosting Thanksgiving without the fight: list together, split the day, one budget, a ten-minute break together, thank each other first.`),
  P('2026-11-22', '9pm', B, 'humble-witness', 'lowSeat', 'Ask your wife to be your witness',
    { label: 'The Low Seat Check', h: 'Brave enough to let your wife *score you too?*', body: 'Take the free check, then send her **the second-witness version.** Compare.', btn: 'Take the check → link in bio' },
    `Brave enough to let your wife score you too?

Take the free Low Seat Check yourself. Then send her the second-witness version: the same twenty statements, answered about you. Compare.

That gap is where the growth is.`,
    `Brave enough to let your wife score you too? Take the free Low Seat Check, then send her the second-witness version. Compare.`),

  // ───── Mon Nov 23 ─────
  R('2026-11-23', C, 'thank-list', 'save', '10 things I love about you',
    [['B:10 things\nI love *about you.*'], ['S:Write the list.', 'S:Small. Specific. Real.'], ['B:Hand it over *Thursday.*']],
    `A Thanksgiving gift that costs nothing: write "10 things I love about you." Small, specific, real.

Hand it over on Thursday. Watch what happens.`,
    `Write "10 things I love about you." Small, specific, real. Hand it over Thursday.`),
  P('2026-11-23', '2pm', B, 'quote-grace', 'challengeOn', 'Quote: progress is grace',
    { h: 'Progress isn’t pride.\n*It’s grace you counted.*' },
    `Progress isn't pride. It's grace you counted.

Look at your number this week, then thank God for it out loud.`,
    `Progress isn't pride. It's grace you counted.`),
  P('2026-11-23', '9pm', B, 'thanks-name', 'comment', 'Name one man you’re thankful for',
    { label: 'Thanksgiving week', h: 'Name one man you’re *thankful for* this year.', body: 'A father, a brother, a pastor, a friend. **Tag him if he’s here.**', btn: 'Answer below ↓' },
    `Thanksgiving week. Name one man you're thankful for this year: a father, a brother, a pastor, a friend.

Tag him if he's here. Then call him this week.`,
    `Name one man you're thankful for this year. Tag him. Then call him this week.`),

  // ───── Tue Nov 24 ─────
  R('2026-11-24', B, 'gratitude-out-loud', 'step1', 'Thank them out loud this week',
    [['S:Your wife.', 'S:Your kids.', 'S:Your father.'], ['B:Thank them *out loud.*'], ['B:Specifically.\n*Before Thursday.*']],
    `Your wife. Your kids. Your father, or the man who stepped in.

Thank them out loud, specifically, before Thursday. "Thanks for everything" doesn't count.`,
    `Thank your wife, your kids and your father out loud, specifically, before Thursday. "Thanks for everything" doesn't count.`),
  K('2026-11-24', C, 'pie-not-politics', 'share', 'Family table boundaries, kindly',
    { label: 'Before Thursday', h: 'How to change the subject *at the family table.*', body: 'Kind, quick, **and together.**',
      slides: [['On *politics.*', '“We’re keeping today about family. Who wants pie?”'], ['On *your parenting.*', '“We’ve got it, Mom. Thanks for caring.”'], ['On *money.*', '“That’s between us. Tell me about your trip.”'], ['On *when’s the baby?*', '“You’ll be the first to know. More rolls?”'], ['Always *together.*', 'A look, a hand on the back. **You’re a team.**']],
      end: { pre: 'One team at the table.', h: 'Love on purpose.\n*Not by accident.*' } },
    `How to change the subject at the family table, kindly and together:

On politics: "We're keeping today about family. Who wants pie?"
On your parenting: "We've got it, Mom. Thanks for caring."
On money: "That's between us."
On "when's the baby?": "You'll be the first to know."

A look, a hand on the back. You're a team.`,
    `Change the subject at the family table: "We're keeping today about family. Who wants pie?" "We've got it, Mom." "That's between us." You're a team.`),
  P('2026-11-24', '9pm', C, 'kw-couples-2', 'couples', 'Comment COUPLES: start 2027 strong',
    { label: 'Engaged or married?', h: 'Start 2027 knowing *exactly* where you stand.', body: 'A validated assessment, then **three sessions** built on your results.', btn: 'Comment “COUPLES” →' },
    `Start 2027 knowing exactly where you stand as a couple: where you're strong, where you're stretched, and what to work on first.

A validated assessment you each take, then three sessions built on your results.`,
    `Start 2027 knowing exactly where you stand as a couple. A validated assessment, then three sessions built on your results.`),

  // ───── Wed Nov 25 ─────
  R('2026-11-25', C, 'travel-calm', 'share', 'The holiday drive',
    [['S:Long drive.', 'S:Tired kids.', 'B:Short *fuses.*'], ['B:Decide the *tone*\nbefore the car starts.'], ['B:Pray in the *driveway.*']],
    `Long drive. Tired kids. Short fuses.

Decide the tone before the car starts. Thirty seconds of prayer in the driveway. Safe travels, everybody.`,
    `Long drive, tired kids, short fuses. Decide the tone before the car starts. Pray in the driveway.`),
  P('2026-11-25', '2pm', B, 'quote-calm', 'step1', 'Quote: a calm father',
    { h: 'The best thing at the table tomorrow is *a calm father.*' },
    `The best thing at the table tomorrow is a calm father. Not a perfect one. A calm one.

Decide your temper today.`,
    `The best thing at the table tomorrow is a calm father. Decide your temper today.`),
  P('2026-11-25', '9pm', B, 'thanksgiving-eve', 'comment', 'What are you thankful for this year?',
    { label: 'Thanksgiving Eve', h: 'One thing you’re *thankful to God for* this year.', body: 'Big or small. **Say it here first.**', btn: 'Answer below ↓' },
    `Thanksgiving Eve. One thing you're thankful to God for this year. Big or small.

Say it here first, then say it at the table tomorrow.`,
    `Thanksgiving Eve: one thing you're thankful to God for this year. Say it here, then at the table.`),

  // ───── Thu Nov 26 (Thanksgiving) ─────
  R('2026-11-26', B, 'happy-thanksgiving', 'share', 'Happy Thanksgiving',
    [['B:Happy *Thanksgiving.*'], ['S:Put the phone down.', 'S:Look around the table.'], ['B:That’s the *wealth.*']],
    `Happy Thanksgiving from our family to yours.

Put the phone down today. Look around the table. That's the wealth.`,
    `Happy Thanksgiving. Put the phone down. Look around the table. That's the wealth.`, { music: 'cpl-home' }),
  K('2026-11-26', C, 'thanks-prayer', 'share', 'A Thanksgiving prayer for your family',
    { label: 'Read it at the table', h: 'A Thanksgiving prayer *for your family.*', body: 'Out loud, **before the plates.**',
      slides: [['For the *food.*', '“Thank you for the hands that made it.”'], ['For the *people.*', '“Thank you for every name at this table.”'], ['For the *missing.*', '“Comfort us for the ones we miss today.”'], ['For the *hard year.*', '“Thank you that we came through it together.”'], ['For *grace.*', '“Make us thankful people, not just on Thursday.”']],
      end: { pre: 'Happy Thanksgiving.', h: 'From our family\n*to yours.*' } },
    `A Thanksgiving prayer for your family, out loud, before the plates:

For the food: thank you for the hands that made it.
For the people: thank you for every name at this table.
For the missing: comfort us for the ones we miss today.
For the hard year: thank you that we came through it together.
For grace: make us thankful people, not just on Thursday.`,
    `A Thanksgiving prayer: for the food, for every name at this table, for the ones we miss, for coming through a hard year together, and for grace beyond Thursday.`),
  P('2026-11-26', '9pm', B, 'thanksgiving-night', 'comment', 'Best moment of the day',
    { label: 'Thanksgiving night', h: 'What was the *best moment* of your day?', body: 'Not the food. **The moment.**', btn: 'Answer below ↓' },
    `Thanksgiving night. What was the best moment of your day? Not the food. The moment.`,
    `Thanksgiving night: what was the best moment of your day? Not the food. The moment.`),

  // ───── Fri Nov 27 ─────
  R('2026-11-27', C, 'black-friday-couples', 'save', 'Black Friday: set one number',
    [['L:Black Friday', 'B:One number.\n*Decided together.*'], ['S:Before the cart.', 'S:Before the deal.'], ['B:Peace in *February.*']],
    `Black Friday: one number, decided together, before the cart and before the deal.

The best gift you can give each other is peace in February.`,
    `Black Friday: one number, decided together, before the cart. The best gift is peace in February.`),
  P('2026-11-27', '2pm', B, 'gift-year', 'clubYear', 'A gift that’s still working in March',
    { label: 'For the man who “doesn’t need anything”', h: 'Give him a gift that’s still working *in March.*', body: 'The Be The Man Club, yearly. **Everything today. $149.**', btn: 'Club yearly → link in bio' },
    `For the man in your life who says he doesn't need anything: give him a gift that's still working in March.

The Be The Man Club, yearly: everything today, plus the monthly tool, for $149.`,
    `For the man who says he doesn't need anything: a gift that's still working in March. The Club, yearly, $149.`),
  P('2026-11-27', '9pm', B, 'leftovers', 'comment', 'Leftovers or the gym?',
    { label: 'Be honest', h: 'Tomorrow morning:\n*leftovers* or *the gym?*', body: 'No judgment. **Just tell the truth.** 😄', btn: 'Answer below ↓' },
    `Be honest. Tomorrow morning: leftovers or the gym?

No judgment. Just tell the truth. 😄 (Both is also an answer.)`,
    `Tomorrow morning: leftovers or the gym? Be honest.`),

  // ───── Sat Nov 28 ─────
  R('2026-11-28', B, 'december-plan', 'challengeOn', 'Plan December before it plans you',
    [['B:December will plan you', 'S:if you don’t'], ['B:plan *it* first.'], ['I:One goal for your soul', 'I:One for your house', 'I:One for your work']],
    `December will plan you if you don't plan it first.

One goal for your soul, one for your house, one for your work. Give each a day and a time this weekend.`,
    `December will plan you if you don't plan it first. One goal each for soul, house and work.`),
  K('2026-11-28', C, 'advent-couples', 'save', '4 Advent habits for couples',
    { label: 'Advent starts tomorrow', h: '4 Advent habits *for couples.*', body: 'One for **each Sunday.**',
      slides: [['Week 1 · *Hope.*', 'Write one hope for next year. Read them aloud.'], ['Week 2 · *Peace.*', 'Settle one old argument. For real.'], ['Week 3 · *Joy.*', 'Plan one silly, fun night.'], ['Week 4 · *Love.*', 'Write each other a letter about this year.'], ['Every night · *Pray.*', 'Two minutes. Hands held.']],
      end: { pre: 'Advent begins tomorrow.', h: 'Love on purpose.\n*Not by accident.*' } },
    `4 Advent habits for couples, one for each Sunday:

Week 1, Hope: write one hope for next year.
Week 2, Peace: settle one old argument, for real.
Week 3, Joy: plan one silly, fun night.
Week 4, Love: write each other a letter about this year.

Every night: pray two minutes, hands held.`,
    `4 Advent habits for couples: hope (one hope for next year), peace (settle one old argument), joy (a silly night), love (a letter about this year). Pray nightly.`),
  P('2026-11-28', '9pm', B, 'workshop-dec2', 'workshopWed', 'Fix Your Wednesday: Dec 2',
    { label: 'Wed Dec 2 · 7 PM Central · $27', h: 'Don’t let December *eat your system.*', body: 'One hour, live. **Leave with your sentence, a goal and a Scorecard.**', btn: 'Reserve → link in bio' },
    `Don't let December eat your system.

Fix Your Wednesday, live Dec 2, 7–8 PM Central. One hour. Leave with your sentence, one goal with a date and a time, and your first Scorecard. Recording included.`,
    `Don't let December eat your system. Fix Your Wednesday, live Dec 2, 7 PM Central. $27, recording included.`),

  // ───── Sun Nov 29 ─────
  R('2026-11-29', C, 'advent-hope', 'share', 'Advent: hope',
    [['L:Advent · week 1', 'B:*Hope.*'], ['S:Write one hope for next year.', 'S:Read it to each other.'], ['B:Then *pray over it.*']],
    `Advent, week one: hope.

Tonight, each write one hope for next year. Read it to each other. Then pray over it together.`,
    `Advent week one, hope: each write one hope for next year, read it aloud, pray over it together.`),
  P('2026-11-29', '2pm', B, 'quote-advent', 'step1', 'Quote: Advent is waiting with purpose',
    { label: 'Advent', h: 'Advent isn’t waiting around.\n*It’s waiting on purpose.*' },
    `Advent isn't waiting around. It's waiting on purpose.

What are you preparing for this December?`,
    `Advent isn't waiting around. It's waiting on purpose.`),
  P('2026-11-29', '9pm', B, 'promise-check', 'comment', 'Did your November promise hold?',
    { label: 'Two weeks ago you told us', h: 'Did your *November promise* hold?', body: '**Held · Mostly · Missed.** Comment yours. No shame. Just data.', btn: 'Answer below ↓' },
    `Two weeks ago, you told us the one promise you were keeping this November.

Did it hold? Comment: Held, Mostly, or Missed. No shame. It's just data for December.`,
    `Did your November promise hold? Held, mostly, or missed? No shame. Just data for December.`),

  // ───── Mon Nov 30 ─────
  R('2026-11-30', B, 'god-center', 'challengeOn', 'Put God at the center',
    [['B:God isn’t goal *number four.*'], ['B:He’s the reason *for the list.*'], ['S:Final week of the challenge:', 'B:put Him *at the center.*']],
    `God isn't goal number four on your list. He's the reason for the list.

The challenge's final week: put Him at the center of every goal you kept.`,
    `God isn't goal number four on your list. He's the reason for the list. Final challenge week: put Him at the center.`),
  K('2026-11-30', B, 'morning-15', 'faithKit', 'A 15-minute morning with God',
    { label: 'Try it tomorrow', h: 'A 15-minute morning *with God.*', body: 'A time, a place, **a plan.**',
      slides: [['*2 min* · Be still.', 'Same chair. Phone in another room.'], ['*5 min* · One passage.', 'Read it twice, slowly.'], ['*3 min* · One line to keep.', 'Write it on a card.'], ['*3 min* · Pray it back.', 'For your wife, kids and work, by name.'], ['*2 min* · One decision.', 'What changes today because of what you read?']],
      end: { pre: 'The Faith Kit: prayer, Scripture and discipleship tools.', h: 'Put God first.\n*On purpose.*' } },
    `A 15-minute morning with God:

2 min: be still. Same chair, phone in another room.
5 min: one passage, read twice.
3 min: write down the one line to keep.
3 min: pray it back, by name.
2 min: one decision for today.`,
    `A 15-minute morning with God: be still, one passage read twice, one line to keep, pray it back by name, one decision for today.`),
  P('2026-11-30', '9pm', B, 'cyber-monday', 'library', 'Cyber Monday: all 11 tools',
    { label: 'Cyber Monday', h: 'Every tool in one download.\n*$97.*', body: 'Field guides, workbooks, devotional, Bible study, prayer strategy, **all three card decks.**', btn: 'All 11 tools → link in bio' },
    `Cyber Monday: every tool in the store in one download, $97.

The Godly Husband and Father's Field Guides, the Marriage Workbook, the Husband's Devotional, the Bible Study, the Discipleship Workbook, the Prayer Strategy, all three card decks and the trackers.`,
    `Cyber Monday: every tool in the store in one download, $97. Field guides, workbooks, devotional, Bible study, card decks.`),

  // ───── Tue Dec 1 ─────
  R('2026-12-01', C, 'december-us', 'save', 'December: one night a week for us',
    [['L:December', 'B:One night a week\n*just for us.*'], ['S:Put it on the calendar', 'B:before the *parties* do.'], ['B:Protect it.']],
    `December: one night a week just for the two of you. Put it on the calendar before the parties do. Then protect it.`,
    `December: one night a week just for the two of you. Put it on the calendar before the parties do.`),
  P('2026-12-01', '2pm', B, 'quote-center', 'challengeOn', 'Quote: the center holds',
    { h: 'When God is at the center,\n*the schedule has somewhere to stand.*' },
    `When God is at the center, the schedule has somewhere to stand.

Final week of the 7-week challenge. You made it. Keep going.`,
    `When God is at the center, the schedule has somewhere to stand.`),
  P('2026-12-01', '9pm', B, 'challenge-done', 'comment', 'You finished seven weeks',
    { label: 'Seven weeks', h: 'You did *seven weeks.*\nWhat changed?', body: 'One sentence. **Your house noticed something.** What was it?', btn: 'Answer below ↓' },
    `Seven weeks of the challenge. If you stuck with it, even partly, something changed.

What did your house notice? One sentence below. Let the next man see it's possible.`,
    `Seven weeks of the challenge. What did your house notice? One sentence. Let the next man see it's possible.`),

  // ───── Wed Dec 2 ─────
  R('2026-12-02', B, 'tonight-dec2', 'workshopWed', 'Tonight: fix your Wednesday (December)',
    [['L:Tonight · 7 PM Central', 'B:Before December *gets loud.*'], ['S:One hour.', 'S:One pen.', 'B:One plan that *holds.*'], ['B:See you *tonight.*']],
    `Tonight, 7 PM Central: Fix Your Wednesday, before December gets loud.

One hour, one pen, one plan that holds through the holidays. Recording included.`,
    `Tonight 7 PM Central: Fix Your Wednesday before December gets loud. One hour, one plan that holds.`),
  K('2026-12-02', C, 'gift-ideas', 'save', 'Gifts your spouse will actually remember',
    { label: 'Christmas list', h: 'Gifts your spouse will *actually remember.*', body: 'Most cost **time, not money.**',
      slides: [['A *planned* day.', 'Sitter booked. Phone off. **Their pick.**'], ['A *letter.*', 'What this year meant. Handwritten.'], ['A *redo.*', 'Your first date, recreated.'], ['A *break.*', 'A whole Saturday off. You take everything.'], ['A *promise* with a date.', '“Every other Friday, 7 PM, all year.”']],
      end: { pre: 'Time beats things.', h: 'Love on purpose.\n*Not by accident.*' } },
    `Gifts your spouse will actually remember:

1. A planned day: sitter booked, phone off, their pick.
2. A handwritten letter about this year.
3. Your first date, recreated.
4. A whole Saturday off. You handle everything.
5. A promise with a date: "Every other Friday, 7 PM, all year."`,
    `Gifts your spouse will actually remember: a planned day, a handwritten letter, your first date recreated, a Saturday off, a promise with a date.`),
  P('2026-12-02', '9pm', C, 'merry-or-stressed', 'comment', 'Merry or stressed?',
    { label: 'Honest check-in', h: 'December so far:\n*merry* or *stressed?*', body: 'Comment one word. **Then ask your spouse the same.**', btn: 'Answer below ↓' },
    `Honest check-in. December so far: merry or stressed?

Comment one word. Then ask your spouse the same question tonight, and actually listen to the answer.`,
    `December so far: merry or stressed? Ask your spouse the same tonight.`),

  // ───── Thu Dec 3 ─────
  R('2026-12-03', C, 'advent-peace', 'share', 'Advent: peace (settle one argument)',
    [['L:Advent · week 2', 'B:*Peace.*'], ['S:Pick one old argument.', 'B:Settle it *for real.*'], ['B:Not who’s right.\n*What’s next.*']],
    `Advent, week two: peace. Pick one old argument and settle it, for real.

Not who's right. What's next.`,
    `Advent week two, peace: pick one old argument and settle it. Not who's right. What's next.`),
  P('2026-12-03', '2pm', B, 'quote-present', 'step1', 'Quote: presence over presents',
    { h: 'Your kids will forget *the presents.*\nThey’ll remember *the presence.*' },
    `Your kids will forget most of the presents. They'll remember your presence.

Phone in a drawer after dinner, all month.`,
    `Your kids will forget the presents. They'll remember your presence.`),
  P('2026-12-03', '9pm', B, 'inner-circle-2', 'innerCircle', 'Inner Circle: a private room',
    { label: 'By application', h: 'A small private room.\n*Me in it every week.*', body: 'Ten men. **Thursday nights.** A monthly one-on-one. A direct line on weekdays.', btn: 'Apply → link in bio' },
    `The Inner Circle: a small private room, and me in it every week.

Ten men at most. Thursday nights, 7–8 PM Central. A monthly one-on-one. A direct line on weekdays. By application; the first step is a free 15-minute call.`,
    `The Inner Circle: ten men, Thursday nights with me, a monthly one-on-one, a direct line on weekdays. By application.`),

  // ───── Fri Dec 4 ─────
  R('2026-12-04', B, 'christmas-calm', 'step1', 'The calm father at Christmas',
    [['S:The best gift under the tree', 'B:is a *calm* father.'], ['S:Not a rich one.', 'S:Not a perfect one.'], ['B:One who doesn’t make the house *hold its breath.*']],
    `The best gift under the tree this year is a calm father.

Not a rich one. Not a perfect one. One who doesn't make the house hold its breath when he walks in.`,
    `The best gift under the tree is a calm father. One who doesn't make the house hold its breath.`),
  K('2026-12-04', B, 'dad-december', 'fatherKit', '5 December traditions for dads',
    { label: 'Start one this year', h: '5 December traditions *for dads.*', body: 'Your kids will remember **these.**',
      slides: [['The *lights* drive.', 'Hot chocolate, pajamas, a slow drive.'], ['The *one-on-one.*', '20 minutes alone with each kid. Their pick.'], ['The *story.*', 'Dad reads Luke 2 out loud.'], ['The *give.*', 'Pick a family to bless together.'], ['The *letter.*', 'Write each child what you saw in them this year.']],
      end: { pre: 'The Father Kit: tools for leading your kids.', h: 'Lead them\n*on purpose.*' } },
    `5 December traditions for dads:

1. The lights drive: hot chocolate, pajamas, a slow drive.
2. The one-on-one: 20 minutes alone with each kid.
3. The story: Dad reads Luke 2 out loud.
4. The give: bless a family together.
5. The letter: write each child what you saw in them this year.`,
    `5 December traditions for dads: the lights drive, a one-on-one with each kid, Dad reads Luke 2, bless a family together, write each child a letter.`),
  P('2026-12-04', '9pm', B, 'tradition-poll', 'comment', 'Your favorite family tradition',
    { label: 'Share it', h: 'What’s your family’s *favorite* December tradition?', body: 'Steal-worthy ideas only. **Somebody needs one.**', btn: 'Answer below ↓' },
    `What's your family's favorite December tradition? Share it below.

Steal-worthy ideas only. Somebody reading this needs one.`,
    `What's your family's favorite December tradition? Somebody reading this needs one.`),

  // ───── Sat Dec 5 ─────
  R('2026-12-05', C, 'saturday-lights', 'save', 'Saturday night: the lights',
    [['B:Saturday night.', 'S:Hot chocolate.'], ['B:A slow drive through *the lights.*'], ['B:Your playlist from *back then.*']],
    `Saturday night: hot chocolate, a slow drive through the lights, and your playlist from back then.

Just you two. Tag your spouse.`,
    `Saturday night: hot chocolate, a slow drive through the lights, your playlist from back then.`),
  P('2026-12-05', '2pm', C, 'quote-emmanuel', 'share', 'Quote: God with us',
    { label: 'Emmanuel', h: 'God *with* us.', sub: 'Be with each other this month. Not just near. With.' },
    `Emmanuel: God with us. Not above us. Not away from us. With us.

Be with each other this month. Not just near. With.`,
    `Emmanuel: God with us. Be with each other this month. Not just near. With.`),
  P('2026-12-05', '9pm', B, 'year-word', 'comment', 'Your word for 2027',
    { label: 'Already thinking ahead?', h: 'One word for *2027.*', body: 'Steady? Present? Faithful? **Drop it below.**', btn: 'Answer below ↓' },
    `Already thinking ahead? Give us one word for 2027. Steady? Present? Faithful? Bold?

Drop it below. We'll come back to it in January.`,
    `One word for 2027. Steady? Present? Faithful? Drop it below.`),

  // ───── Sun Dec 6 ─────
  R('2026-12-06', B, 'before-new-year', 'step1', 'Before the New Year’s promise',
    [['S:You’ll make the', 'B:*New Year’s* promise again.'], ['B:Start *before* it this time.'], ['B:Step 1.\n*20 minutes.* A pen.']],
    `You'll make the New Year's promise again. This time, start before it.

Step 1: twenty minutes, a pen, and one sentence about the man you're becoming.`,
    `You'll make the New Year's promise again. Start before it this time. Step 1: twenty minutes and a pen.`),
  K('2026-12-06', C, 'year-review', 'couples', 'Your year in review, as a couple',
    { label: 'Before 2027', h: 'Your year in review, *as a couple.*', body: 'Thirty minutes. **Coffee. Honest answers.**',
      slides: [['Our *best* moment?', 'Each of you picks one.'], ['Our *hardest* season?', 'What got us through it?'], ['When did we feel *far apart?*', 'No blame. Just name it.'], ['What do we want *more* of?', 'Pick one thing.'], ['One *marriage goal*, with a date.', '“Date night every other Friday at 7.”']],
      end: { pre: 'Want a guided version?', h: 'Certified marriage\n*counseling.*' } },
    `Your year in review as a couple. Thirty minutes, coffee, honest answers:

1. Our best moment?
2. Our hardest season, and what got us through it?
3. When did we feel far apart?
4. What do we want more of?
5. One marriage goal for 2027, with a date.`,
    `Couple's year in review: best moment, hardest season, when you felt far apart, what you want more of, one goal for 2027 with a date.`),
  P('2026-12-06', '9pm', B, 'kw-step1-final', 'step1', 'Comment STEP1: start December 31 early',
    { label: 'Free · before January', h: 'Don’t wait for *January 1.*', body: 'Write your sentence **this week.** Walk into 2027 already moving.', btn: 'Comment “STEP1” →' },
    `Don't wait for January 1. Write your sentence this week and walk into 2027 already moving.

Step 1 is free: twenty minutes and a pen.`,
    `Don't wait for January 1. Write your sentence this week and walk into 2027 already moving.`),

  // ───── Mon Dec 7 ─────
  R('2026-12-07', C, 'advent-joy', 'share', 'Advent: joy',
    [['L:Advent · week 3', 'B:*Joy.*'], ['S:Plan one silly night.', 'S:Pillow fort. Old movie. Bad dancing.'], ['B:Laugh *together.*']],
    `Advent, week three: joy. Plan one silly night this week.

Pillow fort. An old movie. Bad dancing in the kitchen. Laugh together on purpose.`,
    `Advent week three, joy: plan one silly night. Pillow fort, old movie, bad dancing. Laugh together on purpose.`),
  P('2026-12-07', '2pm', B, 'quote-man', 'step1', 'Quote: be the man',
    { h: 'Break the cycle.\nBuild the system.\n*Be the man.*' },
    `Break the cycle. Build the system. Be the man.

Not in January. This week.`,
    `Break the cycle. Build the system. Be the man. Not in January. This week.`),
  P('2026-12-07', '9pm', B, 'call-december', 'call', 'Stuck before the year ends?',
    { label: 'Free · 15 minutes', h: 'Where are you *stuck* before the year ends?', body: 'Book a free call with me. **One next step, with a time on it.**', btn: 'Book a call → link in bio' },
    `Where are you stuck before the year ends? Your marriage, your temper, your faith, the same promise?

Book a free 15-minute call with me. We'll name one next step and give it a time.`,
    `Where are you stuck before the year ends? A free 15-minute call. One next step with a time on it.`),
];
