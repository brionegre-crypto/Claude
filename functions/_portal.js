// The men's portal: data, rules and shared logic.
//
// KV keys:
//   pd:<email>        a man's portal record (worksheets, commitments, marks, reviews, ...)
//   pn:<email>        Brian's private notes on him (never sent to the man)
//   msg:<email>:<n>   messages and prayer requests between a man and Brian
//   up:<email>:<id>   a photo of a paper Ledger (image bytes)
//   pcode:<phone>     a text sign-in code (10 minutes)
//   sh:<token>        a share link -> email
//   sessions          per-session recording link and catch-up note
//   lessons           Brian's edited lessons and materials (else _lessons.js)
//
// Steps: 1 The Calling, 2 The Commitments, 3 The Floor, 4 The Ledger.
// A step opens on its date (pace) once the step before it is approved by Brian.

import { sign, unsign } from "./_club.js";
import { COHORT_DATES } from "./_booking.js";
import { getContact, putContact, addEvent, upsertContact, emailBrian, emailHtml, bodyHtml, centralDay, SITE, BRIAN, uid } from "./_list.js";
import { sendEmail } from "./_mail.js";
import { sendSms, smsReady, toE164 } from "./_sms.js";
import { LESSONS, MATERIALS, EXAMPLES } from "./_lessons.js";

export const COOKIE = "btm_portal";
const DAY = 86400000;
const now = () => Date.now();
export const STEPS = { 1: "The Calling", 2: "The Commitments", 3: "The Floor", 4: "The Ledger" };
// With the cohort pace, a step opens on the day of its session.
const COHORT_STEP_DATE = { 1: null, 2: COHORT_DATES[1], 3: COHORT_DATES[2], 4: COHORT_DATES[4] };
// Lesson week -> the step it belongs to.
export const WEEK_STEP = { 1: 1, 2: 2, 3: 3, 4: 3, 5: 4, 6: 4 };

export const today = () => centralDay();

// ---------- dates (YYYY-MM-DD in Central) ----------

const d2ms = (d) => Date.parse(d + "T12:00:00Z");
const ms2d = (ms) => new Date(ms).toISOString().slice(0, 10);
export const addDays = (d, n) => ms2d(d2ms(d) + n * DAY);
export const dow = (d) => new Date(d2ms(d)).getUTCDay(); // 0 Sunday
// Weeks run Monday to Sunday; a week is named by its Sunday.
export const weekOf = (d) => addDays(d, (7 - dow(d)) % 7);
export const weekDays = (w) => [6, 5, 4, 3, 2, 1, 0].map((n) => addDays(w, -n));

// ---------- records ----------

export function blankRecord(email, role) {
  return {
    email, role: role || "cohort", access: "full", pace: { mode: "cohort", dates: {} }, steps: {}, commitments: [], commitHistory: [],
    marks: {}, reviews: {}, hard: {}, next: [], shared: [], callPrep: {}, attendance: {}, reflections: {}, uploads: [],
    partner: "", share: { on: false, token: "" }, reminders: { hour: 20, channel: "email" }, created: now(), lastActive: 0,
    graduated: false, flags: {},
  };
}

export async function getRecord(env, email) { return env.FILES.get("pd:" + String(email || "").toLowerCase(), "json"); }
export async function putRecord(env, pd) { await env.FILES.put("pd:" + pd.email, JSON.stringify(pd), { metadata: summaryMeta(pd) }); return pd; }

export async function allRecords(env) {
  const out = [];
  let cursor;
  do {
    const page = await env.FILES.list({ prefix: "pd:", cursor, limit: 1000 });
    for (const k of page.keys) out.push({ email: k.name.slice(3), ...(k.metadata || {}) });
    cursor = page.list_complete ? null : page.cursor;
  } while (cursor);
  return out;
}

