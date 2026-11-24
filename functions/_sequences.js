// Default email series. Brian can edit them in the dashboard (/admin/); an edited
// version is saved in KV ("seqdef:<id>") and wins over the default here.
//
// Body format (used in the dashboard too):
//   blank line            new paragraph
//   [[Label|https://...]] a button (on its own line)
//   [text](https://...)   a link
//   **bold**              bold
//   - item                a bullet list
//   {{first_name}}        the man's first name ("friend" if unknown)
//
// "relative" series send each email delayDays after the man joins the series.
// "dated" series send on fixed dates (at, Central time); a man who joins late
// skips the dates already past.

const SITE = "https://bethemansystem.com";
const MEET = "https://meet.google.com/tcg-zspn-cco";

export const SEQUENCES = {
  step1: {
    id: "step1",
    name: "Step 1 welcome series",
    starts: "When a man signs up for Step 1",
    kind: "relative",
    emails: [
      {
        delayDays: 0,
        subject: "Step 1: The Calling",
        body: `{{first_name}}, here is Step 1.

Step 1 is The Calling: one sentence on who God has called you to be. List your roles, ask what God expects of you in each, make it a Tuesday, and write the sentence. Twenty minutes, or four five-minute pieces.

[[Open the worksheet|${SITE}/step-1/worksheet/]]

Rather print it? [Download the PDF](${SITE}/downloads/step-1-the-calling.pdf).

"Write the vision; make it plain on tablets, so he may run who reads it" (Habakkuk 2:2).

Reply any time. It comes straight to me.

Brian`,
      },
      {
        delayDays: 2,
        subject: "Just the first move",
        body: `{{first_name}}, if the worksheet is still sitting there, that is normal. Starting is the wall. Once you begin, you can usually keep going.

So don't do the worksheet tonight. Do the first move only: list your roles. Son of God, husband or future husband, father or future father, son, worker, brother. Three minutes. Then close it.

[[Open the worksheet|${SITE}/step-1/worksheet/]]

One move done is a win. The rest can wait for tomorrow.

Brian`,
      },
      {
        delayDays: 5,
        subject: "Three commitments, not ten",
        body: `Once your sentence is written, Step 2 is The Commitments: no more than three things you will do each week because of who God has called you to be.

Three is not a lack of ambition. It is how a plan survives a real week. Each one has to be a yes or no with a number. "Be more present" can't be checked. "Phone in the drawer, 7:40 to 9 PM, four nights" can.

"Let what you say be simply 'Yes' or 'No'" (Matthew 5:37).

Try it this week: write one commitment that passes that test.

[[See how the four steps work|${SITE}/how-it-works/]]

Brian`,
      },
      {
        delayDays: 9,
        subject: "Your worst day needs a plan too",
        body: `Most plans are built for a good week. Then Wednesday happens: you are tired, the house is loud, and the whole plan goes to zero.

Step 3 is The Floor. Every commitment gets a time, a place and a trigger, and a two-minute version you will still do on your worst day. Prayer becomes one verse and one sentence. Training becomes ten push-ups. A floor day still counts.

"For the righteous falls seven times and rises again" (Proverbs 24:16).

Pick one commitment and write its two-minute version tonight.

Brian`,
      },
      {
        delayDays: 14,
        subject: "Count it without shame",
        body: `Step 4 is The Ledger. Every Sunday night you mark each day kept, floor or missed, write the number (13 of 15, not "pretty good"), and send it to another man. Then you take grace, make one change for Monday, and reset.

A number nobody sees is easy to round up. That is why the Ledger is reported, not just kept.

If you want to build all four steps with other men, live, the Founding Cohort is six weeks with at most ten men.

[[See the Founding Cohort|${SITE}/cohort/]]

Brian`,
      },
    ],
  },
  cohort: {
    id: "cohort",
    name: "Founding Cohort reminders",
    starts: "When a man buys a seat in the Founding Cohort",
    kind: "dated",
    emails: [
      {
        at: "2026-12-09T10:00:00-06:00",
        subject: "Tomorrow, 7 PM Central: Week 1, The Calling",
        body: `{{first_name}}, the Founding Cohort starts tomorrow, Thursday, at 7 PM Central on Google Meet.

[[Join the call|${MEET}]]

Week 1 is The Calling. Bring your Step 1 worksheet, finished or not. If you haven't started it, do the first move tonight: list your roles.

[Open the worksheet](${SITE}/step-1/worksheet/)

Join two minutes early from a quiet room. See you there.

Brian`,
      },
      {
        at: "2026-12-16T10:00:00-06:00",
        subject: "Tomorrow, 7 PM Central: Week 2, The Commitments",
        body: `{{first_name}}, Week 2 is tomorrow, Thursday, at 7 PM Central.

[[Join the call|${MEET}]]

We cut your list to three commitments you can check. Bring your sentence and every commitment you are carrying right now, even the ones you have been avoiding.

After tomorrow we break for Christmas and New Year's. No call December 24 or 31. Week 3 is Thursday, January 7.

Brian`,
      },
      {
        at: "2027-01-06T10:00:00-06:00",
        subject: "Tomorrow, 7 PM Central: Week 3, The Floor",
        body: `{{first_name}}, we are back tomorrow, Thursday, at 7 PM Central.

[[Join the call|${MEET}]]

Week 3 is The Floor, part one: a day, a time, a place and a trigger for each commitment. Bring your three commitments and one honest line on how the holidays went. No shame. It is information.

Brian`,
      },
      {
        at: "2027-01-13T10:00:00-06:00",
        subject: "Tomorrow, 7 PM Central: Week 4, the bad-day version",
        body: `{{first_name}}, Week 4 is tomorrow, Thursday, at 7 PM Central.

[[Join the call|${MEET}]]

The Floor, part two: the two-minute version of every commitment, so one bad Wednesday bends the plan instead of ending it. Bring the commitment you missed most this week.

Brian`,
      },
      {
        at: "2027-01-20T10:00:00-06:00",
        subject: "Tomorrow, 7 PM Central: Week 5, The Ledger",
        body: `{{first_name}}, Week 5 is tomorrow, Thursday, at 7 PM Central.

[[Join the call|${MEET}]]

The Ledger: score, report, take grace, reset. Print the scorecard and fill in this week before the call.

[Print the Ledger](${SITE}/downloads/the-ledger-weekly-scorecard.pdf)

Brian`,
      },
      {
        at: "2027-01-27T10:00:00-06:00",
        subject: "Tomorrow, 7 PM Central: Week 6, the reset",
        body: `{{first_name}}, our last session is tomorrow, Thursday, at 7 PM Central.

[[Join the call|${MEET}]]

Bring every Ledger you have kept. We read the numbers together, decide what stays, and I'll show you how to keep it running in the Club.

Brian`,
      },
    ],
  },
};
