// Schedules Kit broadcast drafts from the "SCHEDULE: <Day> <Mon> <D>, <h:mm> AM|PM Central." line
// in each draft's description.
//
//   KIT_API_KEY=... node scripts/kit-schedule.mjs            # dry run: shows what would be scheduled
//   KIT_API_KEY=... node scripts/kit-schedule.mjs --apply    # schedules every future draft
//   ... --apply --past=send-now   # past-due drafts go out 10 minutes from now (default: left as drafts)
//   ... --only=26434663,26434587  # limit to these broadcast ids
//
// Never touches a broadcast that isn't a draft, so it is safe to run again.

import { centralToUtc } from "../functions/_booking.js";

const KIT = "https://api.kit.com/v4";
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// "SCHEDULE: Tue Oct 27, 6:00 AM Central." -> ISO time in UTC. Dates from Oct to Dec are 2026, Jan to Sep 2027.
export function parseSchedule(description) {
  const m = /SCHEDULE:\s*\w{3}\s+(\w{3})\s+(\d{1,2}),\s*(\d{1,2}):(\d{2})\s*(AM|PM)\s+Central/i.exec(description || "");
  if (!m) return null;
  const month = MONTHS.indexOf(m[1]) + 1;
  if (!month) return null;
  let hour = +m[3] % 12;
  if (m[5].toUpperCase() === "PM") hour += 12;
  const year = month >= 10 ? 2026 : 2027;
  return new Date(centralToUtc(year, month, +m[2], hour, +m[4])).toISOString();
}

export async function run({ key, apply = false, past = "skip", only = null, now = Date.now(), log = console.log }) {
  const kit = (path, init = {}) =>
    fetch(KIT + path, { ...init, headers: { "x-kit-api-key": key, "content-type": "application/json", accept: "application/json" } })
      .then(async (r) => ({ ok: r.ok, status: r.status, body: await r.json().catch(() => ({})) }));
  const drafts = [];
  let after = "";
  do {
    const r = await kit(`/broadcasts?per_page=100${after ? "&after=" + after : ""}`);
    if (!r.ok) throw new Error(`Kit list failed (${r.status}): ${JSON.stringify(r.body)}`);
    drafts.push(...r.body.broadcasts);
    after = r.body.pagination?.has_next_page ? r.body.pagination.end_cursor : "";
  } while (after);

  const results = [];
  for (const b of drafts) {
    if (only && !only.includes(b.id)) continue;
    const at = parseSchedule(b.description);
    if (!at) continue;
    if (b.send_at || b.status !== "draft") { results.push({ id: b.id, subject: b.subject, action: "already " + b.status, at: b.send_at }); continue; }
    let when = at;
    if (Date.parse(at) <= now + 5 * 60000) {
      if (past !== "send-now") { results.push({ id: b.id, subject: b.subject, action: "past due, left as draft", at }); continue; }
      when = new Date(now + 10 * 60000).toISOString();
    }
    if (!apply) { results.push({ id: b.id, subject: b.subject, action: "would schedule", at: when }); continue; }
    const r = await kit(`/broadcasts/${b.id}`, { method: "PUT", body: JSON.stringify({ send_at: when }) });
    const check = await kit(`/broadcasts/${b.id}`);
    const sa = check.body.broadcast?.send_at;
    const ok = r.ok && sa && Math.abs(Date.parse(sa) - Date.parse(when)) < 60000;
    results.push({ id: b.id, subject: b.subject, action: ok ? "scheduled" : `FAILED (${r.status}) ${JSON.stringify(r.body).slice(0, 200)}`, at: when });
  }
  results.sort((a, b) => String(a.at).localeCompare(String(b.at)));
  const fmt = (iso) => iso ? new Intl.DateTimeFormat("en-US", { timeZone: "America/Chicago", weekday: "short", month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit" }).format(new Date(iso)) + " CT" : "";
  for (const x of results) log(`${x.action.padEnd(26)} ${fmt(x.at).padEnd(30)} ${x.id}  ${x.subject}`);
  return results;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const key = process.env.KIT_API_KEY;
  if (!key) { console.error("KIT_API_KEY is not set."); process.exit(2); }
  const arg = (n) => process.argv.find((a) => a.startsWith(`--${n}`));
  const onlyArg = arg("only=");
  const res = await run({
    key, apply: !!arg("apply"),
    past: arg("past=") ? arg("past=").split("=")[1] : "skip",
    only: onlyArg ? onlyArg.split("=")[1].split(",").map(Number) : null,
  });
  if (res.some((x) => x.action.startsWith("FAILED"))) process.exit(1);
}
