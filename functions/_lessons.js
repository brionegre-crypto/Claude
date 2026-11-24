// Default lessons, materials and starter examples for the men's portal.
// Brian edits them in the dashboard (Library); his version is saved in KV ("lessons").
// Body format: blank line = new paragraph, [[Button|link]], [text](link), **bold**, "- " list.

const SITE = "https://bethemansystem.com";

export const LESSONS = [
  {
    id: "w1", week: 1, step: 1, title: "The Calling: who has God called you to be?", scripture: "Habakkuk 2:2", video: "",
    body: `Most men start with goals. That's why the goals don't hold. A goal with no man behind it is a wish with a date on it.

So we start underneath the goals. Not "what do I want to do?" but "who has God called me to be?" in the roles I already carry: son of God, husband or future husband, father or future father, son, worker, brother.

"Write the vision; make it plain on tablets, so he may run who reads it" (Habakkuk 2:2). Notice two things. It's written, not remembered. And it's plain, plain enough to run with. An ADHD brain doesn't need more conviction. It needs the vision outside its head, where it can see it on a Tuesday.

**How to do Step 1**

- List your roles. Start with the one under all the others: a son of God.
- For each role, ask what God expects of you there. Use Scripture, not feelings.
- Make it a Tuesday: what does faithful look like on a normal day, and what's the smallest version on a bad day?
- Write one sentence: "I am a man who ___, so that ___."

Every part of your sentence should be something someone in your house could notice without being told.

[[Open Step 1 in your portal|${SITE}/portal/#step-1]]`,
    action: "Write your sentence and put it where your eyes already go: your lock screen, mirror or truck visor.",
    reflection: "Which role was hardest to write about, and why?",
  },
  {
    id: "w2", week: 2, step: 2, title: "The Commitments: three you can check", scripture: "Matthew 5:37", video: "",
    body: `"Let what you say be simply 'Yes' or 'No'" (Matthew 5:37). Jesus is talking about keeping your word. A commitment you can't check is a word you can't keep, because nobody can tell whether you did.

Your sentence now becomes no more than three commitments a week. Three is not a lack of ambition. Three is how a plan survives a real week.

**The rules**

- Three at most, across faith, home, health and work. If you add one, retire one.
- Checkable: a yes or no with a number. "Be more present" can't be checked. "Phone in the drawer, 7:40 to 9 PM, four nights" can.
- Each one answers to your sentence. If it doesn't move you toward that man, cut it.
- Decide what counts as a miss before Monday, so Sunday is counting, not arguing.

Pick the days for each one. A commitment that's only for Monday, Wednesday and Friday doesn't count as missed on Tuesday.

[[Open Step 2 in your portal|${SITE}/portal/#step-2]]`,
    action: "Write your three commitments with their days, and decide what counts as a miss for each.",
    reflection: "Which commitment are you most afraid you won't keep? What makes it hard?",
  },
  {
    id: "w3", week: 3, step: 3, title: "The Floor, part one: give it an address", scripture: "Proverbs 24:16", video: "",
    body: `"This week" is not a time. An ADHD brain loses time that has no address. So this week every commitment gets one: a day, a time, a place and a trigger.

**A trigger** is something that already happens, that you attach your commitment to. "After I park at home and before I go in, I pray for one minute." "When I sit down to dinner, the phone goes in the kitchen drawer." The trigger does the remembering, so your brain doesn't have to.

**Name what breaks it.** For each commitment, write down what usually stops you: time slipping, evening fatigue, the phone, a loud house, shame after a miss. You can't plan around something you haven't named.

"For the righteous falls seven times and rises again" (Proverbs 24:16). Falling isn't the end of the plan. It's part of the plan. This week we build the address. Next week we build the floor.

[[Open Step 3 in your portal|${SITE}/portal/#step-3]]`,
    action: "Give each commitment a day, a time, a place and a trigger, and add them to your phone calendar from your portal.",
    reflection: "What usually breaks your plans midweek? Be specific.",
  },
  {
    id: "w4", week: 4, step: 3, title: "The Floor, part two: the bad-day version", scripture: "Proverbs 24:16", video: "",
    body: `Most plans are built for a good week. Then Wednesday happens: you're tired, the house is loud, and the whole plan goes to zero.

The Floor is the two-minute version of each commitment that you'll still do on your worst day. Prayer becomes one verse and one sentence. Training becomes ten push-ups. Being present becomes five minutes of real attention when you walk in.

**A floor day counts as kept.** That's the point. A plan that bends doesn't break.

When you feel the week slipping, drop to the floor on purpose. If the whole week is hard, tap "I'm in a hard week" in your portal. Everything switches to its floor version, and Brian knows to check on you.

Zero is the only real miss.

[[Write your floors|${SITE}/portal/#step-3]]`,
    action: "Write the two-minute floor for each commitment, and use it at least once this week.",
    reflection: "When did you last let a bad day turn into a bad week? What would the floor have looked like?",
  },
  {
    id: "w5", week: 5, step: 4, title: "The Ledger: count it without shame", scripture: "Luke 16:10 · Proverbs 27:17", video: "",
    body: `"One who is faithful in a very little is also faithful in much" (Luke 16:10). Faithfulness is counted in small things, on ordinary days. The Ledger is how you see it.

**Every day:** tap each commitment kept, floor or missed. It takes thirty seconds.

**Every Sunday:** look at your number, for example 13 of 15, not "pretty good." Answer four questions: the miss that keeps coming back, one change for Monday, a grace line to yourself, and who you reported to. Then reset.

"Iron sharpens iron, and one man sharpens another" (Proverbs 27:17). A number nobody sees is easy to round up. That's why your partner sees yours, and you see his.

Four out of seven is four out of seven. It's not a verdict. It's information.

[[Open Step 4 in your portal|${SITE}/portal/#step-4]]`,
    action: "Do your Sunday review this week and send your number to your partner.",
    reflection: "What did your numbers tell you that your feelings didn't?",
  },
  {
    id: "w6", week: 6, step: 4, title: "The reset: what stays", scripture: "Lamentations 3:22-23", video: "",
    body: `Six weeks ago you wrote one sentence. Since then you've cut your life to three commitments, given each one an address and a floor, and counted your weeks honestly.

Read your weekly numbers in a row. That line is evidence of who you are becoming. Not a feeling. Evidence.

**Decide what stays**

- Keep the commitments that are running. Consider raising the floor a little.
- Retire the ones that have become habits and no longer need tracking.
- Replace the ones that keep failing with something smaller, or at a better time.

"His mercies never come to an end; they are new every morning" (Lamentations 3:22-23). The Ledger doesn't end here. The Club is where graduates keep it going: a monthly call, a partner, and your portal.

Then tell the next man what changed. Your words, your numbers, with your permission.`,
    action: "Read your six weeks of numbers, decide what stays, and share your result.",
    reflection: "Who are you now that you weren't six weeks ago? Answer with evidence.",
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