// Create a portal record for a man if he doesn't have one (payment, Step 1, Brian).
export async function ensureRecord(env, email, { role, name } = {}) {
  email = String(email || "").trim().toLowerCase();
  let pd = await getRecord(env, email);
  const rank = { step1: 0, club: 1, cohort: 2, admin: 3 };
  if (!pd) {
    pd = blankRecord(email, role);
    await upsertContact(env, { email, name, tags: role === "step1" ? [] : ["Portal"], optIn: false, run: false });
    await putRecord(env, pd);
    return { pd, created: true };
  }
  if (role && (rank[role] || 0) > (rank[pd.role] || 0)) { pd.role = role; pd.access = "full"; await putRecord(env, pd); }
  return { pd, created: false };
}

// ---------- steps ----------

function stepDate(pd, n) {
  if (n === 1) return null;
  if (pd.pace.mode === "self") return null;
  if (pd.pace.mode === "custom") return (pd.pace.dates || {})[n] || null;
  return COHORT_STEP_DATE[n];
}

export function stepState(pd, n) {
  const s = pd.steps[n] || {};
  if (s.status && s.status !== "locked") return { status: s.status, opens: null };
  if (pd.role === "step1" && n > 1) return { status: "locked", opens: null, upgrade: true };
  // Brian's own system: every step is open, no waiting on dates or approval.
  if (pd.role === "admin") return { status: "open", opens: null };
  if (s.forced) return { status: "open", opens: null };
  const prevOk = n === 1 || (pd.steps[n - 1] && pd.steps[n - 1].status === "approved");
  const date = stepDate(pd, n);
  const dateOk = !date || today() >= date;
  return { status: prevOk && dateOk ? "open" : "locked", opens: date, waitingOn: prevOk ? null : n - 1 };
}

export function stepStates(pd) { const o = {}; for (const n of [1, 2, 3, 4]) o[n] = stepState(pd, n); return o; }
export const scorecardOn = (pd) => pd.commitments.some((c) => c.active !== false && c.what);

// ---------- commitments and the scorecard ----------

export function cleanCommitments(list) {
  return (list || []).slice(0, 3).map((c) => ({
    id: c.id || uid(),
    what: String(c.what || "").slice(0, 200),
    pillar: ["faith", "home", "health", "work"].includes(c.pillar) ? c.pillar : "",
    days: (Array.isArray(c.days) ? c.days : []).map(Number).filter((n) => n >= 0 && n <= 6),
    measure: String(c.measure || "").slice(0, 160),
    miss: String(c.miss || "").slice(0, 160),
    time: /^\d{2}:\d{2}$/.test(c.time || "") ? c.time : "",
    place: String(c.place || "").slice(0, 120),
    trigger: String(c.trigger || "").slice(0, 160),
    breaks: String(c.breaks || "").slice(0, 200),
    floor: String(c.floor || "").slice(0, 200),
    active: c.active !== false,
    since: /^\d{4}-\d{2}-\d{2}$/.test(c.since || "") ? c.since : "",
  })).filter((c) => c.what);
}

export function setCommitments(pd, list, by) {
  const next = cleanCommitments(list);
  // A commitment counts from the day it was written (an existing one keeps its date).
  for (const c of next) { const old = pd.commitments.find((o) => o.id === c.id); c.since = (old && old.since) || c.since || today(); }
  if (JSON.stringify(next) === JSON.stringify(pd.commitments)) return false;
  if (pd.commitments.length) {
    pd.commitHistory.unshift({ at: now(), by: by || "him", list: pd.commitments });
    pd.commitHistory = pd.commitHistory.slice(0, 30);
  }
  pd.commitments = next;
  return true;
}

export const scheduledOn = (c, d) => c.active !== false && (!c.since || d >= c.since) && (c.days.length ? c.days.includes(dow(d)) : true);

// The week's number from daily taps: kept and floor count as kept.
export function weekScore(pd, w) {
  let k = 0, t = 0, f = 0, m = 0;
  for (const d of weekDays(w)) {
    for (const c of pd.commitments) {
      if (!scheduledOn(c, d)) continue;
      const v = (pd.marks[d] || {})[c.id];
      if (d > today() && !v) continue;
      t++;
      if (v === "k") k++;
      else if (v === "f") { k++; f++; }
      else if (v === "m") m++;
    }
  }
  return { k, t, floor: f, missed: m };
}

