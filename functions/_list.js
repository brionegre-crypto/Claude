// Be The Man's own email and text list (replaces Kit).
//
// Storage: the FILES KV namespace. Email: Resend. Texts: Twilio (functions/_sms.js).
//
//   c:<email>        a contact (see upsertContact); KV metadata holds a summary
//   p:<+1phone>      phone -> email index for incoming texts
//   seqdef:<id>      an edited email series (otherwise the default in _sequences.js)
//   autos            every automation          segments  every saved segment
//   forms            every form                 st:<key>  stats for one email or text
//   bc:<id>          a broadcast (email or text); bcr:<id> its recipients
//   log:<n>          one line per email sent   slog:<n>  one line per text sent or received
//   count:<day>      emails sent that day      scount:<day> texts sent that day
//   meta:lasttick    when the scheduler last ran
//
// Rules built in: unsubscribe link and one-click header on every list email, the
// mailing address in the footer, no list email to anyone unsubscribed, bounced,
// complained or unconfirmed, and daily caps for email (MAIL_DAILY_CAP, default 90,
// inside Resend's free 100 a day) and texts (SMS_DAILY_CAP, default 50).

import { sign, unsign } from "./_club.js";
import { SEQUENCES } from "./_sequences.js";
import { sendSms, smsReady, smsCap, listText, inQuietHours, nextSendWindow, toE164 } from "./_sms.js";

export const SITE = "https://bethemansystem.com";
export const BRIAN = "brian@bethemansystem.com";
const FROM = "Brian Greene <brian@bethemansystem.com>";
export const ADDRESS = "Be The Man, PO Box 3425, Huntsville, AL 35810, USA";
const DISCLAIMER = "Be The Man is a faith-based coaching and consistency system, not medical treatment, diagnosis, or clinical therapy for ADHD.";
const DAY = 86400000;
const MAX_EVENTS = 40;

const now = () => Date.now();
export const cleanEmail = (e) => String(e || "").trim().toLowerCase().slice(0, 200);
export const validEmail = (e) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e);
const ckey = (email) => "c:" + email;
const uid = () => now().toString(36) + Math.random().toString(36).slice(2, 7);
export const centralDay = (ms = now()) => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Chicago" }).format(new Date(ms));
const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]);
const safeUrl = (u) => (/^(https?:|mailto:|tel:|sms:)/i.test(u) ? u : "#");

// ---------- contacts ----------

export function engagement(c) {
  const s = c.stats || {};
  const last = Math.max(s.lastOpen || 0, s.lastClick || 0);
  if (last && now() - last < 30 * DAY) return "engaged";
  if (last && now() - last < 90 * DAY) return "warm";
  if ((s.sent || 0) >= 3) return "cold";
  return "new";
}

function nextDue(c) {
  let n = 0;
  for (const s of [...Object.values(c.seq || {}), ...Object.values(c.auto || {})]) if (!s.done && s.next && (!n || s.next < n)) n = s.next;
  return n;
}

function meta(c) {
  const active = [...Object.entries(c.seq || {}), ...Object.entries(c.auto || {}).map(([k, v]) => ["a:" + k, v])]
    .filter(([, s]) => !s.done).map(([id]) => id).join(",");
  const s = c.stats || {};
  return {
    n: (c.name || "").slice(0, 60), t: (c.tags || []).join("|").slice(0, 400), s: c.status, d: c.created,
    nx: ["active", "unsubscribed"].includes(c.status) ? nextDue(c) : 0, q: active.slice(0, 200),
    ph: c.phone || "", sm: (c.sms && c.sms.status) || "", en: engagement(c), lo: s.lastOpen || 0, lc: s.lastClick || 0, sn: s.sent || 0,
    so: (c.src || "").slice(0, 40), rc: c.refCount || 0, lg: c.ledger ? Object.keys(c.ledger).length : 0,
  };
}

export async function getContact(env, email) {
  return env.FILES.get(ckey(cleanEmail(email)), "json");
}

export async function putContact(env, c) {
  await env.FILES.put(ckey(c.email), JSON.stringify(c), { metadata: meta(c) });
  return c;
}

