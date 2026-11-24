// Dashboard extras built on the list (functions/_list.js):
//   the Ledger by text, the cohort roster, results collection, where sign-ups come
//   from, referral links, the waitlist, Substack to email, the money view, the
//   Monday report, saved replies, free-call outcomes and follow-up reminders.
//
// KV keys: settings, snippets, result:<email>, ref:<code>, rem:<n>, callout:<start>,
//          ledger:asked:<week>, ledger:nudged:<week>, report:<date>, meta:rss

import {
  getContact, putContact, addEvent, allContacts, tick, textContact, sendToContact, emailBrian, audience,
  putBroadcast, queueBroadcast, getAutomations, startTriggered, runContact, centralDay, recentLog, emailHtml, bodyHtml, SITE, BRIAN, uid,
} from "./_list.js";
import { sign, unsign } from "./_club.js";
import { OFFERS, CLUB } from "./_catalog.js";
import { COHORT_DATES } from "./_booking.js";
import { sendEmail } from "./_mail.js";
import { centralHour, smsReady } from "./_sms.js";

const now = () => Date.now();
const DAY = 86400000;

// ---------- settings ----------

export const DEFAULTS = {
  ledger: { on: true, tag: "Founding Cohort" },
  rss: { mode: "off", url: "https://bethemansystem.substack.com/feed", audience: { type: "all", value: "" } },
  report: { on: true },
};

export async function getSettings(env) {
  const s = (await env.FILES.get("settings", "json")) || {};
  return { ledger: { ...DEFAULTS.ledger, ...(s.ledger || {}) }, rss: { ...DEFAULTS.rss, ...(s.rss || {}) }, report: { ...DEFAULTS.report, ...(s.report || {}) } };
}
export async function saveSettings(env, s) { await env.FILES.put("settings", JSON.stringify(s)); }

// ---------- time helpers (Central) ----------

function centralParts(ms = now()) {
  const p = new Intl.DateTimeFormat("en-US", { timeZone: "America/Chicago", weekday: "short", hour: "numeric", hourCycle: "h23" }).formatToParts(new Date(ms));
  const get = (t) => (p.find((x) => x.type === t) || {}).value;
  return { dow: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].indexOf(get("weekday")), hour: Number(get("hour")), date: centralDay(ms) };
}

// The Ledger week a report belongs to: the Sunday it was asked for. Before 6 PM
// on Sunday, a report still counts for the week before.
export function ledgerWeek(ms = now()) {
  const { dow, hour } = centralParts(ms);
  let back = dow;
  if (dow === 0 && hour < 18) back = 7;
  return centralDay(ms - back * DAY);
}
const weekLabel = (w) => new Date(w + "T12:00:00-06:00").toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "America/Chicago" });

// ---------- the Ledger ----------

// "13/15", "13 of 15", "13 out of 15" -> {k, t}
export function parseLedger(text) {
  const m = String(text || "").match(/(\d{1,3})\s*(?:\/|of|out of)\s*(\d{1,3})/i);
  if (!m) return null;
  const k = Number(m[1]), t = Number(m[2]);
  if (!t || k > t || t > 200) return null;
  return { k, t };
}

export async function recordLedger(env, c, { k, t, miss, change }, via) {
  const week = ledgerWeek();
  c.ledger = c.ledger || {};
  c.ledger[week] = { k, t, at: now(), via, ...(miss ? { miss: String(miss).slice(0, 200) } : {}), ...(change ? { change: String(change).slice(0, 200) } : {}) };
  const weeks = Object.keys(c.ledger).sort();
  while (weeks.length > 30) delete c.ledger[weeks.shift()];
  addEvent(c, "ledger", `${k} of ${t} (week of ${weekLabel(week)})`);
  await putContact(env, c);
  return week;
}

export async function ledgerLink(env, email) {
  return `${SITE}/ledger/?t=${await sign(env, { p: "ledger", e: email, x: Math.floor(now() / 1000) + 60 * 86400 })}`;
}
export async function readLedgerToken(env, t) { const d = await unsign(env, t); return d && d.p === "ledger" ? d.e : null; }

async function ledgerMembers(env, tag) {
  return (await allContacts(env)).filter((m) => (m.t || "").split("|").includes(tag) && m.s !== "complained");
}

