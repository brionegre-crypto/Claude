// Default lessons, materials and starter examples for the men's portal.
// Brian edits them in the dashboard (Library); his version is saved in KV ("lessons") and
// any field he hasn't edited falls back to this file.
//
// Each lesson is a guided week:
//   intro       what this week is for (one or two sentences)
//   scripture   the reference; verse: the text (KJV)
//   body        the teaching. Blank line = new paragraph, **bold**, "- " list, [[Button|link]]
//   learn       two short boxes on the research behind it ({t, b})
//   adhd        one ADHD concept ({t, b}); tool: one practical tool ({t, b})
//   action      the week's checkbox; reflection + questions: what he answers in the portal
//   prayer      a short prayer
//   days        seven days, each {t: title, do: one thing to do, q: one question to answer}
// Scripture is quoted from the King James Version.

const SITE = "https://bethemansystem.com";

export const LESSONS = [
  {
    id: "w1", week: 1, step: 1, title: "The Calling: who has God called you to be?", video: "",
    intro: "This week you don't fix anything. You write down who you are called to be, so the rest of the system has something to answer to.",
    scripture: "Habakkuk 2:2",
    verse: "Write the vision, and make it plain upon tables, that he may run that readeth it.",
    body: `Most men start with goals. Read more. Work out. Be home more. Pray every morning. That's why the goals don't hold. A goal with no man behind it is a wish with a date on it. The first hard week takes it, and then we tell ourselves we're the kind of man who never follows through.

So we start underneath the goals. Not "what do I want to do?" but "who has God called me to be?" in the roles I already carry: son of God, husband or future husband, father or future father, son, worker, brother.

Notice two things in Habakkuk 2:2. The vision is **written**, not remembered. And it's **plain**, plain enough that a man can run with it. For a brain like ours, that isn't a small detail. You don't need more conviction. You've had conviction in church, in the truck, at 2 AM. What you need is the vision outside your head, where you can see it on a Tuesday when the conviction is gone.

**How Step 1 works**

- List your roles. Start with the one under all the others: a son of God. Everything else rests on that.
- For each role, ask, "What does God expect of me here?" Answer from Scripture, not from guilt or from what your father did or didn't do.
- Make it a Tuesday. What does faithful look like on an ordinary day in that role? What's the smallest version on a bad day?
- Write one sentence: "I am a man who ___, so that ___."

The "so that" matters. It names who your faithfulness is for. "I am a man who keeps his word, so that my house can lean on my yes."

Every part of your sentence should be something someone in your house could notice without being told. If your wife or your kids couldn't see it, it's a feeling, not a calling yet.

Don't make it pretty. Make it true. You will revise it. Week 6 is literally a reset. But you can't revise a sentence you never wrote.`,
    learn: [
      { t: "Why writing it down matters", b: "Russell Barkley, one of the leading ADHD researchers, describes ADHD as a problem of doing what you know, not knowing what to do. His advice is to put information at the \"point of performance\": the place and moment where the behavior has to happen. A calling that lives only in your memory isn't there at 6 PM on a Wednesday. A sentence on your lock screen is." },
      { t: "Identity drives behavior", b: "Psychologists Hazel Markus and Paula Nurius (1986) described \"possible selves\": clear pictures of who we could become that guide what we do now. Daryl Bem's self-perception theory adds the other half: we learn who we are partly by watching what we do. Your sentence gives your actions a direction, and your actions slowly make the sentence believable." },
    ],
    adhd: { t: "Working memory", b: "The mental notepad that holds information for a few seconds while you use it. In ADHD this notepad is often smaller or less reliable, which is why good intentions disappear between church and Monday. The fix is not trying harder to remember. It's writing it down where you'll see it." },
    tool: { t: "The lock-screen sentence", b: "Once your sentence is written, make it your phone's lock screen, or tape it to your bathroom mirror or truck visor. Pick the place your eyes already go twenty times a day. Read it once, out loud, each morning this week." },
    action: "Write your sentence and put it where your eyes already go: your lock screen, mirror or truck visor.",
    reflection: "Which role was hardest to write about, and why?",
    questions: ["Read your sentence out loud. Which part do you most believe, and which part do you least believe right now?", "Who in your house would notice first if you lived this sentence for a month? What would they see?"],
    prayer: "Father, I've carried a lot of plans and dropped most of them. Show me who You've called me to be, and make it plain enough that I can run with it.",
    days: [
      { t: "Name your roles", do: "List every role you carry, starting with son of God. Don't write anything else yet.", q: "Which roles did you list? Which one do you think about least?" },
      { t: "What God expects", do: "For two of your roles, write what God expects of you there. Use a verse for each if you can.", q: "Which expectation did you find in Scripture that surprised you?" },
      { t: "Make it a Tuesday", do: "For each role, write what faithful looks like on an ordinary weekday, and the smallest version on a bad day.", q: "What's one thing in your Tuesday that would change if you lived this role well?" },
      { t: "Draft the sentence", do: "Write a rough draft: \"I am a man who ___, so that ___.\" Don't polish it.", q: "Write your first draft here, exactly as it came out." },
      { t: "The kitchen-table test", do: "Read your sentence and ask of each part: could someone in my house see this without being told? Cut or change what fails.", q: "What did you cut or change, and why?" },
      { t: "Put it where you look", do: "Put your sentence on your lock screen, mirror or visor. Read it out loud this morning and tonight.", q: "Where did you put it? How did it feel to read it out loud?" },
      { t: "Send it to Brian", do: "Finish Step 1 in your portal and send it to Brian. Bring your sentence to Thursday's call.", q: "What do you want to ask about your sentence on Thursday?" },
    ],
  },
  {
    id: "w2", week: 2, step: 2, title: "The Commitments: three you can check", video: "",
    intro: "This week your sentence becomes no more than three commitments, each one a yes or no you can check.",
    scripture: "Matthew 5:37",
    verse: "But let your communication be, Yea, yea; Nay, nay: for whatsoever is more than these cometh of evil.",
    body: `Jesus is talking about keeping your word. Let your yes mean yes. Here's the problem most of us live with: a commitment you can't check is a word you can't keep, because nobody, including you, can tell whether you kept it.

"Be more present." "Pray more." "Be a better husband." Those aren't commitments. They're moods. On a good day you'll feel like you did them. On a bad day you'll feel like you failed them. Either way, Sunday turns into an argument with yourself instead of a count.

So your sentence becomes **no more than three commitments a week**, across faith, home, health and work.

Three is not a lack of ambition. Three is how a plan survives a real week. Most of us have tried ten. By Wednesday we're behind on six, and by Friday we've quit all ten and decided we're the problem. We're not the problem. Ten was the problem.

**The four rules**

- **Three at most.** If you want to add one, retire one.
- **Checkable.** A yes or no with a number. "Be more present" can't be checked. "Phone in the kitchen drawer from 7:40 to 9 PM, four nights" can.
- **Tied to your sentence.** Each one should move you toward that man. If it doesn't, cut it, no matter how good it sounds.
- **Decide the miss in advance.** Before Monday, write what counts as a miss. Then Sunday is counting, not negotiating.

Pick the days for each one, too. A commitment for Monday, Wednesday and Friday doesn't count as missed on Tuesday. You aren't trying to do everything every day. You're trying to keep your word on the days you gave it.

If you're unsure, go smaller. A commitment you keep five weeks in a row will change more than a big one you keep for nine days.`,
    learn: [
      { t: "Specific beats \"do your best\"", b: "Edwin Locke and Gary Latham spent decades studying goals. One of their most consistent findings: specific goals lead to better performance than vague \"do your best\" goals. A goal you can measure tells you exactly what to do and when you've done it. That's what \"checkable\" means." },
      { t: "Why three", b: "Psychologist Nelson Cowan (2001) argued that working memory can hold only about four chunks of information at once. Every commitment you carry takes up room. Three leaves space for the rest of your life. Ten guarantees that some of them fall off the table the moment the week gets busy." },
    ],
    adhd: { t: "Executive function", b: "The brain's management skills: planning, starting tasks, holding information in mind, controlling impulses and shifting attention. ADHD involves differences in how reliably these skills work. A short list of checkable commitments takes the load off the parts of the brain that struggle most." },
    tool: { t: "The cut list", b: "Write every goal you've been carrying on one page. Circle three that answer to your sentence. Draw a line through the rest and write \"later\" next to them. You haven't given them up. You've stopped letting them crowd out the three that matter now." },
    action: "Write your three commitments with their days, and decide what counts as a miss for each.",
    reflection: "Which commitment are you most afraid you won't keep? What makes it hard?",
    questions: ["What did you have to cut to get to three? How did it feel to cut it?", "Read each commitment next to your sentence. How does each one move you toward that man?"],
    prayer: "Lord, make my yes mean yes. Help me promise less and keep more, starting with three things this week.",
    days: [
      { t: "Dump the list", do: "Write every goal and \"should\" you're carrying, in any order. Get it all out of your head.", q: "How many did you write? Which one has been on your list the longest?" },
      { t: "Circle three", do: "Circle the three that answer most directly to your sentence. Put \"later\" next to the rest.", q: "Which three did you circle, and why those?" },
      { t: "Make them checkable", do: "Rewrite each one as a yes or no with a number. Add the days.", q: "Write your three commitments here, as checkable as you can make them." },
      { t: "Decide the miss", do: "For each commitment, write what counts as a miss before the week starts.", q: "What counts as a miss for your hardest commitment?" },
      { t: "First full day", do: "Keep your three today. Tap each one in your portal tonight: kept, floor or missed.", q: "What helped you keep one today? What got in the way of another?" },
      { t: "Too big or too small?", do: "Look at your first two days. Is any commitment too big to keep on a normal day? Shrink it now.", q: "Did you change anything? What and why?" },
      { t: "Send it to Brian", do: "Finish Step 2 in your portal and send it to Brian.", q: "What's one question about your commitments you want to bring Thursday?" },
    ],
  },
  {
    id: "w3", week: 3, step: 3, title: "The Floor, part one: give it an address", video: "",
    intro: "This week every commitment gets an address: a day, a time, a place and a trigger. Then you name what usually breaks it.",
    scripture: "Proverbs 24:16",
    verse: "For a just man falleth seven times, and riseth up again.",
    body: `"This week" is not a time. Neither is "in the morning" or "when I get a chance." An ADHD brain loses time that has no address, and it loses plans that are attached to that time.

So this week every commitment gets an address: **a day, a time, a place and a trigger.**

**A trigger** is something that already happens every day, that you hook your commitment to. You're not trying to remember. You're letting something you already do remind you.

- "After I park at home and before I go inside, I pray for one minute."
- "When I sit down to dinner, my phone goes in the kitchen drawer."
- "When the coffee starts brewing, I open my Bible."

The trigger does the remembering, so your brain doesn't have to.

**Then name what breaks it.** For each commitment, write what usually stops you. Be honest and specific. Time slips and it's suddenly 10 PM. You're wiped out after work. The phone pulls you in. The house is loud. Work runs late. Or one miss turns into shame, and shame turns into quitting the whole thing.

You can't plan around something you haven't named. Most men have been fighting the same three things for years without ever writing them down.

"For a just man falleth seven times, and riseth up again." Read that slowly. The just man falls. Seven times. Falling isn't the opposite of righteousness in that verse. Staying down is. This week you build the address. Next week you build the floor, so that when you fall, you have somewhere to land that isn't zero.`,
    learn: [
      { t: "If-then plans", b: "Psychologist Peter Gollwitzer calls these \"implementation intentions\": plans in the form \"if X happens, then I will do Y.\" A 2006 review of many studies by Gollwitzer and Paschal Sheeran found they substantially increase follow-through compared with good intentions alone. Deciding the when and where ahead of time means you don't have to decide in the moment." },
      { t: "Habits live in places", b: "Wendy Wood and David Neal's research shows that habits form through repetition in stable contexts: the same time, the same place, the same cue. That's why \"right after I park\" works better than \"sometime this evening.\" The place and the cue carry the habit when your motivation doesn't." },
    ],
    adhd: { t: "Time blindness", b: "An informal but widely used term for difficulty sensing how much time has passed or how long something will take. Russell Barkley describes ADHD as a kind of nearsightedness to the future. A plan with no time attached to it never arrives, because \"later\" never feels like now." },
    tool: { t: "The address line", b: "For each commitment, write one line: \"On [days], at [time], in [place], right after [trigger], I will [commitment].\" Add it to your phone calendar from your portal, with a reminder ten minutes before." },
    action: "Give each commitment a day, a time, a place and a trigger, and add them to your phone calendar from your portal.",
    reflection: "What usually breaks your plans midweek? Be specific.",
    questions: ["Which of your triggers is strongest, meaning it happens every single day without fail?", "Which breaker shows up for more than one commitment? What does that tell you?"],
    prayer: "Lord, I fall more than seven times. Teach me to rise, and teach me to plan for the falling before it comes.",
    days: [
      { t: "Find your daily anchors", do: "List ten things you already do every day without thinking: parking, coffee, dinner, brushing your teeth.", q: "Which of your anchors happen at the same time every day?" },
      { t: "Hook it on", do: "Attach each commitment to one anchor. Write the full address line for each.", q: "Write your three address lines here." },
      { t: "On the calendar", do: "Add your commitments to your phone calendar from the portal, with a reminder ten minutes before.", q: "Did the reminders fire? Did you act on them?" },
      { t: "Name the breakers", do: "For each commitment, write what usually breaks it. Use the list in your portal if you get stuck.", q: "What breaks your hardest commitment, and how long has it been breaking it?" },
      { t: "Plan around one", do: "Pick the biggest breaker and change one thing to get ahead of it: the time, the place, or what's in the room.", q: "What did you change, and did it help today?" },
      { t: "Watch the slip", do: "If you miss today, write the exact moment the plan slipped. Don't judge it. Just find it.", q: "Where exactly did it slip? What happened in the five minutes before?" },
      { t: "Tighten the address", do: "Adjust any address that isn't working. A trigger that doesn't happen daily isn't a trigger.", q: "Which address did you change, and what's the new one?" },
    ],
  },
  {
    id: "w4", week: 4, step: 3, title: "The Floor, part two: the bad-day version", video: "",
    intro: "This week each commitment gets a floor: the two-minute version you'll still do on your worst day. A floor day counts as kept.",
    scripture: "2 Corinthians 12:9",
    verse: "My grace is sufficient for thee: for my strength is made perfect in weakness.",
    body: `Most plans are built for a good week. Then Wednesday happens. You're tired, the house is loud, work ran over, someone's sick, and the whole plan goes to zero. Then, because it's at zero, you decide the week is gone and start again "next Monday."

The Floor is the fix. It's the two-minute version of each commitment that you'll still do on your worst day.

- Thirty minutes of Scripture becomes one verse and one sentence of prayer.
- Thirty minutes of training becomes ten push-ups.
- An hour of focused family time becomes five minutes of real attention when you walk in.
- Planning your week becomes writing the one thing that matters tomorrow.

**A floor day counts as kept.** That isn't cheating. That's the point. A plan that bends doesn't break. The man who does ten push-ups on a terrible day is still a man who trains. The man who skips because he can't do the full thirty has to start over again.

Paul heard God say, "My grace is sufficient for thee: for my strength is made perfect in weakness." Your weakest day isn't outside God's plan for you. It's where His strength shows up. The floor is how you stay in the room on those days.

**Use it on purpose.** Don't wait until you're desperate. When you feel the week slipping, drop to the floor early and on purpose. It's a tool, not a confession.

And if the whole week is hard, tap "I'm in a hard week" in your portal. Everything switches to its floor version until Sunday, and Brian knows to check on you.

Zero is the only real miss.`,
    learn: [
      { t: "Tiny habits last", b: "Stanford researcher BJ Fogg, in his book Tiny Habits (2019), argues that making a behavior very small is one of the most reliable ways to make it stick. A small version is easy enough to do even when motivation is low, and doing it keeps the habit and your identity intact." },
      { t: "The \"what the heck\" spiral", b: "Psychologists Alan Marlatt and Judith Gordon described the abstinence violation effect: after one slip, guilt and all-or-nothing thinking make people give up completely. \"I already missed, so the week is ruined.\" A floor breaks that chain, because there is always a version you can still do today." },
    ],
    adhd: { t: "Emotional dysregulation", b: "Difficulty managing how strong and how long emotions are. Many adults with ADHD report fast, intense feelings, especially frustration and shame after a miss. It's common in ADHD, though it isn't part of the formal diagnostic criteria. The floor gives you an action to take when the feeling says quit." },
    tool: { t: "The floor test", b: "For each floor, ask: could I do this sick, exhausted, on a 14-hour day, with the kids yelling? If the answer is no, make it smaller. A floor that only works on a good day isn't a floor." },
    action: "Write the two-minute floor for each commitment, and use it at least once this week.",
    reflection: "When did you last let a bad day turn into a bad week? What would the floor have looked like?",
    questions: ["Which floor felt almost too small to count? Why does small feel like failure to you?", "What happened the day you used a floor on purpose?"],
    prayer: "Lord, Your grace is enough for my weakest day. Help me stay in the room when I'm tired, and keep me from quitting over one miss.",
    days: [
      { t: "Remember a bad week", do: "Think of the last week your plans went to zero. Write what happened on the first bad day.", q: "What happened on the day it started to fall apart?" },
      { t: "Write your floors", do: "For each commitment, write the two-minute version. Make it almost too easy.", q: "Write your three floors here." },
      { t: "Run the floor test", do: "Ask of each floor: could I do this sick, exhausted, with the kids yelling? Shrink any that fail.", q: "Which floor did you have to shrink?" },
      { t: "Use one on purpose", do: "Pick one commitment today and do only its floor, on purpose, even if you could do more.", q: "How did it feel to do just the floor? Did it still count to you?" },
      { t: "Catch the slide", do: "Notice the moment today you feel the day slipping. Drop to the floor right then.", q: "When did you feel it slipping, and what did you do?" },
      { t: "Tell someone your floor", do: "Text your partner or a brother one of your floors. Saying it makes it real.", q: "Who did you tell, and what did they say?" },
      { t: "Send Step 3 to Brian", do: "Finish Step 3 in your portal with every time, place, trigger and floor, and send it to Brian.", q: "Which floor are you most likely to need in the next two weeks?" },
    ],
  },
  {
    id: "w5", week: 5, step: 4, title: "The Ledger: count it without shame", video: "",
    intro: "This week you learn the Ledger: tap each day, count each Sunday, tell one man your number, and reset.",
    scripture: "Luke 16:10",
    verse: "He that is faithful in that which is least is faithful also in much.",
    body: `"He that is faithful in that which is least is faithful also in much." Faithfulness isn't measured in big moments. It's measured in small things on ordinary days. The Ledger is how you see it.

**Every day:** tap each commitment kept, floor or missed in your portal. It takes thirty seconds. If you keep it on paper, mark it there.

**Every Sunday:** look at your number, for example 13 of 15. Not "pretty good." Not "a rough week." A number. Then answer four questions:

- What's the miss that keeps coming back?
- What's one change for Monday?
- What would you say to a brother who had your week? That's your grace line. Say it to yourself.
- Who did you report your number to?

Then reset. New week, new count.

**Count it without shame.** Four out of seven is four out of seven. It's not a verdict on your manhood. It's information. Shame says, "See, you always do this." The Ledger says, "Here's what happened, and here's what to change." One leads to hiding. The other leads to Monday.

**Tell one man.** "Iron sharpeneth iron; so a man sharpeneth the countenance of his friend." Proverbs 27:17. A number nobody sees is easy to round up. That's why your partner sees your weekly number and your Sunday answers, and you see his. Not to judge each other. To count with each other.

Most men have never kept an honest record of their own faithfulness. You're about to have five weeks of it. That record will tell you things your feelings never could.`,
    learn: [
      { t: "Tracking helps you reach goals", b: "A 2016 review by Benjamin Harkin and colleagues, combining many studies, found that monitoring your progress toward a goal increases the chance of reaching it. The effect was stronger when progress was physically recorded or reported to someone else. That's the daily tap and the Sunday report." },
      { t: "Self-compassion and accountability", b: "Research by Juliana Breines and Serena Chen (2012) found that people who responded to a failure with self-compassion were more motivated to improve than people who were harsh with themselves. Kindness isn't going soft. Harsh self-criticism tends to push people toward hiding instead of changing." },
    ],
    adhd: { t: "Rejection sensitivity", b: "Many people with ADHD describe intense emotional pain at the idea of being criticized or falling short. Some clinicians call it rejection sensitive dysphoria. It's an informal term, not a formal diagnosis. It's one reason a number can feel like a judgment. The grace line is there to answer it." },
    tool: { t: "The Sunday fifteen", b: "Put fifteen minutes on your calendar every Sunday evening, with a time and a place. Open your portal's Sunday review, check your number, answer the four questions, and text your partner the number before you close it." },
    action: "Do your Sunday review this week and send your number to your partner.",
    reflection: "What did your numbers tell you that your feelings didn't?",
    questions: ["What's your grace line this week? Write it the way you'd say it to a brother.", "What was it like to send your number to another man?"],
    prayer: "Lord, make me faithful in the least things. Let me count my week honestly, receive Your grace for it, and start Monday new.",
    days: [
      { t: "Tap every day", do: "Mark each commitment in your portal tonight: kept, floor or missed. Thirty seconds.", q: "How did it feel to mark a miss honestly?" },
      { t: "Read your week so far", do: "Look at your Ledger screen. Don't judge it. Just read it like a chart.", q: "What do you notice in the pattern so far?" },
      { t: "Find the repeat miss", do: "Find the commitment you've missed most. Write what happened right before each miss.", q: "What happens right before your repeat miss?" },
      { t: "Write a grace line", do: "Write what you'd say to a brother who had your week. Keep it where you'll see it Sunday.", q: "Write your grace line here." },
      { t: "Plan your Sunday fifteen", do: "Put fifteen minutes on your calendar for Sunday with a time and a place.", q: "When and where is your Sunday review?" },
      { t: "Ask your partner", do: "Text your partner: \"Sunday I'll send you my number. Send me yours.\"", q: "How did he respond?" },
      { t: "Sunday review", do: "Do your full Sunday review in the portal, then text your partner your number.", q: "What number did you report, and what's your one change for Monday?" },
    ],
  },
  {
    id: "w6", week: 6, step: 4, title: "The reset: what stays", video: "",
    intro: "This week you read your numbers, decide what stays, and choose how you'll keep going after the cohort.",
    scripture: "Lamentations 3:22-23",
    verse: "It is of the LORD's mercies that we are not consumed, because his compassions fail not. They are new every morning: great is thy faithfulness.",
    body: `Six weeks ago you wrote one sentence. Since then you've cut your life down to three commitments, given each one an address and a floor, and counted your weeks honestly with another man.

Now read your weekly numbers in a row. That line is evidence of who you're becoming. Not a feeling. Evidence. Some weeks were strong. Some weren't. Both are in the line, and the line still moves.

**Decide what stays**

- **Keep** the commitments that are running. Consider raising the floor a little.
- **Retire** the ones that have become habits and no longer need tracking. That's not quitting. That's graduating.
- **Replace** the ones that keep failing with something smaller, or at a better time, or tied to a stronger trigger.

Then reread your sentence from Week 1. Does it still describe the man you're called to be? Revise it if it needs it. The sentence isn't a test you passed or failed. It's a direction.

"It is of the LORD's mercies that we are not consumed, because his compassions fail not. They are new every morning." His mercies didn't wait for you to have a perfect six weeks. They were new on your worst morning too.

**Keep going.** The cohort ends. The Ledger doesn't. Habits take longer than six weeks to become automatic, so this is the middle, not the end. The Club is where graduates keep it running: a monthly call, a partner and your portal.

And tell the next man what changed. Your words, your numbers, with your permission. Somebody is where you were six weeks ago.`,
    learn: [
      { t: "How long habits take", b: "Phillippa Lally and colleagues (2009) followed people building new daily habits. On average it took about 66 days for a habit to feel automatic, with a wide range from 18 to 254 days. Missing a single day didn't derail the process. Six weeks is a strong start, not the finish line." },
      { t: "Small progress is real progress", b: "Teresa Amabile and Steven Kramer's research on the \"progress principle\" found that noticing even small wins is one of the strongest sources of motivation. Reading your weekly numbers side by side makes slow change visible that your feelings would otherwise miss." },
    ],
    adhd: { t: "Novelty and interest", b: "Many people with ADHD find it easier to start new things than to sustain them once they're familiar. Expect your interest to dip after the cohort ends. Plan for it now: keep the Sunday review, keep a partner, and refresh one commitment every few weeks so the system doesn't go stale." },
    tool: { t: "Keep, retire, replace", b: "Draw three columns. Put each commitment in one: keep, retire or replace. For anything you replace, write the new version with its address and floor before you close the page." },
    action: "Read your six weeks of numbers, decide what stays, and share your result.",
    reflection: "Who are you now that you weren't six weeks ago? Answer with evidence.",
    questions: ["Reread your Week 1 sentence. What, if anything, would you change in it now?", "What will you do the first week after the cohort to keep your Ledger going?"],
    prayer: "Lord, thank You for mercies that are new every morning. Thank You for what You've built in six weeks. Help me keep going when nobody is watching.",
    days: [
      { t: "Read the line", do: "Open your Ledger and read all your weekly numbers in order.", q: "What does the line of your numbers tell you?" },
      { t: "Keep, retire, replace", do: "Put each commitment into one of the three columns.", q: "What's in each column, and why?" },
      { t: "Reread your sentence", do: "Read your Week 1 sentence out loud. Revise it if it needs it.", q: "Did you change your sentence? Write the current version here." },
      { t: "Name the evidence", do: "Write three specific things that changed in six weeks. Specific, not \"I feel better.\"", q: "What are your three pieces of evidence?" },
      { t: "Plan the next month", do: "Write next week's commitments with their addresses and floors, as if the cohort were still going.", q: "What will keep you counting when the calls stop?" },
      { t: "Thank your partner", do: "Tell your partner one thing he did that helped you over these six weeks.", q: "What did you tell him?" },
      { t: "Share your result", do: "Answer Brian's results form with your numbers and two sentences in your own words.", q: "What would you say to a man who's where you were six weeks ago?" },
    ],
  },
];