export async function contactByPhone(env, phone) {
  const e = await env.FILES.get("p:" + phone);
  return e ? getContact(env, e) : null;
}

export function addEvent(c, type, detail) {
  c.events = c.events || [];
  c.events.unshift({ t: now(), y: type, d: String(detail || "").slice(0, 160) });
  if (c.events.length > MAX_EVENTS) c.events.length = MAX_EVENTS;
}

// Add or update a contact, apply tags, record text consent, and fire automations
// for any new tag. A man who signs up again through a form opts back in to email.
//   phone, smsConsent: {source, ip}  -> records consent to texts
//   status: "unconfirmed" for double opt-in forms (only for new contacts)
export async function upsertContact(env, { email, name, tags = [], source, fields, optIn = true, phone, smsConsent, status, run = true, autos: useAutos = true }) {
  email = cleanEmail(email);
  if (!validEmail(email) || !env.FILES) return null;
  let c = await getContact(env, email);
  const isNew = !c;
  if (!c) {
    c = { email, name: "", tags: [], status: status || "active", created: now(), source: source || "", fields: {}, seq: {}, auto: {}, stats: {}, events: [] };
    addEvent(c, "joined", source || "");
  }
  if (name && !c.name) c.name = String(name).trim().slice(0, 80);
  if (fields) c.fields = { ...(c.fields || {}), ...fields };
  if (optIn && ["unsubscribed"].includes(c.status)) { c.status = "active"; addEvent(c, "resubscribed", source); }
  if (!isNew && status === "unconfirmed") { /* existing contacts stay as they are */ }
  const p = toE164(phone);
  if (p && p !== c.phone) {
    if (c.phone) await env.FILES.delete("p:" + c.phone);
    c.phone = p;
    await env.FILES.put("p:" + p, email);
  }
  let smsJoined = false;
  if (p && smsConsent && (!c.sms || c.sms.status !== "subscribed")) {
    c.sms = { status: "subscribed", consentAt: now(), source: smsConsent.source || source || "", ip: smsConsent.ip || "", text: "SMS_CONSENT" };
    addEvent(c, "texts on", smsConsent.source || source);
    smsJoined = true;
  }
  const added = [];
  for (const t of tags) if (t && !c.tags.includes(t)) { c.tags.push(t); added.push(t); }
  if (added.length) addEvent(c, "tagged", added.join(", "));
  if (c.status !== "unconfirmed" && useAutos) {
    const autos = await getAutomations(env);
    for (const t of added) startTriggered(c, autos, "tag", t);
    if (smsJoined) startTriggered(c, autos, "sms", "");
  }
  await putContact(env, c);
  if (run && c.status === "active") await runContact(env, c, 3);
  return c;
}

export async function addTag(env, c, tag, autos) {
  if (!tag || c.tags.includes(tag)) return;
  c.tags.push(tag);
  addEvent(c, "tagged", tag);
  startTriggered(c, autos || (await getAutomations(env)), "tag", tag);
}

export async function removeTag(env, email, tag) {
  const c = await getContact(env, email);
  if (!c) return null;
  c.tags = c.tags.filter((t) => t !== tag);
  addEvent(c, "untagged", tag);
  return putContact(env, c);
}

export async function setStatus(env, email, status, why) {
  const c = await getContact(env, email);
  if (!c) return null;
  if (c.status !== status) addEvent(c, status, why || "");
  c.status = status;
  return putContact(env, c);
}

export async function setSms(env, c, status, why) {
  c.sms = { ...(c.sms || {}), status, [status + "At"]: now() };
  addEvent(c, status === "subscribed" ? "texts on" : "texts off", why || "");
  if (status === "subscribed") startTriggered(c, await getAutomations(env), "sms", "");
  return putContact(env, c);
}

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

// ---------- segments ----------
// A segment: {id, name, all: [tags], any: [tags], none: [tags], status, engagement,
//             joinedAfter, joinedBefore (YYYY-MM-DD), texts: "subscribed" | "", field: {key, value}}

export async function getSegments(env) { return (await env.FILES.get("segments", "json")) || []; }
export async function saveSegments(env, list) { await env.FILES.put("segments", JSON.stringify(list)); }

