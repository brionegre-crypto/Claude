// Fix Your Wednesday: a live one-hour workshop on Google Meet, every other
// Wednesday, 7:00 to 8:00 PM Central, from Nov 4, 2026. A ticket is for the next
// session that hasn't started yet when the man pays.
//
// To cancel one session, add its date to SKIP as "YYYY-MM-DD"; buyers then
// roll to the session after it. Keep web/build.py's WORKSHOP_* values in step.

import { centralToUtc, centralDate } from "./_time.js";

export const FIRST = "2026-11-04";
export const EVERY_DAYS = 14;
export const SKIP = [];
export const MEET = "https://meet.google.com/mdt-djbx-kfo";

const day = (date) => Date.UTC(+date.slice(0, 4), date.slice(5, 7) - 1, +date.slice(8, 10)) / 86400000;

export function isSessionDate(date) {
  const n = day(date) - day(FIRST);
  return n >= 0 && n % EVERY_DAYS === 0 && !SKIP.includes(date);
}

const startOf = (date) => centralToUtc(+date.slice(0, 4), +date.slice(5, 7), +date.slice(8, 10), 19, 0);

// The session a ticket bought at `ms` is for: { date, start (ISO), label, tag }.
export function nextSession(ms = Date.now()) {
  const { y, m, d } = centralDate(ms);
  let n = Math.max(0, day(`${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`) - day(FIRST));
  n = Math.ceil(n / EVERY_DAYS) * EVERY_DAYS;
  for (let i = 0; i < 60; i++, n += EVERY_DAYS) {
    const date = new Date((day(FIRST) + n) * 86400000).toISOString().slice(0, 10);
    if (SKIP.includes(date) || startOf(date) <= ms) continue;
    const label = new Intl.DateTimeFormat("en-US", { timeZone: "UTC", weekday: "long", month: "long", day: "numeric" }).format(new Date(date + "T12:00:00Z"));
    return { date, start: new Date(startOf(date)).toISOString(), label, tag: `Workshop ${date}` };
  }
  return null;
}