export const canMark = (d) => d <= today() && d >= addDays(today(), -2);

// Weeks reported in a row (a week counts if it has a Sunday review or a Ledger number).
export function streak(pd, ledger) {
  let n = 0;
  let w = weekOf(today());
  if (!(pd.reviews[w] || (ledger && ledger[w]))) w = addDays(w, -7);
  while (pd.reviews[w] || (ledger && ledger[w])) { n++; w = addDays(w, -7); }
  return n;
}

// Per-man insight for Brian: trend, most-missed commitment, flags.
export function insights(pd, contact) {
  const ledger = (contact && contact.ledger) || {};
  const weeks = [];
  let w = weekOf(today());
  for (let i = 0; i < 8; i++) {
    const s = weekScore(pd, w);
    const L = ledger[w];
    const k = s.t ? s.k : L ? L.k : null, t = s.t ? s.t : L ? L.t : null;
    weeks.unshift({ week: w, k, t, pct: t ? Math.round((100 * k) / t) : null, reviewed: !!pd.reviews[w] || !!L });
    w = addDays(w, -7);
  }
  const misses = {};
  for (const [d, row] of Object.entries(pd.marks)) {
    if (d < addDays(today(), -28)) continue;
    for (const [cid, v] of Object.entries(row)) if (v === "m") misses[cid] = (misses[cid] || 0) + 1;
  }
  const worst = Object.entries(misses).sort((a, b) => b[1] - a[1])[0];
  const mostMissed = worst ? { what: (pd.commitments.find((c) => c.id === worst[0]) || {}).what || "(removed commitment)", count: worst[1] } : null;
  const flags = [];
  // Only weeks that ended after his portal was made can raise a flag.
  const joined = pd.created ? centralDay(pd.created) : "";
  const done = weeks.filter((x) => x.week < weekOf(today()) && x.week >= joined);
  const last2 = done.slice(-2);
  if (last2.length === 2 && last2.every((x) => x.pct != null && x.pct < 50)) flags.push("Two weeks under 50%");
  if (last2.length === 2 && last2.every((x) => !x.reviewed)) flags.push("No report two Sundays running");
  if (pd.lastActive && now() - pd.lastActive > 7 * DAY) flags.push("Quiet for 7+ days");
  const missedSessions = COHORT_DATES.filter((d) => d < today() && !pd.attendance[d]).length;
  if (pd.role === "cohort" && missedSessions >= 2) flags.push(`Missed ${missedSessions} sessions`);
  const waiting = [1, 2, 3, 4].filter((n) => pd.steps[n] && pd.steps[n].status === "submitted");
  if (waiting.length) flags.push(`Step ${waiting.join(", ")} waiting for your approval`);
  return { weeks, mostMissed, flags, streak: streak(pd, ledger), lastActive: pd.lastActive, attendance: COHORT_DATES.map((d) => ({ date: d, here: !!pd.attendance[d], past: d < today() })) };
}

export function summaryMeta(pd) {
  const s = stepStates(pd);
  const cur = [4, 3, 2, 1].find((n) => s[n].status !== "locked") || 1;
  const w = weekScore(pd, addDays(weekOf(today()), -7));
  return {
    r: pd.role, a: pd.access, st: cur + ":" + s[cur].status, la: pd.lastActive || 0, g: pd.graduated ? 1 : 0,
    wk: w.t ? `${w.k}/${w.t}` : "", sub: [1, 2, 3, 4].filter((n) => pd.steps[n] && pd.steps[n].status === "submitted").join(","),
    pace: pd.pace.mode, p: pd.partner || "",
  };
}

// What the man himself may see (no private notes, no admin-only fields).
export function forMan(pd) {
  const { flags, ...rest } = pd;
  return rest;
}

// ---------- safety ----------