export function matches(seg, m, full) {
  const tags = (m.t || "").split("|").filter(Boolean);
  if (seg.all && seg.all.length && !seg.all.every((t) => tags.includes(t))) return false;
  if (seg.any && seg.any.length && !seg.any.some((t) => tags.includes(t))) return false;
  if (seg.none && seg.none.length && seg.none.some((t) => tags.includes(t))) return false;
  if (seg.status && m.s !== seg.status) return false;
  if (seg.engagement && m.en !== seg.engagement) return false;
  if (seg.joinedAfter && (m.d || 0) < Date.parse(seg.joinedAfter + "T00:00:00-06:00")) return false;
  if (seg.joinedBefore && (m.d || 0) >= Date.parse(seg.joinedBefore + "T00:00:00-06:00")) return false;
  if (seg.texts === "subscribed" && m.sm !== "subscribed") return false;
  if (seg.field && seg.field.key) {
    const v = full && full.fields ? String(full.fields[seg.field.key] ?? "") : "";
    if (seg.field.value ? v.toLowerCase() !== String(seg.field.value).toLowerCase() : !v) return false;
  }
  return true;
}

// The contacts an audience reaches. aud: {type: "all"|"tag"|"segment"|"unopened", value}
export async function audience(env, aud, channel = "email") {
  const all = await allContacts(env);
  let list = all.filter((m) => (channel === "sms" ? m.sm === "subscribed" && m.ph && m.s !== "complained" : m.s === "active"));
  if (aud && aud.type === "tag") list = list.filter((m) => (m.t || "").split("|").includes(aud.value));
  if (aud && aud.type === "segment") {
    const seg = (await getSegments(env)).find((s) => s.id === aud.value);
    if (!seg) return [];
    const out = [];
    for (const m of list) {
      const full = seg.field && seg.field.key ? await getContact(env, m.email) : null;
      if (matches(seg, m, full)) out.push(m);
    }
    list = out;
  }
  if (aud && aud.type === "unopened") {
    const b = await getBroadcast(env, aud.value);
    const opened = new Set(b && b.opened ? b.opened : []);
    const got = new Set((await env.FILES.get("bcr:" + aud.value, "json")) || []);
    list = list.filter((m) => got.has(m.email) && !opened.has(m.email));
  }
  return list;
}

// ---------- forms ----------
// A form: {id, name, headline, text, button, tag, series, automationNote, phone: bool,
//          sms: bool, doubleOptIn: bool, success, redirect, created}

export async function getForms(env) { return (await env.FILES.get("forms", "json")) || []; }
export async function saveForms(env, list) { await env.FILES.put("forms", JSON.stringify(list)); }
export async function getForm(env, id) { return (await getForms(env)).find((f) => f.id === id) || null; }

// ---------- automations ----------
// {id, name, enabled, trigger: {type: "form"|"tag"|"purchase"|"click"|"sms", value}, steps: [...]}
// Steps: {type:"wait", days, hours} {type:"email", subject, body} {type:"sms", text}
//        {type:"tag", tag} {type:"untag", tag} {type:"series", id} {type:"notify", text}
//        {type:"iftag", tag}  (stop unless the man has the tag)
//        {type:"ifnottag", tag} (stop if he has it)

export async function getAutomations(env) { return (await env.FILES.get("autos", "json")) || []; }
export async function saveAutomations(env, list) { await env.FILES.put("autos", JSON.stringify(list)); }

function triggerMatches(t, type, value) {
  if (!t || t.type !== type) return false;
  if (type === "click") return !t.value || String(value).includes(t.value);
  if (type === "sms") return true;
  return !t.value || String(t.value) === String(value);
}

// Start every enabled automation this event triggers (each runs once per man).
export function startTriggered(c, autos, type, value) {
  c.auto = c.auto || {};
  let started = 0;
  for (const a of autos) {
    if (!a.enabled || c.auto[a.id] || !triggerMatches(a.trigger, type, value)) continue;
    c.auto[a.id] = { step: 0, start: now(), next: now() };
    addEvent(c, "automation", a.name);
    started++;
  }
  return started;
}

