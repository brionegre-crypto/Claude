// 30-day boost: 3 extra posts per day, Oct 9 – Nov 7, 2026.
// 8am = short hook Reel (views) · 2pm = carousel or quote post (saves/shares)
// 9pm = comment-keyword or question post (CTA + comments).
// Times never collide with the main calendar (9am / 12pm / 4pm / 7pm).
const R = (date, theme, id, cta, title, reel, cap, th, extra = {}) => ({ id: 'b-' + id, theme, type: 'reel', date, time: '8am', cta, title: 'Reel: ' + title, reel, cap, th, ...extra });
const P = (date, time, theme, id, cta, title, post, cap, th) => ({ id: 'b-' + id, theme, type: 'post', date, time, cta, title, post, cap, th });
const K = (date, theme, id, cta, title, carousel, cap, th) => ({ id: 'b-' + id, theme, type: 'carousel', date, time: '2pm', cta, title: 'Carousel: ' + title, carousel, cap, th });
const B = 'btm', C = 'cpl';

export const boost = [
  // ───── Fri Oct 9 ─────
  R('2026-10-09', B, 'stop-scrolling', 'challenge', 'Stop scrolling. This is for the man who…',
    [['B:Stop scrolling.', 'S:This is for the man who'], ['B:keeps making *the same promise.*'], ['B:It’s not willpower.\nIt’s *a missing step.*']],
    `Stop scrolling. This is for the man who keeps making the same promise.

It's not a willpower problem. It's a missing first step. Nobody taught us to decide who we're becoming before we decide what we're doing.

Seven weeks, free, starting Oct 20. Bring a brother.`,
    `This is for the man who keeps making the same promise. It's not willpower. It's a missing first step.`),
  K('2026-10-09', C, 'signs-drifting', 'couples', '5 signs you’re drifting (not fighting)',
    { label: 'Save this', h: '5 signs you’re *drifting*, not fighting.', body: 'Drift is quiet. **That’s why it’s dangerous.**',
      slides: [['You only talk *logistics.*', 'Schedules, bills, kids. **Nothing about you two.**'], ['Phones at *dinner.*', 'Both of you. Every night.'], ['You stopped *asking.*', '“How are you, really?” hasn’t come up in weeks.'], ['Touch is *rare.*', 'Not just intimacy. **Hand holding. A hug in the kitchen.**'], ['Fights feel *pointless.*', 'Nobody expects anything to change, so why bother?']],
      end: { pre: 'Caught it early? Good. That’s the best time.', h: 'Don’t drift.\n*Steer.*' } },
    `5 signs you're drifting, not fighting:

1. You only talk logistics.
2. Phones at dinner, every night.
3. You stopped asking "How are you, really?"
4. Touch is rare. Not just intimacy, everyday touch.
5. Fights feel pointless.

Drift is quiet, and that's why it's dangerous. If you counted 3 or more, it's time to steer.`,
    `5 signs you're drifting, not fighting: only logistics, phones at dinner, no real questions, rare touch, fights that feel pointless. Drift is quiet. That's why it's dangerous.`),
  P('2026-10-09', '9pm', B, 'rate-week', 'comment', 'Rate your week 1–10',
    { label: 'Be honest', h: 'Rate your week.\n*1 to 10.*', body: 'Not how busy it was. **How close you lived to the man you said you’d be.** Drop the number below.', btn: 'Answer below ↓' },
    `Rate your week, 1 to 10.

Not how busy it was. How close you lived to the man you said you'd be.

Drop your number below. No explanation needed. I'll reply to every one.`,
    `Rate your week, 1 to 10. Not how busy it was. How close you lived to the man you said you'd be.`),

  // ───── Sat Oct 10 ─────
  R('2026-10-10', C, 'couples-who-last', 'share', 'Couples who last do this',
    [['S:Couples who last', 'B:don’t fight *less.*'], ['B:They *repair faster.*'], ['S:“I was wrong.”', 'S:“Can we start over?”', 'B:Say it *sooner.*']],
    `Couples who last don't fight less. They repair faster.

"I was wrong." "Can we start over?" "I love you, even right now."

The length of the cold war matters more than the fight. Shorten it.`,
    `Couples who last don't fight less. They repair faster. The length of the cold war matters more than the fight.`),
  P('2026-10-10', '2pm', B, 'quote-promise', 'step1', 'Quote: a promise with no time',
    { h: 'A promise with no time attached is *a feeling.*', sub: 'Give it a day. Give it a time. Then it’s a plan.' },
    `A promise with no time attached is a feeling.

Give it a day. Give it a time. Then it's a plan.

What's the promise you keep making? Give it a time tonight.`,
    `A promise with no time attached is a feeling. Give it a day and a time. Then it's a plan.`),
  P('2026-10-10', '9pm', C, 'one-word', 'comment', 'Describe your marriage in one word',
    { label: 'One word', h: 'Describe your marriage *in one word.*', body: 'Then ask your spouse to do the same. **Compare.** (Brave couples only.)', btn: 'Answer below ↓' },
    `Describe your marriage in one word. Drop it below.

Then ask your spouse to do the same, without showing them yours. Compare.

Brave couples only. 😅`,
    `Describe your marriage in one word. Then ask your spouse for theirs, without showing yours. Compare.`),

  // ───── Sun Oct 11 ─────
  R('2026-10-11', B, 'sunday-15', 'challenge', 'The 15 minutes that run your week',
    [['B:15 minutes on *Sunday*', 'S:decides your Wednesday.'], ['L:Ask', 'I:What did I say I’d do?', 'I:What actually happened?', 'I:What’s the one thing this week?'], ['B:Plan the week, or *the week plans you.*']],
    `15 minutes on Sunday decides your Wednesday.

Ask: What did I say I'd do? What actually happened? What's the ONE thing this week?

Plan the week, or the week plans you.`,
    `15 minutes on Sunday decides your Wednesday. What did I say I'd do? What happened? What's the one thing this week?`),
  K('2026-10-11', C, 'sunday-sync', 'save', 'The Sunday night couple check-in',
    { label: 'Every Sunday · 20 minutes', h: 'The Sunday night *couple check-in.*', body: 'Five questions. **Same time every week.**',
      slides: [['What went *well* for us?', 'Start on the same team.'], ['What was *hard?*', 'No blame. Just name it.'], ['What’s on the *calendar?*', 'No surprises by Wednesday.'], ['What do you *need* from me?', 'One thing. Specific.'], ['How can I *pray* for you?', 'Then pray together, right there.']],
      end: { pre: 'Twenty minutes a week.', h: 'Stay on *the same page.*' } },
    `The Sunday night couple check-in. 20 minutes, 5 questions:

1. What went well for us?
2. What was hard?
3. What's on the calendar this week?
4. What do you need from me?
5. How can I pray for you?

Then pray together, right there. Save this for tonight.`,
    `The Sunday couple check-in: what went well, what was hard, what's on the calendar, what do you need from me, how can I pray for you. 20 minutes a week.`),
  P('2026-10-11', '9pm', B, 'kw-step1-a', 'step1', 'Comment STEP1: one question',
    { label: 'Free · 20 minutes', h: 'One question that changes *every goal after it.*', body: '**What type of man do you want to be?** The worksheet walks you through it.', btn: 'Comment “STEP1” →' },
    `One question that changes every goal after it: what type of man do you want to be?

Not what you want to have. Not what you want to do. Who you want to be on an ordinary Tuesday.

The Step 1 worksheet walks you through it in 20 minutes.`,
    `One question that changes every goal after it: what type of man do you want to be? Not what you want to have. Who you want to be on a Tuesday.`),

  // ───── Mon Oct 12 ─────
  R('2026-10-12', C, 'she-said-fine', 'share', 'When she says “I’m fine”',
    [['S:When she says', 'B:“I’m *fine.*”'], ['B:Don’t *believe it.*', 'B:Don’t *fight it.*'], ['B:Sit down and say:\n*“I’ve got time.”*']],
    `When she says "I'm fine," don't believe it, and don't fight it.

Sit down. Put the phone face down. Say, "I've got time."

Then wait. Most of the time, she'll tell you. She just needed to know you'd stay for the answer.`,
    `When she says "I'm fine": don't believe it, don't fight it. Sit down, phone face down, and say "I've got time." Then wait.`),
  P('2026-10-12', '2pm', B, 'monday-truth', 'challenge', 'Monday doesn’t need motivation',
    { pre: 'Monday doesn’t need more motivation.', h: 'It needs *one decision* with a time on it.' },
    `Monday doesn't need more motivation. It needs one decision with a time on it.

What's yours this week? Write it in the comments: the decision, the day and the time.`,
    `Monday doesn't need more motivation. It needs one decision with a time on it. What's yours this week?`),
  P('2026-10-12', '9pm', B, 'a-or-b', 'comment', 'A or B: which man are you?',
    { label: 'Be honest', h: '*A:* I need motivation.\n*B:* I need a plan.', body: 'Which one are you **right now?** Comment A or B.', btn: 'Comment A or B ↓' },
    `Be honest. Which one are you right now?

A: I need motivation.
B: I need a plan.

Comment A or B. (If you said A, I'd bet money it's actually B.)`,
    `Which one are you right now? A: I need motivation. B: I need a plan. (If you said A, it's probably B.)`),

  // ───── Tue Oct 13 ─────
  R('2026-10-13', B, 'one-week', 'challenge', 'One week from today',
    [['L:One week from today', 'B:you’ll be *exactly* who you are now'], ['S:unless you decide', 'B:*one thing* tonight.'], ['B:Free 7-week challenge.\n*Starts Oct 20.*']],
    `One week from today, you'll be exactly who you are now, unless you decide one thing tonight.

The free 7-week challenge starts Oct 20. One email a week, one action with a time on it. Small enough to actually do.`,
    `One week from today you'll be exactly who you are now, unless you decide one thing tonight. Free 7-week challenge starts Oct 20.`),
  K('2026-10-13', C, 'love-languages-small', 'save', '5 tiny things that say “I see you”',
    { label: 'Under 2 minutes each', h: '5 tiny things that say *“I see you.”*', body: 'Big gestures are rare. **These are daily.**',
      slides: [['Warm up *the car.*', 'Or start the coffee. Do it before they wake up.'], ['Send the *noon text.*', '“Thinking about you. Proud of you.”'], ['Take *one thing* off their list.', 'Without asking which one.'], ['Notice the *small change.*', 'The haircut. The new routine. **Say it out loud.**'], ['Ask a *follow-up.*', '“How did that meeting go?” **They’ll know you listened.**']],
      end: { pre: 'Pick one for tomorrow.', h: 'Small, daily,\n*on purpose.*' } },
    `5 tiny things that say "I see you," under 2 minutes each:

1. Warm up the car or start the coffee.
2. Send a noon text: "Thinking about you."
3. Take one thing off their list without asking.
4. Notice the small change, out loud.
5. Ask a follow-up: "How did that meeting go?"

Pick one for tomorrow.`,
    `5 tiny things that say "I see you": warm up the car, the noon text, take something off their list, notice the small change, ask the follow-up.`),
  P('2026-10-13', '9pm', C, 'kw-couples-a', 'couples', 'Comment COUPLES: where are you strong?',
    { label: 'Engaged or married?', h: 'Do you know where your marriage is *strong*, and where it’s *stretched?*', body: 'A validated assessment shows you both. **Then three sessions built on your results.**', btn: 'Comment “COUPLES” →' },
    `Do you actually know where your marriage is strong, and where it's stretched?

Most couples guess. A validated relationship assessment shows you. Then we meet for three sessions built on your own results.

For engaged and married couples.`,
    `Do you know where your marriage is strong and where it's stretched? Most couples guess. A validated assessment shows you.`),

  // ───── Wed Oct 14 ─────
  R('2026-10-14', C, 'apology', 'share', 'The apology that actually works',
    [['B:“I’m sorry *you feel* that way.”', 'S:isn’t an apology.'], ['L:Try', 'I:“I was wrong when I…”', 'I:“I can see it hurt you.”', 'I:“Next time I’ll…”'], ['B:No *“but.”*']],
    `"I'm sorry you feel that way" isn't an apology.

Try: "I was wrong when I… I can see it hurt you. Next time I'll…"

No "but." The moment you add "but," you've started a defense.`,
    `"I'm sorry you feel that way" isn't an apology. Try: "I was wrong when I… I can see it hurt you. Next time I'll…" No "but."`),
  P('2026-10-14', '2pm', B, 'midweek', 'challenge', 'It’s Wednesday. Is it still standing?',
    { label: 'Wednesday check', h: 'It’s Wednesday.\nIs Monday’s promise *still standing?*', body: 'If not, **don’t quit. Change the time.**' },
    `It's Wednesday. Is Monday's promise still standing?

If not, don't quit the week. Change the time. The promise was fine. 6 AM wasn't.`,
    `It's Wednesday. Is Monday's promise still standing? If not, don't quit the week. Change the time.`),
  P('2026-10-14', '9pm', B, 'fill-blank', 'comment', 'Fill in the blank: I keep breaking…',
    { label: 'Fill in the blank', h: '“I keep promising to *_____*.”', body: 'Be honest. **Nobody here is judging.** You’re in a room of men who’ve done the same.', btn: 'Answer below ↓' },
    `Fill in the blank: "I keep promising to _____."

Be honest. Nobody here is judging. You're in a room full of men who've broken the same promise.

Naming it is step one.`,
    `Fill in the blank: "I keep promising to ___." Nobody here is judging. Naming it is step one.`),

  // ───── Thu Oct 15 ─────
  R('2026-10-15', B, 'phone-9pm', 'challenge', 'The 9 PM phone rule',
    [['S:The best thing I did for my marriage', 'B:cost *zero dollars.*'], ['B:Phone in the kitchen.\n*9 PM.*'], ['S:Every night.', 'B:Try it *for a week.*']],
    `The best thing I did for my marriage cost zero dollars.

Phone in the kitchen at 9 PM. Every night. No exceptions for "just checking."

Try it for one week and tell me what changed.`,
    `The best thing I did for my marriage cost zero dollars: phone in the kitchen at 9 PM, every night. Try it for one week.`),
  K('2026-10-15', C, 'fight-phrases', 'save', '6 phrases that end a fight faster',
    { label: 'Screenshot this', h: '6 phrases that *end a fight* faster.', body: 'Say them **before** you’re right.',
      slides: [['“You’re *right* about that part.”', 'Find the true part. Say it first.'], ['“Can we *start over?*”', 'Reset the tone, not the topic.'], ['“I’m *on your side.*”', 'Even when it doesn’t feel like it.'], ['“What do you *need* right now?”', 'Sometimes it’s a solution. **Usually it’s a hug.**'], ['“I need *20 minutes.*”', 'Then come back. **Every time.**']],
      end: { pre: 'And the sixth one:', h: '“I love you.\n*Even right now.*”' } },
    `6 phrases that end a fight faster:

1. "You're right about that part."
2. "Can we start over?"
3. "I'm on your side."
4. "What do you need right now?"
5. "I need 20 minutes." (Then come back.)
6. "I love you. Even right now."

Screenshot this.`,
    `6 phrases that end a fight faster: "You're right about that part." "Can we start over?" "I'm on your side." "What do you need?" "I need 20 minutes." "I love you, even right now."`),
  P('2026-10-15', '9pm', B, 'kw-step1-b', 'step1', 'Comment STEP1: before New Year’s',
    { label: 'Before January gets here', h: 'Don’t wait for *January* to start over.', body: 'Step 1 takes 20 minutes and a pen. **Start before the promise.**', btn: 'Comment “STEP1” →' },
    `Don't wait for January to start over. That's 80 more days of the same man.

Step 1 takes 20 minutes and a pen. One question: what type of man do you want to be?`,
    `Don't wait for January to start over. That's 80 more days of the same man. Step 1 takes 20 minutes and a pen.`),

  // ───── Fri Oct 16 ─────
  R('2026-10-16', C, 'date-friday', 'save', 'Friday date night in 3 steps',
    [['L:Friday date night', 'B:No sitter? *No problem.*'], ['I:Kids down by 8', 'I:Candles at 8:15', 'I:Phones in a drawer'], ['B:On purpose.\n*Just you two.*']],
    `Friday date night, no sitter needed:

Kids down by 8. Candles at 8:15. Phones in a drawer. Your favorite takeout on the good plates.

On purpose, just you two. Tag your spouse so it actually happens.`,
    `Friday date night, no sitter: kids down by 8, candles at 8:15, phones in a drawer. On purpose, just you two.`),
  P('2026-10-16', '2pm', B, 'quote-house', 'challenge', 'Quote: your house notices',
    { h: 'Your house notices the change *before you announce it.*', sub: 'That’s how you know it’s real.' },
    `Your house notices the change before you announce it. That's how you know it's real.

Don't tell them you're changing. Let them catch you.`,
    `Your house notices the change before you announce it. That's how you know it's real. Let them catch you.`),
  P('2026-10-16', '9pm', C, 'this-that', 'comment', 'This or that: couple edition',
    { label: 'This or that', h: '*Night in* or night out?\n*Talk it out* or sleep on it?', body: 'Answer for you **and** your spouse. **See if you agree.**', btn: 'Answer below ↓' },
    `This or that, couple edition:

Night in or night out?
Talk it out or sleep on it?
Plan everything or wing it?

Answer for you AND your spouse in the comments. Then see if they agree. 😄`,
    `Couple edition: night in or night out? Talk it out or sleep on it? Plan it or wing it? Answer for you and your spouse.`),

  // ───── Sat Oct 17 ─────
  R('2026-10-17', B, 'three-days', 'challenge', 'Three days until the challenge',
    [['L:3 days', 'B:until seven weeks that *change the year.*'], ['S:Free.', 'S:One email a week.', 'S:One action with a time on it.'], ['B:Bring *one brother.*']],
    `Three days until the free 7-week challenge starts.

One email a week. One action with a time on it, small enough to do that week. And one brother, so you each text "done" or "missed."

Who are you bringing? Tag him.`,
    `Three days until the free 7-week challenge. One email a week, one action with a time on it, one brother. Who are you bringing?`),
  K('2026-10-17', B, 'saturday-dad', 'step1', '5 things to do with your kids this weekend',
    { label: 'This weekend', h: '5 things to do with your kids *that cost nothing.*', body: 'They want **you**, not a budget.',
      slides: [['Make *breakfast* together.', 'Let them crack the eggs. Let it be messy.'], ['Take a *walk* and ask questions.', '“What’s something you’re proud of this week?”'], ['Teach them *one skill.*', 'Change a tire. Tie a tie. Fix something.'], ['Let them *win* one game.', 'Then let them see you lose well.'], ['*Pray* over them at bedtime.', 'By name. Out loud. **Every night.**']],
      end: { pre: 'Start with who you want to be.', h: 'Step 1 is *free.*' } },
    `5 things to do with your kids this weekend that cost nothing:

1. Make breakfast together. Let it be messy.
2. Take a walk and ask a real question.
3. Teach them one skill.
4. Let them win one game, and let them see you lose well.
5. Pray over them at bedtime, by name.

They want you, not a budget.`,
    `5 free things to do with your kids this weekend: breakfast together, a walk with a real question, teach one skill, lose a game well, pray over them by name.`),
  P('2026-10-17', '9pm', B, 'brother', 'challenge', 'Tag the brother',
    { label: 'Tag him', h: 'Tag the man you’d want *holding you accountable.*', body: 'Seven weeks. One text a week: **done, or missed.**', btn: 'Tag your brother ↓' },
    `Tag the man you'd want holding you accountable.

The challenge starts Tuesday. Seven weeks. Once a week, you text each other one word: done, or missed. That's the whole system.`,
    `Tag the man you'd want holding you accountable. Seven weeks, one text a week: done, or missed.`),

  // ───── Sun Oct 18 ─────
  R('2026-10-18', C, 'church-car', 'share', 'The fight in the church parking lot',
    [['S:Arguing all morning,', 'S:smiling in the pew,', 'B:fighting again *in the car.*'], ['B:Sound *familiar?*'], ['B:Pray *before* you leave the house.\n*Not after.*']],
    `Arguing all morning. Smiling in the pew. Fighting again in the car.

Sound familiar? You're not the only ones.

Try this: hold hands and pray for 60 seconds before you leave the house on Sunday. Not after. Before.`,
    `Arguing all morning, smiling in the pew, fighting again in the car. Try praying together for 60 seconds before you leave the house.`),
  P('2026-10-18', '2pm', C, 'quote-team', 'share', 'Quote: same team',
    { h: 'You’re not *against* each other.\nYou’re *for* the same marriage.' },
    `You're not against each other. You're for the same marriage.

Remember that in the next argument. Then say it out loud.`,
    `You're not against each other. You're for the same marriage. Say it out loud in the next argument.`),
  P('2026-10-18', '9pm', B, 'kw-challenge-b', 'challenge', 'Challenge starts Tuesday',
    { label: 'Starts Tuesday · free', h: 'Seven weeks.\n*One action a week.*', items: ['Write one sentence about the man you’re becoming', 'Cut your goals to three', 'Give one goal a day and a time', 'Write down what counts as a miss'], btn: 'Join free → link in bio' },
    `The free 7-week challenge starts Tuesday.

Week 1: one sentence about the man you're becoming.
Week 2: cut your goals to three.
Then: name what stops you, give a goal a time, define a miss, count honestly, and put God at the center.

One email a week. Join with a brother.`,
    `Free 7-week challenge starts Tuesday. One sentence, three goals, a day and a time, a written miss, counted honestly, God at the center.`),

  // ───── Mon Oct 19 ─────
  R('2026-10-19', B, 'tomorrow-sentence', 'challenge', 'Tomorrow you write one sentence',
    [['B:Tomorrow you write *one sentence.*'], ['S:Who you’re becoming.', 'S:Not a goal.', 'B:*A man.*'], ['B:Seven weeks starts *tomorrow.*']],
    `Tomorrow you write one sentence: who you're becoming. Not a goal. A man.

The free 7-week challenge starts tomorrow. It's not too late to join.`,
    `Tomorrow you write one sentence: who you're becoming. Not a goal. A man. Free 7-week challenge starts tomorrow.`),
  K('2026-10-19', C, 'in-law-scripts', 'couples', 'Scripts for in-law boundaries',
    { label: 'Before the holidays', h: 'What to say when in-laws *cross a line.*', body: 'Kind, clear, **and together.**',
      slides: [['On *advice.*', '“Thanks, Mom. We’re going to try it our way.”'], ['On *visits.*', '“We’d love to see you. Saturday from 2 to 5 works for us.”'], ['On *the kids.*', '“We’ve decided on that one. Thanks for understanding.”'], ['On *criticism.*', '“We’re good. She’s with me.” **Then change the subject.**'], ['Always *together.*', 'Decide at home. **Present it as “we.”**']],
      end: { pre: 'Struggling to get on the same page?', h: 'Certified marriage\n*counseling.*' } },
    `What to say when in-laws cross a line:

On advice: "Thanks, Mom. We're going to try it our way."
On visits: "Saturday from 2 to 5 works for us."
On the kids: "We've decided on that one."
On criticism: "We're good. She's with me."

Always decide at home, together, and present it as "we."`,
    `When in-laws cross a line: "Thanks, we'll try it our way." "Saturday 2 to 5 works for us." "We've decided on that one." "We're good. She's with me." Always as "we."`),
  P('2026-10-19', '9pm', B, 'workshop-6', 'workshop', 'Workshop in 6 days',
    { label: 'Sun Oct 25 · 7 PM Central · $27', h: 'One hour to *fix your Wednesday.*', items: ['Your **one sentence**', '**One goal** with a date', 'Your first **Scorecard**'], btn: 'Reserve a spot → link in bio' },
    `Six days until Fix Your Wednesday, live on Google Meet.

One hour. You leave with your one sentence, one goal with a date, and your first weekly Scorecard. Recording included.`,
    `Six days until Fix Your Wednesday. One hour, live. Leave with your sentence, one goal with a date, and your first Scorecard.`),

  // ───── Tue Oct 20 ─────
  R('2026-10-20', C, 'tuesday-kiss', 'share', 'The 6-second kiss (Tuesday edition)',
    [['B:6 seconds.'], ['S:Long enough to stop.', 'S:Short enough to do', 'B:*every day.*'], ['B:Leaving and coming home.\n*Starting today.*']],
    `Six seconds. Long enough to actually stop, short enough to do every day.

Leaving and coming home, starting today. Count if you have to. Laugh about counting. That's part of it.`,
    `Six seconds. Long enough to stop, short enough to do every day. Leaving and coming home, starting today.`),
  P('2026-10-20', '2pm', B, 'day-one', 'challengeOn', 'Day one: write it now',
    { label: 'Challenge · day one', h: 'Write it *now*,\nbefore the day gets loud.', body: '**“I am becoming a man who…”** Finish the sentence. Then cut it in half.' },
    `Day one of the challenge. Write it now, before the day gets loud:

"I am becoming a man who…"

Finish the sentence. Then cut it in half. The shorter it is, the more you'll remember it at 6 PM.`,
    `Challenge day one. Write it before the day gets loud: "I am becoming a man who…" Finish it. Then cut it in half.`),
  P('2026-10-20', '9pm', B, 'share-sentence', 'comment', 'Share your sentence',
    { label: 'Week 1 of 7', h: 'Share your *sentence.*', body: 'One line. **“I am becoming a man who…”** Let another brother read it and borrow your courage.', btn: 'Share it below ↓' },
    `Week 1 of the challenge: share your sentence below.

"I am becoming a man who…"

Saying it out loud in front of other men changes how seriously you take it. Go first. Someone needs to see it.`,
    `Week 1: share your sentence. "I am becoming a man who…" Saying it in front of other men changes how seriously you take it.`),

  // ───── Wed Oct 21 ─────
  R('2026-10-21', B, 'wednesday-again', 'workshop', 'It’s Wednesday again',
    [['B:It’s *Wednesday.*'], ['S:Monday’s promise is', 'B:already *slipping.*'], ['B:Sunday we *fix it.*\nLive. One hour.']],
    `It's Wednesday. Monday's promise is already slipping. You know the feeling.

Sunday at 7 PM Central, we fix it. Live, one hour, $27. You leave with your sentence, a goal with a date, and your first Scorecard.`,
    `It's Wednesday. Monday's promise is already slipping. Sunday at 7 PM Central we fix it. Live, one hour.`),
  K('2026-10-21', C, 'money-talk', 'save', 'How to talk money without a fight',
    { label: 'Save for your next money talk', h: 'How to talk about money *without a fight.*', body: 'It’s rarely about the money. **It’s about safety.**',
      slides: [['Pick a *calm* time.', 'Never right after a surprise charge.'], ['Start with *the dream.*', 'Where do we want to be in a year?'], ['Share *your fear.*', '“I get anxious when the account is low.”'], ['Agree on *one* change.', 'Not a whole new budget. **One thing.**'], ['End with *thanks.*', '“Thank you for working on this with me.”']],
      end: { pre: 'Money is one of the top things couples fight about.', h: 'Talk about it\n*on purpose.*' } },
    `How to talk about money without a fight:

1. Pick a calm time, never right after a surprise charge.
2. Start with the dream: where do we want to be in a year?
3. Share your fear, not your accusation.
4. Agree on ONE change.
5. End with thanks.

It's rarely about the money. It's about feeling safe.`,
    `How to talk money without a fight: calm time, start with the dream, share your fear, agree on one change, end with thanks. It's rarely about money. It's about safety.`),
  P('2026-10-21', '9pm', B, 'workshop-4', 'workshop', 'Four days: what you leave with',
    { label: 'Sunday · 7 PM CT · live', h: 'Most men start Monday strong and lose the week *by Wednesday.*', body: 'One hour on Sunday. **We fix that together.** $27, recording included.', btn: 'Reserve → link in bio' },
    `Most men start Monday strong and lose the week by Wednesday.

Sunday at 7 PM Central, we fix that, live and together. One hour, $27, recording included. Bring a pen.`,
    `Most men start Monday strong and lose the week by Wednesday. Sunday 7 PM CT, we fix it. One hour, $27.`),

  // ───── Thu Oct 22 ─────
  R('2026-10-22', C, 'kids-watching-love', 'share', 'Your kids are learning love from you',
    [['S:Your kids are learning', 'B:what love *looks like*'], ['B:from how you two *talk in the kitchen.*'], ['B:Give them a good one *to copy.*']],
    `Your kids are learning what love looks like from how you two talk in the kitchen.

Not from movies. Not from sermons. From you, on a tired Tuesday.

Give them a good one to copy.`,
    `Your kids are learning what love looks like from how you two talk in the kitchen. Give them a good one to copy.`),
  P('2026-10-22', '2pm', B, 'quote-legacy', 'step1', 'Quote: break the cycle',
    { h: 'The cycle didn’t start with you.\n*It can end with you.*' },
    `The cycle didn't start with you. It can end with you.

Not with a promise. With a system your kids can see working.`,
    `The cycle didn't start with you. It can end with you. Not with a promise. With a system your kids can see working.`),
  P('2026-10-22', '9pm', C, 'kw-couples-b', 'couples', 'Comment COUPLES: before the holidays',
    { label: 'Before the holidays', h: 'Go into the holidays *on the same page.*', body: 'Three sessions, built on a validated assessment you each take. **For engaged and married couples.**', btn: 'Comment “COUPLES” →' },
    `Go into the holidays on the same page, not on edge.

Certified marriage counseling for engaged and married couples: a validated assessment you each take, then three sessions built on your results.`,
    `Go into the holidays on the same page, not on edge. A validated assessment, then three sessions built on your results.`),

  // ───── Fri Oct 23 ─────
  R('2026-10-23', B, 'two-days', 'workshop', 'Two days: bring a pen',
    [['L:Sunday · 7 PM Central', 'B:Bring *a pen.*'], ['S:Leave with', 'I:One sentence', 'I:One goal with a date', 'I:Your first Scorecard'], ['B:One hour.\n*Live.*']],
    `Sunday at 7 PM Central. Bring a pen.

You leave with one sentence, one goal with a date, and your first Scorecard. One hour, live on Google Meet. Recording included.`,
    `Sunday 7 PM Central, bring a pen. Leave with one sentence, one goal with a date, and your first Scorecard.`),
  K('2026-10-23', B, 'myths', 'step1', '5 lies men believe about discipline',
    { label: 'Save this', h: '5 lies men believe about *discipline.*', body: 'Most of what you were told is **motivation dressed up.**',
      slides: [['“I just need to *want it* more.”', 'You want it plenty. **You need a time.**'], ['“Real men don’t need *help.*”', 'Real men have a brother who asks.'], ['“I’ll start *Monday.*”', 'Monday is a feeling. **Tuesday 6:10 is a plan.**'], ['“One miss means *I failed.*”', 'One miss is information.'], ['“It has to be *big* to count.”', 'Small and kept beats big and broken.']],
      end: { pre: 'Start where every system starts.', h: 'Step 1 is\n*free.*' } },
    `5 lies men believe about discipline:

1. "I just need to want it more."
2. "Real men don't need help."
3. "I'll start Monday."
4. "One miss means I failed."
5. "It has to be big to count."

You don't need more motivation. You need a time, a brother, and a plan for the miss.`,
    `5 lies about discipline: "I need to want it more." "Real men don't need help." "I'll start Monday." "One miss = failure." "It has to be big." None of them are true.`),
  P('2026-10-23', '9pm', C, 'first-date', 'comment', 'Where was your first date?',
    { label: 'Couples', h: 'Where was your *first date?*', body: 'Tell us below. **Then go back** sometime this month.', btn: 'Answer below ↓' },
    `Where was your first date? Tell us below.

Then go back sometime this month. Same place, same order if you can. Remember who you were when you chose each other.`,
    `Where was your first date? Go back sometime this month. Remember who you were when you chose each other.`),

  // ───── Sat Oct 24 ─────
  R('2026-10-24', C, 'saturday-chores', 'share', 'Chores are a love language',
    [['S:Nothing says “I love you”', 'B:like *doing the thing* she hates.'], ['S:Without being asked.', 'B:Without *announcing it.*'], ['B:That’s *romance* in year ten.']],
    `Nothing says "I love you" in year ten like doing the thing they hate, without being asked and without announcing it.

The dishes. The insurance call. The gutter. That's romance with mileage on it.`,
    `Nothing says "I love you" in year ten like doing the thing they hate, without being asked or announcing it.`),
  P('2026-10-24', '2pm', B, 'tomorrow-night', 'workshop', 'Tomorrow night',
    { label: 'Tomorrow · 7 PM Central', h: 'Fix your Wednesday.\n*Tomorrow night.*', body: 'One hour, live. **Last day to grab a spot.**', btn: 'Reserve → link in bio' },
    `Tomorrow night, 7 PM Central: Fix Your Wednesday, live.

One hour. Leave with your sentence, one goal with a date and your first Scorecard. Today's the last full day to grab a spot.`,
    `Tomorrow 7 PM Central: Fix Your Wednesday, live. One hour. Last full day to grab a spot.`),
  P('2026-10-24', '9pm', B, 'what-stops', 'comment', 'What stops you on Wednesdays?',
    { label: 'Honest answers only', h: 'What usually kills your week by *Wednesday?*', body: 'Work? The phone? Being tired? **Name it below.** We’ll tackle the top answers tomorrow night.', btn: 'Answer below ↓' },
    `What usually kills your week by Wednesday?

Work? The phone? Being tired? Family stuff? Name it below. We'll tackle the top answers live tomorrow night.`,
    `What usually kills your week by Wednesday? Work, the phone, being tired? Name it below.`),

  // ───── Sun Oct 25 ─────
  R('2026-10-25', B, 'tonight', 'workshop', 'Tonight, 7 PM: fix your Wednesday',
    [['L:Tonight · 7 PM Central', 'B:One hour that fixes *your week.*'], ['S:Bring a pen.', 'S:Bring your honesty.'], ['B:See you *tonight.*']],
    `Tonight, 7 PM Central. One hour that fixes your week.

Bring a pen. Bring your honesty. Can't make it live? The recording comes with your ticket.`,
    `Tonight 7 PM Central: one hour that fixes your week. Bring a pen. Recording included.`),
  K('2026-10-25', C, 'sunday-blessing', 'share', 'A Sunday blessing for your marriage',
    { label: 'Read it together', h: 'A Sunday blessing *for your marriage.*', body: 'Out loud. **Hand in hand.**',
      slides: [['*Peace* in our home.', '“The Lord bless you and keep you.” **Numbers 6:24**'], ['*Patience* with each other.', '“Love is patient, love is kind.” **1 Cor 13:4**'], ['*Wisdom* in our choices.', '“If any of you lacks wisdom, ask God.” **James 1:5**'], ['*Strength* when it’s hard.', '“Two are better than one.” **Ecclesiastes 4:9**'], ['*Christ* at the center.', '“Unless the Lord builds the house…” **Psalm 127:1**']],
      end: { pre: 'Read it together tonight.', h: 'Love on purpose.\n*Not by accident.*' } },
    `A Sunday blessing for your marriage. Read it together, out loud:

Peace in our home. (Numbers 6:24)
Patience with each other. (1 Cor 13:4)
Wisdom in our choices. (James 1:5)
Strength when it's hard. (Ecclesiastes 4:9)
Christ at the center. (Psalm 127:1)`,
    `A Sunday blessing for your marriage: peace in our home, patience with each other, wisdom in our choices, strength when it's hard, Christ at the center.`),
  P('2026-10-25', '9pm', B, 'workshop-done', 'group', 'After the workshop: keep it going',
    { label: 'Missed it? Want more?', h: 'Don’t let tonight become *another promise.*', body: 'The 6-week live group starts **Nov 15.** Same men, every Sunday. **Four seats.**', btn: 'Reserve a seat → link in bio' },
    `Don't let tonight become another promise.

The 6-week live group starts Nov 15: Sundays, 7–8 PM Central, the same men every week. Four seats.`,
    `Don't let tonight become another promise. 6-week live group, Sundays from Nov 15. Same men every week. Four seats.`),

  // ───── Mon Oct 26 ─────
  R('2026-10-26', C, 'monday-text', 'share', 'Send this text before 10 AM',
    [['L:Send this before 10 AM', 'B:“I’m glad I *married you.*”'], ['S:No reason.', 'S:No occasion.'], ['B:Just *Monday.*']],
    `Send this text before 10 AM: "I'm glad I married you."

No reason. No occasion. Just Monday.

Then tell us below what they texted back. 😄`,
    `Send this text before 10 AM: "I'm glad I married you." No reason. No occasion. Just Monday.`),
  P('2026-10-26', '2pm', B, 'three-goals', 'challengeOn', 'Week 2: cut to three',
    { label: 'Challenge · week 2', h: 'You don’t have twelve goals.\nYou have *twelve wishes.*', body: 'Cut it to **three.** Soul, house, work.' },
    `Week 2 of the challenge: you don't have twelve goals. You have twelve wishes.

Cut it to three: one for your soul, one for your house, one for your work. Everything else waits.`,
    `You don't have twelve goals. You have twelve wishes. Cut it to three: soul, house, work.`),
  P('2026-10-26', '9pm', B, 'group-why', 'group', 'Why a group, not an app',
    { label: '6-week live group', h: 'Apps don’t notice when you *go quiet.*', body: '**Men do.** Six Sundays, four seats, starts Nov 15.', btn: 'Reserve a seat → link in bio' },
    `Apps don't notice when you go quiet. Men do.

The 6-week live group: Sundays, 7–8 PM Central, Nov 15 to Dec 20, on Google Meet. Four seats.`,
    `Apps don't notice when you go quiet. Men do. 6-week live group, Sundays from Nov 15. Four seats.`),

  // ───── Tue Oct 27 ─────
  R('2026-10-27', B, 'soul-house-work', 'challengeOn', 'Soul. House. Work.',
    [['B:Soul.'], ['B:House.'], ['B:Work.'], ['S:One goal each.', 'B:Everything else *waits.*']],
    `Soul. House. Work.

One goal each. Everything else waits. Not forever. For now.

What are your three? Write them below.`,
    `Soul. House. Work. One goal each. Everything else waits. Not forever. For now.`),
  K('2026-10-27', C, 'married-vs-roommates', 'couples', 'Married vs. roommates',
    { label: 'Which one are you?', h: 'Married *vs.* roommates.', body: 'Same house. **Very different marriages.**',
      slides: [['Roommates *update.*', 'Married people **talk.**'], ['Roommates *split chores.*', 'Married people **carry each other.**'], ['Roommates *avoid conflict.*', 'Married people **repair.**'], ['Roommates *coexist.*', 'Married people **pursue.**'], ['Roommates *drift.*', 'Married people **steer.**']],
      end: { pre: 'Feel more like roommates lately?', h: 'Get help\n*early.*' } },
    `Married vs. roommates:

Roommates update. Married people talk.
Roommates split chores. Married people carry each other.
Roommates avoid conflict. Married people repair.
Roommates coexist. Married people pursue.
Roommates drift. Married people steer.

Which column are you living in this month?`,
    `Roommates update; married people talk. Roommates avoid conflict; married people repair. Roommates drift; married people steer.`),
  P('2026-10-27', '9pm', C, 'pray-poll', 'comment', 'Do you pray together?',
    { label: 'Honest poll', h: 'Do you and your spouse *pray together?*', body: 'Comment: **Daily · Sometimes · Not yet.** No shame. Just a starting point.', btn: 'Answer below ↓' },
    `Honest poll: do you and your spouse pray together?

Comment: Daily, Sometimes, or Not yet.

No shame in "not yet." It's just a starting point. Two minutes tonight changes the answer.`,
    `Do you and your spouse pray together? Daily, sometimes, or not yet? No shame in "not yet." Two minutes tonight changes it.`),

  // ───── Wed Oct 28 ─────
  R('2026-10-28', C, 'listen', 'share', 'Listen to understand',
    [['B:“Yeah, *but…*”', 'S:is listening to reply.'], ['B:“So what you’re saying *is…*”', 'S:is listening to understand.'], ['B:Try the second one *tonight.*']],
    `"Yeah, but…" is listening to reply.
"So what you're saying is…" is listening to understand.

Try the second one tonight. Say back what you heard before you say anything of your own.`,
    `"Yeah, but…" is listening to reply. "So what you're saying is…" is listening to understand. Try the second one tonight.`),
  P('2026-10-28', '2pm', B, 'quote-small', 'step1', 'Quote: small and kept',
    { h: 'Small and kept beats *big and broken.*', sub: 'Every time.' },
    `Small and kept beats big and broken. Every time.

Twenty pushups you do beats an hour at the gym you don't.`,
    `Small and kept beats big and broken. Every time.`),
  P('2026-10-28', '9pm', B, 'kw-step1-c', 'step1', 'Comment STEP1: 20 minutes tonight',
    { label: '20 minutes · a pen · free', h: 'The worksheet that comes *before every goal.*', body: 'You finish with **one sentence** that says who you’re becoming.', btn: 'Comment “STEP1” →' },
    `The worksheet that comes before every goal. Twenty minutes, a pen, and you finish with one sentence that says who you're becoming.`,
    `The worksheet that comes before every goal. 20 minutes, a pen, one sentence that says who you're becoming.`),

  // ───── Thu Oct 29 ─────
  R('2026-10-29', B, 'first-ten', 'challengeOn', 'The first 10 minutes home',
    [['S:Your family meets the man', 'B:who walks *through the door.*'], ['B:Decide who that is *in the car.*'], ['B:The first 10 minutes\n*set the night.*']],
    `Your family meets the man who walks through the door. Decide who that is in the car.

The first ten minutes set the whole night. Phone in your pocket. Hug first. Ask one real question.`,
    `Your family meets the man who walks through the door. Decide who that is in the car. The first 10 minutes set the night.`),
  K('2026-10-29', C, 'gratitude-list', 'save', '10 things to thank your spouse for this week',
    { label: 'One a day', h: 'Things to thank your spouse for *this week.*', body: 'Specific beats general. **Every time.**',
      slides: [['The *ordinary* stuff.', '“Thank you for making lunches every day.”'], ['The *invisible* stuff.', '“Thank you for remembering the appointments.”'], ['The *hard* stuff.', '“Thank you for handling that call with my mom.”'], ['The *character* stuff.', '“Thank you for being honest when it cost you.”'], ['The *staying.*', '“Thank you for staying when it was hard.”']],
      end: { pre: 'One thank-you a day.', h: 'Notice it\n*out loud.*' } },
    `Things to thank your spouse for this week:

The ordinary stuff: lunches, laundry, the commute.
The invisible stuff: remembering everything.
The hard stuff: the difficult phone call.
The character stuff: honesty when it cost them.
The staying: "Thank you for staying when it was hard."

One specific thank-you a day.`,
    `Thank your spouse this week for the ordinary, the invisible, the hard, their character, and for staying. One specific thank-you a day.`),
  P('2026-10-29', '9pm', B, 'group-sunday', 'group', 'What a Sunday in the group looks like',
    { label: 'Starts Nov 15 · four seats', h: '7:00 done or missed.\n7:15 one tool.\n*8:00 home.*', body: 'One hour. Same men. **Six Sundays.**', btn: 'Reserve a seat → link in bio' },
    `What a Sunday in the 6-week group looks like:

7:00 Done or missed. No speeches.
7:15 One tool, worked live.
7:40 Next week's one decision, with a time.
8:00 Home with your family.

Starts Nov 15. Four seats.`,
    `A Sunday in the 6-week group: 7:00 done or missed, 7:15 one tool, 7:40 next week's decision, 8:00 home. Four seats.`),

  // ───── Fri Oct 30 ─────
  R('2026-10-30', C, 'friday-plan', 'save', 'Make Friday night yours',
    [['S:Friday isn’t for', 'B:catching up on *chores.*'], ['B:It’s for catching up on *each other.*'], ['B:Plan it *by noon.*']],
    `Friday isn't for catching up on chores. It's for catching up on each other.

Plan it by noon so it actually happens. Text your spouse right now: "Tonight, 8:30, just us?"`,
    `Friday isn't for catching up on chores. It's for catching up on each other. Plan it by noon.`),
  P('2026-10-30', '2pm', B, 'quote-information', 'challengeOn', 'Quote: a miss is information',
    { h: 'A miss is *information.*\nNot a verdict.' },
    `A miss is information, not a verdict.

Missed Tuesday? Tuesday at 6 doesn't work. Try 9 PM. Change the time, not the goal.`,
    `A miss is information, not a verdict. Change the time, not the goal.`),
  P('2026-10-30', '9pm', C, 'kw-couples-c', 'couples', 'Comment COUPLES: no crisis needed',
    { label: 'Healthy couples get coached too', h: 'You don’t need a crisis to get *a check-up.*', body: 'A validated assessment, then **three sessions** built on your results.', btn: 'Comment “COUPLES” →' },
    `You don't need a crisis to get a check-up. Healthy couples get coached too, and they stay healthy partly because they do.

A validated assessment, then three sessions built on your results.`,
    `You don't need a crisis to get a marriage check-up. Healthy couples get coached too.`),

  // ───── Sat Oct 31 ─────
  R('2026-10-31', B, 'scary', 'challengeOn', 'The scariest thing a man can do',
    [['S:The scariest thing', 'B:isn’t *failing.*'], ['B:It’s being the *same man* next year.'], ['B:Decide *tonight.*']],
    `The scariest thing isn't failing. It's being the same man next year.

Same temper. Same phone. Same promise. Decide tonight who you're becoming.`,
    `The scariest thing isn't failing. It's being the same man next year. Decide tonight who you're becoming.`),
  K('2026-10-31', B, 'saturday-reset', 'step1', 'The 30-minute Saturday reset',
    { label: 'Saturday morning', h: 'The 30-minute *Saturday reset.*', body: 'Before the yard, before the games. **This first.**',
      slides: [['*5 min* · Clear one surface.', 'The desk, the counter, the truck. **Order outside helps order inside.**'], ['*5 min* · Read one psalm.', 'Slowly. Twice.'], ['*10 min* · Review the week.', 'What did I keep? What slipped?'], ['*5 min* · Plan one thing with the kids.', 'Today, not someday.'], ['*5 min* · Ask your wife one question.', '“What would make today easier for you?”']],
      end: { pre: 'Start with who you want to be.', h: 'Step 1 is\n*free.*' } },
    `The 30-minute Saturday reset:

5 min: clear one surface.
5 min: read one psalm, slowly.
10 min: review the week. What did I keep? What slipped?
5 min: plan one thing with the kids, today.
5 min: ask your wife, "What would make today easier for you?"`,
    `The 30-minute Saturday reset: clear one surface, one psalm, review the week, plan one thing with the kids, ask your wife what would make today easier.`),
  P('2026-10-31', '9pm', B, 'one-word-man', 'comment', 'One word for the man you’re becoming',
    { label: 'One word', h: 'The man you’re becoming, *in one word.*', body: 'Patient? Present? Steady? **Drop it below.**', btn: 'Answer below ↓' },
    `The man you're becoming, in one word. Patient? Present? Steady? Faithful?

Drop it below. Then live that word for 24 hours.`,
    `The man you're becoming, in one word. Patient? Present? Steady? Live it for 24 hours.`),

  // ───── Sun Nov 1 ─────
  R('2026-11-01', C, 'new-month', 'save', 'New month, one marriage goal',
    [['L:New month', 'B:One marriage goal.\n*Not ten.*'], ['S:With a day.', 'S:With a time.'], ['B:Put it on *both calendars.*']],
    `New month. One marriage goal, not ten. With a day and a time.

"Date night every other Friday at 7" beats "spend more time together." Put it on both calendars today.`,
    `New month, one marriage goal. With a day and a time. Put it on both calendars today.`),
  P('2026-11-01', '2pm', C, 'quote-choose', 'share', 'Quote: choose each other',
    { h: 'Love is a feeling *sometimes.*\nIt’s a choice *every day.*' },
    `Love is a feeling sometimes. It's a choice every day.

Choose each other again this month, on purpose.`,
    `Love is a feeling sometimes. It's a choice every day.`),
  P('2026-11-01', '9pm', B, 'november-promise', 'group', 'November: two weeks until the group',
    { label: 'Starts in two weeks', h: 'Don’t let the holidays *eat your system.*', body: 'Six Sundays, **Nov 15 – Dec 20.** Four seats.', btn: 'Reserve a seat → link in bio' },
    `Don't let the holidays eat your system.

The 6-week live group runs right through them: six Sundays, Nov 15 to Dec 20, 7–8 PM Central. Four seats.`,
    `Don't let the holidays eat your system. 6-week live group, Nov 15 to Dec 20. Four seats.`),

  // ───── Mon Nov 2 ─────
  R('2026-11-02', B, 'name-it', 'challengeOn', 'Name the one thing',
    [['B:It’s not ten things.'], ['B:It’s *one.*', 'S:And you already know its name.'], ['B:Name it. Then *plan for it.*']],
    `It's not ten things stopping you. It's one, and you already know its name.

This week's challenge step: name it, write it down, and give it an "if this, then that" plan.`,
    `It's not ten things stopping you. It's one, and you know its name. Name it. Then plan for it.`),
  K('2026-11-02', C, 'questions-deep', 'save', '5 questions for a deeper conversation',
    { label: 'Tonight', h: '5 questions for a *deeper* conversation.', body: 'Ask one. **Then really listen.**',
      slides: [['“What are you *afraid* of lately?”', 'Don’t fix it. Ask “what else?”'], ['“What do you *miss* about us?”', 'Write the answer down later.'], ['“What dream did you *put on hold?*”', 'Maybe it’s time to bring it back.'], ['“When do you feel most *respected* by me?”', 'Do more of that.'], ['“What should we *stop* doing?”', 'Brave question. **Big payoff.**']],
      end: { pre: 'Pick one for tonight.', h: 'Talk.\n*Don’t just update.*' } },
    `5 questions for a deeper conversation:

1. "What are you afraid of lately?"
2. "What do you miss about us?"
3. "What dream did you put on hold?"
4. "When do you feel most respected by me?"
5. "What should we stop doing?"

Ask one tonight. Then really listen.`,
    `5 deeper questions: What are you afraid of? What do you miss about us? What dream is on hold? When do you feel respected? What should we stop doing?`),
  P('2026-11-02', '9pm', B, 'blocker-poll', 'comment', 'What’s your #1 blocker?',
    { label: 'Pick one', h: 'Your #1 blocker:\n*Phone · Tired · Temper · Time*', body: 'Comment yours. **The most common answer gets its own post this week.**', btn: 'Answer below ↓' },
    `What's your number one blocker right now?

Phone. Tired. Temper. Time.

Comment yours. The most common answer gets its own post this week.`,
    `Your #1 blocker right now: phone, tired, temper or time? Comment yours.`),

  // ───── Tue Nov 3 ─────
  R('2026-11-03', C, 'tone', 'share', 'It’s not what you said',
    [['S:“I didn’t say anything wrong!”'], ['B:It wasn’t *what.*\nIt was *how.*'], ['B:Same words.\nSofter voice.\n*Different marriage.*']],
    `"I didn't say anything wrong!" It wasn't what you said. It was how.

Same words, softer voice, different marriage.`,
    `"I didn't say anything wrong!" It wasn't what. It was how. Same words, softer voice, different marriage.`),
  P('2026-11-03', '2pm', B, 'if-then', 'challengeOn', 'If this, then that',
    { label: 'Plan for the blocker', h: 'If I walk in tired,\nthen I *pray in the car* first.', body: 'Write yours: **“If ___, then I will ___.”** Decide it while you’re calm.' },
    `Plan for the blocker before it shows up:

"If I walk in tired, then I pray in the car for two minutes first."
"If I grab my phone after 9, then I put it on the kitchen counter."

Write yours below. Decide it while you're calm.`,
    `Plan for the blocker before it shows up: "If I walk in tired, then I pray in the car first." Decide it while you're calm.`),
  P('2026-11-03', '9pm', B, 'kw-step1-d', 'step1', 'Comment STEP1: start before the promise',
    { label: 'Free worksheet', h: 'Start *before* the promise.', body: 'One question. One sentence. **Every goal after it gets checked against it.**', btn: 'Comment “STEP1” →' },
    `Start before the promise. One question, one sentence, and every goal after it gets checked against it.`,
    `Start before the promise. One question, one sentence. Every goal after it gets checked against it.`),

  // ───── Wed Nov 4 ─────
  R('2026-11-04', B, 'phone-blocker', 'challengeOn', 'You said the phone',
    [['L:You voted', 'B:*The phone.*'], ['I:Charges in the kitchen', 'I:Gray screen after 8', 'I:First hour of the day: no scroll'], ['B:Pick *one.* Start tonight.']],
    `You voted, and the phone won.

Three fixes, pick one: charge it in the kitchen, turn the screen gray after 8 PM, or no scrolling in the first hour of the day.

Start tonight.`,
    `You voted: the phone. Pick one fix: charge it in the kitchen, gray screen after 8, or no scrolling the first hour of the day.`),
  K('2026-11-04', C, 'holiday-team', 'couples', 'How to stay a team through the holidays',
    { label: 'Save before Thanksgiving', h: 'How to stay *a team* through the holidays.', body: 'Decide at home. **Not in the car.**',
      slides: [['Agree on *where* and *how long.*', 'Then actually leave on time.'], ['Pick a *signal.*', 'A word that means “I need you” or “let’s go.”'], ['Split the *kid duty.*', 'So nobody ends up resentful.'], ['Set the *budget.*', 'One number. No surprises in January.'], ['Debrief *kindly.*', 'One good thing on the drive home.']],
      end: { pre: 'Want to get on the same page first?', h: 'Certified marriage\n*counseling.*' } },
    `How to stay a team through the holidays. Decide at home, not in the car:

1. Where and how long. Then leave on time.
2. A signal that means "I need you."
3. Split kid duty.
4. One budget number.
5. Debrief kindly: one good thing on the drive home.`,
    `Stay a team through the holidays: agree on where and how long, pick a signal, split kid duty, one budget number, and debrief kindly on the drive home.`),
  P('2026-11-04', '9pm', C, 'pet-peeve', 'comment', 'Small habit, big love',
    { label: 'Couples', h: 'What small habit of your spouse’s do you *secretly love?*', body: 'Tell us below. **Then tell them.**', btn: 'Answer below ↓' },
    `What small habit of your spouse's do you secretly love?

The way they hum while cooking. How they check the locks twice. Tell us below. Then tell them.`,
    `What small habit of your spouse's do you secretly love? Tell us. Then tell them.`),

  // ───── Thu Nov 5 ─────
  R('2026-11-05', C, 'holiday-budget', 'share', 'Don’t start January in debt',
    [['S:A lot of couples start January', 'B:in debt *and* in a fight.'], ['B:One number.\n*Decided together.*'], ['B:Write it *on the fridge.*']],
    `A lot of couples start January in debt, and in a fight about the debt.

One holiday number, decided together, written on the fridge. Surprise gifts are fun. Surprise bills aren't.`,
    `A lot of couples start January in debt and in a fight. One holiday number, decided together, written on the fridge.`),
  P('2026-11-05', '2pm', B, 'quote-time', 'challengeOn', 'Quote: give it a time',
    { h: 'A goal with no time is *a wish.*' },
    `A goal with no time is a wish.

This week's challenge step: give one goal a day and a time. "Tuesday, 6:10, garage." Done.`,
    `A goal with no time is a wish. Give one goal a day and a time.`),
  P('2026-11-05', '9pm', B, 'group-10', 'group', 'Group: 10 days',
    { label: '10 days · four seats', h: 'Six Sundays.\nSame men.\n*Real accountability.*', body: 'Nov 15 – Dec 20, **7–8 PM Central**, Google Meet.', btn: 'Reserve a seat → link in bio' },
    `Ten days until the 6-week live group starts.

Six Sundays, the same men every week, real accountability right through the holidays. Nov 15 to Dec 20, 7–8 PM Central. Four seats.`,
    `10 days until the 6-week live group. Six Sundays, same men, real accountability through the holidays. Four seats.`),

  // ───── Fri Nov 6 ─────
  R('2026-11-06', B, 'friday-dad', 'step1', 'Friday night, dad edition',
    [['S:Friday night.', 'B:The kids don’t need *a plan.*'], ['B:They need *you on the floor.*'], ['B:Phone in a drawer.\n*One game.* Their pick.']],
    `Friday night. The kids don't need a plan. They need you on the floor.

Phone in a drawer. One game, their pick. Let them see you lose well.`,
    `Friday night. The kids don't need a plan. They need you on the floor. Phone in a drawer, one game, their pick.`),
  K('2026-11-06', C, 'weekend-ideas', 'save', '5 weekend ideas for couples',
    { label: 'This weekend', h: '5 weekend ideas *for couples.*', body: 'No sitter. **Low budget.**',
      slides: [['*Sunrise* coffee.', 'Up 30 minutes before the kids. Porch. Blanket.'], ['Cook *something new.*', 'Pick a recipe neither of you has made.'], ['The *old photos* night.', 'Wedding album, phone, dessert.'], ['A *walk* with one question.', '“What’s been on your mind lately?”'], ['*Serve* together.', 'Bring a meal to someone who needs it.']],
      end: { pre: 'Pick one. Put it on the calendar.', h: 'Love on purpose.\n*Not by accident.*' } },
    `5 weekend ideas for couples, no sitter, low budget:

1. Sunrise coffee before the kids are up.
2. Cook something neither of you has made.
3. Old photos night with dessert.
4. A walk with one real question.
5. Serve someone together.

Pick one and put it on the calendar.`,
    `5 weekend ideas for couples: sunrise coffee, cook something new, old photos night, a walk with one question, serve someone together.`),
  P('2026-11-06', '9pm', B, 'win-week', 'comment', 'Share one win from this week',
    { label: 'End the week strong', h: 'Share *one win* from this week.', body: 'Small counts. **Especially small.**', btn: 'Share it below ↓' },
    `Share one win from this week. Small counts. Especially small.

"Prayed 4 of 5 mornings." "Phone in the kitchen 3 nights." "Apologized first."

Let another man see it's possible.`,
    `Share one win from this week. Small counts. Especially small.`),

  // ───── Sat Nov 7 ─────
  R('2026-11-07', C, 'saturday-yes', 'share', 'Say yes to one thing today',
    [['S:She asked for help', 'B:three times *this week.*'], ['B:Today, say *yes* before she asks.'], ['B:That’s *leadership.*']],
    `She asked for help three times this week. Today, say yes before she asks.

Take the kids. Handle the errand. Let her rest. That's leadership.`,
    `She asked for help three times this week. Today, say yes before she asks. That's leadership.`),
  K('2026-11-07', B, 'group-preview', 'group', 'What we’ll build in 6 Sundays',
    { label: 'Starts Nov 15', h: 'What we’ll build in *six Sundays.*', body: 'One step a week, **with the same men.**',
      slides: [['Week 1 · Your *sentence.*', 'Who you’re becoming, in one line.'], ['Week 2 · Your *three.*', 'Soul, house, work.'], ['Week 3 · Your *blocker.*', 'Named, with an if-then plan.'], ['Week 4 · Your *times.*', 'On the calendar like a meeting.'], ['Weeks 5–6 · Your *misses* and *God.*', 'Count it honestly. Put Him at the center.']],
      end: { pre: 'Four seats. Sundays, 7 PM Central.', h: 'Reserve\n*your seat.*' } },
    `What we'll build in the 6-week group, one step a week:

Week 1: your sentence.
Week 2: your three goals.
Week 3: your blocker, with a plan.
Week 4: your times, on the calendar.
Weeks 5–6: your misses, counted honestly, and God at the center.

Starts Nov 15. Four seats.`,
    `What we'll build in six Sundays: your sentence, your three goals, your blocker plan, your times, your misses, and God at the center. Starts Nov 15.`),
  P('2026-11-07', '9pm', B, 'kw-step1-e', 'step1', 'Comment STEP1: the weekend start',
    { label: 'This weekend · 20 minutes', h: 'Give yourself 20 minutes *this weekend.*', body: 'A pen. One question. **One sentence that changes Monday.**', btn: 'Comment “STEP1” →' },
    `Give yourself 20 minutes this weekend. A pen, one question, and one sentence that changes Monday.`,
    `Give yourself 20 minutes this weekend. A pen, one question, one sentence that changes Monday.`),
];