async function askOne(env, m, week, nudge) {
  const c = await getContact(env, m.email);
  if (!c || (c.ledger && c.ledger[week])) return false;
  const link = await ledgerLink(env, c.email);
  let done = false;
  if (c.sms && c.sms.status === "subscribed" && c.phone && smsReady(env)) {
    const msg = nudge ? `{{first_name}}, still need your number for the week of ${weekLabel(week)}. Reply like 13/15. No shame, just the count.`
      : `{{first_name}}, Ledger time. How many did you keep this week? Reply with your number, like 13/15.`;
    const r = await textContact(env, c, msg, "ledger", { key: "ledger:" + week, anyHour: false });
    done = r.ok;
  }
  if (!done && c.status === "active") {
    const r = await sendToContact(env, c, {
      subject: nudge ? "Still need your number" : "Your Ledger: this week's number",
      body: `${nudge ? "{{first_name}}, I don't have your number yet for the week of " + weekLabel(week) + "." : "{{first_name}}, it's Sunday. Time to score the week."}\n\nMark each commitment kept, floor or missed, add it up, and send me the number. Four out of seven is four out of seven.\n\n[[Report my number|${link}]]\n\nThen take grace, make one change for Monday, and reset.\n\nBrian`,
    }, "ledger", { key: "ledger:" + week });
    done = r.ok;
  }
  return done;
}

export async function ledgerJob(env, settings) {
  if (!settings.ledger.on) return null;
  const { dow, hour } = centralParts();
  const week = ledgerWeek();
  const out = {};
  if (dow === 0 && hour >= 18 && !(await env.FILES.get("ledger:asked:" + week))) {
    await env.FILES.put("ledger:asked:" + week, "1", { expirationTtl: 30 * 86400 });
    let n = 0;
    for (const m of await ledgerMembers(env, settings.ledger.tag)) if (await askOne(env, m, week, false)) n++;
    out.asked = n;
  }
  if (dow === 1 && hour >= 12 && (await env.FILES.get("ledger:asked:" + week)) && !(await env.FILES.get("ledger:nudged:" + week))) {
    await env.FILES.put("ledger:nudged:" + week, "1", { expirationTtl: 30 * 86400 });
    const missing = [];
    for (const m of await ledgerMembers(env, settings.ledger.tag)) {
      const c = await getContact(env, m.email);
      if (c && !(c.ledger && c.ledger[week])) { missing.push(c.name || c.email); await askOne(env, m, week, true); }
    }
    if (missing.length) await emailBrian(env, `Ledger: ${missing.length} still to report`, `These men haven't reported their number for the week of ${weekLabel(week)}. They've been nudged.\n\n${missing.map((x) => "- " + x).join("\n")}\n\n[[Open the cohort roster|${SITE}/admin/#cohort]]`);
    out.nudged = missing.length;
  }
  return out;
}

// ---------- results (testimonials with permission) ----------

export async function resultsLink(env, email) {
  return `${SITE}/results/?t=${await sign(env, { p: "results", e: email, x: Math.floor(now() / 1000) + 90 * 86400 })}`;
}
export async function readResultsToken(env, t) { const d = await unsign(env, t); return d && d.p === "results" ? d.e : null; }

export async function allResults(env) {
  const page = await env.FILES.list({ prefix: "result:" });
  const out = [];
  for (const k of page.keys) { const r = await env.FILES.get(k.name, "json"); if (r) out.push(r); }
  return out.sort((a, b) => (b.at || 0) - (a.at || 0));
}

export async function publicResults(env) {
  return (await allResults(env)).filter((r) => r.approved && r.permission).map((r) => ({ name: r.name, before: r.before, after: r.after, quote: r.quote }));
}

// ---------- attribution and referrals ----------

const cleanSrc = (s) => String(s || "").toLowerCase().replace(/[^a-z0-9_:-]/g, "").slice(0, 40);

async function ensureRef(env, c) {
  if (c.ref) return;
  for (let i = 0; i < 5; i++) {
    const code = Math.random().toString(36).slice(2, 8);
    if (!(await env.FILES.get("ref:" + code))) { c.ref = code; await env.FILES.put("ref:" + code, c.email); return; }
  }
}

// Record where a man came from (first touch) and who referred him, and give him his own referral code.
export async function attribute(env, c, { src, ref } = {}) {
  if (!c) return c;
  let changed = false;
  const s = cleanSrc(src);
  if (s && !c.src) { c.src = s; changed = true; }
  const code = String(ref || "").replace(/[^a-z0-9]/gi, "").slice(0, 12);
  if (code && !c.referredBy && code !== c.ref) {
    const by = await env.FILES.get("ref:" + code);
    if (by && by !== c.email) {
      c.referredBy = by;
      if (!c.src) c.src = "referral";
      addEvent(c, "referred by", by);
      const r = await getContact(env, by);
      if (r) {
        r.refCount = (r.refCount || 0) + 1;
        addEvent(r, "referral", c.email);
        startTriggered(r, await getAutomations(env), "referral", "");
        await putContact(env, r);
        await runContact(env, r, 2);
      }
      changed = true;
    }
  }
  if (!c.ref) { await ensureRef(env, c); changed = true; }
  if (changed) await putContact(env, c);
  return c;
}

