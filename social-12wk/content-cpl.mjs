// Couples, weeks 1–12 (Oct 6 – Dec 27). Posted on the Be The Man accounts, cream theme,
// written to both spouses. CTAs: couples (counseling inquiry), share, save.
const C = (o) => ({ theme: 'cpl', ...o });
export const cpl = [
  // ───────── WEEK 1 · Oct 6–11 · Talking, not just updating ─────────
  C({ id: 'c1-updates', type: 'reel', week: 1, slot: 'r1', cta: 'share', title: 'Reel: You’re not talking, you’re updating',
    reel: [['S:“Did you pay the light bill?”', 'S:“Who’s picking up Jordan?”', 'S:“We’re out of milk.”'], ['B:That’s not talking. *That’s updating.*'], ['S:Roommates update.', 'B:Married people *talk.*'], ['L:Tonight, ask', 'B:“What was the best *ten minutes* of your day?”']],
    cap: `"Did you pay the light bill?" "Who's picking up Jordan?" "We're out of milk."

That's not talking. That's updating. Roommates update. Married people talk.

Tonight, ask one real question: "What was the best ten minutes of your day?" Then put the phone down and actually listen to the answer.`,
    th: `"Did you pay the light bill?" "Who's picking up the kids?" "We're out of milk."

That's not talking. That's updating. Roommates update. Married people talk.

Tonight ask: "What was the best ten minutes of your day?"` }),
  C({ id: 'c1-ten-minutes', type: 'post', week: 1, slot: 'p1', cta: 'save', title: 'Ten minutes, no screens',
    post: { label: 'Try it tonight', h: 'Ten minutes.\nNo screens.\n*Just us.*', body: 'After the kids are down. Same time every night. **The porch, the kitchen, the edge of the bed.**' },
    cap: `Ten minutes. No screens. Just us.

After the kids are down. Same time every night. The porch, the kitchen table, the edge of the bed.

It's not a date night. It's smaller than that, and that's why it works: you'll actually do it.`,
    th: `Ten minutes. No screens. Just us.

After the kids are down, same time every night. It's smaller than a date night, and that's why it works: you'll actually do it.` }),
  C({ id: 'c1-questions', type: 'carousel', week: 1, slot: 'c', cta: 'save', title: 'Carousel: 5 better questions than “How was your day?”',
    carousel: { label: 'Save for tonight', h: '5 better questions than *“How was your day?”*', body: '“Fine” is not an answer. **These are.**',
      slides: [['“What’s *weighing* on you right now?”', 'Then don’t fix it. **Just ask, “What else?”**'], ['“When did you feel most *like yourself* today?”', 'You’ll learn what fills them up.'], ['“What’s one thing I did this week that *helped?*”', 'Now you know what to do again.'], ['“What are you *looking forward* to?”', 'If the answer is “nothing,” that’s a conversation.'], ['“How can I *pray* for you tomorrow?”', 'Then actually do it. **And tell them you did.**']],
      end: { pre: 'Pick one. Ask it tonight.', h: 'Talk.\n*Don’t just update.*' } },
    cap: `5 better questions than "How was your day?":

1. "What's weighing on you right now?" (Don't fix it. Ask "What else?")
2. "When did you feel most like yourself today?"
3. "What's one thing I did this week that helped?"
4. "What are you looking forward to?"
5. "How can I pray for you tomorrow?" Then do it, and tell them you did.`,
    th: `5 better questions than "How was your day?":

What's weighing on you? When did you feel most like yourself? What did I do this week that helped? What are you looking forward to? How can I pray for you tomorrow?` }),
  C({ id: 'c1-listen', type: 'reel', week: 1, slot: 'r2', cta: 'couples', title: 'Reel: Listening to reply vs. listening to understand',
    reel: [['B:Most couples don’t have a *talking* problem.'], ['B:They have a *listening* problem.'], ['S:Listening to reply sounds like', 'T:“Yeah, but…”'], ['S:Listening to understand sounds like', 'B:“So what you’re saying is…”']],
    cap: `Most couples don't have a talking problem. They have a listening problem.

Listening to reply sounds like: "Yeah, but…"
Listening to understand sounds like: "So what you're saying is…"

Try the second one tonight. Say back what you heard before you say anything of your own. Watch how fast the temperature drops.`,
    th: `Most couples don't have a talking problem. They have a listening problem.

Listening to reply: "Yeah, but…"
Listening to understand: "So what you're saying is…"

Say back what you heard before you answer.` }),
  C({ id: 'c1-roommates', type: 'post', week: 1, slot: 'p2', cta: 'couples', title: 'Married, not roommates',
    post: { pre: 'Same house. Same bills. Same kids.', h: 'Still *married?*\nOr just *roommates?*', body: 'If you can’t remember your last real conversation, **that’s not failure. That’s a signal.**' },
    cap: `Same house. Same bills. Same kids. Still married, or just roommates?

If you can't remember your last real conversation, that's not failure. It's a signal, and signals are good news: you caught it.

Engaged or married, sometimes the best next step is a structured look at how the two of you communicate.`,
    th: `Same house. Same bills. Same kids. Still married, or just roommates?

If you can't remember your last real conversation, that's not failure. It's a signal. And you caught it.` }),

  // ───────── WEEK 2 · Oct 12–18 · Conflict ─────────
  C({ id: 'c2-problem', type: 'reel', week: 2, slot: 'r1', cta: 'share', title: 'Reel: It’s you two vs. the problem',
    reel: [['B:It’s not you *vs. me.*'], ['B:It’s *us* vs. the problem.'], ['S:Same side of the table.', 'S:Problem on the other side.'], ['L:Literally', 'B:Sit *next to each other* when you argue.']],
    cap: `It's not you vs. me. It's us vs. the problem.

Here's a strange one that works: when you need to have a hard conversation, sit next to each other, not across from each other. Same side of the table, the problem written on paper in front of you both.

Your body will remember you're on the same team even when your mouth forgets.`,
    th: `It's not you vs. me. It's us vs. the problem.

Try this: when you argue, sit next to each other, not across. Same side of the table. Your body remembers you're on the same team even when your mouth forgets.` }),
  C({ id: 'c2-always', type: 'post', week: 2, slot: 'p1', cta: 'share', title: 'Delete “always” and “never”',
    post: { label: 'Two words to retire', h: '“You *always*…”\n“You *never*…”', body: 'Nobody always or never does anything. **Say what happened, when, and how it felt.**' },
    cap: `Two words to retire from your arguments: "always" and "never."

"You always leave me to handle the kids."
"You never listen."

Nobody always or never does anything, so the other person will spend the whole fight proving the exception. Say what happened, when, and how it felt:

"Last night when I was doing bedtime alone, I felt invisible."`,
    th: `Retire two words from your arguments: "always" and "never."

Nobody always or never does anything, so your spouse spends the fight proving the exception.

Say what happened, when, and how it felt.` }),
  C({ id: 'c2-fight-fair', type: 'carousel', week: 2, slot: 'c', cta: 'couples', title: 'Carousel: 5 rules for fighting fair',
    carousel: { label: 'Agree on these before the next one', h: '5 rules for *fighting fair.*', body: 'Decide them **while you’re calm**, not in the middle of it.',
      slides: [['One topic *at a time.*', 'If it’s about the dishes, it’s about the dishes. **Not 2019.**'], ['No *names.* No *“always.”*', 'Talk about the action, never the person’s character.'], ['Either one can call a *timeout.*', '20 minutes. **And the one who calls it sets the time to come back.**'], ['Not in front of *the kids.*', 'Disagree in front of them sometimes. **Fight in private.**'], ['End with *“we.”*', '“What are we going to do differently?” **Then pray, even if it’s short.**']],
      end: { pre: 'Want a structured look at how you two handle conflict?', h: 'Certified marriage\n*counseling.*' } },
    cap: `5 rules for fighting fair. Agree on them while you're calm:

1. One topic at a time. Not 2019.
2. No names, no "always." Talk about the action, not the person.
3. Either of you can call a 20-minute timeout, and the one who calls it sets the time to come back.
4. Not in front of the kids.
5. End with "we": "What are we going to do differently?" Then pray, even if it's short.`,
    th: `5 rules for fighting fair:

One topic at a time. No names, no "always." Either of you can call a 20-minute timeout, and whoever calls it sets the time to come back. Not in front of the kids. End with "we," then pray.` }),
  C({ id: 'c2-timeout', type: 'reel', week: 2, slot: 'r2', cta: 'share', title: 'Reel: The 20-minute timeout',
    reel: [['S:When your heart rate is over 100,', 'B:you can’t *hear* each other.'], ['B:So stop.\n*Twenty minutes.*'], ['L:The rule', 'I:Either one can call it', 'I:No storming off. Say when you’ll be back.', 'I:Come back. Every time.'], ['B:A timeout is not *walking out.*']],
    cap: `When your heart is racing, you can't really hear each other. Nothing productive happens past that point.

So stop. Twenty minutes.

The rule: either one of you can call it. No storming off; say when you'll be back. And then come back, every time.

A timeout is not walking out. Walking out says "I'm leaving." A timeout says "I'm coming back calmer."`,
    th: `When your heart is racing, you can't hear each other. So stop. Twenty minutes.

Either one can call it. Say when you'll be back. Then come back, every time.

A timeout isn't walking out. It's coming back calmer.` }),
  C({ id: 'c2-sun', type: 'post', week: 2, slot: 'p2', cta: 'couples', title: 'Don’t let the sun go down on your anger',
    post: { label: 'Ephesians 4:26', h: 'Don’t let the sun go down *on your anger.*', sub: 'That doesn’t mean solve it by midnight.', body: 'It means **don’t go to sleep enemies.** “I love you. We’ll finish this tomorrow at 7.”' },
    cap: `"Do not let the sun go down while you are still angry." Ephesians 4:26

That doesn't mean you have to solve it by midnight. Some things take more than one night.

It means don't go to sleep enemies. "I love you. I'm still upset. Let's finish this tomorrow at 7." Then actually finish it at 7.`,
    th: `"Do not let the sun go down while you are still angry." Ephesians 4:26

That doesn't mean solve it by midnight. It means don't go to sleep enemies. "I love you. We'll finish this tomorrow at 7."` }),

  // ───────── WEEK 3 · Oct 19–25 · Decisions & money ─────────
  C({ id: 'c3-decide', type: 'reel', week: 3, slot: 'r1', cta: 'couples', title: 'Reel: Who decides?',
    reel: [['B:Who decides in *your* house?'], ['S:If the answer is', 'B:“whoever’s *louder*”…'], ['B:that’s not leadership. *That’s volume.*'], ['L:Decide how you’ll decide', 'I:Big money: both, always', 'I:Kids’ schedules: whoever’s driving', 'I:Tie: pray, wait 24 hours']],
    cap: `Who decides in your house?

If the honest answer is "whoever's louder" or "whoever cares more that day," that's not leadership. That's volume.

Decide how you'll decide, before the next decision:
→ Big money: both of you, always
→ Kids' schedules: whoever's driving
→ A tie: pray, and wait 24 hours`,
    th: `Who decides in your house? If the answer is "whoever's louder," that's not leadership. That's volume.

Decide how you'll decide before the next decision: big money together, always; ties wait 24 hours and get prayed over.` }),
  C({ id: 'c3-number', type: 'post', week: 3, slot: 'p1', cta: 'share', title: 'Pick your number',
    post: { label: 'One money rule', h: 'Pick a number.\nAnything over it, *we talk first.*', body: '$100. $250. $500. **The number matters less than having one.**' },
    cap: `One money rule that prevents a lot of fights: pick a number.

Anything over it, we talk before we buy. $100, $250, $500. The number matters less than having one, agreed on, out loud.

No more "you spent how much?" Just "hey, this is over our number. Can we talk?"`,
    th: `One money rule that prevents a lot of fights: pick a number. Anything over it, you talk before you buy.

$100, $250, $500. The number matters less than having one.` }),
  C({ id: 'c3-money-date', type: 'carousel', week: 3, slot: 'c', cta: 'save', title: 'Carousel: A 30-minute money date',
    carousel: { label: 'Once a month', h: 'The 30-minute *money date.*', body: 'Make it a date, not an audit. **Coffee, snacks, one laptop.**',
      slides: [['*Celebrate* first.', 'One money win from this month. **Start on the same team.**'], ['Look at *what came in.*', 'Just the numbers. No commentary yet.'], ['Look at *what went out.*', 'No blame. **“Huh, that’s more than I thought” is allowed.**'], ['Pick *one* thing to change.', 'One. Not a whole new budget.'], ['*Dream* for five minutes.', 'Where do you want to be in a year? **Money is a tool for that.**']],
      end: { pre: 'Money is one of the top things couples fight about.', h: 'Talk about it\n*on purpose.*' } },
    cap: `The 30-minute money date. Once a month, with coffee:

1. Celebrate one money win first.
2. Look at what came in. Just numbers.
3. Look at what went out. No blame.
4. Pick ONE thing to change. Not a whole new budget.
5. Dream for five minutes. Where do you want to be in a year?

Make it a date, not an audit.`,
    th: `The 30-minute money date, once a month:

Celebrate one win. Look at what came in. Look at what went out, no blame. Change one thing. Dream for five minutes about where you want to be in a year.

A date, not an audit.` }),
  C({ id: 'c3-mine', type: 'reel', week: 3, slot: 'r2', cta: 'share', title: 'Reel: “My money” vs “our money”',
    reel: [['S:“My money.”', 'S:“Your debt.”', 'S:“My account.”'], ['B:Listen to *your pronouns.*'], ['B:Two people, one life,\n*one plan.*'], ['S:It doesn’t have to be one account.', 'B:It has to be *one team.*']],
    cap: `"My money." "Your debt." "My account."

Listen to your pronouns. They tell you how married your money is.

It doesn't have to be one bank account. Plenty of healthy couples keep separate ones. But it has to be one team and one plan, with no secrets.`,
    th: `"My money." "Your debt." "My account."

Listen to your pronouns. It doesn't have to be one bank account. It has to be one team and one plan, with no secrets.` }),
  C({ id: 'c3-secrets', type: 'post', week: 3, slot: 'p2', cta: 'couples', title: 'No money secrets',
    post: { pre: 'The card she doesn’t know about.\nThe account he doesn’t mention.', h: 'Money secrets are *trust secrets.*', body: 'Tell it this week. **Before it’s found.**' },
    cap: `The card she doesn't know about. The account he doesn't mention. The "it was on sale" that wasn't.

Money secrets are trust secrets. And they almost always come out.

If there's something, tell it this week, calmly, before it's found. A confession hurts. A discovery breaks something.`,
    th: `The card she doesn't know about. The account he doesn't mention.

Money secrets are trust secrets. If there's something, tell it this week, before it's found. A confession hurts. A discovery breaks something.` }),

  // ───────── WEEK 4 · Oct 26 – Nov 1 · Engaged couples / premarital ─────────
  C({ id: 'c4-engaged', type: 'reel', week: 4, slot: 'r1', cta: 'couples', title: 'Reel: You planned the wedding. Plan the marriage.',
    reel: [['S:Engaged?'], ['S:You’ve planned the venue.', 'S:The colors.', 'S:The playlist.'], ['B:Who’s planning *the marriage?*'], ['B:The wedding is *one day.*', 'T:**The marriage is the rest of your life.**']],
    cap: `Engaged? You've planned the venue, the colors, the food and the playlist.

Who's planning the marriage?

The wedding is one day. The marriage is the next fifty years of Tuesdays. Spend at least as much time on that as on the seating chart.`,
    th: `Engaged? You've planned the venue, the colors and the playlist.

Who's planning the marriage? The wedding is one day. The marriage is the next fifty years of Tuesdays.` }),
  C({ id: 'c4-research', type: 'post', week: 4, slot: 'p1', cta: 'couples', title: 'Premarital counseling: what the research shows',
    post: { label: 'What the research shows', h: 'About *30% less likely* to divorce.', body: 'Couples who did premarital education had **higher satisfaction and less conflict.** Before the wedding is the cheapest time to learn how you fight.' },
    cap: `What the research shows: couples who did premarital education were about 30% less likely to divorce, with higher satisfaction and less conflict.

Before the wedding is the cheapest, easiest time to learn how the two of you communicate, handle conflict and make decisions.

I'm a pastor and certified marriage counselor. You each take a validated relationship assessment online, then we meet for three sessions built on your results.`,
    th: `Couples who did premarital education were about 30% less likely to divorce, with higher satisfaction and less conflict.

Before the wedding is the cheapest time to learn how the two of you fight.` }),
  C({ id: 'c4-before-yes', type: 'carousel', week: 4, slot: 'c', cta: 'couples', title: 'Carousel: 5 conversations before “I do”',
    carousel: { label: 'Engaged couples · save this', h: '5 conversations to have *before “I do.”*', body: 'Not to scare you. **So nothing surprises you.**',
      slides: [['*Money.*', 'Debts, credit scores, spending habits. **All of it, on paper.**'], ['*Kids.*', 'How many, when, and how you’ll raise them in the faith.'], ['*Family.*', 'Holidays, in-laws, and how much say they get. **Before Thanksgiving.**'], ['*Conflict.*', 'How did your parents fight? **You’ll copy it unless you choose not to.**'], ['*Faith.*', 'Church, prayer, tithing. **What does Christ at the center look like on a Tuesday?**']],
      end: { pre: 'Want help having them?', h: 'Premarital\n*counseling.*' } },
    cap: `5 conversations to have before "I do":

1. Money: debts, credit, habits. All of it, on paper.
2. Kids: how many, when, and how you'll raise them in the faith.
3. Family: holidays, in-laws, and how much say they get.
4. Conflict: how did your parents fight? You'll copy it unless you choose not to.
5. Faith: what does Christ at the center look like on a Tuesday?

Not to scare you. So nothing surprises you.`,
    th: `5 conversations to have before "I do": money (all of it, on paper), kids, family and holidays, how your parents fought, and what faith looks like on a Tuesday.

Not to scare you. So nothing surprises you.` }),
  C({ id: 'c4-already', type: 'reel', week: 4, slot: 'r2', cta: 'couples', title: 'Reel: Already married? It’s not too late',
    reel: [['S:Already married and', 'B:never had *premarital counseling?*'], ['B:It’s not *too late.*'], ['S:You don’t need a crisis', 'B:to get a *check-up.*'], ['B:Healthy couples get *coached* too.']],
    cap: `Already married and never had premarital counseling?

It's not too late. You don't need a crisis to get a check-up. Healthy couples get coached too, and they stay healthy partly because they do.

Engaged and married couples both take the same assessment. Your results show where you're strong, where you're stretched, and what to work on first.`,
    th: `Already married and never had premarital counseling? It's not too late.

You don't need a crisis to get a check-up. Healthy couples get coached too, and they stay healthy partly because they do.` }),
  C({ id: 'c4-assessment', type: 'post', week: 4, slot: 'p2', cta: 'couples', title: 'How counseling works',
    post: { label: 'Certified marriage counseling', h: 'How it *works.*', items: ['**You each take** a validated relationship assessment online, separately', '**Three sessions** together, built on your own results', '**You leave** knowing where you’re strong, where you’re stretched, and what to work on first'], body: '' },
    cap: `How certified marriage counseling with me works, for engaged and married couples:

→ You each take a validated relationship assessment online, separately, on your own time.
→ We meet for three sessions built on your own results.
→ You leave knowing where you're strong, where you're stretched, and what to work on first.

It includes the Couples Conversation Cards and the Christian Marriage Workbook to keep going at home.`,
    th: `How certified marriage counseling with me works: you each take a validated assessment online, then three sessions built on your results. You leave knowing where you're strong, where you're stretched, and what to work on first.` }),

  // ───────── WEEK 5 · Nov 2–8 · Time together / dating your spouse ─────────
  C({ id: 'c5-dating', type: 'reel', week: 5, slot: 'r1', cta: 'save', title: 'Reel: When did you stop dating?',
    reel: [['B:When did you stop *dating* each other?'], ['S:You didn’t decide to.', 'B:It just *drifted.*'], ['S:Drift is always', 'B:*downstream.*'], ['B:Put it back on *the calendar.*']],
    cap: `When did you stop dating each other?

Nobody decides to. It just drifts: a baby, a new job, a busy season that never ended.

And drift always goes downstream. Put it back on the calendar. Not someday. Pick the night this week.`,
    th: `When did you stop dating each other? Nobody decides to. It just drifts.

And drift always goes downstream. Put it back on the calendar. Pick the night this week.` }),
  C({ id: 'c5-cheap', type: 'post', week: 5, slot: 'p1', cta: 'save', title: 'Date night doesn’t need a budget',
    post: { label: 'No sitter? No budget?', h: 'Date night doesn’t need *a reservation.*', items: ['Kids down by 8, **candles at 8:15**', 'Drive-thru dessert and **a long drive**', 'Cook one new recipe **together**'], body: '' },
    cap: `Date night doesn't need a reservation or a sitter.

→ Kids down by 8, candles at 8:15, the good plates
→ Drive-thru dessert and a long drive with your playlist from back then
→ Cook one new recipe together, badly, laughing

What matters is that it's on purpose and it's just you two.`,
    th: `Date night doesn't need a reservation or a sitter.

Kids down by 8, candles at 8:15. Drive-thru dessert and a long drive with your old playlist. Cook one new recipe together, badly.

On purpose, just you two.` }),
  C({ id: 'c5-date-questions', type: 'carousel', week: 5, slot: 'c', cta: 'save', title: 'Carousel: 5 date-night questions',
    carousel: { label: 'Friday night', h: '5 date-night questions that *aren’t about the kids.*', body: 'One rule: **no logistics allowed.**',
      slides: [['“What did you think the first time *you saw me?*”', 'Let them tell the whole story.'], ['“What’s a dream you’ve *stopped* talking about?”', 'Don’t solve it. **Just ask more.**'], ['“What’s something *new* you want to try together?”', 'Then book it before the night ends.'], ['“When do you feel most *loved* by me?”', 'You’ll be surprised. **Write it down later.**'], ['“What should we *thank God* for this year, just us?”', 'End the night in a short prayer together.']],
      end: { pre: 'Save it. Use one per date night.', h: 'Talk like *you used to.*' } },
    cap: `5 date-night questions that aren't about the kids. One rule: no logistics.

1. "What did you think the first time you saw me?"
2. "What's a dream you've stopped talking about?"
3. "What's something new you want to try together?"
4. "When do you feel most loved by me?"
5. "What should we thank God for this year, just us?"

End the night in a short prayer together.`,
    th: `5 date-night questions that aren't about the kids:

What did you think when you first saw me? What dream have you stopped talking about? What should we try together? When do you feel most loved by me? What should we thank God for, just us?` }),
  C({ id: 'c5-phones', type: 'reel', week: 5, slot: 'r2', cta: 'share', title: 'Reel: The third person in your bed',
    reel: [['S:There’s a third person', 'B:in a lot of beds *tonight.*'], ['B:It glows.'], ['S:Phones charge', 'B:in *the kitchen.*'], ['B:The bedroom is for *the two of you.*']],
    cap: `There's a third person in a lot of marriage beds tonight. It glows.

Try this for one week: phones charge in the kitchen. Both of them. Buy a $10 alarm clock if you need one.

The bedroom is for the two of you. Watch what comes back when the scrolling leaves.`,
    th: `There's a third person in a lot of marriage beds tonight. It glows.

One week: both phones charge in the kitchen. The bedroom is for the two of you. Watch what comes back when the scrolling leaves.` }),
  C({ id: 'c5-friend', type: 'post', week: 5, slot: 'p2', cta: 'couples', title: 'Are you still friends?',
    post: { pre: 'Partners, parents, co-workers on the household.', h: 'But are you still *friends?*', body: 'Friends **laugh, play and waste time together.** When did you last waste time together on purpose?' },
    cap: `You're partners. You're parents. You're co-workers on the household.

But are you still friends?

Friends laugh, play and waste time together. When did the two of you last waste time together on purpose? Not productive. Not planned. Just fun.

Do something pointless together this week.`,
    th: `You're partners, parents, co-workers on the household. But are you still friends?

Friends laugh and waste time together. When did you two last waste time together on purpose?` }),

  // ───────── WEEK 6 · Nov 9–15 · Praying together ─────────
  C({ id: 'c6-pray', type: 'reel', week: 6, slot: 'r1', cta: 'share', title: 'Reel: Pray together for 2 minutes',
    reel: [['S:Most Christian couples', 'B:don’t *pray together.*'], ['S:Not because they don’t believe.', 'B:Because it feels *awkward.*'], ['L:Start here', 'I:Hold hands', 'I:One sentence each', 'I:“Amen.” Done.'], ['B:Two minutes. *Every night.*']],
    cap: `Most Christian couples don't pray together. Not because they don't believe, but because it feels awkward.

Start smaller than you think: hold hands, one sentence each, "Amen." Done.

Two minutes, every night, before you sleep. The awkward wears off in about a week. What it builds doesn't.`,
    th: `Most Christian couples don't pray together. Not because they don't believe, but because it's awkward.

Start small: hold hands, one sentence each, amen. Two minutes every night. The awkward wears off in a week.` }),
  C({ id: 'c6-cord', type: 'post', week: 6, slot: 'p1', cta: 'couples', title: 'A cord of three strands',
    post: { label: 'Ecclesiastes 4:12', h: 'A cord of three strands is *not quickly broken.*', body: 'Two of you holding on is strong. **Two of you holding on to Him is stronger.**' },
    cap: `"A cord of three strands is not quickly broken." Ecclesiastes 4:12

Two of you holding on to each other is strong. Two of you holding on to Him is stronger, especially in the seasons when you're struggling to hold on to each other.

What's one way you put Him in the middle of your marriage this week?`,
    th: `"A cord of three strands is not quickly broken." Ecclesiastes 4:12

Two of you holding on to each other is strong. Two of you holding on to Him is stronger, especially when holding on to each other is hard.` }),
  C({ id: 'c6-pray-guide', type: 'carousel', week: 6, slot: 'c', cta: 'save', title: 'Carousel: How to pray together when it feels awkward',
    carousel: { label: 'For couples who don’t know where to start', h: 'How to pray together when it *feels awkward.*', body: 'It’s supposed to at first. **Do it anyway.**',
      slides: [['Same *time*, same *place.*', 'Edge of the bed, lights off. **Make it a habit, not a decision.**'], ['Start with *thanks.*', 'One thing each from today. Easiest way in.'], ['Pray *for*, not *at.*', '“Lord, give her rest” not “Lord, help him listen.” **No sermons in prayer.**'], ['Keep a *list.*', 'Write down what you prayed for. **Check it in a month.**'], ['Let the *quiet one* lead sometimes.', 'Short is fine. **Faithful matters more than fancy.**']],
      end: { pre: 'Two minutes. Every night.', h: 'Pray *together.*' } },
    cap: `How to pray together when it feels awkward (it's supposed to at first):

1. Same time, same place. Make it a habit, not a decision.
2. Start with thanks, one thing each.
3. Pray FOR each other, not AT each other. No sermons in prayer.
4. Keep a list. Check it in a month.
5. Let the quiet one lead sometimes. Short is fine. Faithful matters more than fancy.`,
    th: `How to pray together when it feels awkward:

Same time, same place. Start with thanks. Pray FOR each other, not AT each other (no sermons in prayer). Keep a list. Let the quiet one lead. Short is fine.` }),
  C({ id: 'c6-at', type: 'reel', week: 6, slot: 'r2', cta: 'share', title: 'Reel: Don’t preach at your spouse in prayer',
    reel: [['S:“Lord, help my husband', 'S:to finally listen…”'], ['B:That’s not a prayer.\n*That’s a sermon.*'], ['S:Pray *for* them,', 'B:not *at* them.'], ['B:“Lord, give her *rest.*”']],
    cap: `"Lord, help my husband to finally listen…"

That's not a prayer. That's a sermon with your eyes closed.

Pray for them, not at them. "Lord, give her rest." "Lord, give him wisdom at work tomorrow." Your spouse should feel covered when you pray, not corrected.`,
    th: `"Lord, help my husband to finally listen…"

That's not a prayer. That's a sermon with your eyes closed.

Pray for them, not at them. Your spouse should feel covered when you pray, not corrected.` }),
  C({ id: 'c6-sunday', type: 'post', week: 6, slot: 'p2', cta: 'couples', title: 'Sitting together in church isn’t the same as praying together',
    post: { pre: 'Same pew every Sunday.', h: 'Sitting together *isn’t praying together.*', body: 'Church is where you worship with everyone. **The edge of your bed is where you pray with each other.**' },
    cap: `Same pew every Sunday. That's good. But sitting together isn't the same as praying together.

Church is where you worship with everyone. The edge of your bed on a Tuesday is where you pray with each other.

Both matter. Most couples only have the first one.`,
    th: `Same pew every Sunday. That's good. But sitting together isn't praying together.

Church is where you worship with everyone. The edge of your bed on a Tuesday is where you pray with each other.` }),

  // ───────── WEEK 7 · Nov 16–22 · Family, in-laws & the holidays ─────────
  C({ id: 'c7-leave', type: 'reel', week: 7, slot: 'r1', cta: 'couples', title: 'Reel: Leave and cleave — before Thanksgiving',
    reel: [['S:“A man shall leave his father and mother', 'S:and be united to his wife.”'], ['B:Leave doesn’t mean *love less.*'], ['B:It means your spouse is *first.*'], ['L:Before Thanksgiving', 'B:Decide the plan *together.* Then tell the family.']],
    cap: `"A man shall leave his father and mother and be united to his wife." Genesis 2:24

Leave doesn't mean love your parents less. It means your spouse comes first, and both families can tell.

Before Thanksgiving: decide the plan together, as a couple. Then tell the family, together. Don't let either family negotiate with just one of you.`,
    th: `"A man shall leave his father and mother and be united to his wife."

Leave doesn't mean love your parents less. It means your spouse is first. Before Thanksgiving: decide the plan together, then tell the family together.` }),
  C({ id: 'c7-team', type: 'post', week: 7, slot: 'p1', cta: 'share', title: 'Your mama, your call',
    post: { label: 'A rule that saves holidays', h: 'Your family, *you* handle it.\nMine, *I* handle it.', body: 'Hard conversations with parents go **through their own child.** Never through the in-law.' },
    cap: `A rule that saves a lot of holidays: your family, you handle it. My family, I handle it.

Hard conversations with parents go through their own child, never through the in-law. Same message, much less damage.

And whatever was said, you present it as "we decided," not "she wants…" or "he says…"`,
    th: `A rule that saves holidays: your family, you handle it. My family, I handle it.

Hard conversations with parents go through their own child, never through the in-law. And it's always "we decided."` }),
  C({ id: 'c7-holiday-plan', type: 'carousel', week: 7, slot: 'c', cta: 'save', title: 'Carousel: Your holiday game plan as a couple',
    carousel: { label: 'Before Thanksgiving', h: 'Your holiday game plan *as a couple.*', body: 'Make these decisions **at home, calm**, not in the car on the way there.',
      slides: [['*Where* and *how long.*', 'Agree on arrival and leave times before you go. **And actually leave.**'], ['The *signal.*', 'A word or a touch that means “I need you” or “let’s go.” **Honor it, no questions.**'], ['The *topics.*', 'Which conversations you won’t have at the table this year.'], ['The *kids.*', 'Who’s on duty when. **So nobody ends up resentful.**'], ['The *debrief.*', 'In the car home: one thing that went well. **Save the rest for tomorrow.**']],
      end: { pre: 'One team, two families.', h: 'Walk in *together.*' } },
    cap: `Your holiday game plan as a couple. Decide it at home, calm, not in the car on the way there:

1. Where, and how long. Agree on leave time, then actually leave.
2. The signal: a word or touch that means "I need you" or "let's go." Honor it.
3. The topics you won't take on at the table.
4. The kids: who's on duty when.
5. The debrief: one good thing in the car home. Save the rest for tomorrow.`,
    th: `Holiday game plan for couples, decided at home, not in the car:

How long you'll stay. A signal that means "I need you." Topics you won't take on. Who's on kid duty. One good thing on the drive home; save the rest for tomorrow.` }),
  C({ id: 'c7-side', type: 'reel', week: 7, slot: 'r2', cta: 'share', title: 'Reel: Never choose your mother over your wife in public',
    reel: [['S:If your mother criticizes your wife', 'B:in front of *everyone…*'], ['B:silence is *a side.*'], ['S:You don’t have to be rude.', 'B:You do have to be *clear.*'], ['B:“Mom, we’re good. *She’s with me.*”']],
    cap: `If your mother criticizes your wife in front of everyone and you say nothing, silence is a side.

You don't have to be rude. You don't have to make a scene. You do have to be clear.

"Mom, we're good. She's with me." Then talk to your mother privately, later. Your wife needs to know, in that moment, whose team you're on.`,
    th: `If your mother criticizes your wife in front of everyone and you say nothing, silence is a side.

You don't have to be rude. You do have to be clear: "Mom, we're good. She's with me."` }),
  C({ id: 'c7-boundary', type: 'post', week: 7, slot: 'p2', cta: 'couples', title: 'Boundaries aren’t disrespect',
    post: { pre: 'Honoring your parents', h: 'and obeying them *are not the same thing.*', body: 'You can **honor them and still decide** as a couple. That’s what a new family does.' },
    cap: `Honoring your parents and obeying your parents are not the same thing once you're married.

You can honor them, love them, visit them, and still make your own decisions as a couple. That isn't disrespect. That's what a new family does.

If in-law boundaries are a recurring fight, it's worth working on with someone outside both families.`,
    th: `Honoring your parents and obeying them are not the same thing once you're married.

You can honor them, love them, visit them, and still decide as a couple. That's not disrespect. That's what a new family does.` }),

  // ───────── WEEK 8 · Nov 23–29 · Gratitude (Thanksgiving) ─────────
  C({ id: 'c8-notice', type: 'reel', week: 8, slot: 'r1', cta: 'share', title: 'Reel: Notice it out loud',
    reel: [['S:You notice when they forget.', 'B:Do you notice when they *remember?*'], ['B:Say it *out loud.*'], ['S:“Thank you for”', 'B:is the cheapest *marriage repair* there is.'], ['L:This week', 'B:Three specific thank-yous. *Every day.*']],
    cap: `You notice when they forget to take the trash out. Do you notice, out loud, when they remember?

"Thank you for…" is the cheapest marriage repair there is.

Thanksgiving week challenge: three specific thank-yous to your spouse every day. Not "thanks for everything." Specific: "Thank you for getting up with the baby so I could sleep."`,
    th: `You notice when they forget. Do you notice, out loud, when they remember?

Thanksgiving week: three specific thank-yous to your spouse every day. "Thank you for getting up with the baby so I could sleep."` }),
  C({ id: 'c8-list', type: 'post', week: 8, slot: 'p1', cta: 'save', title: 'Ten things I’m thankful for about you',
    post: { label: 'Thanksgiving', h: '10 things I’m thankful for *about you.*', body: 'Write the list. **Hand it to them on Thursday.** Watch what happens.' },
    cap: `A Thanksgiving gift that costs nothing:

Write "10 things I'm thankful for about you" on a piece of paper. Specific, small, real. "The way you sing in the car." "How you talk to my mother." "That you never gave up on us in 2022."

Hand it to them on Thursday. Watch what happens.`,
    th: `A Thanksgiving gift that costs nothing: write "10 things I'm thankful for about you." Specific, small, real.

Hand it to your spouse on Thursday. Watch what happens.` }),
  C({ id: 'c8-gratitude', type: 'carousel', week: 8, slot: 'c', cta: 'couples', title: 'Carousel: Gratitude habits for married couples',
    carousel: { label: 'Black Friday edition', h: 'Gratitude habits that *outlast Thanksgiving.*', body: 'One day of thanks won’t carry a marriage. **A habit will.**',
      slides: [['The *pillow* thank-you.', 'Last thing before sleep: one thing they did today. **Every night.**'], ['The *public* praise.', 'Brag on your spouse in front of the kids. **They’re watching how you talk about each other.**'], ['The *text* at noon.', '“Thinking about how you handled this morning. Proud of you.”'], ['The *jar.*', 'Write thanks on scraps of paper all year. **Read them next Thanksgiving.**'], ['The *prayer.*', '“Thank you, Lord, for her.” **Out loud, where she can hear it.**']],
      end: { pre: 'Want help building habits that last?', h: 'Certified marriage\n*counseling.*' } },
    cap: `Gratitude habits that outlast Thanksgiving:

1. The pillow thank-you: one thing they did today, every night.
2. Public praise: brag on your spouse in front of the kids.
3. The text at noon: "Proud of how you handled this morning."
4. The jar: thanks on scraps of paper all year. Read them next Thanksgiving.
5. The prayer: "Thank you, Lord, for her," out loud, where she can hear it.`,
    th: `Gratitude habits that outlast Thanksgiving:

A thank-you on the pillow every night. Brag on your spouse in front of the kids. A noon text. A thanks jar you read next November. And thank God for them out loud, where they can hear.` }),
  C({ id: 'c8-season', type: 'reel', week: 8, slot: 'r2', cta: 'share', title: 'Reel: Thankful in a hard season',
    reel: [['S:Maybe this wasn’t', 'B:your best year *together.*'], ['S:Be thankful anyway.', 'B:Not for the *hard.*'], ['B:For the one who *stayed* in it with you.'], ['B:You’re *still here.* That counts.']],
    cap: `Maybe this wasn't your best year together. Job loss, a diagnosis, a season of distance, a lot of fights.

Be thankful anyway. Not for the hard parts. For the one who stayed in them with you.

You're still here. That counts.`,
    th: `Maybe this wasn't your best year together. Be thankful anyway.

Not for the hard parts. For the one who stayed in them with you. You're still here. That counts.` }),
  C({ id: 'c8-kids-watch', type: 'post', week: 8, slot: 'p2', cta: 'couples', title: 'Your kids are learning marriage from you',
    post: { pre: 'Your kids aren’t learning marriage from sermons.', h: 'They’re learning it *from your kitchen.*', body: 'How you talk, apologize and **make up** is the marriage they’ll copy.' },
    cap: `Your kids aren't learning marriage from sermons or movies. They're learning it from your kitchen.

How you talk to each other when you're tired. How you apologize. Whether they ever see you make up after a fight.

That's the marriage they'll copy. Give them a good one to copy.`,
    th: `Your kids aren't learning marriage from sermons. They're learning it from your kitchen.

How you talk when you're tired. How you apologize. Whether they see you make up. That's the marriage they'll copy.` }),

  // ───────── WEEK 9 · Nov 30 – Dec 6 · Money & holiday spending ─────────
  C({ id: 'c9-december', type: 'reel', week: 9, slot: 'r1', cta: 'share', title: 'Reel: Don’t start January in debt and in a fight',
    reel: [['S:A lot of couples', 'B:start January *in debt*'], ['B:and in *a fight.*'], ['L:Decide now', 'I:One Christmas number, together', 'I:Who you buy for', 'I:Cash or card, not both'], ['B:The best gift is *peace in February.*']],
    cap: `A lot of couples start January in debt, and in a fight about the debt.

Decide now, together:
→ One Christmas number for everything
→ Who you're buying for, and who you're not this year
→ Cash or card, not both

The best gift you can give each other is peace in February.`,
    th: `A lot of couples start January in debt, and in a fight about the debt.

Decide now: one Christmas number, together. Who you're buying for. Cash or card, not both. The best gift is peace in February.` }),
  C({ id: 'c9-number', type: 'post', week: 9, slot: 'p1', cta: 'save', title: 'One number for Christmas',
    post: { label: 'December money rule', h: 'One number.\n*Decided together.*\nNo surprises.', body: 'Gifts, food, travel, the extra stuff. **Write it on the fridge.**' },
    cap: `December money rule: one number. Decided together. No surprises.

Gifts, food, travel, the teacher gifts, the extra "while we're out" stuff. All of it under one number, written on the fridge where both of you can see it.

Surprise gifts are fun. Surprise credit card bills are not.`,
    th: `December money rule: one number, decided together, written on the fridge.

Surprise gifts are fun. Surprise credit card bills are not.` }),
  C({ id: 'c9-spending', type: 'carousel', week: 9, slot: 'c', cta: 'couples', title: 'Carousel: When you spend differently',
    carousel: { label: 'Spender + saver?', h: 'When one of you is a spender and one is *a saver.*', body: 'You probably married your opposite. **That’s a strength, if you use it.**',
      slides: [['Name your *money story.*', 'What did money mean in the house you grew up in? **Tell each other.**'], ['The saver *protects.*', 'Thank them for it. **They’re the reason you sleep at night.**'], ['The spender *enjoys.*', 'Thank them too. **They’re the reason you have memories.**'], ['Give each a *“no questions”* amount.', 'Small, monthly, personal. **Freedom reduces fights.**'], ['Plan *together*, not *against.*', 'One plan, both voices. **Then pray over it.**']],
      end: { pre: 'Money fights are rarely about money.', h: 'Talk to *someone.*' } },
    cap: `When one of you is a spender and one is a saver (most couples):

1. Tell each other your money story. What did money mean growing up?
2. Thank the saver. They're why you sleep at night.
3. Thank the spender. They're why you have memories.
4. Give each person a small monthly "no questions" amount.
5. Plan together, not against each other. Then pray over it.

Money fights are rarely about money.`,
    th: `Spender married to a saver? Most couples are.

Share your money stories. Thank the saver (that's why you sleep). Thank the spender (that's why you have memories). Give each a small "no questions" amount. Plan together, not against.` }),
  C({ id: 'c9-gift', type: 'reel', week: 9, slot: 'r2', cta: 'save', title: 'Reel: The gift they actually want',
    reel: [['S:She doesn’t want', 'B:another *candle.*'], ['S:He doesn’t want', 'B:another *gadget.*'], ['B:They want to feel *known.*'], ['L:Give', 'B:a *planned* day. Your phone off. *Their* pick.']],
    cap: `She doesn't want another candle. He doesn't want another gadget.

Most spouses want to feel known. Give a planned day: sitter booked, your phone off, everything their pick. Write it on a card and put it under the tree.

Cheaper than most gifts. Remembered longer than all of them.`,
    th: `She doesn't want another candle. He doesn't want another gadget.

They want to feel known. Give a planned day: sitter booked, phone off, everything their pick. Cheaper than most gifts, remembered longer.` }),
  C({ id: 'c9-generous', type: 'post', week: 9, slot: 'p2', cta: 'couples', title: 'Give together',
    post: { label: 'This December', h: 'Pick one family to *bless together.*', body: 'Decide it as a couple. Do it as a family. **Generosity is a marriage glue nobody talks about.**' },
    cap: `This December: pick one family to bless together.

A single mom at church. A neighbor who lost a job. Decide it as a couple, do it as a family, and let the kids help.

Generosity is a marriage glue nobody talks about. It's hard to stay petty with each other when you're giving side by side.`,
    th: `This December, pick one family to bless together. Decide it as a couple, do it as a family, let the kids help.

It's hard to stay petty with each other when you're giving side by side.` }),

  // ───────── WEEK 10 · Dec 7–13 · Affection & kindness ─────────
  C({ id: 'c10-kiss', type: 'reel', week: 10, slot: 'r1', cta: 'share', title: 'Reel: The six-second kiss',
    reel: [['B:When did you last kiss for longer than *a peck?*'], ['S:The goodbye peck', 'S:is a habit.'], ['B:Six seconds is *a choice.*'], ['L:Every day this week', 'B:Leaving and coming home. *Six seconds.*']],
    cap: `When did you last kiss for longer than a peck?

The goodbye peck is a habit. Six seconds is a choice. Long enough to actually stop, and short enough to do every day.

This week: leaving and coming home, six seconds. Count if you have to. Laugh about counting. That's part of it.`,
    th: `When did you last kiss for longer than a peck?

The goodbye peck is a habit. Six seconds is a choice. This week, leaving and coming home: six seconds. Count if you have to.` }),
  C({ id: 'c10-kind', type: 'post', week: 10, slot: 'p1', cta: 'share', title: 'Be as kind at home as you are at work',
    post: { pre: 'Patient with customers.\nGentle with co-workers.', h: 'Be at least that kind *at home.*', body: 'Your spouse shouldn’t get **the leftovers of your patience.**' },
    cap: `Patient with customers. Gentle with co-workers. Polite to the cashier.

Be at least that kind at home.

Your spouse shouldn't get the leftovers of your patience. They should get the best of it. That might mean resting before you walk in, or praying in the car, or just deciding to.`,
    th: `Patient with customers. Gentle with co-workers. Polite to the cashier.

Be at least that kind at home. Your spouse shouldn't get the leftovers of your patience.` }),
  C({ id: 'c10-love-ways', type: 'carousel', week: 10, slot: 'c', cta: 'save', title: 'Carousel: 5 ways to say “I love you” without saying it',
    carousel: { label: 'Small, daily, on purpose', h: '5 ways to say “I love you” *without saying it.*', body: 'Big gestures are rare. **Small ones are the marriage.**',
      slides: [['Do the thing they *hate.*', 'The dishes. The call to the insurance company. **Without being asked.**'], ['Touch on the way *past.*', 'A hand on the shoulder in the kitchen. **Every time.**'], ['Remember the *small* stuff.', 'The doctor’s appointment. The hard meeting. **Ask how it went.**'], ['Protect their *rest.*', '“I’ve got the kids. Go lie down.”'], ['Speak well of them *when they’re not there.*', 'To your friends, your family, your kids. **It always gets back.**']],
      end: { pre: 'Pick one. Do it today.', h: 'Love on purpose.\n*Not by accident.*' } },
    cap: `5 ways to say "I love you" without saying it:

1. Do the thing they hate doing, without being asked.
2. Touch on the way past. A hand on the shoulder in the kitchen.
3. Remember the small stuff. Ask how the appointment went.
4. Protect their rest. "I've got the kids. Go lie down."
5. Speak well of them when they're not there. It always gets back.`,
    th: `5 ways to say "I love you" without saying it:

Do the thing they hate, unasked. Touch on the way past. Ask how the appointment went. Protect their rest. Speak well of them when they're not there. It always gets back.` }),
  C({ id: 'c10-tone', type: 'reel', week: 10, slot: 'r2', cta: 'couples', title: 'Reel: It’s not what you said, it’s how',
    reel: [['S:“I didn’t say anything wrong!”'], ['B:It wasn’t *what* you said.'], ['B:It was *how.*'], ['S:Same words.', 'S:Softer voice.', 'B:Different *marriage.*']],
    cap: `"I didn't say anything wrong!"

It wasn't what you said. It was how. The sigh before it. The eye roll during it. The tone that said "you again."

Same words, softer voice, different marriage. Try saying the next hard thing like you're talking to someone you love. Because you are.`,
    th: `"I didn't say anything wrong!"

It wasn't what you said. It was how: the sigh, the eye roll, the tone that said "you again."

Same words, softer voice, different marriage.` }),
  C({ id: 'c10-repair', type: 'post', week: 10, slot: 'p2', cta: 'couples', title: 'A real apology has three parts',
    post: { label: 'A real apology', h: 'Three parts.\n*No “but.”*', items: ['**“I was wrong when I…”** (name it)', '**“I can see it made you feel…”**', '**“Next time, I’ll…”**'], body: '' },
    cap: `A real apology has three parts and no "but":

1. "I was wrong when I…" (name the specific thing)
2. "I can see it made you feel…"
3. "Next time, I'll…"

"I'm sorry you feel that way" is not an apology. Neither is anything with "but" in the middle.`,
    th: `A real apology has three parts and no "but":

"I was wrong when I…" (name it)
"I can see it made you feel…"
"Next time, I'll…"

"I'm sorry you feel that way" isn't one.` }),

  // ───────── WEEK 11 · Dec 14–20 · Christmas: the kids are watching ─────────
  C({ id: 'c11-peace', type: 'reel', week: 11, slot: 'r1', cta: 'share', title: 'Reel: The house they’ll remember',
    reel: [['S:Your kids won’t remember', 'B:what was *under the tree.*'], ['S:They’ll remember', 'B:what it *felt like* in the house.'], ['B:Was it *peace?*', 'B:Or was it *tension?*'], ['B:Give them *peace.*']],
    cap: `Your kids won't remember what was under the tree this year.

They'll remember what it felt like in the house. Whether Christmas morning was peace or tension. Whether Mom and Dad were a team or keeping score.

Give them peace. It's the gift they'll still have at forty.`,
    th: `Your kids won't remember what was under the tree. They'll remember what it felt like in the house.

Peace or tension. A team or keeping score. Give them peace.` }),
  C({ id: 'c11-tired', type: 'post', week: 11, slot: 'p1', cta: 'share', title: 'December tired is real',
    post: { pre: 'If you’re snapping at each other this week:', h: 'You’re not falling apart.\n*You’re tired.*', body: 'Go to bed **an hour earlier.** Both of you. Tonight.' },
    cap: `If you've been snapping at each other this week: you're probably not falling apart. You're tired.

December tired is real. Late nights, extra events, extra spending, extra family.

Go to bed an hour earlier tonight, both of you. Have the hard conversation after you've slept. Most of it will be smaller in the morning.`,
    th: `If you've been snapping at each other this week, you're probably not falling apart. You're tired.

Go to bed an hour earlier tonight. Both of you. Most of it will be smaller in the morning.` }),
  C({ id: 'c11-traditions', type: 'carousel', week: 11, slot: 'c', cta: 'save', title: 'Carousel: 5 Christmas traditions for couples',
    carousel: { label: 'Start one this year', h: '5 Christmas traditions *just for the two of you.*', body: 'The kids get a lot of traditions. **Your marriage needs some too.**',
      slides: [['The *letter.*', 'Write each other a letter about this year. **Read them on Christmas Eve after the kids are down.**'], ['The *drive.*', 'Hot chocolate and a slow drive through the lights. **Just you two.**'], ['The *ornament.*', 'One ornament a year that marks your year together.'], ['The *prayer walk.*', 'Christmas night, a short walk and **a prayer for next year.**'], ['The *photo.*', 'Same spot, same pose, every year. **Watch yourselves grow old together.**']],
      end: { pre: 'Pick one. Start it this year.', h: 'Make it *yours.*' } },
    cap: `5 Christmas traditions just for the two of you:

1. The letter: write each other a letter about this year. Read them Christmas Eve.
2. The drive: hot chocolate and a slow drive through the lights.
3. The ornament: one each year that marks your year together.
4. The prayer walk: Christmas night, a short walk and a prayer for next year.
5. The photo: same spot, same pose, every year.

The kids get traditions. Your marriage needs some too.`,
    th: `5 Christmas traditions just for the two of you:

A letter about this year, read Christmas Eve. A slow drive through the lights. One ornament a year. A Christmas-night prayer walk. Same photo, same spot, every year.` }),
  C({ id: 'c11-hope', type: 'reel', week: 11, slot: 'r2', cta: 'couples', title: 'Reel: If Christmas is hard this year',
    reel: [['S:If Christmas is hard', 'B:in your marriage *this year…*'], ['S:Remember the first one:', 'B:a tired couple, a *hard* road,'], ['B:and *God* showed up anyway.'], ['B:He still does. *Ask for help.*']],
    cap: `If Christmas is hard in your marriage this year, remember the first one.

A tired young couple. A hard road. No room anywhere. A situation nobody would have picked.

And God showed up right in the middle of it. He still does.

Asking for help isn't giving up. It's the first step back toward each other.`,
    th: `If Christmas is hard in your marriage this year, remember the first one: a tired couple, a hard road, no room anywhere.

And God showed up right in the middle of it. He still does. Asking for help isn't giving up.` }),
  C({ id: 'c11-emmanuel', type: 'post', week: 11, slot: 'p2', cta: 'share', title: 'Emmanuel: God with us',
    post: { label: 'Emmanuel', h: 'God *with* us.', sub: 'Not above us. Not away from us. With us.', body: 'Be **with** each other this week. Not near. **With.**' },
    cap: `Emmanuel: God with us. Not above us. Not away from us. With us.

That's the whole Christmas story, and it's a pretty good picture of marriage too.

Be with each other this week. Not just in the same room. With.

Merry Christmas from our family to yours.`,
    th: `Emmanuel: God with us. Not above us, not away from us. With us.

Be with each other this week. Not just in the same room. With. Merry Christmas.` }),

  // ───────── WEEK 12 · Dec 21–27 · New Year as a couple ─────────
  C({ id: 'c12-review', type: 'reel', week: 12, slot: 'r1', cta: 'save', title: 'Reel: Look back together before you look ahead',
    reel: [['S:Before you make', 'B:resolutions *for next year…*'], ['B:look back at this one *together.*'], ['L:Ask each other', 'I:What was our best moment?', 'I:When did we feel far apart?', 'I:What do we want more of?'], ['B:Then plan *2027* as a team.']],
    cap: `Before you make resolutions for next year, look back at this one together.

Ask each other:
→ What was our best moment this year?
→ When did we feel far apart?
→ What do we want more of next year?

Listen more than you talk. Then plan 2027 as a team.`,
    th: `Before resolutions, look back together:

What was our best moment this year? When did we feel far apart? What do we want more of next year?

Then plan 2027 as a team.` }),
  C({ id: 'c12-one-goal', type: 'post', week: 12, slot: 'p1', cta: 'couples', title: 'One marriage goal for 2027',
    post: { label: 'One goal for 2027', h: 'Not ten.\n*One marriage goal.*\nWith a day and a time.', body: '“Date night **every other Friday at 7.**” Not “spend more time together.”' },
    cap: `Not ten resolutions. One marriage goal for 2027, with a day and a time.

"Date night every other Friday at 7" beats "spend more time together."
"Pray together at 9:45 every night" beats "be more spiritual."

Pick it together. Put it on both calendars before January 1st.`,
    th: `Not ten resolutions. One marriage goal for 2027, with a day and a time.

"Date night every other Friday at 7" beats "spend more time together." Put it on both calendars before the 1st.` }),
  C({ id: 'c12-christmas', type: 'carousel', week: 12, slot: 'c', cta: 'share', title: 'Carousel: Christmas Day — 5 blessings to say out loud',
    carousel: { label: 'Merry Christmas', h: 'Five blessings to *speak over your marriage* today.', body: 'Read them together. **Out loud.**',
      slides: [['*Peace* in our home.', '“The Lord bless you and keep you.” **Numbers 6:24**'], ['*Patience* with each other.', '“Love is patient, love is kind.” **1 Corinthians 13:4**'], ['*Unity* in our decisions.', '“Two are better than one.” **Ecclesiastes 4:9**'], ['*Joy* that doesn’t depend on the year.', '“The joy of the Lord is your strength.” **Nehemiah 8:10**'], ['*Christ* at the center.', '“Unless the Lord builds the house…” **Psalm 127:1**']],
      end: { pre: 'Merry Christmas from our family to yours.', h: 'God *with* us.' } },
    cap: `Merry Christmas. Five blessings to speak over your marriage today, out loud, together:

1. Peace in our home. (Numbers 6:24)
2. Patience with each other. (1 Corinthians 13:4)
3. Unity in our decisions. (Ecclesiastes 4:9)
4. Joy that doesn't depend on the year. (Nehemiah 8:10)
5. Christ at the center. (Psalm 127:1)

From our family to yours.`,
    th: `Merry Christmas. Five blessings to speak over your marriage today:

Peace in our home. Patience with each other. Unity in our decisions. Joy that doesn't depend on the year. Christ at the center.` }),
  C({ id: 'c12-start', type: 'reel', week: 12, slot: 'r2', cta: 'couples', title: 'Reel: Start the new year with a check-up',
    reel: [['S:You get a physical.', 'S:You get the car checked.'], ['B:When did your marriage get *a check-up?*'], ['S:Not because it’s broken.', 'B:Because it *matters.*'], ['B:Start 2027 *knowing* where you stand.']],
    cap: `You get a physical. You get the car checked before a road trip.

When did your marriage get a check-up?

Not because it's broken. Because it matters more than the car. Start 2027 knowing where you're strong, where you're stretched, and what to work on first.

Engaged or married: a validated assessment, then three sessions built on your results.`,
    th: `You get a physical. You get the car checked. When did your marriage get a check-up?

Not because it's broken. Because it matters. Start 2027 knowing where you stand.` }),
  C({ id: 'c12-again', type: 'post', week: 12, slot: 'p2', cta: 'share', title: 'Choose each other again',
    post: { h: 'Choose each other *again.*', sub: 'You did it once at the altar.', body: 'Do it again **this year, on purpose, every ordinary Tuesday.**' },
    cap: `Choose each other again.

You did it once at the altar, in front of everybody. Do it again this year, on purpose, on every ordinary Tuesday when nobody's watching.

Happy New Year from our family to yours.`,
    th: `Choose each other again.

You did it once at the altar, in front of everybody. Do it again this year, on every ordinary Tuesday when nobody's watching. Happy New Year.` }),
];