export async function fireTrigger(env, c, type, value) {
  const n = startTriggered(c, await getAutomations(env), type, value);
  await putContact(env, c);
  if (n && c.status === "active") await runContact(env, c, 3);
  return n;
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

function firstStep(def, from, start) {
  let step = from;
  if (def.kind === "dated") while (def.emails[step] && Date.parse(def.emails[step].at) < start) step++;
  return step;
}

export async function enroll(env, c, id) {
  const def = await getSequence(env, id);
  if (!def || (c.seq && c.seq[id])) return c;
  c.seq = c.seq || {};
  const start = now();
  const step = firstStep(def, 0, start);
  const st = { step, start };
  if (step >= def.emails.length) st.done = true; else st.next = dueAt(def, st, step);
  c.seq[id] = st;
  addEvent(c, "series", def.name);
  return c;
}

// ---------- rendering and tracking ----------

async function token(env, data) {
  return sign(env, { ...data, x: Math.floor(now() / 1000) + 5 * 365 * 86400 });
}
export async function readToken(env, t) { return unsign(env, t); }

function merge(body, c) {
  const first = (c && c.name ? c.name.trim().split(/\s+/)[0] : "") || "friend";
  return String(body || "")
    .replace(/\{\{first_name\}\}/g, first)
    .replace(/\{\{name\}\}/g, (c && c.name) || "friend")
    .replace(/\{\{email\}\}/g, (c && c.email) || "")
    .replace(/\{\{referral_link\}\}/g, c && c.ref ? `${SITE}/r/${c.ref}` : `${SITE}/step-1/`)
    .replace(/\{\{([a-z0-9_]+)\}\}/gi, (m, k) => (c && c.fields && c.fields[k] != null ? String(c.fields[k]) : ""));
}

function inline(s, link) {
  return s
    .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (m, t, u) => `<a href="${link(safeUrl(u))}" style="color:#b8730f">${t}</a>`)
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
}

// track: {env, e, k, v} to rewrite links for click tracking (async: links collected first)
export async function bodyHtmlTracked(body, c, track) {
  const urls = new Map();
  const collect = (u) => { if (track && /^https?:/i.test(u) && !urls.has(u)) urls.set(u, null); return u; };
  const draft = renderBody(body, c, collect);
  if (!track || !urls.size) return draft;
  for (const u of urls.keys()) urls.set(u, `${SITE}/api/mail/c?t=${await token(track.env, { p: "click", e: track.e, k: track.k, v: track.v || "", u })}`);
  return renderBody(body, c, (u) => urls.get(u) || u);
}

function renderBody(body, c, link = (u) => u) {
  const text = esc(merge(body, c));
  return text.split(/\n\s*\n/).map((block) => {
    const b = block.trim();
    const btn = b.match(/^\[\[([^|\]]+)\|([^\]]+)\]\]$/);
    if (btn) return `<p style="margin:0 0 18px"><a href="${link(safeUrl(btn[2].trim()).replace(/&amp;/g, "&"))}" style="display:inline-block;background:#e18b1f;color:#0b0b0c;font-weight:700;text-decoration:none;padding:14px 26px;border-radius:12px">${btn[1].trim()}</a></p>`;
    const lines = b.split("\n");
    if (lines.every((l) => /^\s*- /.test(l))) return `<ul style="margin:0 0 16px;padding-left:22px">${lines.map((l) => `<li style="margin:0 0 6px">${inline(l.replace(/^\s*- /, ""), link)}</li>`).join("")}</ul>`;
    return `<p style="margin:0 0 16px">${inline(lines.join("<br>"), link)}</p>`;
  }).join("");
}

export function bodyHtml(body, c) { return renderBody(body, c); }

export async function unsubUrl(env, email, key) {
  return `${SITE}/api/mail/unsub?t=${await token(env, { e: email, p: "unsub", k: key || "" })}`;
}

