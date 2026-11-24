// The dashboard's API: /api/admin/<route>. Every route needs a signed-in admin.
//
// GET  overview                      counts, cohort seats, recent sends
// GET  contacts                      every contact (summary)
// GET  contact?e=                    one contact in full
// POST contact {email,name,addTags,removeTags,status}
// POST contact-delete {email}
// GET  export                        CSV of every contact
// POST import {csv, tag}             add contacts from CSV (email,name)
// GET  sequences                     both series with their emails
// POST sequence {id, emails}         save edited emails
// POST sequence-reset {id}           back to the default emails
// POST enroll {email, id}            put a contact into a series
// GET  broadcasts                    every broadcast
// GET  broadcast?id=
// POST broadcast {id?, subject, body, tag}  save a draft
// POST broadcast-send {id}           queue it (sent within the daily cap)
// POST broadcast-delete {id}         drafts only
// POST preview {subject, body}       the email as HTML
// POST test {subject, body}          a test copy to the admin
// POST tick                          send what is due now

import { adminFrom } from "../../_admin.js";
import { OFFERS } from "../../_catalog.js";
import {
  allContacts, getContact, putContact, upsertContact, removeTag, setStatus, enroll, runContact,
  allSequences, getSequence, allBroadcasts, getBroadcast, putBroadcast, queueBroadcast,
  recentLog, sentToday, dailyCap, emailHtml, bodyHtml, sendTest, tick, cleanEmail, validEmail,
} from "../../_list.js";