// Stripe client_reference_id from the site's checkout links: "src-youtube" or "ref-abc123".
export function parseClientRef(v) {
  const s = String(v || "");
  if (s.startsWith("ref-")) return { ref: s.slice(4) };
  if (s.startsWith("src-")) return { src: s.slice(4) };
  return {};
}

// ---------- the cohort ----------

export const SESSIONS = COHORT_DATES;
export function cohortStarted(ms = now()) { return ms > Date.parse(COHORT_DATES[0] + "T19:00:00-06:00"); }

export async function cohortStatus(env) {
  const plink = OFFERS.cohort && OFFERS.cohort.plink;
  let link = null, stripe = env.STRIPE_KEY ? "" : "no key";
  if (plink && env.STRIPE_KEY) {
    const r = await fetch("https://api.stripe.com/v1/payment_links/" + plink, { headers: { authorization: `Bearer ${env.STRIPE_KEY}` } });
    if (r.ok) { link = await r.json(); stripe = "ok"; }
    else stripe = r.status === 401 ? "bad key" : r.status === 403 ? "missing permission: payment links" : "error " + r.status;
  }
  let cs = link && link.restrictions && link.restrictions.completed_sessions;
  if (!cs && plink && env.STRIPE_KEY) {
    // The key may not read payment links; count paid cohort checkouts instead.
    const r = await fetch(`https://api.stripe.com/v1/checkout/sessions?payment_link=${plink}&status=complete&limit=100`, { headers: { authorization: `Bearer ${env.STRIPE_KEY}` } });
    if (r.ok) { const d = await r.json(); cs = { count: (d.data || []).filter((s) => s.payment_status === "paid").length, limit: 10 }; }
    else stripe += r.status === 403 ? "; missing permission: checkout sessions" : "";
  }
  const sold = cs ? cs.count : null, limit = cs ? cs.limit : 10;
  const full = (link && !link.active) || !!(cs && cs.count >= cs.limit);
  const started = cohortStarted();
  return { open: !full && !started, full, started, sold, limit, start: COHORT_DATES[0], stripe };
}

// ---------- reminders ----------

export async function addReminder(env, at, text) {
  await env.FILES.put("rem:" + String(at).padStart(14, "0") + ":" + uid(), JSON.stringify({ at, text }), { expirationTtl: Math.max(60, Math.ceil((at - now()) / 1000) + 30 * 86400) });
}

async function reminderJob(env) {
  const page = await env.FILES.list({ prefix: "rem:" });
  let n = 0;
  for (const k of page.keys) {
    const at = Number(k.name.split(":")[1]);
    if (at > now()) break;
    const r = await env.FILES.get(k.name, "json");
    await env.FILES.delete(k.name);
    if (r) { await emailBrian(env, "Reminder: " + r.text.split("\n")[0].slice(0, 80), r.text + `\n\n[[Open the dashboard|${SITE}/admin/#calls]]`); n++; }
  }
  return n;
}

// ---------- Substack to email ----------