export function emailHtml(inner, unsub, pixel) {
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>` +
    `<body style="margin:0;padding:0;background:#f4f2ee"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f2ee"><tr><td align="center" style="padding:32px 16px">` +
    `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:16px"><tr><td style="padding:36px 32px;font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;color:#1d1d1f;font-size:17px;line-height:1.55">` +
    `<p style="margin:0 0 14px;font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#b8730f">Be The Man</p>${inner}</td></tr></table>` +
    `<p style="max-width:560px;margin:16px auto 0;font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.5;color:#6e6e73">${esc(DISCLAIMER)}<br>${esc(ADDRESS)}<br>` +
    (unsub ? `You're getting this because you signed up at bethemansystem.com. <a href="${unsub}" style="color:#6e6e73">Unsubscribe</a>.` : "") +
    `</p>${pixel ? `<img src="${pixel}" width="1" height="1" alt="" style="display:block;border:0">` : ""}</td></tr></table></body></html>`;
}

// ---------- stats ----------

export async function getStats(env, key) {
  return (await env.FILES.get("st:" + key, "json")) || { sent: 0, opens: 0, clicks: 0, unsubs: 0, bounces: 0, links: {}, v: {} };
}

async function bump(env, key, field, variant, link) {
  if (!key) return;
  const s = await getStats(env, key);
  s[field] = (s[field] || 0) + 1;
  if (variant) { s.v[variant] = s.v[variant] || { sent: 0, opens: 0, clicks: 0 }; s.v[variant][field] = (s.v[variant][field] || 0) + 1; }
  if (link) s.links[link] = (s.links[link] || 0) + 1;
  await env.FILES.put("st:" + key, JSON.stringify(s), { expirationTtl: 400 * 86400 });
}

export async function recordOpen(env, t) {
  if (!t || t.p !== "open") return;
  const c = await getContact(env, t.e);
  if (!c) return;
  c.opened = c.opened || {};
  c.stats = c.stats || {};
  c.stats.lastOpen = now();
  if (!c.opened[t.k]) {
    c.opened[t.k] = now();
    const keys = Object.keys(c.opened);
    if (keys.length > 120) delete c.opened[keys[0]];
    c.stats.opens = (c.stats.opens || 0) + 1;
    addEvent(c, "opened", t.k);
    await bump(env, t.k, "opens", t.v);
    if (t.k.startsWith("bc:")) {
      const b = await getBroadcast(env, t.k.slice(3));
      if (b) { b.opened = b.opened || []; if (!b.opened.includes(c.email) && b.opened.length < 5000) { b.opened.push(c.email); await putBroadcast(env, b); } }
    }
  }
  await putContact(env, c);
}

