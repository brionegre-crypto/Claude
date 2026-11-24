// Portal jobs, run by the hourly scheduler (runAll in _extras.js):
//   daily reminders at each man's chosen hour, the quiet-man check-in after 7 days,
//   Wednesday call-prep reminders, the Monday backup email, and Club access checks.
// Each job marks what it sent in KV so a repeat run in the same hour sends nothing twice.

import { allRecords, getRecord, putRecord, addDays, scheduledOn, nextSession } from "./_portal.js";
import { getContact, emailHtml, bodyHtml, centralDay, SITE, BRIAN, emailBrian, textContact } from "./_list.js";
import { sendEmail } from "./_mail.js";
import { stripe, clubSubscription } from "./_club.js";
import { buildBackup } from "./_portaladmin.js";

const DAY = 86400000;
const PORTAL = `${SITE}/portal/`;
function central(ms = Date.now()) {
  const p = new Intl.DateTimeFormat("en-US", { timeZone: "America/Chicago", weekday: "short", hour: "numeric", hourCycle: "h23" }).formatToParts(new Date(ms));
  const get = (t) => (p.find((x) => x.type === t) || {}).value;
  return { dow: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].indexOf(get("weekday")), hour: Number(get("hour")), date: centralDay(ms) };
}
const first = (c) => (c && c.name ? c.name.split(/\s+/)[0] : "Brother");
const once = async (env, key, ttlDays) => { if (await env.FILES.get(key)) return false; await env.FILES.put(key, "1", { expirationTtl: Math.max(60, ttlDays * 86400) }); return true; };
const mail = (env, c, subject, body) => sendEmail(env, { to: c.email, subject, html: emailHtml(bodyHtml(body, c), null) });

export async function portalJobs(env) {
  const { dow, hour, date } = central();
  const out = { reminders: 0, quiet: 0, prep: 0 };
  const recs = await allRecords(env);

  for (const r of recs) {
    if (r.a === "readonly") continue;
    const pd = await getRecord(env, r.email);
    if (!pd || pd.access === "readonly") continue;
    const c = await getContact(env, pd.email);
    if (!c || c.status === "unsubscribed" || c.status === "bounced" || c.status === "complained") continue;

    // 1. Daily reminder at his hour, only if today has something unmarked.
    const rm = pd.reminders || {};
    if (rm.on && Number(rm.hour) === hour) {
      const due = pd.commitments.filter((x) => scheduledOn(x, date) && !(pd.marks[date] || {})[x.id]);
      if (due.length && (await once(env, `prem:${pd.email}:${date}`, 2))) {
        const list = due.map((x) => x.what).join("; ");
        const texted = rm.channel === "sms" && (await textContact(env, c, `Mark your day: ${due.length} left (${list.slice(0, 90)}). ${PORTAL}`, "portal-reminder")).ok;
        if (!texted) {
          await mail(env, c, "Mark your day", `${first(c)}, ${due.length === 1 ? "one commitment is" : due.length + " commitments are"} still open today:\n\n${due.map((x) => "- " + x.what).join("\n")}\n\nA floor day counts as kept.\n\n[[Mark my day|${PORTAL}]]\n\nTurn these reminders off in your portal settings.`);
        }
        out.reminders++;
      }
    }

    // 2. Quiet for 7 days: one gentle note to him (10 AM), and Brian sees the flag.
    if (hour === 10 && (pd.role === "cohort" || pd.role === "club") && pd.lastActive && Date.now() - pd.lastActive > 7 * DAY && !pd.graduated) {
      if (await once(env, `pquiet:${pd.email}`, 14)) {
        await mail(env, c, "Checking on you, brother", `${first(c)}, I haven't seen you in the portal for a week. No guilt here. Weeks like that happen to every one of us.\n\nYou don't have to catch up. Just start with today. Pick the floor version of one commitment and mark it.\n\n[[Open my portal|${PORTAL}]]\n\nIf something is going on, reply to this email. I read every one.\n\nBrian`);
        out.quiet++;
        out.quietMen = (out.quietMen || []).concat(c.name || c.email);
      }
    }

    // 3. Wednesday 6 PM before a session: ask what he wants help with.
    if (dow === 3 && hour === 18 && pd.role === "cohort") {
      const s = nextSession(date);
      if (s === addDays(date, 1) && !pd.callPrep[s] && (await once(env, `pprep:${pd.email}:${s}`, 3))) {
        await mail(env, c, "What do you want help with tomorrow?", `${first(c)}, we meet tomorrow at 7 PM Central.\n\nBefore the call, tell me one thing you want help with: the commitment that keeps slipping, a question, anything. It takes a minute, and it helps me use our time well.\n\n[[Tell Brian|${PORTAL}#today]]\n\nBrian`);
        out.prep++;
      }
    }
  }
  if (out.quietMen && out.quietMen.length) await emailBrian(env, `Quiet for a week: ${out.quietMen.length} ${out.quietMen.length === 1 ? "man" : "men"}`, `These men haven't opened their portal for 7 days. Each got a short note from you:\n\n${out.quietMen.map((n) => "- " + n).join("\n")}\n\nA personal text goes further.\n\n[[Open Men|${SITE}/admin/#men]]`);

  // 4. Monday 7 AM: the weekly backup, emailed to Brian as a file.
  if (dow === 1 && hour === 7 && (await once(env, `pbackup:${date}`, 8))) {
    try {
      const data = JSON.stringify(await buildBackup(env));
      const b64 = btoa(unescape(encodeURIComponent(data)));
      await sendEmail(env, { to: BRIAN, subject: `Weekly backup: ${date}`, html: emailHtml(bodyHtml(`Your weekly backup of the portal and your list is attached. Keep it somewhere safe, like a folder in your Google Drive.\n\nYou can also download one any time from the dashboard: Men, then Download backup.`, { name: "Brian" }), null),
        attachments: [{ filename: `be-the-man-backup-${date}.json`, content: b64 }] });
      out.backup = true;
    } catch (e) { out.backupError = String(e); }
  }

  // 5. 3 AM daily: Club members whose membership ended become read-only.
  if (hour === 3 && env.STRIPE_KEY && (await once(env, `pclub:${date}`, 2))) {
    let changed = 0;
    for (const r of recs.filter((x) => x.r === "club" && x.a !== "readonly")) {
      const list = await stripe(env, `/customers?email=${encodeURIComponent(r.email)}&limit=10`);
      if (!list || !Array.isArray(list.data)) continue; // Stripe didn't answer: change nothing
      let active = false;
      for (const cu of list.data) if (await clubSubscription(env, cu.id)) { active = true; break; }
      if (!active) { const pd = await getRecord(env, r.email); if (pd) { pd.access = "readonly"; await putRecord(env, pd); changed++; } }
    }
    out.clubEnded = changed;
  }
  return out;
}