const DANGER = /\b(suicid\w*|kill (my ?self|myself)|end (my|it all|my life)|want to die|wanna die|better off dead|no reason to live|self[- ]?harm|hurt (my ?self|myself)|don'?t want to (be here|live)|take my (own )?life)\b/i;
export const isDanger = (text) => DANGER.test(String(text || ""));
export const CRISIS = "If you're in crisis or thinking about ending your life, call or text 988 (Suicide & Crisis Lifeline) now, or call 911. Brian has been alerted and will reach out.";

export async function safetyCheck(env, waitUntil, pd, name, text, where) {
  if (!isDanger(text)) return false;
  const who = `${name || pd.email} (${pd.email})`;
  const p = (async () => {
    await emailBrian(env, `URGENT: check on ${name || pd.email} now`, `**${who}** wrote something in his portal (${where}) that may mean he is thinking about harming himself:\n\n"${String(text).slice(0, 600)}"\n\nPlease reach him today. If he is in immediate danger, call 911. The 988 Suicide & Crisis Lifeline (call or text 988) can also guide you.`);
    if (env.ADMIN_PHONE && smsReady(env)) await sendSms(env, { to: env.ADMIN_PHONE, body: `Be The Man URGENT: ${name || pd.email} wrote something in his portal that may mean self-harm. Check your email and reach him now.` });
  })().catch(() => null);
  if (waitUntil) waitUntil(p); else await p;
  pd.flags = pd.flags || {};
  pd.flags.safety = now();
  return true;
}

// ---------- sign-in ----------

export async function portalCookie(env, email) {
  const t = await sign(env, { p: "portal", e: email, x: Math.floor(now() / 1000) + 60 * 86400 });
  return `${COOKIE}=${t}; Path=/; Max-Age=${60 * 86400}; HttpOnly; Secure; SameSite=Lax`;
}
export const clearPortalCookie = `${COOKIE}=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Lax`;

export async function portalUser(request, env) {
  const m = (request.headers.get("cookie") || "").match(new RegExp(`(?:^|;\\s*)${COOKIE}=([^;]+)`));
  const d = m ? await unsign(env, m[1]) : null;
  return d && d.p === "portal" ? d.e : null;
}

export async function sendSignInLink(env, email, next) {
  const t = await sign(env, { p: "plogin", e: email, x: Math.floor(now() / 1000) + 1800 });
  const url = `${SITE}/api/portal/verify?t=${t}${next ? "&next=" + encodeURIComponent(next) : ""}`;
  const c = await getContact(env, email);
  const first = c && c.name ? c.name.split(/\s+/)[0] : "Brother";
  return sendEmail(env, { to: email, subject: "Your Be The Man sign-in link",
    html: emailHtml(bodyHtml(`${first}, here is your sign-in link. It works for 30 minutes.\n\n[[Open my portal|${url}]]\n\nIf you didn't ask for this, ignore it.`, c || {}), null) });
}

export async function sendSignInCode(env, phone) {
  const p = toE164(phone);
  if (!p || !smsReady(env)) return false;
  const email = await env.FILES.get("p:" + p);
  if (!email || !(await getRecord(env, email))) return true; // same answer either way
  const code = String(Math.floor(100000 + Math.random() * 900000));
  await env.FILES.put("pcode:" + p, JSON.stringify({ code, e: email, tries: 0 }), { expirationTtl: 600 });
  await sendSms(env, { to: p, body: `Be The Man: your sign-in code is ${code}. It works for 10 minutes.` });
  return true;
}

export async function checkSignInCode(env, phone, code) {
  const p = toE164(phone);
  const rec = p ? await env.FILES.get("pcode:" + p, "json") : null;
  if (!rec) return null;
  if (rec.code !== String(code || "").trim()) {
    rec.tries++;
    if (rec.tries >= 5) await env.FILES.delete("pcode:" + p); else await env.FILES.put("pcode:" + p, JSON.stringify(rec), { expirationTtl: 600 });
    return null;
  }
  await env.FILES.delete("pcode:" + p);
  return rec.e;
}

// ---------- tokens for calendar and share ----------

export async function calendarUrl(env, email) {
  return `${SITE}/api/portal-cal?t=${await sign(env, { p: "cal", e: email, x: Math.floor(now() / 1000) + 5 * 365 * 86400 })}`;
}
export async function readCalToken(env, t) { const d = await unsign(env, t); return d && d.p === "cal" ? d.e : null; }

export async function setShare(env, pd, on) {
  if (on && !pd.share.token) {
    pd.share.token = Math.random().toString(36).slice(2, 10) + Math.random().toString(36).slice(2, 6);
  }
  if (pd.share.token) {
    if (on) await env.FILES.put("sh:" + pd.share.token, pd.email);
    else await env.FILES.delete("sh:" + pd.share.token);
  }
  pd.share.on = !!on;
}

// ---------- calendar file ----------

const ICS_DAY = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];
const icsEsc = (s) => String(s || "").replace(/[\\;,]/g, (c) => "\\" + c).replace(/\n/g, "\\n");
export function calendarFile(pd, name) {
  const lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Be The Man//Portal//EN", "CALSCALE:GREGORIAN", "METHOD:PUBLISH", `X-WR-CALNAME:${icsEsc((name ? name + "'s " : "") + "Be The Man commitments")}`,
    "BEGIN:VTIMEZONE", "TZID:America/Chicago", "BEGIN:DAYLIGHT", "TZOFFSETFROM:-0600", "TZOFFSETTO:-0500", "TZNAME:CDT", "DTSTART:19700308T020000", "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU", "END:DAYLIGHT",
    "BEGIN:STANDARD", "TZOFFSETFROM:-0500", "TZOFFSETTO:-0600", "TZNAME:CST", "DTSTART:19701101T020000", "RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU", "END:STANDARD", "END:VTIMEZONE"];
  const start = today().replace(/-/g, "");
  for (const c of pd.commitments) {
    if (c.active === false || !c.time) continue;
    const [h, m] = c.time.split(":");
    const days = (c.days.length ? c.days : [0, 1, 2, 3, 4, 5, 6]).map((d) => ICS_DAY[d]).join(",");
    lines.push("BEGIN:VEVENT", `UID:btm-${pd.email.replace(/[^a-z0-9]/g, "")}-${c.id}@bethemansystem.com`, `DTSTAMP:${new Date().toISOString().replace(/[-:]/g, "").slice(0, 15)}Z`,
      `DTSTART;TZID=America/Chicago:${start}T${h}${m}00`, "DURATION:PT15M", `RRULE:FREQ=WEEKLY;BYDAY=${days}`,
      `SUMMARY:${icsEsc(c.what)}`, `LOCATION:${icsEsc(c.place)}`,
      `DESCRIPTION:${icsEsc(`${c.trigger ? "Trigger: " + c.trigger + "\n" : ""}${c.floor ? "Bad-day version: " + c.floor + "\n" : ""}Mark it in your portal: ${SITE}/portal/`)}`,
      "BEGIN:VALARM", "ACTION:DISPLAY", `DESCRIPTION:${icsEsc(c.what)}`, "TRIGGER:-PT10M", "END:VALARM", "END:VEVENT");
  }
  lines.push("END:VCALENDAR");
  return lines.join("\r\n") + "\r\n";
}

