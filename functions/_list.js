// Be The Man's own email list (replaces Kit).
//
// Everything lives in the FILES KV namespace and goes out through Resend:
//   c:<email>          a contact {email, name, tags[], status, created, source, fields, seq}
//                      (KV metadata holds a summary so lists and the scheduler stay cheap)
//   seqdef:<id>        an edited email series (otherwise the default in _sequences.js)
//   bc:<id>            a broadcast {id, subject, body, tag, status, created, sentAt, cursor, sent, failed}
//   bcr:<id>           the recipients of a broadcast, snapshotted when it is sent
//   log:<n>            one line per email sent (kept 90 days)
//   count:<date>       emails sent per Central-time day (for the daily cap)
//
// Marketing email carries an unsubscribe link and the one-click unsubscribe
// header, and the mailing address in the footer (CAN-SPAM). Nobody who
// unsubscribed or bounced is emailed by a series or a broadcast.
//
// The daily cap (MAIL_DAILY_CAP, default 90) keeps the list inside Resend's
// free plan of 100 emails a day, leaving room for receipts and alerts. Raise it
// if Resend is upgraded.

import { sign, unsign } from "./_club.js";
import { SEQUENCES } from "./_sequences.js";

export const SITE = "https://bethemansystem.com";
export const BRIAN = "brian@bethemansystem.com";
const FROM = "Brian Greene <brian@bethemansystem.com>";
export const ADDRESS = "Be The Man, PO Box 3425, Huntsville, AL 35810, USA";
const DISCLAIMER = "Be The Man is a faith-based coaching and consistency system, not medical treatment, diagnosis, or clinical therapy for ADHD.";
const DAY = 86400000;

const now = () => Date.now();
const ckey = (email) => "c:" + email;
export const cleanEmail = (e) => String(e || "").trim().toLowerCase().slice(0, 200);
export const validEmail = (e) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e);

function centralDay(ms = now()) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Chicago" }).format(new Date(ms));
}

// ---------- contacts ----------

function nextDue(c) {
  let n = 0;
  for (const s of Object.values(c.seq || {})) if (!s.done && s.next && (!n || s.next < n)) n = s.next;
  return n;
}

function meta(c) {
  const active = Object.entries(c.seq || {}).filter(([, s]) => !s.done).map(([id]) => id).join(",");
  return { n: (c.name || "").slice(0, 60), t: (c.tags || []).join("|").slice(0, 500), s: c.status, d: c.created, nx: c.status === "active" ? nextDue(c) : 0, q: active };
}

export async function getContact(env, email) {
  return env.FILES.get(ckey(cleanEmail(email)), "json");
}

export async function putContact(env, c) {
  await env.FILES.put(ckey(c.email), JSON.stringify(c), { metadata: meta(c) });
  return c;
}

// Add or update a contact. A man who signs up again through a form opts back in.
export async function upsertContact(env, { email, name, tags = [], source, fields, optIn = true }) {
  email = cleanEmail(email);
  if (!validEmail(email) || !env.FILES) return null;
  let c = await getContact(env, email);
  if (!c) c = { email, name: "", tags: [], status: "active", created: now(), source: source || "", fields: {}, seq: {} };
  if (name && !c.name) c.name = String(name).trim().slice(0, 80);
  for (const t of tags) if (t && !c.tags.includes(t)) c.tags.push(t);
  if (fields) c.fields = { ...(c.fields || {}), ...fields };
  if (optIn && c.status === "unsubscribed") { c.status = "active"; c.resubscribed = now(); }
  return putContact(env, c);
}

export async function removeTag(env, email, tag) {
  const c = await getContact(env, email);
  if (!c) return null;
  c.tags = c.tags.filter((t) => t !== tag);
  return putContact(env, c);
}

export async function setStatus(env, email, status) {
  const c = await getContact(env, email);
  if (!c) return null;
  c.status = status;
  if (status !== "active") c[status] = now();
  return putContact(env, c);
}

// Every contact's summary, from KV metadata (no per-contact reads).
export async function allContacts(env) {
  const out = [];
  let cursor;
  do {
    const page = await env.FILES.list({ prefix: "c:", cursor, limit: 1000 });
    for (const k of page.keys) out.push({ email: k.name.slice(2), ...(k.metadata || {}) });
    cursor = page.list_complete ? null : page.cursor;
  } while (cursor);
  return out;
}

// ---------- series ----------

export async function getSequence(env, id) {
  const saved = env.FILES ? await env.FILES.get("seqdef:" + id, "json") : null;
  const def = SEQUENCES[id];
  if (!def) return null;
  return saved ? { ...def, emails: saved.emails, edited: saved.edited } : def;
}

export async function allSequences(env) {
  return Promise.all(Object.keys(SEQUENCES).map((id) => getSequence(env, id)));
}

function dueAt(def, state, step) {
  const e = def.emails[step];
  if (!e) return 0;
  return def.kind === "dated" ? Date.parse(e.at) : state.start + (e.delayDays || 0) * DAY;
}