export const MATERIALS = [
  { id: "m1", title: "Step 1 worksheet: The Calling (printable)", url: `${SITE}/downloads/step-1-the-calling.pdf`, kind: "pdf" },
  { id: "m2", title: "The Ledger: weekly scorecard (printable)", url: `${SITE}/downloads/the-ledger-weekly-scorecard.pdf`, kind: "pdf" },
  { id: "m3", title: "How the four steps work", url: `${SITE}/how-it-works/`, kind: "link" },
];

// Pick-and-edit starters, so nobody stalls on a blank page.
export const EXAMPLES = {
  sentences: [
    "I am a man who is home when he is home, keeps his word to his wife, and lets his kids see him pray, so that my house knows what faithful looks like.",
    "I am a man who starts the day with God before a screen and finishes what he says he'll do, so that my family can lean on my yes.",
    "I am a man who shows up on time, tells the truth when it costs him, and stays steady under pressure, so that the people I lead can trust me.",
  ],
  commitments: [
    { what: "Phone in the kitchen drawer from 7:40 to 9 PM", pillar: "home", days: [1, 2, 3, 4], time: "19:40", place: "Kitchen", trigger: "When dinner ends", floor: "Phone face down for the first 10 minutes" },
    { what: "Read one chapter of Scripture before my phone", pillar: "faith", days: [1, 2, 3, 4, 5, 6, 0], time: "06:15", place: "Kitchen table", trigger: "Before the coffee is poured", floor: "Read one verse and pray one sentence" },
    { what: "Train for 30 minutes", pillar: "health", days: [1, 3, 5], time: "17:30", place: "Garage", trigger: "As soon as I park at home", floor: "Ten push-ups" },
    { what: "Ask my wife about her day and listen without fixing", pillar: "home", days: [1, 2, 3, 4, 5], time: "18:00", place: "Living room", trigger: "When I walk in the door", floor: "Five minutes of real eye contact" },
    { what: "Plan tomorrow on paper before I leave work", pillar: "work", days: [1, 2, 3, 4, 5], time: "16:45", place: "My desk", trigger: "When I close my laptop", floor: "Write the one thing that matters tomorrow" },
    { what: "Pray with my kids at bedtime", pillar: "faith", days: [0, 1, 2, 3, 4], time: "20:30", place: "Kids' room", trigger: "After the lights go off", floor: "One sentence prayer at the door" },
  ],
  breakers: ["Time slips and it's suddenly late", "Too tired after work", "The phone pulls me in", "The house is loud or chaotic", "One miss turns into shame and I quit", "I forget until it's too late", "Work runs over"],
};