// ---------- lessons and sessions ----------

export async function getLibrary(env) {
  const saved = (await env.FILES.get("lessons", "json")) || {};
  return { lessons: saved.lessons || LESSONS, materials: saved.materials || MATERIALS, examples: EXAMPLES, edited: saved.edited || 0 };
}
export async function saveLibrary(env, lib) { await env.FILES.put("lessons", JSON.stringify({ lessons: lib.lessons, materials: lib.materials, edited: now() })); }

export async function getSessions(env) { return (await env.FILES.get("sessions", "json")) || {}; }
export async function saveSessions(env, s) { await env.FILES.put("sessions", JSON.stringify(s)); }

export function lessonOpen(pd, week) {
  if (pd.role === "admin") return true;
  if (pd.role === "step1") return week === 1;
  if (pd.pace.mode === "cohort") return week === 1 || today() >= COHORT_DATES[week - 1];
  const st = stepState(pd, WEEK_STEP[week]).status;
  return st !== "locked";
}

export function nextSession(d = today()) { return COHORT_DATES.find((x) => x >= d) || null; }
export function inCheckInWindow(ms = now()) {
  const d = centralDay(ms);
  if (!COHORT_DATES.includes(d)) return null;
  const h = Number(new Intl.DateTimeFormat("en-US", { timeZone: "America/Chicago", hour: "numeric", minute: "numeric", hourCycle: "h23" }).format(new Date(ms)).replace(":", "."));
  return h >= 18.3 && h <= 20.3 ? d : null;
}