// First step that hasn't passed yet (dated series skip dates already gone).
function firstStep(def, from, start) {
  let step = from;
  if (def.kind === "dated") while (def.emails[step] && Date.parse(def.emails[step].at) < start) step++;
  return step;
}

// Put a contact into a series. Returns the contact (not saved).
export async function enroll(env, c, id) {
  const def = await getSequence(env, id);
  if (!def || (c.seq && c.seq[id])) return c;
  c.seq = c.seq || {};
  const start = now();
  const step = firstStep(def, 0, start);
  const st = { step, start };
  if (step >= def.emails.length) st.done = true; else st.next = dueAt(def, st, step);
  c.seq[id] = st;
  return c;
}

// ---------- rendering ----------

const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]);
const safeUrl = (u) => (/^(https?:|mailto:)/i.test(u) ? u : "#");

function inline(s) {
  return s
    .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (m, t, u) => `<a href="${safeUrl(u)}" style="color:#b8730f">${t}</a>`)
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
}

export function bodyHtml(body, c) {
  const first = (c && c.name ? c.name.trim().split(/\s+/)[0] : "") || "friend";
  const text = esc(String(body || "").replace(/\{\{first_name\}\}/g, first));
  return text.split(/\n\s*\n/).map((block) => {
    const b = block.trim();
    const btn = b.match(/^\[\[([^|\]]+)\|([^\]]+)\]\]$/);
    if (btn) return `<p style="margin:0 0 18px"><a href="${safeUrl(btn[2].trim())}" style="display:inline-block;background:#e18b1f;color:#0b0b0c;font-weight:700;text-decoration:none;padding:14px 26px;border-radius:12px">${btn[1].trim()}</a></p>`;
    const lines = b.split("\n");
    if (lines.every((l) => /^\s*- /.test(l))) return `<ul style="margin:0 0 16px;padding-left:22px">${lines.map((l) => `<li style="margin:0 0 6px">${inline(l.replace(/^\s*- /, ""))}</li>`).join("")}</ul>`;
    return `<p style="margin:0 0 16px">${inline(lines.join("<br>"))}</p>`;
  }).join("");
}

export async function unsubUrl(env, email) {
  const t = await sign(env, { e: email, p: "unsub", x: Math.floor(now() / 1000) + 10 * 365 * 86400 });
  return `${SITE}/api/mail/unsub?t=${t}`;
}

export function emailHtml(inner, unsub) {
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>` +
    `<body style="margin:0;padding:0;background:#f4f2ee"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f2ee"><tr><td align="center" style="padding:32px 16px">` +
    `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:16px"><tr><td style="padding:36px 32px;font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;color:#1d1d1f;font-size:17px;line-height:1.55">` +
    `<p style="margin:0 0 14px;font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#b8730f">Be The Man</p>${inner}</td></tr></table>` +
    `<p style="max-width:560px;margin:16px auto 0;font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.5;color:#6e6e73">${esc(DISCLAIMER)}<br>${esc(ADDRESS)}<br>` +
    (unsub ? `You're getting this because you signed up at bethemansystem.com. <a href="${unsub}" style="color:#6e6e73">Unsubscribe</a>.` : "") +
    `</p></td></tr></table></body></html>`;
}

// ---------- sending ----------

async function resend(env, { to, subject, html, headers }) {
  if (!env.RESEND_API_KEY) return { ok: false, error: "no RESEND_API_KEY" };
  try {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({ from: FROM, to: [to], subject, html, reply_to: BRIAN, headers }),
    });
    const d = await r.json().catch(() => ({}));
    return r.ok ? { ok: true, id: d.id } : { ok: false, error: d.message || `Resend ${r.status}` };
  } catch (e) {
    return { ok: false, error: String(e) };
  }
}

export async function sentToday(env) {
  return Number((await env.FILES.get("count:" + centralDay())) || 0);
}

async function bumpCount(env) {
  const k = "count:" + centralDay();
  const n = Number((await env.FILES.get(k)) || 0) + 1;
  await env.FILES.put(k, String(n), { expirationTtl: 3 * 86400 });
}

async function log(env, entry) {
  const k = "log:" + String(9e15 - now()).padStart(16, "0") + Math.random().toString(36).slice(2, 6);
  await env.FILES.put(k, "", { metadata: { ...entry, at: now() }, expirationTtl: 90 * 86400 });
}

export async function recentLog(env, limit = 50) {
  const page = await env.FILES.list({ prefix: "log:", limit });
  return page.keys.map((k) => k.metadata || {});
}

export const dailyCap = (env) => Number(env.MAIL_DAILY_CAP || 90);

