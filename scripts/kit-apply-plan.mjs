// Reschedules Kit broadcasts (and fixes date-bound wording) from a plan file.
//
//   KIT_API_KEY=... node scripts/kit-apply-plan.mjs                       # dry run, shows every change
//   KIT_API_KEY=... node scripts/kit-apply-plan.mjs --apply               # makes the changes
//   ... --apply --resend-completed   # also sends a FRESH COPY of emails Kit already delivered
//   ... --plan=scripts/other-plan.json --only=26434619,26434620
//
// Per item: GET the broadcast; for a draft or scheduled one, apply the text replacements to its
// content and set send_at, description, subject and preview_text. An item is skipped, untouched,
// when its content does not match a replacement exactly once or its send time is in the past.
// Emails Kit has already sent are skipped unless --resend-completed (that creates a new broadcast
// to the same audience, so existing subscribers would see the email again).

import { readFileSync } from "node:fs";

const KIT = "https://api.kit.com/v4";
const fmt = (iso) => iso ? new Intl.DateTimeFormat("en-US", { timeZone: "America/Chicago", weekday: "short", month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit" }).format(new Date(iso)) + " CT" : "";

export function applyReplacements(content, pairs) {
  let out = content;
  for (const [a, b] of pairs) {
    const n = out.split(a).length - 1;
    if (n !== 1) return { ok: false, why: `"${a.slice(0, 50)}" found ${n} times` };
    out = out.replace(a, () => b);
  }
  return { ok: true, content: out };
}

export async function run({ key, plan, apply = false, resendCompleted = false, only = null, now = Date.now(), log = console.log }) {
  const kit = (path, init = {}) =>
    fetch(KIT + path, { ...init, headers: { "x-kit-api-key": key, "content-type": "application/json", accept: "application/json" } })
      .then(async (r) => ({ ok: r.ok, status: r.status, body: await r.json().catch(() => ({})) }));
  const rows = [];
  for (const it of plan.items) {
    if (only && !only.includes(it.id)) continue;
    const row = (action) => rows.push({ id: it.id, label: it.label, action, at: it.send_at });
    if (Date.parse(it.send_at) <= now + 5 * 60000) { row("skipped: send time is in the past"); continue; }
    const r = await kit(`/broadcasts/${it.id}`);
    if (!r.ok || !r.body.broadcast) { row(`FAILED to read (${r.status}): ${JSON.stringify(r.body).slice(0, 120)}`); continue; }
    const b = r.body.broadcast;
    let content = b.content;
    if (it.replace && it.replace.length) {
      const res = applyReplacements(b.content || "", it.replace);
      if (!res.ok) { row(`NEEDS ATTENTION, left as is: ${res.why}`); continue; }
      content = res.content;
    }
    const fields = { send_at: it.send_at, description: it.description };
    if (it.subject) fields.subject = it.subject;
    if (it.preview_text) fields.preview_text = it.preview_text;
    if (content !== b.content) fields.content = content;
    if (["completed", "sending", "aborted"].includes(b.status)) {
      if (!resendCompleted) { row(`already ${b.status}, skipped (use --resend-completed for a fresh copy)`); continue; }
      if (!apply) { row("would create a fresh copy and schedule it"); continue; }
      const copy = { subject: fields.subject || b.subject, preview_text: fields.preview_text ?? b.preview_text, content, description: it.description, public: false,
        email_address: b.email_address, email_template_id: b.email_template && b.email_template.id, subscriber_filter: b.subscriber_filter, send_at: it.send_at };
      const c = await kit("/broadcasts", { method: "POST", body: JSON.stringify(copy) });
      row(c.ok ? "created a fresh copy, scheduled" : `FAILED to create (${c.status}): ${JSON.stringify(c.body).slice(0, 160)}`);
      continue;
    }
    if (!apply) { row(`would update (${b.status})${fields.content ? " + wording" : ""}`); continue; }
    const u = await kit(`/broadcasts/${it.id}`, { method: "PUT", body: JSON.stringify(fields) });
    const v = await kit(`/broadcasts/${it.id}`);
    const sa = v.body.broadcast && v.body.broadcast.send_at;
    const ok = u.ok && sa && Math.abs(Date.parse(sa) - Date.parse(it.send_at)) < 60000;
    row(ok ? "updated and verified" : `FAILED (${u.status}): ${JSON.stringify(u.body).slice(0, 160)}`);
  }
  rows.sort((a, b) => a.at.localeCompare(b.at));
  for (const x of rows) log(`${x.action.padEnd(58)} ${fmt(x.at).padEnd(30)} ${x.id}  ${x.label}`);
  return rows;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const key = process.env.KIT_API_KEY;
  if (!key) { console.error("KIT_API_KEY is not set."); process.exit(2); }
  const arg = (n) => process.argv.find((a) => a.startsWith(`--${n}`));
  const planFile = arg("plan=") ? arg("plan=").split("=")[1] : new URL("./kit-december-plan.json", import.meta.url).pathname;
  const onlyArg = arg("only=");
  const rows = await run({ key, plan: JSON.parse(readFileSync(planFile, "utf8")), apply: !!arg("apply"), resendCompleted: !!arg("resend-completed"),
    only: onlyArg ? onlyArg.split("=")[1].split(",").map(Number) : null });
  if (rows.some((x) => x.action.startsWith("FAILED") || x.action.startsWith("NEEDS"))) process.exit(1);
}
