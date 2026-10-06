"""Turn calendar.csv into an .ics file for Apple Calendar (America/Chicago).
Each post is a 15-minute event with a 30-minute reminder; the notes hold the
folder name and the Instagram caption so you can copy it straight from the event.
Usage: python3 make_ics.py
"""
import csv, os, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
rows = list(csv.DictReader(open(os.path.join(HERE, 'calendar.csv'))))
HOUR = {'9am': 9, '12pm': 12, '4pm': 16, '7pm': 19}
TYPE = {'post': 'Post', 'carousel': 'Carousel', 'reel': 'Reel'}

def esc(s):
    return s.replace('\\', '\\\\').replace(';', '\\;').replace(',', '\\,').replace('\n', '\\n')

def fold(line):
    b = line.encode('utf-8'); out = []
    while len(b) > 74:
        cut = 74
        while (b[cut] & 0xC0) == 0x80:  # don't split a UTF-8 character
            cut -= 1
        out.append(b[:cut].decode()); b = b[cut:]
    out.append(b.decode())
    return '\r\n '.join(out)

stamp = datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
L = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Be The Man//Content Calendar//EN', 'CALSCALE:GREGORIAN',
     'X-WR-CALNAME:Be The Man content', 'X-WR-TIMEZONE:America/Chicago',
     'BEGIN:VTIMEZONE', 'TZID:America/Chicago',
     'BEGIN:DAYLIGHT', 'TZOFFSETFROM:-0600', 'TZOFFSETTO:-0500', 'TZNAME:CDT', 'DTSTART:19700308T020000', 'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU', 'END:DAYLIGHT',
     'BEGIN:STANDARD', 'TZOFFSETFROM:-0500', 'TZOFFSETTO:-0600', 'TZNAME:CST', 'DTSTART:19701101T020000', 'RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU', 'END:STANDARD',
     'END:VTIMEZONE']
for r in rows:
    d = datetime.date.fromisoformat(r['date'])
    start = datetime.datetime(d.year, d.month, d.day, HOUR[r['time']])
    end = start + datetime.timedelta(minutes=15)
    brand = 'BTM' if r['brand'] == 'Be The Man' else 'Couples'
    import re as _re
    title = f"📱 {brand} {TYPE[r['type']]}: {_re.sub(r'^(Reel|Carousel): ', '', r['title'])}"
    cap_path = os.path.join(HERE, 'posts', r['folder'], 'instagram.txt')
    cap = open(cap_path).read().strip() if os.path.exists(cap_path) else ''
    notes = (f"Post to Instagram, Facebook and Threads.\nFolder: {r['folder']}\n"
             f"(captions: instagram.txt, facebook.txt, threads.txt)\n\nInstagram caption:\n{cap}")
    L += ['BEGIN:VEVENT', f"UID:{r['folder']}@bethemansystem", f'DTSTAMP:{stamp}',
          f"DTSTART;TZID=America/Chicago:{start:%Y%m%dT%H%M%S}", f"DTEND;TZID=America/Chicago:{end:%Y%m%dT%H%M%S}",
          fold('SUMMARY:' + esc(title)), fold('DESCRIPTION:' + esc(notes)),
          f"CATEGORIES:{brand}", 'BEGIN:VALARM', 'ACTION:DISPLAY', 'TRIGGER:-PT30M', fold('DESCRIPTION:' + esc(title)), 'END:VALARM',
          'END:VEVENT']
L.append('END:VCALENDAR')
out = os.path.join(HERE, 'Be-The-Man-content-calendar.ics')
open(out, 'w', newline='').write('\r\n'.join(fold(x) if not x.startswith(' ') else x for x in L) + '\r\n')
print(out, len(rows), 'events')