// One list email to one contact. kind: "series:<id>" | "broadcast:<id>" | "result".
export async function sendToContact(env, c, { subject, body }, kind) {
  if (!c || c.status !== "active") return { ok: false, skipped: true };
  const unsub = await unsubUrl(env, c.email);
  const r = await resend(env, {
    to: c.email, subject, html: emailHtml(bodyHtml(body, c), unsub),
    headers: { "List-Unsubscribe": `<${unsub}>`, "List-Unsubscribe-Post": "List-Unsubscribe=One-Click" },
  });
  await log(env, { e: c.email, s: subject.slice(0, 120), k: kind, ok: r.ok ? 1 : 0, err: r.ok ? undefined : String(r.error).slice(0, 160) });
  if (r.ok) await bumpCount(env);
  return r;
}

// A test copy to Brian (not logged, no daily count).
export async function sendTest(env, { subject, body }, to = BRIAN) {
  return resend(env, { to, subject: "[Test] " + subject, html: emailHtml(bodyHtml(body, { name: "Brian" }), `${SITE}/#unsubscribe-preview`) });
}

// Send every series email that is due for this contact, then save it.
export async function runContact(env, c, budget = Infinity) {
  let sent = 0;
  for (const [id, st] of Object.entries(c.seq || {})) {
    if (st.done || !st.next || st.next > now() || sent >= budget) continue;
    const def = await getSequence(env, id);
    if (!def) { st.done = true; continue; }
    const email = def.emails[st.step];
    if (email) {
      const r = await sendToContact(env, c, email, "series:" + id);
      if (!r.ok && !r.skipped) { st.fails = (st.fails || 0) + 1; if (st.fails < 3) { st.next = now() + 3600000; continue; } }
      if (r.ok) sent++;
    }
    st.step = firstStep(def, st.step + 1, now());
    st.fails = 0;
    if (st.step >= def.emails.length) { st.done = true; delete st.next; } else st.next = dueAt(def, st, st.step);
  }
  await putContact(env, c);
  return sent;
}

// ---------- broadcasts ----------

export async function getBroadcast(env, id) {
  return env.FILES.get("bc:" + id, "json");
}

export async function putBroadcast(env, b) {
  await env.FILES.put("bc:" + b.id, JSON.stringify(b), { metadata: { s: b.subject.slice(0, 120), st: b.status, t: b.tag || "", c: b.created, sent: b.sent || 0, total: b.total || 0 } });
  return b;
}

export async function allBroadcasts(env) {
  const page = await env.FILES.list({ prefix: "bc:", limit: 1000 });
  return page.keys.map((k) => ({ id: k.name.slice(3), ...(k.metadata || {}) })).sort((a, b) => (b.c || 0) - (a.c || 0));
}

// Snapshot the recipients and mark the broadcast as sending.
export async function queueBroadcast(env, b) {
  const all = await allContacts(env);
  const to = all.filter((c) => c.s === "active" && (!b.tag || (c.t || "").split("|").includes(b.tag))).map((c) => c.email);
  await env.FILES.put("bcr:" + b.id, JSON.stringify(to));
  Object.assign(b, { status: "sending", total: to.length, cursor: 0, sent: 0, failed: 0, queuedAt: now() });
  return putBroadcast(env, b);
}

// ---------- the scheduler ----------

// Sends what is due, within the daily cap. Safe to call often.
export async function tick(env, { max = 200 } = {}) {
  if (!env.FILES || !env.RESEND_API_KEY) return { ok: false, error: "not configured" };
  const lock = await env.FILES.get("lock:tick");
  if (lock && now() - Number(lock) < 90000) return { ok: true, busy: true };
  await env.FILES.put("lock:tick", String(now()), { expirationTtl: 120 });
  let budget = Math.min(max, dailyCap(env) - (await sentToday(env)));
  const out = { ok: true, series: 0, broadcast: 0, capped: budget <= 0 };
  try {
    // Series first: they are personal and time-sensitive.
    if (budget > 0) {
      const due = (await allContacts(env)).filter((c) => c.s === "active" && c.nx && c.nx <= now());
      for (const s of due) {
        if (budget <= 0) break;
        const c = await getContact(env, s.email);
        if (!c) continue;
        const n = await runContact(env, c, budget);
        out.series += n;
        budget -= n;
      }
    }
    // Then broadcasts that are sending.
    for (const meta of await allBroadcasts(env)) {
      if (budget <= 0 || meta.st !== "sending") continue;
      const b = await getBroadcast(env, meta.id);
      const to = (await env.FILES.get("bcr:" + b.id, "json")) || [];
      while (b.cursor < to.length && budget > 0) {
        const c = await getContact(env, to[b.cursor]);
        const r = await sendToContact(env, c, b, "broadcast:" + b.id);
        b.cursor++;
        if (r.ok) { b.sent++; budget--; out.broadcast++; } else if (!r.skipped) b.failed++;
        if (b.cursor % 10 === 0) await putBroadcast(env, b);
      }
      if (b.cursor >= to.length) { b.status = "sent"; b.sentAt = now(); }
      await putBroadcast(env, b);
    }
    out.capped = out.capped || budget <= 0;
  } finally {
    await env.FILES.delete("lock:tick");
  }
  return out;
}

export async function verifyUnsub(env, token) {
  const t = await unsign(env, token);
  return t && t.p === "unsub" ? t.e : null;
}
