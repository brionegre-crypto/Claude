"""Build The Truth Ledger outputs from content.py.
  python3 build.py  ->  install-truth-ledger.command, Truth-Ledger.ics, The-Truth-Ledger.html
"""
import datetime, html, os
from content import *

HERE = os.path.dirname(os.path.abspath(__file__))
TONIGHT = ("TONIGHT, BEFORE YOU SLEEP (30 min)\n"
           "1. Write one sentence: \"I am a man whose word holds, even when the truth costs me.\"\n"
           "2. Count honestly: roughly how many lies did you tell this week? Write the number.\n"
           "3. Write two names: one man to be your accountability brother, and a pastor or older man you respect to be your witness. You'll ask them by Day 3.\n"
           "4. Text your brother now: \"I'm working on something. Can I send you my numbers once a week?\"\n"
           "5. If she's open to it, tell your wife: \"I've lied to you, and it comes from fear. I'm not asking you to trust me. I've started daily work and I'm getting men around me to hold me to it. You'll see it, not just hear it.\"\n"
           "Then do not tell another lie tonight.")

def week_of(i): return WEEKS[i // 7]

def items():
    """Every reminder as (day_number, slot, title, body); slot is a key of TIMES."""
    out = []
    for i, (title, focus, question) in enumerate(DAYS):
        d, w = i + 1, week_of(i)
        sci = SCIENCE[DAY_SCI[d]]
        out.append((d, "morning", f"Day {d} Morning: {title}",
                    f"Week {w['n']}: {w['name']}. {w['line']}\n\n{focus}\n\nBefore you go, write today's if-then: \"If ___ happens, then I'll say ___.\"\n\nWhy it works: {sci['title']}. {sci['use']} ({sci['source']})"))
        out.append((d, "midday", f"Day {d} Midday check", MIDDAY))
        if d % 7 == 0:
            nxt = WEEKS[w['n']] if w['n'] < 7 else None
            body = ("WEEKLY REVIEW (20 min)\nAdd up this week's ledgers: lies told, lies caught, corrections made. "
                    "Text the three numbers to your brother. Share the week's patterns with your witness.")
            body += f"\n\nNext week: {nxt['name']}. {nxt['why']}" if nxt else "\n\nYou made it to Day 49. Decide what keeps running from here."
            out.append((d, "review", f"Week {w['n']} review", body))
        out.append((d, "evening", f"Day {d} Evening Ledger",
                    f"Tonight's question: {question}\n\n{LEDGER}"))
    return out

# ---------- Apple Reminders installer (macOS) ----------
def as_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'

def build_command():
    rows = "\n".join(f"  my addOne({d}, \"{slot}\", {as_str(t)}, {as_str(b)})" for d, slot, t, b in items())
    tm = lambda k: f"{TIMES[k][0]}:{TIMES[k][1]:02d}"
    script = f'''#!/bin/bash
# THE TRUTH LEDGER · a Be The Man daily system
# Puts 49 days of reminders (morning, midday, evening + weekly reviews) into a
# new list in Apple Reminders called "{LIST_NAME}". It syncs to your iPhone
# through iCloud.
#
# Run it in Terminal:   bash ~/Downloads/install-truth-ledger.command
# Start today instead of tomorrow:   bash ~/Downloads/install-truth-ledger.command today
set -euo pipefail

# Your reminder times (24-hour clock). Change these before running if your day is different.
MORNING="{tm('morning')}"
MIDDAY="{tm('midday')}"
EVENING="{tm('evening')}"
REVIEW="{tm('review')}"     # weekly review, every 7th day

START=1                       # Day 1 = tomorrow
[ "${{1:-}}" = "today" ] && START=0
LIST="{LIST_NAME}"

if osascript -e "tell application \\"Reminders\\" to exists list \\"$LIST\\"" | grep -q true; then
  read -r -p "The list \\"$LIST\\" already exists. Replace everything in it? (y/n) " ans
  [ "$ans" = "y" ] || {{ echo "Nothing changed."; exit 0; }}
  REPLACE=1
else
  REPLACE=0
fi

echo "Adding {len(items()) + 2} reminders to \\"$LIST\\". This takes a minute or two. Leave Reminders alone until it finishes…"
osascript - "$START" "$REPLACE" "$LIST" "$MORNING" "$MIDDAY" "$EVENING" "$REVIEW" <<'APPLESCRIPT'
property startOffset : 1
property listName : ""
property slotNames : {{"morning", "midday", "evening", "review"}}
property slotTimes : {{}}

on hm(s)
  set AppleScript's text item delimiters to ":"
  set p to text items of s
  set AppleScript's text item delimiters to ""
  return (((item 1 of p) as integer) * hours) + (((item 2 of p) as integer) * minutes)
end hm

on dayAt(n, secs)
  -- noon on the target day so daylight-saving changes can't push it to the wrong date
  set d to (current date)
  set time of d to 12 * hours
  set d to d + (startOffset + n - 1) * days
  set time of d to secs
  return d
end dayAt

on addOne(n, slot, theName, theBody)
  set secs to 0
  repeat with i from 1 to 4
    if item i of slotNames is slot then set secs to item i of slotTimes
  end repeat
  set d to my dayAt(n, secs)
  tell application "Reminders" to tell list listName
    try
      make new reminder with properties {{name:theName, body:theBody, due date:d, remind me date:d}}
    on error
      make new reminder with properties {{name:theName, body:theBody, due date:d}}
    end try
  end tell
end addOne

on run argv
  set startOffset to (item 1 of argv) as integer
  set replaceIt to (item 2 of argv) as integer
  set listName to item 3 of argv
  set slotTimes to {{my hm(item 4 of argv), my hm(item 5 of argv), my hm(item 6 of argv), my hm(item 7 of argv)}}
  tell application "Reminders"
    if replaceIt is 1 then
      delete (every reminder of list listName)
    else
      make new list with properties {{name:listName}}
    end if
  end tell
  -- Day 0: tonight, ten minutes from now
  set t to (current date) + 10 * minutes
  tell application "Reminders" to tell list listName to make new reminder with properties {{name:"Day 0 Tonight: start here", body:{as_str(TONIGHT)}, due date:t, remind me date:t}}
{rows}
  -- Day 50: set up the next 90 days
  my addOne(50, "review", "Day 50 Keep it running", "Set your ongoing reminders: nightly ledger, weekly review, weekly text to your brother. A streak ends. An identity keeps going.")
end run
APPLESCRIPT

echo "Done. Open Reminders and find \\"$LIST\\". Your first reminder (Day 0) goes off in 10 minutes."
'''
    p = os.path.join(HERE, "install-truth-ledger.command")
    open(p, "w").write(script); os.chmod(p, 0o755)

# ---------- Calendar backup (.ics), Day 1 = tomorrow's date at build time ----------
def esc(s): return s.replace('\\', '\\\\').replace(';', '\\;').replace(',', '\\,').replace('\n', '\\n')
def fold(line):
    b = line.encode(); out = []
    while len(b) > 74:
        cut = 74
        while (b[cut] & 0xC0) == 0x80: cut -= 1
        out.append(b[:cut].decode()); b = b[cut:]
    out.append(b.decode()); return '\r\n '.join(out)

def build_ics(day1):
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    L = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Be The Man//Truth Ledger//EN', 'CALSCALE:GREGORIAN', f'X-WR-CALNAME:{LIST_NAME}']
    for k, (d, slot, t, b) in enumerate(items()):
        h, m = TIMES[slot]
        start = datetime.datetime.combine(day1 + datetime.timedelta(days=d - 1), datetime.time(h, m))
        mins = {'review': 20, 'evening': 10}.get(slot, 5)
        L += ['BEGIN:VEVENT', f'UID:truth-ledger-{k}@bethemansystem.com', f'DTSTAMP:{stamp}',
              f'DTSTART:{start:%Y%m%dT%H%M%S}', f'DTEND:{start + datetime.timedelta(minutes=mins):%Y%m%dT%H%M%S}',
              f'SUMMARY:{esc(t)}', f'DESCRIPTION:{esc(b)}',
              'BEGIN:VALARM', 'ACTION:DISPLAY', f'DESCRIPTION:{esc(t)}', 'TRIGGER:PT0M', 'END:VALARM', 'END:VEVENT']
    L.append('END:VCALENDAR')
    open(os.path.join(HERE, 'Truth-Ledger.ics'), 'w', newline='').write('\r\n'.join(fold(x) for x in L) + '\r\n')

if __name__ == '__main__':
    build_command()
    build_ics(datetime.date.today() + datetime.timedelta(days=1))
    import guide; guide.build(os.path.join(HERE, 'The-Truth-Ledger.html'))
    print(len(items()) + 2, 'reminders')