function rssItems(xml) {
  const items = [];
  const re = /<item>([\s\S]*?)<\/item>/g;
  let m;
  const pick = (s, tag) => { const x = s.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`)); return x ? x[1].replace(/^<!\[CDATA\[|\]\]>$/g, "").trim() : ""; };
  while ((m = re.exec(xml))) {
    const s = m[1];
    items.push({ title: pick(s, "title"), link: pick(s, "link"), guid: pick(s, "guid") || pick(s, "link"), date: Date.parse(pick(s, "pubDate")) || 0,
      text: pick(s, "description").replace(/<[^>]+>/g, " ").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&#39;|&rsquo;/g, "'").replace(/&quot;|&ldquo;|&rdquo;/g, '"').replace(/\s+/g, " ").trim() });
  }
  return items;
}

export async function rssJob(env, settings, { force } = {}) {
  const cfg = settings.rss;
  if (cfg.mode === "off" && !force) return null;
  const last = (await env.FILES.get("meta:rss", "json")) || { checked: 0, seen: [] };
  if (!force && now() - last.checked < 3600000) return null;
  let xml = "";
  try { const r = await fetch(cfg.url, { headers: { "user-agent": "BeTheMan-RSS/1.0" } }); if (r.ok) xml = await r.text(); } catch (e) {}
  last.checked = now();
  const items = rssItems(xml);
  const out = { found: items.length, created: 0 };
  if (!last.seen.length) {
    // First run: remember what's already published so old posts aren't sent.
    last.seen = items.map((i) => i.guid).slice(0, 50);
  } else {
    for (const it of items.slice(0, 5).reverse()) {
      if (last.seen.includes(it.guid) || !it.title || !it.link) continue;
      last.seen.unshift(it.guid);
      if (cfg.mode === "off") continue;
      const b = { id: uid(), created: now(), status: "draft", channel: "email", subject: it.title, subjectB: "", text: "",
        body: `{{first_name}}, I just published a new piece: **${it.title}**\n\n${it.text.slice(0, 500)}${it.text.length > 500 ? "…" : ""}\n\n[[Read it on Substack|${it.link}]]\n\nBrian`,
        audience: cfg.audience || { type: "all", value: "" }, fromRss: it.link };
      await putBroadcast(env, b);
      if (cfg.mode === "send") await queueBroadcast(env, b);
      else await emailBrian(env, "New Substack post ready to send", `A draft email for **${it.title}** is waiting in Broadcasts.\n\n[[Review and send|${SITE}/admin/#broadcasts]]`);
      out.created++;
    }
    last.seen = last.seen.slice(0, 50);
  }
  await env.FILES.put("meta:rss", JSON.stringify(last));
  return out;
}

// ---------- money ----------

async function stripeList(env, path) {
  const out = [];
  let after = "";
  for (let i = 0; i < 10; i++) {
    const r = await fetch(`https://api.stripe.com/v1${path}${path.includes("?") ? "&" : "?"}limit=100${after ? "&starting_after=" + after : ""}`, { headers: { authorization: `Bearer ${env.STRIPE_KEY}` } });
    if (!r.ok) break;
    const d = await r.json();
    out.push(...d.data);
    if (!d.has_more || !d.data.length) break;
    after = d.data[d.data.length - 1].id;
  }
  return out;
}

export async function money(env) {
  if (!env.STRIPE_KEY) return { ok: false, error: "Stripe isn't connected." };
  const since = Math.floor((now() - 30 * DAY) / 1000);
  const monthStart = Math.floor(Date.parse(centralDay().slice(0, 8) + "01T00:00:00-06:00") / 1000);
  const plinkName = {};
  for (const o of Object.values(OFFERS)) if (o.plink) plinkName[o.plink] = o.name;
  for (const p of Object.values(CLUB.plinks || {})) plinkName[p] = "The Club";
  const sessions = (await stripeList(env, `/checkout/sessions?status=complete&created[gte]=${since}`)).filter((s) => s.payment_status === "paid" || s.payment_status === "no_payment_required");
  const byProduct = {}, bySource = {};
  let total30 = 0, totalMonth = 0;
  const recent = [];
  for (const s of sessions) {
    const name = plinkName[s.payment_link] || "Other";
    const amt = (s.amount_total || 0) / 100;
    total30 += amt;
    if (s.created >= monthStart) totalMonth += amt;
    byProduct[name] = byProduct[name] || { count: 0, amount: 0 };
    byProduct[name].count++; byProduct[name].amount += amt;
    const attr = parseClientRef(s.client_reference_id);
    const src = attr.src || (attr.ref ? "referral" : "direct");
    bySource[src] = (bySource[src] || 0) + amt;
    if (recent.length < 20) recent.push({ at: s.created * 1000, name, amount: amt, email: (s.customer_details || {}).email || "" });
  }
  const refunds = await stripeList(env, `/refunds?created[gte]=${since}`);
  const subs = await stripeList(env, "/subscriptions?status=active");
  const clubPrices = Object.values(CLUB.prices || {});
  const club = subs.filter((s) => (s.items.data || []).some((i) => clubPrices.includes(i.price.id)));
  const mrr = club.reduce((a, s) => a + (s.items.data || []).reduce((b, i) => b + (i.price.unit_amount || 0) * (i.quantity || 1) / (i.price.recurring && i.price.recurring.interval === "year" ? 12 : 1), 0), 0) / 100;
  // Funnel, last 30 days, from the list.
  const all = await allContacts(env);
  const joined = all.filter((m) => (m.d || 0) >= now() - 30 * DAY && (m.t || "").split("|").includes("Step 1"));
  const funnel = {
    signedUp: joined.length,
    opened: joined.filter((m) => m.lo).length,
    clicked: joined.filter((m) => m.lc).length,
    bought: joined.filter((m) => (m.t || "").split("|").some((t) => t === "Customer" || t === "Founding Cohort")).length,
  };
  const sources = {};
  for (const m of all) {
    const s = m.so || "unknown";
    sources[s] = sources[s] || { signups: 0, buyers: 0 };
    sources[s].signups++;
    if ((m.t || "").split("|").some((t) => t === "Customer" || t === "Founding Cohort")) sources[s].buyers++;
  }
  return {
    ok: true, total30, totalMonth, byProduct, bySourceRevenue: bySource, recent,
    refunds: { count: refunds.length, amount: refunds.reduce((a, r) => a + (r.amount || 0), 0) / 100 },
    club: { members: club.length, mrr }, funnel, sources,
  };
}

// ---------- the Monday report ----------

export async function weeklyReport(env) {
  const all = await allContacts(env);
  const week = all.filter((m) => (m.d || 0) >= now() - 7 * DAY);
  const bySrc = {};
  for (const m of week) bySrc[m.so || "unknown"] = (bySrc[m.so || "unknown"] || 0) + 1;
  let m = { ok: false };
  try { m = await money(env); } catch (e) {}
  const cs = await cohortStatus(env).catch(() => ({}));
  const settings = await getSettings(env);
  const lw = ledgerWeek(now() - 2 * DAY);
  const members = all.filter((x) => (x.t || "").split("|").includes(settings.ledger.tag));
  let reported = 0;
  for (const x of members) { const c = await getContact(env, x.email); if (c && c.ledger && c.ledger[lw]) reported++; }
  const log = await recentLog(env, 200);
  const failed = log.filter((l) => !l.ok && l.at >= now() - 7 * DAY).length;
  const unread = !!(await env.FILES.get("unread:texts"));
  const lines = [
    `**Your week at Be The Man**`,
    `- New sign-ups: **${week.length}**${week.length ? " (" + Object.entries(bySrc).map(([k, v]) => `${k} ${v}`).join(", ") + ")" : ""}`,
    `- Active on email: **${all.filter((x) => x.s === "active").length}**, on texts: **${all.filter((x) => x.sm === "subscribed").length}**`,
    cs.sold != null ? `- Founding Cohort seats: **${cs.sold} of ${cs.limit}**` : "",
    m.ok ? `- Revenue, last 30 days: **$${m.total30.toFixed(2)}** (this month $${m.totalMonth.toFixed(2)}); Club members: ${m.club.members}` : "",
    members.length ? `- Ledger last week: **${reported} of ${members.length}** men reported` : "",
    failed ? `- Emails that failed this week: ${failed}` : "",
    unread ? `- You have unread text replies.` : "",
    "",
    `[[Open the dashboard|${SITE}/admin/]]`,
  ].filter((x) => x !== "");
  return lines.join("\n");
}

async function reportJob(env, settings) {
  if (!settings.report.on) return null;
  const { dow, hour, date } = centralParts();
  if (dow !== 1 || hour < 8 || (await env.FILES.get("report:" + date))) return null;
  await env.FILES.put("report:" + date, "1", { expirationTtl: 10 * 86400 });
  await emailBrian(env, "Your Monday report", await weeklyReport(env));
  return true;
}

// ---------- saved replies ----------

export async function getSnippets(env) { return (await env.FILES.get("snippets", "json")) || []; }
export async function saveSnippets(env, list) { await env.FILES.put("snippets", JSON.stringify(list)); }

// A personal one-to-one email from Brian (not a list email).
export async function personalEmail(env, c, subject, body) {
  const ok = await sendEmail(env, { to: c.email, subject, html: emailHtml(bodyHtml(body, c), null) });
  if (ok) { addEvent(c, "emailed by Brian", subject); await putContact(env, c); }
  return ok;
}

// ---------- the full scheduler run (cron and dashboard) ----------

export async function runAll(env) {
  const out = { list: await tick(env) };
  const settings = await getSettings(env);
  try { out.ledger = await ledgerJob(env, settings); } catch (e) { out.ledgerError = String(e); }
  try { out.rss = await rssJob(env, settings); } catch (e) { out.rssError = String(e); }
  try { out.report = await reportJob(env, settings); } catch (e) { out.reportError = String(e); }
  try { out.reminders = await reminderJob(env); } catch (e) { out.reminderError = String(e); }
  return out;
}
