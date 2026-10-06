// Be The Man, weeks 3–12 (Oct 19 – Dec 27). Each week follows that week's
// 7-week-challenge step, and carries at most one or two selling CTAs.
const B = (o) => ({ theme: 'btm', ...o });
export const btm = [
  // ───────── WEEK 3 · Oct 19–25 · One sentence · challenge starts Tue, workshop Sun ─────────
  B({ id: 'w3-starts-tomorrow', type: 'reel', week: 3, slot: 'r1', cta: 'challenge', title: 'Reel: Seven weeks starts tomorrow',
    reel: [['B:Tomorrow, a lot of men will *start over.*'], ['S:Same promise.', 'S:Same Monday energy.', 'B:Same *Wednesday.*'], ['L:Seven weeks. Free.', 'I:One email a week', 'I:One action with a time on it', 'I:One brother texting you: *done* or *missed*'], ['B:Don’t start over. *Start with a brother.*']],
    cap: `Tomorrow a lot of men will start over. Same promise, same Monday energy, same Wednesday.

The free 7-week challenge starts tomorrow, Oct 20. One email a week. One action with a time on it, small enough to do that week.

And one rule: don't do it alone. Forward it to one man you trust. Once a week, text each other one word: done, or missed. That's the whole accountability.`,
    th: `Tomorrow a lot of men will start over. Same promise, same Wednesday.

Free 7-week challenge starts Oct 20. One action a week with a time on it. Do it with a brother: once a week, text each other "done" or "missed."` }),
  B({ id: 'w3-week-one', type: 'post', week: 3, slot: 'p1', cta: 'challengeOn', title: 'Challenge week 1: one sentence',
    post: { label: 'Week 1 of 7 · starts today', h: 'Write one sentence about the man *you’re becoming.*', body: 'Not a goal. Not a list. **One sentence** your wife could read and say, “Yes. That’s him.”', btn: 'Join free → link in bio' },
    cap: `The free 7-week challenge starts today. Week 1 is one sentence.

Write one sentence about the man you're becoming. Not a goal. Not a list. One sentence your wife could read and say, "Yes. That's him."

Mine started as three paragraphs. The cutting is the work.

Joining late is fine. You'll start with this week's email, and the first step comes in your welcome email.`,
    th: `The free 7-week challenge starts today.

Week 1: write one sentence about the man you're becoming. Not a goal. Not a list. One sentence your wife could read and say, "That's him."

The cutting is the work.` }),
  B({ id: 'w3-wednesday', type: 'carousel', week: 3, slot: 'c', cta: 'workshop', title: 'Carousel: Why you lose the week by Wednesday',
    carousel: { label: 'Fix your Wednesday', h: 'Why you start Monday strong and *lose the week by Wednesday.*', body: 'Four leaks. One fix for each.',
      slides: [['Monday had *a feeling.*', 'Monday ran on fresh motivation. **Motivation lasts about two days.** Wednesday needs something already decided.'], ['Nothing had *a time.*', '“Work out this week” isn’t a plan. **Tuesday, 6:10, garage** is.'], ['There was no *miss.*', 'You never wrote down what counts as missing, so one slip felt like failing the whole week.'], ['It lived in *your head.*', 'Your head is a terrible place to store a promise. **Put it on one page** you can see.'], ['Nobody *knew.*', 'One brother. One text a week: done, or missed. **That’s the accountability.**']],
      end: { pre: 'One hour, live, together.', h: 'Fix Your Wednesday.\n*Sun Oct 25 · 7 PM CT.*' } },
    cap: `Why you start Monday strong and lose the week by Wednesday:

1. Monday ran on a feeling. Feelings last about two days.
2. Nothing had a time. "This week" is not a time.
3. There was no written miss, so one slip felt like failing everything.
4. It lived in your head instead of on a page.
5. Nobody knew. One brother, one text a week, fixes that.

💾 Save this.`,
    th: `Why you start Monday strong and lose the week by Wednesday:

Monday ran on a feeling. Nothing had a time. There was no written miss. It lived in your head. And nobody knew.

Five leaks. Each one has a fix.` }),
  B({ id: 'w3-workshop-tomorrow', type: 'post', week: 3, slot: 'p2', cta: 'workshop', title: 'Workshop tomorrow: leave with three things',
    post: { label: 'Live tomorrow · Sun Oct 25 · 7 PM CT', h: 'One hour. *Three things* written down.', items: ['**One sentence** naming the man you’re becoming', '**One goal** with a date', '**Your first weekly Scorecard**'], body: '', btn: '$27 · recording included' },
    cap: `Tomorrow night: Fix Your Wednesday, live on Google Meet.

One hour. You leave with three things written down:
→ One sentence naming the man you're becoming
→ One goal with a date
→ Your first weekly Scorecard

Bring a pen. The Step 1 worksheet comes with your ticket, and the Meet link is emailed as soon as you pay. Can't make it live? Every ticket includes the recording.`,
    th: `Tomorrow, 7 PM Central: Fix Your Wednesday, live.

One hour. You leave with one sentence about the man you're becoming, one goal with a date, and your first Scorecard. Bring a pen.` }),
  B({ id: 'w3-tonight', type: 'reel', week: 3, slot: 'r2', time: '12pm', cta: 'workshop', title: 'Reel: Tonight, 7 PM — Fix Your Wednesday',
    reel: [['L:Tonight · 7 PM Central', 'B:Most men start Monday strong and *lose the week by Wednesday.*'], ['B:Tonight we *fix Wednesday.*'], ['L:You leave with', 'I:One sentence', 'I:One goal with a date', 'I:Your first Scorecard'], ['S:Bring a pen.', 'S:Can’t make it live?', 'B:The recording is *included.*']],
    endH: 'Fix Your Wednesday.\n*Tonight, 7 PM CT.*',
    cap: `Tonight, 7 PM Central. Live on Google Meet.

Most men start Monday strong and lose the week by Wednesday. Tonight we fix that together.

You leave with one sentence, one goal with a date, and your first Scorecard. Bring a pen.

Can't make it live? Every ticket includes the recording.`,
    th: `Tonight, 7 PM Central: Fix Your Wednesday.

One hour, live. You leave with one sentence, one goal with a date, and your first Scorecard. Recording included.` }),

  // ───────── WEEK 4 · Oct 26 – Nov 1 · Cut your goals down to three · group opens ─────────
  B({ id: 'w4-twelve-goals', type: 'reel', week: 4, slot: 'r1', cta: 'challengeOn', title: 'Reel: Twelve goals is zero goals',
    reel: [['B:You don’t have twelve goals.'], ['B:You have *zero goals* and twelve wishes.'], ['S:A goal gets a time.', 'S:A goal gets a miss.', 'S:A goal gets checked.'], ['L:This week', 'B:Cut it to *three.*', 'T:Cross out the rest. **Not forever. For now.**']],
    cap: `You don't have twelve goals. You have zero goals and twelve wishes.

A goal gets a time. It gets a written miss. It gets checked every week. You can't do that for twelve things.

Week 2 of the challenge: cut it to three. Cross out the rest. Not forever. For now.`,
    th: `You don't have twelve goals. You have zero goals and twelve wishes.

A goal gets a time, a written miss, and a weekly check. Nobody can do that for twelve things. Cut it to three.` }),
  B({ id: 'w4-three', type: 'post', week: 4, slot: 'p1', cta: 'group', title: 'Three goals: one for each place you lead',
    post: { label: 'Cut it to three', h: 'One for *your soul.*\nOne for *your house.*\nOne for *your work.*', body: 'Everything else waits. **Not forever. For now.**' },
    cap: `If you can only keep three goals, make them these:

→ One for your soul
→ One for your house
→ One for your work

Everything else waits. Not forever. For now.

Want to do this with other men, out loud, every Sunday? The 6-week live group starts Nov 15. Four seats.`,
    th: `If you can only keep three goals:

One for your soul.
One for your house.
One for your work.

Everything else waits. Not forever. For now.` }),
  B({ id: 'w4-cut-list', type: 'carousel', week: 4, slot: 'c', cta: 'challengeOn', title: 'Carousel: How to cut your goals to three',
    carousel: { label: 'Grab a pen · 15 minutes', h: 'How to cut your goals down to *three.*', body: 'The hardest part of discipline is **deciding what you won’t do.**',
      slides: [['Write *every* goal down.', 'All of them. The gym, the debt, the book, the business, the marriage. **Get them out of your head.**'], ['Circle the ones your *house* would notice.', 'If your wife and kids wouldn’t feel it by Christmas, it’s not first.'], ['Ask: which one *unlocks* others?', 'Sleep fixes the gym. Prayer fixes your temper. **Pick the domino.**'], ['Keep *three.*', 'One for your soul, one for your house, one for your work.'], ['Write the rest on a *later* list.', 'You’re not quitting them. **You’re scheduling them for after.**']],
      end: { pre: 'Week 2 of the free 7-week challenge.', h: 'Three goals.\n*Not twelve.*' } },
    cap: `How to cut your goals down to three (15 minutes, a pen):

1. Write every goal down. Get them out of your head.
2. Circle the ones your house would notice by Christmas.
3. Ask which one unlocks the others. Sleep fixes the gym. Prayer fixes your temper.
4. Keep three: soul, house, work.
5. Put the rest on a "later" list. You're not quitting them. You're scheduling them for after.

💾 Save this.`,
    th: `How to cut your goals to three:

1. Write every goal down
2. Circle what your house would notice
3. Pick the one that unlocks the others
4. Keep three: soul, house, work
5. Put the rest on a "later" list` }),
  B({ id: 'w4-group-seats', type: 'post', week: 4, slot: 'p2', cta: 'group', title: '6-week group: four seats',
    post: { label: 'Sundays · Nov 15 – Dec 20 · 7 PM CT', h: 'Four seats. *Six Sundays.*', body: 'A live group for husbands and fathers who are done doing this alone. **One hour a week, on Google Meet.**', btn: 'Reserve a seat → link in bio' },
    cap: `A 6-week live group for husbands and fathers.

Sundays, 7–8 PM Central, on Google Meet. November 15 to December 20. Four seats.

Six Sundays. One hour. The same men every week, so the miss has somewhere to go. You'll leave it with a system that held through the holidays instead of one that died in them.`,
    th: `A 6-week live group for husbands and fathers. Sundays, 7–8 PM Central, Nov 15 to Dec 20. Four seats.

The same men every week, so the miss has somewhere to go.` }),
  B({ id: 'w4-not-forever', type: 'reel', week: 4, slot: 'r2', cta: 'step1', title: 'Reel: Not forever. For now.',
    reel: [['S:The goal you crossed out', 'B:isn’t *dead.*'], ['B:It’s *waiting.*'], ['S:You can’t lead your soul, your house and your work', 'B:and *nine other things.*'], ['B:Not forever. *For now.*']],
    cap: `The goal you crossed out isn't dead. It's waiting.

You can't lead your soul, your house and your work and nine other things at once. Nobody can.

Three now. The rest later. Not forever. For now.`,
    th: `The goal you crossed out isn't dead. It's waiting.

You can't lead your soul, your house, your work and nine other things at once. Three now. The rest later. Not forever. For now.` }),

  // ───────── WEEK 5 · Nov 2–8 · Name the one thing that keeps stopping you ─────────
  B({ id: 'w5-one-thing', type: 'reel', week: 5, slot: 'r1', cta: 'group', title: 'Reel: It’s not ten things stopping you',
    reel: [['B:It’s not ten things *stopping you.*'], ['B:It’s *one.*', 'S:And you already know its name.'], ['L:Usually it’s', 'I:The phone after 9 PM', 'I:The drive home', 'I:The first “no” of the day'], ['B:Name it. Then give it a *plan.*']],
    cap: `It's not ten things stopping you. It's one. And you already know its name.

Usually it's the phone after 9 PM. Or the drive home, when you walk in already spent. Or the first "no" of the day, and you ride that mood till bedtime.

Name it. Write it down. Then give it a plan, not a promise.

Week 3 of the challenge is exactly this.`,
    th: `It's not ten things stopping you. It's one, and you already know its name.

The phone after 9 PM. The drive home. The first "no" of the day.

Name it. Then give it a plan, not a promise.` }),
  B({ id: 'w5-if-then', type: 'post', week: 5, slot: 'p1', cta: 'challengeOn', title: 'If ___ happens, then I will ___',
    post: { label: 'A plan, not a promise', h: 'If *this* happens,\nthen I will *that.*', body: '“If I walk in tired, **I sit in the car for two minutes and pray** before I open the door.” Decide it now, while you’re calm.' },
    cap: `Fill this in tonight:

If ______ happens, then I will ______.

"If I walk in tired, I sit in the car for two minutes and pray before I open the door."
"If I pick up my phone after 9, I put it on the kitchen counter and walk away."

Decide it now, while you're calm. Don't try to decide it in the moment.`,
    th: `Fill this in tonight: "If ___ happens, then I will ___."

"If I walk in tired, I sit in the car two minutes and pray before I open the door."

Decide it while you're calm, not in the moment.` }),
  B({ id: 'w5-doorway', type: 'carousel', week: 5, slot: 'c', cta: 'training', title: 'Carousel: The two minutes before you walk in the door',
    carousel: { label: 'Save this · try it tonight', h: 'The two minutes before you walk *in the door.*', body: 'Your family meets the man who gets out of the car. **Decide who that is.**',
      slides: [['Park. *Engine off.*', 'Don’t walk in mid-phone-call. Don’t walk in carrying the meeting.'], ['Name the *day.*', 'Out loud: “Today was heavy.” **Naming it keeps you from handing it to them.**'], ['Pray *one line.*', '“Lord, let them get the best of me, not the rest of me.”'], ['Decide the *first ten minutes.*', 'Who you hug first. What you ask. **Phone stays in the car.**'], ['Walk in *on purpose.*', 'Same door. Different man.']],
      end: { pre: 'Free 6-minute training:', h: 'Why you keep breaking *the same promise.*' } },
    cap: `The two minutes before you walk in the door decide your whole evening.

1. Park. Engine off. Don't walk in mid-call.
2. Name the day out loud. Naming it keeps you from handing it to them.
3. Pray one line: "Lord, let them get the best of me, not the rest of me."
4. Decide the first ten minutes. Who you hug first. What you ask. Phone stays in the car.
5. Walk in on purpose.

Same door. Different man.`,
    th: `Before you walk in the door tonight:

Park, engine off. Name the day out loud. Pray one line: "Lord, let them get the best of me, not the rest of me." Decide the first ten minutes. Phone stays in the car.

Same door. Different man.` }),
  B({ id: 'w5-group-week', type: 'post', week: 5, slot: 'p2', cta: 'group', title: 'The group: what happens on a Sunday',
    post: { label: '6-week live group · starts Nov 15', h: 'What happens on *a Sunday night.*', items: ['**7:00** · Everyone says done or missed. No speeches.', '**7:15** · One tool, worked live', '**7:40** · Each man sets next week’s one decision, with a time', '**8:00** · Done. Home with your family.'] },
    cap: `What happens in the 6-week group on a Sunday night:

7:00. Everyone says done or missed. No speeches.
7:15. One tool, worked live.
7:40. Each man sets next week's one decision, with a time.
8:00. Done. You're home with your family.

Nov 15 to Dec 20. Four seats.`,
    th: `What a Sunday in the 6-week group looks like:

7:00 done or missed, no speeches.
7:15 one tool, worked live.
7:40 next week's one decision, with a time.
8:00 home with your family.

Four seats. Starts Nov 15.` }),
  B({ id: 'w5-not-lazy', type: 'reel', week: 5, slot: 'r2', cta: 'step1', title: 'Reel: You’re not lazy',
    reel: [['B:You’re not *lazy.*'], ['S:You worked ten hours.', 'S:You fixed the sink.', 'S:You showed up for everyone.'], ['B:You’re *unplanned.*'], ['S:Lazy men don’t feel guilty.', 'B:You feel guilty because you *care.*', 'T:Give that care **a time.**']],
    cap: `You're not lazy.

You worked ten hours. You fixed the sink. You showed up for everybody.

You're unplanned. Lazy men don't feel guilty. You feel guilty because you care.

Give that care a time.`,
    th: `You're not lazy. You worked ten hours, fixed the sink, showed up for everyone.

You're unplanned. Lazy men don't feel guilty. You feel guilty because you care. Give that care a time.` }),

  // ───────── WEEK 6 · Nov 9–15 · Give one goal a day and a time · group last call ─────────
  B({ id: 'w6-this-week', type: 'reel', week: 6, slot: 'r1', cta: 'challengeOn', title: 'Reel: “This week” is not a time',
    reel: [['B:“This week” is not a *time.*'], ['S:“When things slow down”', 'S:“After the holidays”', 'S:“Once work calms down”'], ['B:None of those are on *a calendar.*'], ['L:Try this', 'B:*Tuesday. 6:10. Garage.*']],
    cap: `"This week" is not a time.

Neither is "when things slow down," "after the holidays" or "once work calms down." None of those are on a calendar.

Tuesday. 6:10. Garage. That's a time.

Week 4 of the challenge: give one goal a day and a time.`,
    th: `"This week" is not a time. Neither is "when things slow down" or "after the holidays."

Tuesday. 6:10. Garage. That's a time.` }),
  B({ id: 'w6-day-time', type: 'post', week: 6, slot: 'p1', cta: 'scorecard', title: 'A goal with no time is a wish',
    post: { label: 'Week 4 of 7', h: 'Give one goal *a day and a time.*', items: ['**Day:** Tuesday and Thursday', '**Time:** 6:10 AM', '**Place:** the garage', '**Miss:** two in a row'], body: '' },
    cap: `A goal with no time is a wish.

Pick one of your three and give it:
→ A day: Tuesday and Thursday
→ A time: 6:10 AM
→ A place: the garage
→ A miss: two in a row

Write it where you'll see it. That's what the Scorecard is for: four decisions, one page, every week.`,
    th: `A goal with no time is a wish.

Give one goal a day (Tue/Thu), a time (6:10), a place (the garage) and a miss (two in a row). Write it where you'll see it.` }),
  B({ id: 'w6-calendar', type: 'carousel', week: 6, slot: 'c', cta: 'challengeOn', title: 'Carousel: Put it on the calendar like a meeting',
    carousel: { label: 'Save this', h: 'Put your goal on the calendar like it’s *a meeting with your boss.*', body: 'You don’t skip those. **Why skip this one?**',
      slides: [['Block it *in ink.*', 'A real calendar event. Name, time, place. **Not a reminder. A meeting.**'], ['Make it *small.*', '20 minutes you’ll keep beats 90 you won’t.'], ['Protect it like *a client.*', '“I have something at 6:10” is a full sentence.'], ['Tell *one person.*', 'Your wife or a brother. **Someone who will ask.**'], ['Review it *Sunday.*', 'Did it happen? If not, change the time. **Don’t change the goal.**']],
      end: { pre: 'Week 4 of the free 7-week challenge.', h: 'A day. A time.\n*A meeting.*' } },
    cap: `Put your goal on the calendar like it's a meeting with your boss. You don't skip those.

1. Block it in ink. Name, time, place.
2. Make it small. 20 minutes you'll keep beats 90 you won't.
3. Protect it like a client. "I have something at 6:10" is a full sentence.
4. Tell one person who will ask.
5. Review it Sunday. If it didn't happen, change the time, not the goal.`,
    th: `Put your goal on the calendar like a meeting with your boss.

Block it in ink. Make it small. Protect it like a client. Tell one person. Review Sunday: if it didn't happen, change the time, not the goal.` }),
  B({ id: 'w6-last-call', type: 'post', week: 6, slot: 'p2', cta: 'group', title: 'Group starts tomorrow',
    post: { label: 'Starts tomorrow · Sun Nov 15 · 7 PM CT', h: 'The holidays are where *systems go to die.*', body: 'Six Sundays, Nov 15 to Dec 20. **Come out of December with your system still standing.**', btn: 'Last seats → link in bio' },
    cap: `The holidays are where systems go to die. Travel, family, food, late nights, no routine.

The 6-week group runs right through them: six Sundays, Nov 15 to Dec 20, 7–8 PM Central.

Come out of December with your system still standing, and with men who watched you keep it.

Starts tomorrow.`,
    th: `The holidays are where systems go to die.

The 6-week group runs right through them, Sundays Nov 15 to Dec 20. Come out of December with your system still standing. Starts tomorrow.` }),
  B({ id: 'w6-small', type: 'reel', week: 6, slot: 'r2', cta: 'step1', title: 'Reel: Smaller than you think',
    reel: [['B:Make it smaller than *your pride* wants.'], ['S:Not an hour at the gym.', 'B:*Twenty pushups.*'], ['S:Not a chapter a day.', 'B:*One psalm.*'], ['B:Kept small beats *broken big.*']],
    cap: `Make it smaller than your pride wants.

Not an hour at the gym. Twenty pushups.
Not a chapter a day. One psalm.
Not a weekly date night. Ten minutes on the porch after the kids are down.

Kept small beats broken big. Every time.`,
    th: `Make it smaller than your pride wants.

Not an hour at the gym: twenty pushups. Not a chapter a day: one psalm.

Kept small beats broken big. Every time.` }),

  // ───────── WEEK 7 · Nov 16–22 · Write down what counts as a miss · Club ─────────
  B({ id: 'w7-miss', type: 'reel', week: 7, slot: 'r1', cta: 'challengeOn', title: 'Reel: Define the miss before it happens',
    reel: [['B:Decide what a miss is *before* you miss.'], ['S:Otherwise one bad day', 'B:becomes *“I’m just not that guy.”*'], ['L:Write it down', 'I:One miss: normal', 'I:Two in a row: change the time', 'I:Three: tell a brother'], ['B:A miss is *information.* Not a verdict.']],
    cap: `Decide what a miss is before you miss.

Otherwise one bad day turns into "I'm just not that guy," and you quit.

One miss: normal.
Two in a row: change the time.
Three: tell a brother.

A miss is information, not a verdict. Week 5 of the challenge.`,
    th: `Decide what a miss is before you miss, or one bad day becomes "I'm just not that guy."

One miss: normal. Two in a row: change the time. Three: tell a brother.

A miss is information, not a verdict.` }),
  B({ id: 'w7-club', type: 'post', week: 7, slot: 'p1', cta: 'club', title: 'The Club: $19 a month',
    post: { label: 'The Be The Man Club', h: 'A new tool *every month.*\n$19.', items: ['**Every tool in the store**, the day you join', '**A new tool each month**, Club-only', '**One email a week:** a time, a trigger, a way to tell if it held'], body: '' },
    cap: `The Be The Man Club. $19 a month.

→ Every tool in the store, the day you join
→ A new tool each month, Club-only
→ One email a week: a time, a trigger, a way to tell if it held

No group chat. No badges. Cancel anytime; the files are yours to keep.`,
    th: `The Be The Man Club: every tool in the store, a new one each month, and one email a week with a time and a trigger. $19 a month. Cancel anytime, keep the files.` }),
  B({ id: 'w7-miss-plan', type: 'carousel', week: 7, slot: 'c', cta: 'scorecard', title: 'Carousel: Your miss plan',
    carousel: { label: 'Write this before Monday', h: 'Your *miss plan.*', body: 'What you’ll do when it doesn’t happen, **decided while you’re calm.**',
      slides: [['Name the *goal.*', 'One sentence. “Pray at 6:10 in the same chair.”'], ['Define *one* miss.', '“Didn’t happen by 7:00.” **Specific, so you can’t argue with it.**'], ['Decide the *bounce-back.*', '“If I miss the morning, I pray in the car at lunch.”'], ['Set the *two-miss rule.*', 'Two in a row means the time is wrong. **Change the time, not the goal.**'], ['Pick the *brother.*', 'Three misses, he hears about it. From you, first.']],
      end: { pre: 'The Weekly Scorecard has a miss written on every line.', h: 'Your week,\n*on one page.*' } },
    cap: `Your miss plan. Write it before Monday:

1. Name the goal in one sentence.
2. Define one miss specifically, so you can't argue with it.
3. Decide the bounce-back: "If I miss the morning, I pray in the car at lunch."
4. Two in a row means the time is wrong. Change the time, not the goal.
5. Three misses, your brother hears about it, from you first.`,
    th: `Write your miss plan before Monday:

Name the goal. Define one miss. Decide the bounce-back. Two in a row = wrong time; change the time, not the goal. Three misses, your brother hears it from you first.` }),
  B({ id: 'w7-name-it', type: 'post', week: 7, slot: 'p2', cta: 'club', title: 'Name the miss before she has to',
    post: { pre: 'The fastest way to rebuild trust at home:', h: 'Name the miss *before she has to.*', body: '“I said I’d be off my phone by 9. **I wasn’t. Tomorrow I will.**” That’s it. No speech.' },
    cap: `The fastest way to rebuild trust at home: name the miss before she has to.

"I said I'd be off my phone by 9. I wasn't. Tomorrow I will."

That's it. No speech, no excuses, no making her the bad guy for noticing.

A man who names his own misses is a man his wife can stop keeping score on.`,
    th: `The fastest way to rebuild trust at home: name the miss before she has to.

"I said I'd be off my phone by 9. I wasn't. Tomorrow I will."

No speech. No excuses.` }),
  B({ id: 'w7-verdict', type: 'reel', week: 7, slot: 'r2', cta: 'step1', title: 'Reel: Information, not a verdict',
    reel: [['S:You missed Tuesday.'], ['S:The enemy says:', 'B:“See? *You never change.*”'], ['S:The Scorecard says:', 'B:“Tuesday at 6 doesn’t work. *Try 9 PM.*”'], ['B:Listen to the one that *helps you.*']],
    cap: `You missed Tuesday.

The enemy says: "See? You never change."
The Scorecard says: "Tuesday at 6 doesn't work. Try 9 PM."

One of those is a verdict. One is information. Listen to the one that helps you.`,
    th: `You missed Tuesday.

The enemy says, "See? You never change."
The Scorecard says, "Tuesday at 6 doesn't work. Try 9 PM."

Listen to the one that helps you.` }),

  // ───────── WEEK 8 · Nov 23–29 · Count it honestly · Thanksgiving ─────────
  B({ id: 'w8-count', type: 'reel', week: 8, slot: 'r1', cta: 'challengeOn', title: 'Reel: Count it honestly',
    reel: [['B:Count it *honestly.*'], ['S:Not how you felt about the week.', 'B:How many times it *actually happened.*'], ['L:This month', 'I:Prayer: 14 of 20', 'I:Phone down by 9: 9 of 20', 'I:Kids’ bedtime: 17 of 20'], ['B:That’s not failure. That’s *a starting line.*']],
    cap: `Count it honestly. Not how you felt about the month. How many times it actually happened.

Prayer: 14 of 20.
Phone down by 9: 9 of 20.
Kids' bedtime: 17 of 20.

That's not failure. That's a starting line. And it's more than "I'm doing better, I think."

Week 6 of the challenge.`,
    th: `Count it honestly. Not how you felt about the month. How many times it actually happened.

Prayer 14 of 20. Phone down by 9: 9 of 20.

That's not failure. That's a starting line.` }),
  B({ id: 'w8-husband-kit', type: 'post', week: 8, slot: 'p1', cta: 'husbandKit', title: 'Husband Kit: before the holidays',
    post: { label: 'Before the holidays', h: 'Lead your marriage on purpose *this December.*', body: 'The Husband Kit: the tools for leading your marriage, **in one download. $39.**' },
    cap: `December is loud. Travel, family, money, schedules. Marriages don't usually break in December. They drift.

Lead yours on purpose this year. The Husband Kit puts the tools for leading your marriage in one download.`,
    th: `Marriages don't usually break in December. They drift.

Travel, family, money, schedules. Lead yours on purpose this year.` }),
  B({ id: 'w8-thanks', type: 'carousel', week: 8, slot: 'c', cta: 'step1', title: 'Carousel: Thanksgiving: say it out loud',
    carousel: { label: 'Happy Thanksgiving', h: 'Five people to *thank out loud* today.', body: 'Gratitude you don’t say is just **a nice thought you kept.**',
      slides: [['Your *wife.*', 'Specific. “Thank you for how you handled Tuesday.” **Not “thanks for everything.”**'], ['Each *child.*', 'One thing you saw them do this year. **In front of everyone.**'], ['The man who *raised you.*', 'Or the one who should have, and the one who stepped in.'], ['A *brother.*', 'The one who texted “done or missed?” Tell him it mattered.'], ['*God.*', 'Before the plate. Out loud. Your kids are listening to how you pray.']],
      end: { pre: 'Grateful men are still building.', h: 'Start with *Step 1.*' } },
    cap: `Five people to thank out loud today:

1. Your wife. Be specific. "Thank you for how you handled Tuesday."
2. Each child. One thing you saw them do this year, in front of everyone.
3. The man who raised you, or the one who stepped in.
4. A brother who kept you honest this year.
5. God. Before the plate, out loud. Your kids are listening to how you pray.

Gratitude you don't say is just a nice thought you kept. Happy Thanksgiving.`,
    th: `Five people to thank out loud today: your wife (specifically), each child (in front of everyone), the man who raised you, a brother who kept you honest, and God, before the plate, out loud.

Happy Thanksgiving.` }),
  B({ id: 'w8-father-kit', type: 'post', week: 8, slot: 'p2', cta: 'fatherKit', title: 'Father Kit: they’re home for the holidays',
    post: { label: 'They’re home all month', h: 'Your kids won’t remember *the gifts.*', sub: 'They’ll remember whether you were in the room.', body: 'The Father Kit: tools for leading your kids, **one download, $29.**' },
    cap: `The kids are home all month. They won't remember most of the gifts. They'll remember whether you were in the room, and whether the room felt safe when you were.

The Father Kit gives you the tools for leading them on purpose: the conversations, the plan, the questions.`,
    th: `Your kids won't remember most of the gifts.

They'll remember whether you were in the room, and whether the room felt safe when you were in it.` }),
  B({ id: 'w8-more-than', type: 'reel', week: 8, slot: 'r2', cta: 'challengeOn', title: 'Reel: More than “I think I’m doing better”',
    reel: [['S:“I think I’m doing better.”'], ['B:You *think?*'], ['S:A man who counts', 'B:*knows.*'], ['B:Count it. Then *thank God* for every one.']],
    cap: `"I think I'm doing better."

You think?

A man who counts knows. Fourteen of twenty isn't perfect. It's fourteen mornings you showed up that you would have forgotten about.

Count it. Then thank God for every one.`,
    th: `"I think I'm doing better." You think?

A man who counts knows. Fourteen of twenty isn't perfect. It's fourteen mornings you'd have forgotten. Count it, then thank God for every one.` }),

  // ───────── WEEK 9 · Nov 30 – Dec 6 · Put God at the center · Faith Kit ─────────
  B({ id: 'w9-center', type: 'reel', week: 9, slot: 'r1', cta: 'faithKit', title: 'Reel: God isn’t goal number four',
    reel: [['B:God isn’t *goal number four.*'], ['S:He’s not on the list.', 'B:He’s the reason *for the list.*'], ['L:Ask of every goal', 'I:Does this make me more like Him?', 'I:Does my house get the better man?'], ['B:If not, *cut it.*']],
    cap: `God isn't goal number four on your list. He's the reason for the list.

Ask it of every goal you kept:
→ Does this make me more like Him?
→ Does my house get the better man because of it?

If not, cut it. Week 7 of the challenge: put God at the center of it.`,
    th: `God isn't goal number four on your list. He's the reason for the list.

Ask every goal: does this make me more like Him? Does my house get the better man? If not, cut it.` }),
  B({ id: 'w9-seek', type: 'post', week: 9, slot: 'p1', cta: 'step1', title: 'Seek first — with a time attached',
    post: { label: 'Matthew 6:33', h: 'Seek first.\n*Then* schedule.', body: 'If He’s first, **He gets the first slot**, not the one left over after the phone.' },
    cap: `"But seek first his kingdom and his righteousness, and all these things will be given to you as well." Matthew 6:33

Seek first. Then schedule.

If He's first, He gets the first slot of the day, not the one left over after the phone, the news and the email.

What's the first thing you touch tomorrow morning?`,
    th: `"Seek first his kingdom." Matthew 6:33

If He's first, He gets the first slot of the day, not the one left over after the phone, the news and the email.

What's the first thing you touch tomorrow?` }),
  B({ id: 'w9-faith-routine', type: 'carousel', week: 9, slot: 'c', cta: 'faithKit', title: 'Carousel: A 15-minute morning with God',
    carousel: { label: 'Save this · try it tomorrow', h: 'A 15-minute morning *with God.*', body: 'Not a mood. **A time, a place and a plan.**',
      slides: [['*2 min* · Be still.', 'Same chair. Phone in another room. **Just breathe and show up.**'], ['*5 min* · One passage.', 'A psalm or a few verses. **Read it twice, slowly.**'], ['*3 min* · One line to keep.', 'Write down the one sentence that stopped you.'], ['*3 min* · Pray it back.', 'For your wife, your kids, your work. **By name.**'], ['*2 min* · One decision.', 'What will you do differently today because of what you read?']],
      end: { pre: 'The Faith Kit: prayer, Scripture and discipleship tools with a time attached.', h: 'Put God *first.*\nOn purpose.' } },
    cap: `A 15-minute morning with God. Save this and try it tomorrow:

2 min: be still. Same chair, phone in another room.
5 min: one passage. Read it twice, slowly.
3 min: write down the one line that stopped you.
3 min: pray it back for your wife, your kids, your work, by name.
2 min: one decision. What changes today because of what you read?

Not a mood. A time, a place and a plan.`,
    th: `A 15-minute morning with God:

2 min be still. 5 min one passage, read twice. 3 min write the line that stopped you. 3 min pray it back, by name. 2 min one decision for today.

A time, a place, a plan.` }),
  B({ id: 'w9-pray-for-her', type: 'post', week: 9, slot: 'p2', cta: 'challengeOn', title: 'Pray for her by name',
    post: { pre: 'When was the last time your wife', h: 'heard you pray *for her*, by name?', body: 'Not over dinner. Not in general. **Her name, her day, her worries**, out loud.' },
    cap: `When was the last time your wife heard you pray for her, by name?

Not over dinner. Not "bless this family." Her name, her day, the thing she's worried about, out loud, with your hand on her shoulder.

Thirty seconds. Tonight.`,
    th: `When was the last time your wife heard you pray for her, by name?

Not "bless this family." Her name, her day, the thing she's worried about. Out loud. Thirty seconds. Tonight.` }),
  B({ id: 'w9-priest', type: 'reel', week: 9, slot: 'r2', cta: 'step1', title: 'Reel: Your kids learn God from your Tuesday',
    reel: [['S:Your kids will learn who God is', 'B:from how you act on *a Tuesday.*'], ['S:Not from Sunday.', 'B:From the *drive home.*'], ['B:From how you speak to *their mother.*'], ['B:Show them a God who *keeps His word.*', 'T:**Keep yours.**']],
    cap: `Your kids will learn who God is from how you act on a Tuesday.

Not just from Sunday. From the drive home. From how you speak to their mother when you're tired. From whether you keep your word.

Show them a God who keeps His word. Keep yours.`,
    th: `Your kids will learn who God is from how you act on a Tuesday.

From the drive home. From how you speak to their mother when you're tired.

Show them a God who keeps His word. Keep yours.` }),

  // ───────── WEEK 10 · Dec 7–13 · Fatherhood & legacy · gifts ─────────
  B({ id: 'w10-presence', type: 'reel', week: 10, slot: 'r1', cta: 'fatherKit', title: 'Reel: They want you, not the gift',
    reel: [['S:Your son doesn’t want the gift', 'B:as much as he wants *you.*'], ['S:Ten minutes.', 'S:No phone.', 'B:*His* topic.'], ['B:Do that every day this month and you’ll give him *five hours.*']],
    cap: `Your son doesn't want the gift as much as he wants you.

Ten minutes. No phone. His topic, not yours.

Do that every day in December and you'll give him five hours of a father who was all the way there. He'll remember that longer than anything under the tree.`,
    th: `Your son doesn't want the gift as much as he wants you.

Ten minutes a day, no phone, his topic. Every day in December is five hours of a father who was all the way there.` }),
  B({ id: 'w10-legacy', type: 'post', week: 10, slot: 'p1', cta: 'step1', title: 'Legacy is a Tuesday',
    post: { h: 'Legacy isn’t a speech at your funeral.\n*It’s a Tuesday.*', body: 'It’s what your kids watched you do **when nobody was clapping.**' },
    cap: `Legacy isn't a speech at your funeral. It's a Tuesday.

It's what your kids watched you do when nobody was clapping. How you answered the phone when it was their mother. Whether you came home when you said you would.

You're writing it this week whether you mean to or not.`,
    th: `Legacy isn't a speech at your funeral. It's a Tuesday.

It's what your kids watched you do when nobody was clapping. You're writing it this week whether you mean to or not.` }),
  B({ id: 'w10-questions', type: 'carousel', week: 10, slot: 'c', cta: 'library', title: 'Carousel: 5 questions to ask your kids this month',
    carousel: { label: 'Ask one a night', h: '5 questions to ask your kids *this December.*', body: 'Better than “How was school?” **Every one of them.**',
      slides: [['“What was the *best* part of your year?”', 'Then stop talking. **Let the silence work.**'], ['“What’s something you wish I *knew* about you?”', 'Don’t correct. Don’t fix. **Just thank them.**'], ['“When do you feel *closest* to me?”', 'Whatever they say, do more of that.'], ['“What’s something *hard* right now?”', 'Ask in the car. **Side by side is easier than face to face.**'], ['“What should *we* do more of next year?”', 'Write it down where they can see you write it.']],
      end: { pre: 'All three card decks, the Father’s Field Guide and the rest:', h: 'The Complete Library.\n*All 11 tools.*' } },
    cap: `5 questions to ask your kids this December, one a night:

1. "What was the best part of your year?"
2. "What's something you wish I knew about you?"
3. "When do you feel closest to me?"
4. "What's something hard right now?" (Ask it in the car. Side by side is easier.)
5. "What should we do more of next year?"

Then stop talking. Let the silence work.`,
    th: `5 questions to ask your kids this month:

"What was the best part of your year?"
"What do you wish I knew about you?"
"When do you feel closest to me?"
"What's hard right now?"
"What should we do more of next year?"` }),
  B({ id: 'w10-gift', type: 'post', week: 10, slot: 'p2', cta: 'clubYear', title: 'A gift that’s still working in March',
    post: { label: 'For the man who has everything', h: 'Give him a gift that’s still working *in March.*', body: 'The Be The Man Club, yearly. **Twelve months of tools. $149.**' },
    cap: `For the man in your life who says he doesn't need anything:

Give him a gift that's still working in March. The Be The Man Club, yearly: twelve months of tools, a new one every month, and one email a week with a time and a trigger.`,
    th: `For the man who says he doesn't need anything: give him a gift that's still working in March.

Twelve months of tools, one email a week with a time and a trigger.` }),
  B({ id: 'w10-cycle', type: 'reel', week: 10, slot: 'r2', cta: 'training', title: 'Reel: The cycle stops with you',
    reel: [['S:Some of us didn’t have a father', 'B:who *came home.*'], ['S:Some of us had one who came home', 'B:but never *came in.*'], ['B:The cycle stops *with you.*'], ['B:Not with a promise.\n*With a system.*']],
    cap: `Some of us didn't have a father who came home. Some of us had one who came home but never came in.

The cycle stops with you. Not with a promise you'll forget by February. With a system your kids can see working on an ordinary Tuesday.

Break the cycle. Build the system. Be the man.`,
    th: `Some of us didn't have a father who came home. Some had one who came home but never came in.

The cycle stops with you. Not with a promise. With a system your kids can see working.` }),

  // ───────── WEEK 11 · Dec 14–20 · Christmas: presence over presents ─────────
  B({ id: 'w11-presence', type: 'reel', week: 11, slot: 'r1', cta: 'step1', title: 'Reel: Present, not just there',
    reel: [['B:There’s a difference between *there* and *present.*'], ['S:There: on the couch, on the phone.', 'B:Present: *on the floor.*'], ['L:This week', 'I:Phone in a drawer after dinner', 'I:One game they pick', 'I:One prayer at bedtime, by name'], ['B:Be *present.*']],
    cap: `There's a difference between there and present.

There: on the couch, on the phone, nodding.
Present: on the floor, playing the game they picked.

This week: phone in a drawer after dinner. One game they pick. One prayer at bedtime, by name.`,
    th: `There's a difference between there and present.

There: on the couch, on the phone. Present: on the floor, playing the game they picked.

Phone in a drawer after dinner this week.` }),
  B({ id: 'w11-husband', type: 'post', week: 11, slot: 'p1', cta: 'husbandKit', title: 'Who’s carrying Christmas?',
    post: { label: 'Honest question', h: 'Who’s carrying Christmas *in your house?*', body: 'The list, the gifts, the cooking, the family. **Pick up three things off her list tonight.** Without being asked.' },
    cap: `Honest question: who's carrying Christmas in your house?

The list. The gifts. The cooking. The family calls. The teacher gifts. The schedule.

Pick up three things off her list tonight, without being asked, and don't announce it. That's leadership.`,
    th: `Honest question: who's carrying Christmas in your house?

Pick up three things off her list tonight. Without being asked. Without announcing it. That's leadership.` }),
  B({ id: 'w11-christmas-plan', type: 'carousel', week: 11, slot: 'c', cta: 'clubYear', title: 'Carousel: A Christmas week plan for fathers',
    carousel: { label: 'Christmas week', h: 'A Christmas week plan *for fathers.*', body: 'Five decisions, made **before** the house gets loud.',
      slides: [['Read the *story* yourself.', 'Luke 2, out loud, before presents. **Dad reads. Kids hear.**'], ['One *kid* at a time.', '20 minutes alone with each child this week. **Their pick.**'], ['Protect *her* morning.', 'You handle breakfast and the first round of chaos. **She sits with coffee.**'], ['Decide your *temper* now.', 'When the family gets loud, you step outside for two minutes. **Decided today.**'], ['End with *thanks.*', 'Last thing Christmas night: each person says one thing they’re thankful for.']],
      end: { pre: 'Give a gift that lasts past January:', h: 'The Club, yearly.\n*$149.*' } },
    cap: `A Christmas week plan for fathers, made before the house gets loud:

1. Read Luke 2 out loud yourself, before presents.
2. 20 minutes alone with each child this week. Their pick.
3. Protect her morning. You handle breakfast; she sits with coffee.
4. Decide your temper now. When it gets loud, you step outside for two minutes.
5. End Christmas night with each person saying one thing they're thankful for.

💾 Save this.`,
    th: `A Christmas week plan for fathers:

Read Luke 2 out loud before presents. 20 minutes alone with each child. Protect her morning. Decide your temper now. End the night with thanks, one each.` }),
  B({ id: 'w11-call', type: 'post', week: 11, slot: 'p2', cta: 'call', title: 'Stuck? 15 minutes',
    post: { label: 'Before the year ends', h: 'Where are you *stuck?*', body: 'Fifteen minutes on the phone with me. **No pitch. Just where you are and one next step.**' },
    cap: `Before the year ends: where are you stuck?

Your marriage. Your temper. Your faith. The same promise you've made every January.

Book a free 15-minute call with me. No pitch. We'll name where you are and one next step, and you'll leave with a time on it.`,
    th: `Before the year ends: where are you stuck? Your marriage, your temper, your faith, the same January promise.

15 minutes, free. We'll name one next step with a time on it.` }),
  B({ id: 'w11-silent-night', type: 'reel', week: 11, slot: 'r2', cta: 'step1', title: 'Reel: The best gift is a calm father',
    reel: [['B:The best gift under the tree is a *calm father.*'], ['S:Not a perfect one.', 'S:Not a rich one.'], ['B:One who doesn’t make the house *hold its breath.*'], ['B:Be the reason it feels like *peace.*']],
    cap: `The best gift under the tree this year is a calm father.

Not a perfect one. Not a rich one. One who doesn't make the house hold its breath when he walks in.

Be the reason your home feels like peace this Christmas.`,
    th: `The best gift under the tree is a calm father.

Not a perfect one. Not a rich one. One who doesn't make the house hold its breath when he walks in.` }),

  // ───────── WEEK 12 · Dec 21–27 · Before the New Year's promise ─────────
  B({ id: 'w12-before', type: 'reel', week: 12, slot: 'r1', cta: 'step1', title: 'Reel: Before you make the New Year’s promise',
    reel: [['B:Before you make the *New Year’s* promise.'], ['S:You made it last year.', 'S:And the year before.', 'B:You meant it *every time.*'], ['B:This year, start with *Step 1.*', 'T:What type of man do you want to be?'], ['B:Then give it *a time.*']],
    cap: `Before you make the New Year's promise again:

You made it last year. And the year before. You meant it every time.

This year, start before the promise. Step 1 is one question: what type of man do you want to be? Twenty minutes, a pen, one sentence.

Then give it a time.`,
    th: `Before you make the New Year's promise again: you made it last year, and the year before, and meant it every time.

This year, start before the promise. One question: what type of man do you want to be?` }),
  B({ id: 'w12-scorecard', type: 'post', week: 12, slot: 'p1', cta: 'scorecard', title: 'Start January with one page',
    post: { label: 'Start January with one page', h: 'Four decisions.\nFour times.\n*Four misses.*', body: 'The Weekly Scorecard: your week, on one page. **$7. Print it before the 1st.**' },
    cap: `Start January with one page, not a new personality.

Four decisions. Each with a time. Each with a miss written down before the week starts. Filled in the day it happens, not from memory on Sunday night.

The Weekly Scorecard: $7. Print it before the 1st.`,
    th: `Start January with one page, not a new personality.

Four decisions, each with a time and a written miss. Filled in the day it happens.` }),
  B({ id: 'w12-review', type: 'carousel', week: 12, slot: 'c', cta: 'step1', title: 'Carousel: Your year-end review in 30 minutes',
    carousel: { label: 'Between Christmas and New Year', h: 'Your year-end review *in 30 minutes.*', body: 'Before you plan 2027, **look honestly at 2026.**',
      slides: [['What did I *keep?*', 'Write every promise you actually kept, even small. **Thank God for each one.**'], ['What did I *drop?*', 'No shame. Just a list. **What fell first, and when?**'], ['Where did it *die?*', 'Usually the same place: Wednesday, the drive home, after 9 PM.'], ['What would my *house* say?', 'Ask her. Ask the kids. **“What was different about me this year?”**'], ['One sentence for *2027.*', 'Who you’re becoming. Not a goal. **A man.**']],
      end: { pre: 'The sentence comes first.', h: 'Start 2027\nwith *Step 1.*' } },
    cap: `Your year-end review in 30 minutes, somewhere between Christmas and New Year's:

1. What did I keep? Even small things. Thank God for each.
2. What did I drop? No shame, just a list.
3. Where did it die? Usually the same place every time.
4. What would my house say? Ask them: "What was different about me this year?"
5. One sentence for 2027. Not a goal. A man.

💾 Save this.`,
    th: `Year-end review in 30 minutes:

What did I keep? What did I drop? Where did it die? What would my house say was different about me? Then one sentence for 2027. Not a goal. A man.` }),
  B({ id: 'w12-call', type: 'post', week: 12, slot: 'p2', cta: 'call', title: 'Don’t start 2027 alone',
    post: { pre: 'Every January you start over alone.', h: 'Not this year.', body: '**Fifteen minutes, free.** We’ll name where you are and one decision with a time on it.' },
    cap: `Every January you start over, and you start alone.

Not this year. Book a free 15-minute call with me before the 1st. We'll name where you are, what keeps stopping you, and one decision with a time on it.`,
    th: `Every January you start over, and you start alone.

Not this year. 15 minutes, free, before the 1st. One decision with a time on it.` }),
  B({ id: 'w12-year', type: 'reel', week: 12, slot: 'r2', cta: 'step1', title: 'Reel: Next year, same man?',
    reel: [['S:A year from now', 'B:will your house meet *the same man?*'], ['S:Same temper.', 'S:Same phone.', 'S:Same promise.'], ['B:Or the man you wrote down in *one sentence?*'], ['B:Break the cycle.\nBuild the system.\n*Be the man.*']],
    endH: 'Happy New Year.\n*Be the man.*',
    cap: `A year from now, will your house meet the same man? Same temper, same phone, same promise?

Or the man you wrote down in one sentence, and then gave a time?

Break the cycle. Build the system. Be the man. Happy New Year, brothers.`,
    th: `A year from now, will your house meet the same man? Same temper, same phone, same promise?

Or the one you wrote down in one sentence and then gave a time? Happy New Year, brothers.` }),
];
