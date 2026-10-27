// Central-time helpers shared by the call booking and the workshop schedule.

export const TZ = "America/Chicago";

// Offset of Central time from UTC at a given instant, in minutes (-300 or -360).
export function offsetMinutes(ms) {
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

export function centralDate(ms) {
  const p = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit", weekday: "short" })
      .formatToParts(new Date(ms)).map((x) => [x.type, x.value])
  );
  return { y: +p.year, m: +p.month, d: +p.day, dow: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].indexOf(p.weekday) };
}
