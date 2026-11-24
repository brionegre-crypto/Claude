// The Thursday email: ten weekly tips for the four-step system, one each Thursday at 8 AM Central.
// Every Step 1 sign-up gets them in order, starting the Thursday after he joins, every week with no breaks.
// Brian can edit them in the dashboard (Email series); his version is saved in KV and wins over this file.

const SITE = "https://bethemansystem.com";
const STEP1 = `[[Start Step 1 free|${SITE}/step-1/#get]]`;
const END = `Hit reply and tell me how it went. I read every one.\n\nBrian`;

export const WEEKLY = {
  id: "weekly",
  name: "The Thursday email (weekly tips)",
  starts: "Every Step 1 sign-up, the Thursday after he joins",
  kind: "weekly",
  day: 4,
  hour: 8,
  skip: [],
  emails: [
    {
      subject: "\"This week\" is not a time",
      body: `{{first_name}}, most of the plans you've dropped didn't fail because you didn't care. They failed because they never had an address.

"I'll pray more this week." "I'll be more present this week." This week is not a time. A brain that loses track of time will lose a plan that has no time attached to it.

So give one thing an address. A day, a time, a place, and a trigger: something that already happens that you hook it to.

**This week:** pick one thing you keep meaning to do. Write it like this: "Thursday, 7:40 PM, kitchen, right after dinner, phone goes in the drawer."

When it has a time and a place, it stops being a feeling and starts being an appointment.

"Write the vision; make it plain." Habakkuk 2:2

If you haven't done Step 1 yet, it takes about twenty minutes. That's where the plan starts.

${STEP1}

${END}`,
    },
    {
      subject: "Start with who, not what",
      body: `{{first_name}}, most men start with goals. Read more. Work out. Be home more. That's why the goals don't hold. A goal with no man behind it is a wish with a date on it.

Start underneath the goals. Who has God called you to be in the roles you already carry? Son of God. Husband or future husband. Father or future father. Son. Worker. Brother.

Then write it in one sentence: "I am a man who ___, so that ___."

Every part of that sentence should be something someone in your house could notice without being told.

**This week:** write your sentence. Put it where your eyes already go: your lock screen, your mirror, your truck visor. Read it once a day.

"Write the vision; make it plain, so he may run who reads it." Habakkuk 2:2

Step 1 walks you through it, role by role.

${STEP1}

${END}`,
    },
    {
      subject: "Three, not ten",
      body: `{{first_name}}, here is what usually happens. A man gets fired up and writes ten goals. By Wednesday he's behind on six of them. By Friday he's quit all ten.

Ten goals isn't ambition. For a brain like ours, it's a setup.

Cut it to three. No more than three commitments a week, across faith, home, health and work. Each one a yes or no with a number. "Be more present" can't be checked. "Phone in the drawer from 7:40 to 9 PM, four nights" can.

And decide what counts as a miss before the week starts, so Sunday is counting, not arguing.

**This week:** look at everything you've been trying to do. Circle three. Let the rest wait. They'll still be there when these three are running.

"Let what you say be simply 'Yes' or 'No.'" Matthew 5:37

${END}`,
    },
    {
      subject: "The first ten minutes home",
      body: `{{first_name}}, the first ten minutes after you walk in the door decide a lot about your evening, and about how your family experiences you.

Most of us walk in still at work in our heads. Phone in hand. Half listening. Then we wonder why the house feels tense by 7.

Give those ten minutes a plan. Sit in the truck for one minute and pray before you go in. Phone stays in your pocket. The first thing you do is find your wife or your kids and ask one real question, then listen without fixing.

That's it. Ten minutes. It's small enough to do on a hard day, and it changes the whole evening.

**This week:** try it four nights. Count how many you kept. Four out of four or two out of four, the number is information, not a verdict.

"Love one another with brotherly affection. Outdo one another in showing honor." Romans 12:10

${END}`,
    },
    {
      subject: "The smallest version that still counts",
      body: `{{first_name}}, most plans are built for a good week. Then Wednesday happens. You're tired, the house is loud, work ran over, and the whole plan goes to zero.

Here's the fix: every commitment needs a floor. The two-minute version you'll still do on your worst day.

Prayer becomes one verse and one sentence. Thirty minutes of training becomes ten push-ups. A real conversation becomes five minutes of eye contact.

**A floor day counts as kept.** That's the point. A plan that bends doesn't break. Zero is the only real miss.

**This week:** write the floor for each thing you're working on. Then use it on purpose at least once, before you're desperate.

"For the righteous falls seven times and rises again." Proverbs 24:16

${END}`,
    },
    {
      subject: "Fifteen minutes on Sunday",
      body: `{{first_name}}, if you only add one habit this year, make it this one: fifteen minutes on Sunday.

Look at your week. For each commitment, how many did you keep? Write the number: 9 of 12, not "pretty good." Then answer four questions:

- What's the miss that keeps coming back?
- What's one change for Monday?
- What would you say to a brother who had your week? Say that to yourself.
- Who did you tell your number to?

Then reset. New week, new count.

**This week:** put fifteen minutes on your calendar for Sunday evening. Give it a time and a place, like everything else.

"One who is faithful in a very little is also faithful in much." Luke 16:10

${END}`,
    },
    {
      subject: "The miss that keeps coming back",
      body: `{{first_name}}, if the same commitment keeps slipping, don't try harder. Look closer.

A repeat miss is almost never about how much you care. It's about what keeps breaking it. Time slips and it's suddenly 10 PM. You're wiped out after work. The phone pulls you in. The house is loud. Or one miss turns into shame, and shame turns into quitting.

Name it. You can't plan around something you haven't named.

Then change one thing: the time, the place, the trigger, or the size. Move the workout to the morning. Put the phone in another room. Make it smaller.

**This week:** find your one repeat miss. Write down what breaks it. Change one thing about it before Monday.

"Search me, O God, and know my heart! Try me and know my thoughts!" Psalm 139:23

${END}`,
    },
    {
      subject: "Say it out loud to one man",
      body: `{{first_name}}, a number nobody sees is easy to round up.

You know how this goes. You kept three of seven, but by the time you think about it on Sunday it feels like "most of the week." Nobody checks, so nothing changes.

Tell one man your number. Not a speech. Just a text on Sunday: "9 of 12 this week. Phone at night is still the problem." Ask him for his.

That's what accountability actually is. Not someone watching you. Someone counting with you.

**This week:** pick one man. Ask him if he'll trade numbers with you on Sundays for a month. Most men will say yes, because most men want it too.

"Iron sharpens iron, and one man sharpens another." Proverbs 27:17

If you'd rather do this with a group of men, that's what the Be The Man Cohort is.

[[See the Cohort|${SITE}/cohort/]]

${END}`,
    },
    {
      subject: "When shame says quit",
      body: `{{first_name}}, the most dangerous moment in any plan isn't the miss. It's what you tell yourself after the miss.

"See, you always do this." "Why even try." That voice ends more plans than any bad day does.

Here is the truth. A miss is information, not a verdict. Four out of seven is four out of seven. It's not zero, and it's not who you are.

So when you miss, you don't wait for next month or next year. You don't even wait for Monday. You go back to the floor version today.

**This week:** write one grace line for yourself, the kind of thing you'd say to a brother. Read it the next time you miss.

"The steadfast love of the Lord never ceases; his mercies never come to an end; they are new every morning." Lamentations 3:22-23

${END}`,
    },
    {
      subject: "One evening to reset",
      body: `{{first_name}}, every few weeks, a plan needs a reset. Not a restart from scratch. A reset.

Take one evening. Read your weekly numbers in a row. That line is evidence of who you're becoming. Not a feeling. Evidence.

Then decide three things:

- **Keep** the commitments that are running. Maybe raise the floor a little.
- **Retire** the ones that have become habits and don't need tracking anymore.
- **Replace** the ones that keep failing with something smaller, or at a better time.

Then write next week's three, with their times and their floors.

**This week:** block one evening. Do the reset. You'll walk out of it with a plan that fits the man you are now.

"Forgetting what lies behind and straining forward to what lies ahead, I press on." Philippians 3:13-14

If you want to build all four steps with other men, with me in the room, the Cohort is six live weeks.

[[See the Cohort|${SITE}/cohort/]]

${END}`,
    },
  ],
};