export async function recordClick(env, t) {
  if (!t || t.p !== "click") return null;
  const c = await getContact(env, t.e);
  if (c) {
    c.stats = c.stats || {};
    c.stats.lastClick = now();
    c.stats.clicks = (c.stats.clicks || 0) + 1;
    c.clicked = c.clicked || {};
    const first = !c.clicked[t.k];
    c.clicked[t.k] = now();
    const keys = Object.keys(c.clicked);
    if (keys.length > 120) delete c.clicked[keys[0]];
    if (c.opened && !c.opened[t.k]) c.opened[t.k] = now();
    addEvent(c, "clicked", t.u);
    startTriggered(c, await getAutomations(env), "click", t.u);
    await putContact(env, c);
    await bump(env, t.k, first ? "clicks" : "repeatClicks", first ? t.v : "", t.u);
    if (c.status === "active") await runContact(env, c, 2);
  }
  return t.u;
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

async function counter(env, prefix) {
  return Number((await env.FILES.get(prefix + centralDay())) || 0);
}
async function bumpCounter(env, prefix) {
  const k = prefix + centralDay();
  await env.FILES.put(k, String(Number((await env.FILES.get(k)) || 0) + 1), { expirationTtl: 3 * 86400 });
}
export const sentToday = (env) => counter(env, "count:");
export const textsToday = (env) => counter(env, "scount:");
export const dailyCap = (env) => Number(env.MAIL_DAILY_CAP || 90);

async function log(env, prefix, entry) {
  const k = prefix + String(9e15 - now()).padStart(16, "0") + Math.random().toString(36).slice(2, 6);
  await env.FILES.put(k, "", { metadata: { ...entry, at: now() }, expirationTtl: 120 * 86400 });
}
export async function recentLog(env, limit = 50, prefix = "log:") {
  const page = await env.FILES.list({ prefix, limit });
  return page.keys.map((k) => k.metadata || {});
}
export const logText = (env, entry) => log(env, "slog:", entry);

// One list email to one contact. key: stats key ("bc:<id>", "sq:<id>:<step>", "au:<id>:<step>", "result").
export async function sendToContact(env, c, { subject, body }, kind, opts = {}) {
  if (!c || c.status !== "active") return { ok: false, skipped: true };
  const key = opts.key || kind;
  const unsub = await unsubUrl(env, c.email, key);
  const pixel = `${SITE}/api/mail/o?t=${await token(env, { p: "open", e: c.email, k: key, v: opts.variant || "" })}`;
  const inner = await bodyHtmlTracked(body, c, { env, e: c.email, k: key, v: opts.variant || "" });
  const subj = merge(subject, c);
  const r = await resend(env, {
    to: c.email, subject: subj, html: emailHtml(inner, unsub, pixel),
    headers: { "List-Unsubscribe": `<${unsub}>`, "List-Unsubscribe-Post": "List-Unsubscribe=One-Click" },
  });
  await log(env, "log:", { e: c.email, s: subj.slice(0, 120), k: kind, ok: r.ok ? 1 : 0, err: r.ok ? undefined : String(r.error).slice(0, 160) });
  if (r.ok) {
    await bumpCounter(env, "count:");
    await bump(env, key, "sent", opts.variant);
    c.stats = c.stats || {};
    c.stats.sent = (c.stats.sent || 0) + 1;
    c.stats.lastSent = now();
    addEvent(c, "sent", subj);
    if (!opts.noSave) await putContact(env, c);
  }
  return r;
}

// One list text to one contact (only if he opted in; waits for sending hours).
export async function textContact(env, c, text, kind, opts = {}) {
  if (!c || !c.phone || !c.sms || c.sms.status !== "subscribed") return { ok: false, skipped: true };
  if (!smsReady(env)) return { ok: false, skipped: true, error: "not connected" };
  if (!opts.anyHour && inQuietHours()) return { ok: false, later: nextSendWindow() };
  if ((await textsToday(env)) >= smsCap(env)) return { ok: false, later: now() + 3600000 };
  const body = opts.raw ? merge(text, c) : listText(merge(text, c));
  const r = await sendSms(env, { to: c.phone, body });
  await logText(env, { e: c.email, ph: c.phone, dir: "out", b: body.slice(0, 300), k: kind, ok: r.ok ? 1 : 0, err: r.ok ? undefined : String(r.error).slice(0, 160) });
  if (r.ok) {
    await bumpCounter(env, "scount:");
    await bump(env, opts.key || kind, "sent");
    addEvent(c, "texted", body.slice(0, 100));
    if (!opts.noSave) await putContact(env, c);
  } else if (r.code === 21610) {
    // Twilio: the number replied STOP.
    c.sms.status = "unsubscribed";
    addEvent(c, "texts off", "carrier opt-out");
    if (!opts.noSave) await putContact(env, c);
  }
  return r;
}

export async function sendTest(env, { subject, body }, to = BRIAN) {
  return resend(env, { to, subject: "[Test] " + merge(subject, { name: "Brian" }), html: emailHtml(bodyHtml(body, { name: "Brian", email: to }), `${SITE}/#unsubscribe-preview`) });
}

export async function emailBrian(env, subject, text) {
  return resend(env, { to: BRIAN, subject, html: emailHtml(bodyHtml(text, { name: "Brian" }), null) });
}

// ---------- running a contact: series and automations ----------

// Sends what is due for one contact. Returns the number of emails sent.
export async function runContact(env, c, budget = Infinity) {
  let sent = 0;
  // Series
  for (const [id, st] of Object.entries(c.seq || {})) {
    if (st.done || !st.next || st.next > now() || sent >= budget) continue;
    const def = await getSequence(env, id);
    if (!def) { st.done = true; continue; }
    const email = def.emails[st.step];
    if (email && email.text && !st.texted) {
      // A text in a series step goes to men who opted in to texts (sending hours apply).
      const r = await textContact(env, c, email.text, "series:" + id, { key: `sq:${id}:${st.step}:sms`, noSave: true });
      if (r.later) { st.next = r.later; continue; }
      st.texted = true;
    }
    if (email && email.subject && email.body) {
      const r = await sendToContact(env, c, email, "series:" + id, { key: `sq:${id}:${st.step}`, noSave: true });
      if (!r.ok && !r.skipped) { st.fails = (st.fails || 0) + 1; if (st.fails < 3) { st.next = now() + 3600000; continue; } }
      if (r.ok) sent++;
    }
    delete st.texted;
    st.step = firstStep(def, st.step + 1, now());
    st.fails = 0;
    if (st.step >= def.emails.length) { st.done = true; delete st.next; } else st.next = dueAt(def, st, st.step);
  }
  // Automations
  const autos = await getAutomations(env);
  for (let pass = 0; pass < 3; pass++) {
    let moved = false;
    for (const [id, st] of Object.entries(c.auto || {})) {
      if (st.done || !st.next || st.next > now()) continue;
      const a = autos.find((x) => x.id === id);
      if (!a || !a.enabled) { if (!a) st.done = true; continue; }
      while (!st.done && st.next <= now()) {
        const step = a.steps[st.step];
        if (!step) { st.done = true; delete st.next; break; }
        let advance = true;
        if (step.type === "wait") {
          st.next = now() + ((Number(step.days) || 0) * 24 + (Number(step.hours) || 0)) * 3600000;
          st.step++;
          if (st.step >= a.steps.length) { st.done = true; delete st.next; }
          break;
        } else if (step.type === "email") {
          if (c.status !== "active") { /* not on the email list: skip this email, keep going */ }
          else if (sent >= budget) { st.next = now() + 3600000; advance = false; break; }
          else {
            const r = await sendToContact(env, c, step, "automation:" + a.name, { key: `au:${id}:${st.step}`, noSave: true });
            if (r.ok) sent++;
            else if (!r.skipped) { st.fails = (st.fails || 0) + 1; if (st.fails < 3) { st.next = now() + 3600000; advance = false; break; } }
          }
        } else if (step.type === "sms") {
          const r = await textContact(env, c, step.text, "automation:" + a.name, { key: `au:${id}:${st.step}`, noSave: true });
          if (r.later) { st.next = r.later; advance = false; break; }
        } else if (step.type === "tag") await addTag(env, c, step.tag, autos);
        else if (step.type === "untag") { c.tags = c.tags.filter((t) => t !== step.tag); addEvent(c, "untagged", step.tag); }
        else if (step.type === "series") await enroll(env, c, step.id);
        else if (step.type === "notify") await emailBrian(env, `Automation: ${a.name}`, `${step.text || "A contact reached this step."}\n\n${c.name || ""} ${c.email}${c.phone ? " " + c.phone : ""}`);
        else if (step.type === "iftag" && !c.tags.includes(step.tag)) { st.done = true; delete st.next; break; }
        else if (step.type === "ifnottag" && c.tags.includes(step.tag)) { st.done = true; delete st.next; break; }
        if (advance) { st.step++; st.fails = 0; moved = true; if (st.step >= a.steps.length) { st.done = true; delete st.next; } }
      }
    }
    if (!moved) break;
  }
  await putContact(env, c);
  return sent;
}

// ---------- broadcasts ----------
// {id, channel: "email"|"sms", subject, subjectB, body, text, audience: {type, value},
//  status: "draft"|"scheduled"|"sending"|"sent", scheduledAt, created, total, cursor, sent, failed, opened[]}

export async function getBroadcast(env, id) { return env.FILES.get("bc:" + id, "json"); }

export async function putBroadcast(env, b) {
  const aud = b.audience || {};
  await env.FILES.put("bc:" + b.id, JSON.stringify(b), {
    metadata: { s: (b.channel === "sms" ? b.text : b.subject || "").slice(0, 120), ch: b.channel || "email", st: b.status, a: aud.type ? `${aud.type}:${aud.value || ""}` : "all", c: b.created, at: b.scheduledAt || 0, sent: b.sent || 0, total: b.total || 0 },
  });
  return b;
}

export async function allBroadcasts(env) {
  const page = await env.FILES.list({ prefix: "bc:", limit: 1000 });
  return page.keys.map((k) => ({ id: k.name.slice(3), ...(k.metadata || {}) })).sort((a, b) => (b.c || 0) - (a.c || 0));
}

export async function queueBroadcast(env, b) {
  const list = await audience(env, b.audience, b.channel || "email");
  const to = list.map((m) => m.email);
  await env.FILES.put("bcr:" + b.id, JSON.stringify(to));
  Object.assign(b, { status: "sending", total: to.length, cursor: 0, sent: 0, failed: 0, queuedAt: now(), opened: [] });
  return putBroadcast(env, b);
}

// ---------- the scheduler ----------

export async function tick(env, { max = 200 } = {}) {
  if (!env.FILES || !env.RESEND_API_KEY) return { ok: false, error: "not configured" };
  const lock = await env.FILES.get("lock:tick");
  if (lock && now() - Number(lock) < 90000) return { ok: true, busy: true };
  await env.FILES.put("lock:tick", String(now()), { expirationTtl: 120 });
  let budget = Math.min(max, dailyCap(env) - (await sentToday(env)));
  const out = { ok: true, series: 0, broadcast: 0, texts: 0, capped: budget <= 0 };
  try {
    const due = (await allContacts(env)).filter((m) => m.nx && m.nx <= now()).sort((a, b) => a.nx - b.nx);
    for (const m of due.slice(0, 300)) {
      if (budget <= 0 && m.s === "active") continue;
      const c = await getContact(env, m.email);
      if (!c) continue;
      const n = await runContact(env, c, Math.max(0, budget));
      out.series += n;
      budget -= n;
    }
    for (const meta of await allBroadcasts(env)) {
      if (meta.st === "scheduled" && meta.at && meta.at <= now()) {
        const b = await getBroadcast(env, meta.id);
        await queueBroadcast(env, b);
        meta.st = "sending";
      }
      if (meta.st !== "sending") continue;
      const b = await getBroadcast(env, meta.id);
      const to = (await env.FILES.get("bcr:" + b.id, "json")) || [];
      const sms = b.channel === "sms";
      if (sms && inQuietHours()) continue;
      while (b.cursor < to.length) {
        if (!sms && budget <= 0) break;
        const c = await getContact(env, to[b.cursor]);
        let r;
        if (sms) {
          r = await textContact(env, c, b.text, "broadcast:" + b.id, { key: "bc:" + b.id });
          if (r.later) break;
        } else {
          const variant = b.subjectB ? (b.cursor % 2 ? "B" : "A") : "";
          r = await sendToContact(env, c, { subject: variant === "B" ? b.subjectB : b.subject, body: b.body }, "broadcast:" + b.id, { key: "bc:" + b.id, variant });
        }
        b.cursor++;
        if (r.ok) { b.sent++; if (sms) out.texts++; else { budget--; out.broadcast++; } } else if (!r.skipped) b.failed++;
        if (b.cursor % 10 === 0) await putBroadcast(env, b);
      }
      if (b.cursor >= to.length) { b.status = "sent"; b.sentAt = now(); }
      await putBroadcast(env, b);
    }
    out.capped = out.capped || budget <= 0;
    await env.FILES.put("meta:lasttick", JSON.stringify({ at: now(), ...out }));
  } finally {
    await env.FILES.delete("lock:tick");
  }
  return out;
}

export async function verifyUnsub(env, t) {
  const d = await unsign(env, t);
  return d && d.p === "unsub" ? d : null;
}

export async function recordUnsub(env, d) {
  const c = await getContact(env, d.e);
  if (!c || c.status === "unsubscribed") return;
  c.status = "unsubscribed";
  addEvent(c, "unsubscribed", d.k || "");
  await putContact(env, c);
  if (d.k) await bump(env, d.k, "unsubs");
}

// Resend webhook: a hard bounce or a spam complaint stops all list email to that address.
export async function recordBounce(env, email, kind, key) {
  const c = await getContact(env, email);
  if (!c) return;
  const status = kind === "complained" ? "complained" : "bounced";
  if (c.status !== status) { c.status = status; addEvent(c, status, ""); await putContact(env, c); }
  if (key) await bump(env, key, kind === "complained" ? "complaints" : "bounces");
}

export { uid };