const json = (b, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json", "cache-control": "no-store" } });
const bad = (msg) => json({ ok: false, error: msg }, 400);

async function stripeGet(env, path) {
  if (!env.STRIPE_KEY) return null;
  const r = await fetch("https://api.stripe.com/v1" + path, { headers: { authorization: `Bearer ${env.STRIPE_KEY}` } });
  return r.ok ? r.json() : null;
}

function csvCell(v) {
  const s = String(v ?? "");
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function parseCsv(text) {
  const rows = [];
  for (const line of String(text || "").split(/\r?\n/)) {
    if (!line.trim()) continue;
    const cells = [];
    let cur = "", q = false;
    for (let i = 0; i < line.length; i++) {
      const ch = line[i];
      if (q) { if (ch === '"' && line[i + 1] === '"') { cur += '"'; i++; } else if (ch === '"') q = false; else cur += ch; }
      else if (ch === '"') q = true; else if (ch === ",") { cells.push(cur); cur = ""; } else cur += ch;
    }
    cells.push(cur);
    rows.push(cells.map((c) => c.trim()));
  }
  return rows;
}

export async function onRequest(context) {
  const { request, env, params } = context;
  const admin = await adminFrom(request, env);
  if (!admin) return json({ ok: false, error: "Please sign in again." }, 401);
  if (!env.FILES) return json({ ok: false, error: "The FILES store isn't connected." }, 503);
  const route = (params.path || []).join("/");
  const url = new URL(request.url);
  let d = {};
  if (request.method === "POST") { try { d = await request.json(); } catch (e) {} }

  if (route === "overview") {
    const all = await allContacts(env);
    const week = Date.now() - 7 * 86400000;
    const tags = {};
    for (const c of all) for (const t of (c.t || "").split("|").filter(Boolean)) tags[t] = (tags[t] || 0) + 1;
    const plink = OFFERS.cohort && OFFERS.cohort.plink;
    const link = plink ? await stripeGet(env, "/payment_links/" + plink) : null;
    const seats = link && link.restrictions && link.restrictions.completed_sessions;
    context.waitUntil(tick(env, { max: 20 }).catch(() => null));
    return json({
      ok: true,
      contacts: all.length,
      active: all.filter((c) => c.s === "active").length,
      unsubscribed: all.filter((c) => c.s === "unsubscribed").length,
      bounced: all.filter((c) => c.s === "bounced").length,
      newThisWeek: all.filter((c) => (c.d || 0) >= week).length,
      tags,
      seats: seats ? { sold: seats.count, limit: seats.limit } : null,
      sentToday: await sentToday(env),
      cap: dailyCap(env),
      log: await recentLog(env, 30),
    });
  }

  if (route === "contacts") return json({ ok: true, contacts: (await allContacts(env)).sort((a, b) => (b.d || 0) - (a.d || 0)) });

  if (route === "contact" && request.method === "GET") {
    const c = await getContact(env, url.searchParams.get("e"));
    return c ? json({ ok: true, contact: c }) : bad("No contact with that email.");
  }

  if (route === "contact" && request.method === "POST") {
    const email = cleanEmail(d.email);
    if (!validEmail(email)) return bad("Enter a valid email address.");
    let c = await upsertContact(env, { email, name: d.name, tags: d.addTags || [], source: "Added in dashboard", optIn: false });
    if (d.name !== undefined && d.name !== c.name) { c.name = String(d.name).slice(0, 80); await putContact(env, c); }
    for (const t of d.removeTags || []) c = await removeTag(env, email, t);
    if (d.status && ["active", "unsubscribed", "bounced"].includes(d.status)) c = await setStatus(env, email, d.status);
    return json({ ok: true, contact: c });
  }

  if (route === "contact-delete") {
    await env.FILES.delete("c:" + cleanEmail(d.email));
    return json({ ok: true });
  }

  if (route === "export") {
    const all = await allContacts(env);
    const lines = ["email,name,tags,status,joined"].concat(all.map((c) =>
      [c.email, c.n, (c.t || "").split("|").join("; "), c.s, c.d ? new Date(c.d).toISOString().slice(0, 10) : ""].map(csvCell).join(",")));
    return new Response(lines.join("\n") + "\n", { headers: { "content-type": "text/csv; charset=utf-8", "content-disposition": "attachment; filename=be-the-man-contacts.csv", "cache-control": "no-store" } });
  }

  if (route === "import") {
    const rows = parseCsv(d.csv);
    if (!rows.length) return bad("Paste at least one line: email, name.");
    const head = rows[0].map((h) => h.toLowerCase());
    const ei = head.findIndex((h) => h.includes("email"));
    const ni = head.findIndex((h) => h.includes("name"));
    const body = ei >= 0 ? rows.slice(1) : rows;
    const E = ei >= 0 ? ei : 0, N = ei >= 0 ? ni : 1;
    let added = 0, skipped = 0;
    for (const r of body.slice(0, 2000)) {
      const email = cleanEmail(r[E]);
      if (!validEmail(email)) { skipped++; continue; }
      await upsertContact(env, { email, name: N >= 0 ? r[N] : "", tags: d.tag ? [d.tag] : [], source: "Imported", optIn: false });
      added++;
    }
    return json({ ok: true, added, skipped });
  }

  if (route === "sequences") {
    const all = await allContacts(env);
    const seqs = await allSequences(env);
    return json({ ok: true, sequences: seqs.map((s) => ({ ...s, inProgress: all.filter((c) => (c.q || "").split(",").includes(s.id)).length })) });
  }

  if (route === "sequence") {
    const def = await getSequence(env, d.id);
    if (!def) return bad("Unknown series.");
    const emails = (d.emails || []).map((e) => ({
      subject: String(e.subject || "").slice(0, 200), body: String(e.body || "").slice(0, 20000),
      ...(def.kind === "dated" ? { at: String(e.at || "") } : { delayDays: Math.max(0, Number(e.delayDays) || 0) }),
    }));
    if (!emails.length || emails.some((e) => !e.subject || !e.body)) return bad("Every email needs a subject and a body.");
    if (def.kind === "dated" && emails.some((e) => isNaN(Date.parse(e.at)))) return bad("Every dated email needs a valid date and time.");
    await env.FILES.put("seqdef:" + d.id, JSON.stringify({ emails, edited: Date.now() }));
    return json({ ok: true });
  }

  if (route === "sequence-reset") {
    await env.FILES.delete("seqdef:" + d.id);
    return json({ ok: true });
  }

  if (route === "enroll") {
    const c = await getContact(env, d.email);
    if (!c) return bad("No contact with that email.");
    if (!(await getSequence(env, d.id))) return bad("Unknown series.");
    await enroll(env, c, d.id);
    await runContact(env, c);
    return json({ ok: true, contact: await getContact(env, d.email) });
  }

  if (route === "broadcasts") return json({ ok: true, broadcasts: await allBroadcasts(env) });

  if (route === "broadcast" && request.method === "GET") {
    const b = await getBroadcast(env, url.searchParams.get("id"));
    return b ? json({ ok: true, broadcast: b }) : bad("Not found.");
  }

  if (route === "broadcast" && request.method === "POST") {
    if (!d.subject || !d.body) return bad("A broadcast needs a subject and a body.");
    let b = d.id ? await getBroadcast(env, d.id) : null;
    if (b && b.status !== "draft") return bad("That broadcast has already been sent.");
    b = b || { id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6), created: Date.now(), status: "draft" };
    Object.assign(b, { subject: String(d.subject).slice(0, 200), body: String(d.body).slice(0, 20000), tag: String(d.tag || "") });
    await putBroadcast(env, b);
    return json({ ok: true, broadcast: b });
  }

  if (route === "broadcast-send") {
    const b = await getBroadcast(env, d.id);
    if (!b || b.status !== "draft") return bad("Only a saved draft can be sent.");
    await queueBroadcast(env, b);
    context.waitUntil(tick(env).catch(() => null));
    return json({ ok: true, broadcast: b });
  }

  if (route === "broadcast-delete") {
    const b = await getBroadcast(env, d.id);
    if (!b || b.status !== "draft") return bad("Only drafts can be deleted.");
    await env.FILES.delete("bc:" + d.id);
    return json({ ok: true });
  }

  if (route === "preview") return json({ ok: true, html: emailHtml(bodyHtml(d.body, { name: "Brian" }), "#unsubscribe") });

  if (route === "test") {
    if (!d.subject || !d.body) return bad("Add a subject and a body first.");
    const r = await sendTest(env, d, admin);
    return r.ok ? json({ ok: true, to: admin }) : bad(r.error || "Resend didn't accept it.");
  }

  if (route === "tick") return json(await tick(env));

  return json({ ok: false, error: "Not found." }, 404);
}