// ---------- messages ----------

export async function addMessage(env, email, from, type, text) {
  const key = `msg:${email}:${String(now()).padStart(14, "0")}${Math.random().toString(36).slice(2, 5)}`;
  const m = { from, type, text: String(text).slice(0, 3000), at: now() };
  await env.FILES.put(key, JSON.stringify(m), { metadata: { f: from, y: type, at: m.at, s: m.text.slice(0, 120) } });
  return m;
}
export async function thread(env, email) {
  const page = await env.FILES.list({ prefix: `msg:${email}:` });
  const out = [];
  for (const k of page.keys) { const v = await env.FILES.get(k.name, "json"); if (v) out.push(v); }
  return out;
}
export async function inbox(env) {
  const page = await env.FILES.list({ prefix: "msg:" });
  const byMan = {};
  for (const k of page.keys) {
    const email = k.name.split(":")[1];
    const m = k.metadata || {};
    const cur = byMan[email] || { email, last: 0, unread: 0, preview: "", type: "" };
    if (m.at > cur.last) { cur.last = m.at; cur.preview = m.s; cur.type = m.y; cur.from = m.f; }
    byMan[email] = cur;
  }
  return Object.values(byMan).sort((a, b) => b.last - a.last);
}

// ---------- graduation and access ----------

export async function graduate(env, pd) {
  pd.graduated = true;
  pd.graduatedAt = now();
  const c = await getContact(env, pd.email);
  const club = c && c.tags.includes("Club member");
  if (!club && pd.role !== "admin") pd.access = "readonly";
  if (c) { if (!c.tags.includes("Founding Cohort graduate")) c.tags.push("Founding Cohort graduate"); addEvent(c, "graduated", ""); await putContact(env, c); }
  return pd;
}

export { DAY };

// First email when a portal is made for him (payment, Club, Brian). The link works for 7 days.
export async function sendWelcome(env, email, role) {
  const t = await sign(env, { p: "plogin", e: email, x: Math.floor(now() / 1000) + 7 * 86400 });
  const url = `${SITE}/api/portal/verify?t=${t}`;
  const c = await getContact(env, email);
  const first = c && c.name ? c.name.split(/\s+/)[0] : "Brother";
  const what = role === "club"
    ? "Your Club membership includes the Be The Man portal: your four steps, your daily scorecard, your Sunday review and private messages with me."
    : "Your Founding Cohort seat includes the Be The Man portal. It's where you'll work the four steps, tap your commitments each day, do your Sunday review and message me privately.";
  return sendEmail(env, { to: email, subject: "Your Be The Man portal is ready",
    html: emailHtml(bodyHtml(`${first}, ${what}\n\nStep 1, The Calling, is open now.\n\n[[Open my portal|${url}]]\n\nThis button signs you in for the next 7 days. After that, sign in any time at ${SITE}/portal with your email. No password.\n\nOn your phone? Once you're in, add it to your home screen so it opens like an app.\n\nPrefer paper? Every worksheet prints, and you can report your number or upload a photo of your paper Ledger.\n\nBrian`, c || {}), null) });
}
