// Free 15-minute call booking (/call/). Brian calls the man at the time he picks.
// Open times: Monday to Thursday evenings, Central time, for the next two weeks,
// minus Brian's standing commitments below. Bookings live in the FILES KV
// namespace under "booking:<start time>".
//
// To block a day (travel, family), add it to OFF_DAYS as "YYYY-MM-DD".

export const TZ = "America/Chicago";
const DAYS = [1, 2, 3, 4]; // Mon to Thu
const TIMES = ["19:00", "19:20", "19:40", "20:00", "20:20", "20:40"];
export const CALL_MINUTES = 15;
const HORIZON_DAYS = 14;
const MIN_NOTICE_MS = 12 * 3600 * 1000;
export const OFF_DAYS = [];

// Brian's standing commitments (from his calendar), as [from, to) in Central time.
function busy(date, dow, dayOfMonth) {
  const out = [];
  // Inner Circle weekly class: Thursdays 7 to 8 PM, from Nov 5, 2026.
  if (dow === 4 && date >= "2026-11-05") out.push(["19:00", "20:00"]);
  // Club live call: second Tuesday of the month, 7 to 8 PM.
  if (dow === 2 && dayOfMonth >= 8 && dayOfMonth <= 14) out.push(["19:00", "20:00"]);
  return out;
}

// Offset of Central time from UTC at a given instant, in minutes (-300 or -360).
function offsetMinutes(ms) {
  const p = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", { timeZone: TZ, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" })
      .formatToParts(new Date(ms)).map((x) => [x.type, x.value])
  );
  return (Date.UTC(+p.year, p.month - 1, +p.day, +p.hour, +p.minute) - Math.floor(ms / 60000) * 60000) / 60000;
}

// Central wall-clock time -> UTC milliseconds.
export function centralToUtc(y, m, d, hh, mm) {
  const guess = Date.UTC(y, m - 1, d, hh, mm);
  return guess - offsetMinutes(guess - offsetMinutes(guess) * 60000) * 60000;
}

function centralDate(ms) {
  const p = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit", weekday: "short" })
      .formatToParts(new Date(ms)).map((x) => [x.type, x.value])
  );
  return { y: +p.year, m: +p.month, d: +p.day, dow: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].indexOf(p.weekday) };
}

// Every open start time (ISO, UTC) from now through the horizon, before removing booked ones.
export function openTimes(now = Date.now()) {
  const out = [];
  for (let i = 0; i <= HORIZON_DAYS; i++) {
    const { y, m, d, dow } = centralDate(now + i * 86400000);
    const date = `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
    if (!DAYS.includes(dow) || OFF_DAYS.includes(date)) continue;
    const blocks = busy(date, dow, d);
    for (const t of TIMES) {
      if (blocks.some(([a, b]) => t >= a && t < b)) continue;
      const [hh, mm] = t.split(":").map(Number);
      const ms = centralToUtc(y, m, d, hh, mm);
      if (ms - now >= MIN_NOTICE_MS) out.push(new Date(ms).toISOString());
    }
  }
  return out;
}

export function label(iso) {
  return new Intl.DateTimeFormat("en-US", { timeZone: TZ, weekday: "long", month: "long", day: "numeric", hour: "numeric", minute: "2-digit" })
    .format(new Date(iso)) + " Central";
}

const icsDate = (ms) => new Date(ms).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
const icsText = (v) => String(v || "").replace(/[\;,]/g, (c) => "\\" + c).replace(/\r?\n/g, "\\n");

// A calendar file for the call, base64-encoded for a Resend attachment.
export function icsFile({ start, uid, summary, description }) {
  const ms = Date.parse(start);
  const ics = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Be The Man//Free call//EN", "METHOD:PUBLISH",
    "BEGIN:VEVENT", `UID:${uid}@bethemansystem.com`, `DTSTAMP:${icsDate(Date.now())}`,
    `DTSTART:${icsDate(ms)}`, `DTEND:${icsDate(ms + CALL_MINUTES * 60000)}`,
    `SUMMARY:${icsText(summary)}`, `DESCRIPTION:${icsText(description)}`,
    "BEGIN:VALARM", "TRIGGER:-PT10M", "ACTION:DISPLAY", "DESCRIPTION:Call", "END:VALARM",
    "END:VEVENT", "END:VCALENDAR", "",
  ].join("\r\n");
  const bytes = new TextEncoder().encode(ics);
  let bin = "";
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return { filename: "free-call.ics", content: btoa(bin) };
}
