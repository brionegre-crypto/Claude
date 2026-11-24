// The dashboard's API: /api/admin/<route>. Every route needs a signed-in admin.
// See web/static/assets/admin.js for the screens that use it.

import { adminFrom } from "../../_admin.js";
import { OFFERS } from "../../_catalog.js";
import {
  allContacts, getContact, putContact, upsertContact, setStatus, setSms, addEvent, enroll, runContact,
  allSequences, getSequence, allBroadcasts, getBroadcast, putBroadcast, queueBroadcast, audience,
  getSegments, saveSegments, matches, getAutomations, saveAutomations, startTriggered, getForms, saveForms,
  recentLog, sentToday, textsToday, dailyCap, emailHtml, bodyHtml, sendTest, tick, cleanEmail, validEmail,
  getStats, logText, uid,
} from "../../_list.js";
import { smsReady, smsCap, sendSms, toE164, listText } from "../../_sms.js";

const json = (b, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json", "cache-control": "no-store" } });
const bad = (msg) => json({ ok: false, error: msg }, 400);
const str = (v, n = 200) => String(v ?? "").slice(0, n);

async function stripeGet(env, path) {
  if (!env.STRIPE_KEY) return null;
  const r = await fetch("https://api.stripe.com/v1" + path, { headers: { authorization: `Bearer ${env.STRIPE_KEY}` } });
  return r.ok ? r.json() : null;
}

function csvCell(v) { const s = String(v ?? ""); return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; }

function parseCsv(text) {
  const rows = [];
  for (const line of String(text || "").split(/\r?\n/)) {
    if (!line.trim()) continue;
    const cells = []; let cur = "", q = false;
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

const STEP_TYPES = ["wait", "email", "sms", "tag", "untag", "series", "notify", "iftag", "ifnottag"];
const TRIGGERS = ["form", "tag", "purchase", "click", "sms"];

function cleanAutomation(a) {
  return {
    id: a.id || uid(), name: str(a.name, 80) || "Untitled automation", enabled: !!a.enabled,
    trigger: { type: TRIGGERS.includes(a.trigger && a.trigger.type) ? a.trigger.type : "tag", value: str(a.trigger && a.trigger.value, 300) },
    steps: (a.steps || []).filter((s) => STEP_TYPES.includes(s.type)).slice(0, 40).map((s) => ({
      type: s.type,
      ...(s.type === "wait" ? { days: Math.max(0, Number(s.days) || 0), hours: Math.max(0, Number(s.hours) || 0) } : {}),
      ...(s.type === "email" ? { subject: str(s.subject), body: str(s.body, 20000) } : {}),
      ...(s.type === "sms" ? { text: str(s.text, 600) } : {}),
      ...(["tag", "untag", "iftag", "ifnottag"].includes(s.type) ? { tag: str(s.tag, 80) } : {}),
      ...(s.type === "series" ? { id: str(s.id, 40) } : {}),
      ...(s.type === "notify" ? { text: str(s.text, 500) } : {}),
    })),
    created: a.created || Date.now(),
  };
}

function cleanSegment(s) {
  const list = (v) => (Array.isArray(v) ? v : String(v || "").split(",")).map((x) => String(x).trim()).filter(Boolean).slice(0, 20);
  return {
    id: s.id || uid(), name: str(s.name, 80) || "Untitled segment", all: list(s.all), any: list(s.any), none: list(s.none),
    status: ["active", "unsubscribed", "bounced", "complained", "unconfirmed"].includes(s.status) ? s.status : "",
    engagement: ["engaged", "warm", "cold", "new"].includes(s.engagement) ? s.engagement : "",
    joinedAfter: /^\d{4}-\d{2}-\d{2}$/.test(s.joinedAfter || "") ? s.joinedAfter : "",
    joinedBefore: /^\d{4}-\d{2}-\d{2}$/.test(s.joinedBefore || "") ? s.joinedBefore : "",
    texts: s.texts === "subscribed" ? "subscribed" : "",
    field: s.field && s.field.key ? { key: str(s.field.key, 40).replace(/[^a-z0-9_]/gi, ""), value: str(s.field.value, 120) } : null,
  };
}

function cleanForm(f) {
  const slug = str(f.id || f.name, 40).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || uid();
  return {
    id: slug, name: str(f.name, 80) || "Untitled form", headline: str(f.headline, 140), text: str(f.text, 1200), button: str(f.button, 40) || "Sign up",
    tag: str(f.tag, 80), series: ["", "step1", "cohort"].includes(f.series) ? f.series : "", phone: !!f.phone, sms: !!f.phone && !!f.sms,
    doubleOptIn: !!f.doubleOptIn, success: str(f.success, 300), redirect: /^https?:\/\/|^\//.test(f.redirect || "") ? str(f.redirect, 300) : "",
    archived: !!f.archived, created: f.created || Date.now(),
  };
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

  // ----- overview -----
  if (route === "overview") {
    const all = await allContacts(env);
    const week = Date.now() - 7 * 86400000;
    const tags = {}, eng = { engaged: 0, warm: 0, cold: 0, new: 0 }, growth = {};
    for (const c of all) {
      for (const t of (c.t || "").split("|").filter(Boolean)) tags[t] = (tags[t] || 0) + 1;
      if (c.s === "active" && eng[c.en] !== undefined) eng[c.en]++;
      const day = new Date(c.d || 0).toISOString().slice(0, 10);
      if (Date.now() - (c.d || 0) < 30 * 86400000) growth[day] = (growth[day] || 0) + 1;
    }
    const plink = OFFERS.cohort && OFFERS.cohort.plink;
    const link = plink ? await stripeGet(env, "/payment_links/" + plink) : null;
    const seats = link && link.restrictions && link.restrictions.completed_sessions;
    context.waitUntil(tick(env, { max: 20 }).catch(() => null));
    return json({
      ok: true, contacts: all.length,
      active: all.filter((c) => c.s === "active").length,
      unsubscribed: all.filter((c) => c.s === "unsubscribed").length,
      bounced: all.filter((c) => c.s === "bounced" || c.s === "complained").length,
      unconfirmed: all.filter((c) => c.s === "unconfirmed").length,
      texting: all.filter((c) => c.sm === "subscribed").length,
      newThisWeek: all.filter((c) => (c.d || 0) >= week).length,
      tags, engagement: eng, growth,
      seats: seats ? { sold: seats.count, limit: seats.limit } : null,
      sentToday: await sentToday(env), cap: dailyCap(env), textsToday: await textsToday(env), smsCap: smsCap(env),
      log: await recentLog(env, 30),
      setup: {
        email: !!env.RESEND_API_KEY, texts: smsReady(env), bounces: !!env.RESEND_WEBHOOK_SECRET, scheduler: !!env.CRON_SECRET,
        lastTick: await env.FILES.get("meta:lasttick", "json"),
      },
      unreadTexts: !!(await env.FILES.get("unread:texts")),
    });
  }

  // ----- contacts -----
  if (route === "contacts") return json({ ok: true, contacts: (await allContacts(env)).sort((a, b) => (b.d || 0) - (a.d || 0)) });

  if (route === "contact" && request.method === "GET") {
    const c = await getContact(env, url.searchParams.get("e"));
    return c ? json({ ok: true, contact: c }) : bad("No contact with that email.");
  }

  if (route === "contact" && request.method === "POST") {
    const email = cleanEmail(d.email);
    if (!validEmail(email)) return bad("Enter a valid email address.");
    if (d.phone && !toE164(d.phone)) return bad("That mobile number doesn't look right.");
    let c = await upsertContact(env, { email, name: d.name, tags: d.addTags || [], source: "Added in dashboard", optIn: false, phone: d.phone || undefined });
    if (d.name !== undefined && d.name !== c.name) c.name = str(d.name, 80);
    if (d.removeTags && d.removeTags.length) { c.tags = c.tags.filter((t) => !d.removeTags.includes(t)); addEvent(c, "untagged", d.removeTags.join(", ")); }
    if (d.fields && typeof d.fields === "object") {
      const f = {};
      for (const [k, v] of Object.entries(d.fields).slice(0, 30)) { const key = String(k).replace(/[^a-z0-9_]/gi, "").slice(0, 40); if (key && v !== "") f[key] = str(v, 300); }
      c.fields = f;
    }
    if (d.phone === "") { if (c.phone) await env.FILES.delete("p:" + c.phone); c.phone = ""; }
    await putContact(env, c);
    if (d.status && ["active", "unsubscribed", "bounced"].includes(d.status) && d.status !== c.status) c = await setStatus(env, email, d.status, "set in dashboard by " + admin);
    if (d.sms === "unsubscribed" && c.sms && c.sms.status === "subscribed") c = await setSms(env, c, "unsubscribed", "set in dashboard");
    if (d.sms === "subscribed" && (!c.sms || c.sms.status !== "subscribed")) {
      if (!c.phone) return bad("Add a mobile number first.");
      if (!d.consentNote || String(d.consentNote).trim().length < 8) return bad("Say how he agreed to texts (for example, \"asked on our call Nov 30\"). The law requires a record.");
      c.sms = { status: "subscribed", consentAt: Date.now(), source: "Dashboard: " + str(d.consentNote, 200), ip: "" };
      addEvent(c, "texts on", "dashboard: " + str(d.consentNote, 100));
      await putContact(env, c);
    }
    return json({ ok: true, contact: c });
  }

  if (route === "contact-delete") {
    const c = await getContact(env, d.email);
    if (c && c.phone) await env.FILES.delete("p:" + c.phone);
    await env.FILES.delete("c:" + cleanEmail(d.email));
    return json({ ok: true });
  }

  if (route === "export") {
    const all = await allContacts(env);
    const lines = ["email,name,mobile,texts,tags,status,engagement,joined"].concat(all.map((c) =>
      [c.email, c.n, c.ph, c.sm, (c.t || "").split("|").join("; "), c.s, c.en, c.d ? new Date(c.d).toISOString().slice(0, 10) : ""].map(csvCell).join(",")));
    return new Response(lines.join("\n") + "\n", { headers: { "content-type": "text/csv; charset=utf-8", "content-disposition": "attachment; filename=be-the-man-contacts.csv", "cache-control": "no-store" } });
  }

  if (route === "import") {
    const rows = parseCsv(d.csv);
    if (!rows.length) return bad("Paste at least one line: email, name.");
    const head = rows[0].map((h) => h.toLowerCase());
    const ei = head.findIndex((h) => h.includes("email"));
    const ni = head.findIndex((h) => h.includes("name") && !h.includes("last"));
    const body = ei >= 0 ? rows.slice(1) : rows;
    const E = ei >= 0 ? ei : 0, N = ei >= 0 ? ni : 1;
    let added = 0, skipped = 0;
    for (const r of body.slice(0, 2000)) {
      const email = cleanEmail(r[E]);
      if (!validEmail(email)) { skipped++; continue; }
      await upsertContact(env, { email, name: N >= 0 ? r[N] : "", tags: d.tag ? [d.tag] : [], source: "Imported", optIn: false, run: false });
      added++;
    }
    return json({ ok: true, added, skipped });
  }

  // ----- segments -----
  if (route === "segments" && request.method === "GET") {
    const segs = await getSegments(env);
    const all = await allContacts(env);
    return json({ ok: true, segments: segs.map((s) => ({ ...s, count: s.field ? null : all.filter((m) => matches(s, m)).length })) });
  }
  if (route === "segments" && request.method === "POST") {
    const list = (d.segments || []).slice(0, 100).map(cleanSegment);
    await saveSegments(env, list);
    return json({ ok: true, segments: list });
  }
  if (route === "segment-count") {
    const seg = cleanSegment(d.segment || {});
    const all = await allContacts(env);
    let n = 0;
    for (const m of all) if (matches(seg, m, seg.field ? await getContact(env, m.email) : null)) n++;
    return json({ ok: true, count: n });
  }

  // ----- automations -----
  if (route === "automations" && request.method === "GET") {
    const autos = await getAutomations(env);
    const all = await allContacts(env);
    const out = [];
    for (const a of autos) {
      const stats = [];
      for (let i = 0; i < a.steps.length; i++) if (a.steps[i].type === "email" || a.steps[i].type === "sms") stats.push({ i, ...(await getStats(env, `au:${a.id}:${i}`)) });
      out.push({ ...a, inProgress: all.filter((m) => (m.q || "").split(",").includes("a:" + a.id)).length, stats });
    }
    return json({ ok: true, automations: out });
  }
  if (route === "automations" && request.method === "POST") {
    const list = (d.automations || []).slice(0, 100).map(cleanAutomation);
    await saveAutomations(env, list);
    return json({ ok: true, automations: list });
  }
  if (route === "automation-start") {
    const c = await getContact(env, d.email);
    const autos = await getAutomations(env);
    const a = autos.find((x) => x.id === d.id);
    if (!c || !a) return bad("Contact or automation not found.");
    if (c.auto && c.auto[a.id]) delete c.auto[a.id];
    startTriggered(c, [{ ...a, enabled: true, trigger: { type: "manual", value: "" } }], "manual", "");
    await putContact(env, c);
    await runContact(env, c, 3);
    return json({ ok: true });
  }

  // ----- forms -----
  if (route === "forms" && request.method === "GET") {
    const forms = await getForms(env);
    const all = await allContacts(env);
    return json({ ok: true, forms: forms.map((f) => ({ ...f, signups: f.tag ? all.filter((m) => (m.t || "").split("|").includes(f.tag)).length : null })) });
  }
  if (route === "forms" && request.method === "POST") {
    const list = (d.forms || []).slice(0, 100).map(cleanForm);
    const ids = new Set();
    for (const f of list) { if (ids.has(f.id)) f.id += "-" + uid().slice(-4); ids.add(f.id); }
    await saveForms(env, list);
    return json({ ok: true, forms: list });
  }

  // ----- series -----
  if (route === "sequences") {
    const all = await allContacts(env);
    const seqs = await allSequences(env);
    const out = [];
    for (const s of seqs) {
      const stats = [];
      for (let i = 0; i < s.emails.length; i++) stats.push({ i, ...(await getStats(env, `sq:${s.id}:${i}`)) });
      out.push({ ...s, inProgress: all.filter((c) => (c.q || "").split(",").includes(s.id)).length, stats });
    }
    return json({ ok: true, sequences: out });
  }
  if (route === "sequence") {
    const def = await getSequence(env, d.id);
    if (!def) return bad("Unknown series.");
    const emails = (d.emails || []).map((e) => ({
      ...(e.subject || e.body ? { subject: str(e.subject), body: str(e.body, 20000) } : {}),
      ...(e.text ? { text: str(e.text, 600) } : {}),
      ...(def.kind === "dated" ? { at: str(e.at, 40) } : { delayDays: Math.max(0, Number(e.delayDays) || 0) }),
    }));
    if (!emails.length) return bad("A series needs at least one step.");
    if (emails.some((e) => !(e.subject && e.body) && !e.text)) return bad("Each step needs an email (subject and body), a text, or both.");
    if (emails.some((e) => (e.subject && !e.body) || (!e.subject && e.body))) return bad("An email needs both a subject and a body.");
    if (def.kind === "dated" && emails.some((e) => isNaN(Date.parse(e.at)))) return bad("Every dated step needs a valid date and time.");
    if (def.kind === "dated") emails.sort((a, b) => Date.parse(a.at) - Date.parse(b.at));
    await env.FILES.put("seqdef:" + d.id, JSON.stringify({ emails, edited: Date.now() }));
    return json({ ok: true });
  }
  if (route === "sequence-reset") { await env.FILES.delete("seqdef:" + d.id); return json({ ok: true }); }
  if (route === "enroll") {
    const c = await getContact(env, d.email);
    if (!c) return bad("No contact with that email.");
    if (!(await getSequence(env, d.id))) return bad("Unknown series.");
    await enroll(env, c, d.id);
    await runContact(env, c);
    return json({ ok: true, contact: await getContact(env, d.email) });
  }

  // ----- broadcasts -----
  if (route === "broadcasts") {
    const list = await allBroadcasts(env);
    for (const b of list) if (b.st !== "draft") b.stats = await getStats(env, "bc:" + b.id);
    return json({ ok: true, broadcasts: list });
  }
  if (route === "broadcast" && request.method === "GET") {
    const b = await getBroadcast(env, url.searchParams.get("id"));
    if (!b) return bad("Not found.");
    return json({ ok: true, broadcast: { ...b, opened: undefined, openedCount: (b.opened || []).length }, stats: await getStats(env, "bc:" + b.id) });
  }
  if (route === "broadcast" && request.method === "POST") {
    const channel = d.channel === "sms" ? "sms" : "email";
    if (channel === "email" && (!d.subject || !d.body)) return bad("An email broadcast needs a subject and a body.");
    if (channel === "sms" && !d.text) return bad("A text broadcast needs a message.");
    let b = d.id ? await getBroadcast(env, d.id) : null;
    if (b && !["draft", "scheduled"].includes(b.status)) return bad("That broadcast has already gone out.");
    b = b || { id: uid(), created: Date.now(), status: "draft" };
    const aud = d.audience && ["all", "tag", "segment", "unopened"].includes(d.audience.type) ? { type: d.audience.type, value: str(d.audience.value, 80) } : { type: "all", value: "" };
    Object.assign(b, { channel, subject: str(d.subject), subjectB: str(d.subjectB), body: str(d.body, 20000), text: str(d.text, 600), audience: aud, status: "draft", scheduledAt: 0 });
    await putBroadcast(env, b);
    return json({ ok: true, broadcast: b });
  }
  if (route === "broadcast-count") {
    const list = await audience(env, d.audience, d.channel === "sms" ? "sms" : "email");
    return json({ ok: true, count: list.length });
  }
  if (route === "broadcast-send") {
    const b = await getBroadcast(env, d.id);
    if (!b || !["draft", "scheduled"].includes(b.status)) return bad("Only a saved draft can be sent.");
    if (b.channel === "sms" && !smsReady(env)) return bad("Texting isn't connected yet. Add the Twilio keys in Cloudflare first.");
    if (d.at) {
      const at = Date.parse(d.at);
      if (isNaN(at) || at < Date.now() - 60000) return bad("Pick a time in the future.");
      Object.assign(b, { status: "scheduled", scheduledAt: at });
      await putBroadcast(env, b);
      return json({ ok: true, broadcast: b });
    }
    await queueBroadcast(env, b);
    context.waitUntil(tick(env).catch(() => null));
    return json({ ok: true, broadcast: b });
  }
  if (route === "broadcast-unschedule") {
    const b = await getBroadcast(env, d.id);
    if (!b || b.status !== "scheduled") return bad("That broadcast isn't scheduled.");
    Object.assign(b, { status: "draft", scheduledAt: 0 });
    await putBroadcast(env, b);
    return json({ ok: true });
  }
  if (route === "broadcast-resend") {
    const src = await getBroadcast(env, d.id);
    if (!src || src.status !== "sent" || src.channel === "sms") return bad("Only a sent email broadcast can be resent.");
    const b = { id: uid(), created: Date.now(), status: "draft", channel: "email", subject: src.subject, body: src.body, text: "", subjectB: "", audience: { type: "unopened", value: src.id }, resendOf: src.id };
    await putBroadcast(env, b);
    return json({ ok: true, broadcast: b });
  }
  if (route === "broadcast-delete") {
    const b = await getBroadcast(env, d.id);
    if (!b || !["draft", "scheduled"].includes(b.status)) return bad("Only drafts can be deleted.");
    await env.FILES.delete("bc:" + d.id);
    return json({ ok: true });
  }

  // ----- texts inbox -----
  if (route === "texts") {
    await env.FILES.delete("unread:texts");
    return json({ ok: true, texts: await recentLog(env, 300, "slog:"), ready: smsReady(env) });
  }
  if (route === "text-reply") {
    const to = toE164(d.phone);
    if (!to) return bad("That number doesn't look right.");
    if (!d.body) return bad("Write a message first.");
    const r = await sendSms(env, { to, body: str(d.body, 600) });
    await logText(env, { e: d.email || "", ph: to, dir: "out", b: str(d.body, 300), k: "reply", ok: r.ok ? 1 : 0, err: r.ok ? undefined : str(r.error, 160) });
    return r.ok ? json({ ok: true }) : bad(r.error);
  }
  if (route === "test-sms") {
    const to = toE164(d.phone);
    if (!to) return bad("Enter your mobile number.");
    const r = await sendSms(env, { to, body: "[Test] " + listText(d.text || "This is a test text.") });
    return r.ok ? json({ ok: true }) : bad(r.error);
  }

  // ----- misc -----
  if (route === "stats") return json({ ok: true, stats: await getStats(env, url.searchParams.get("k")) });
  if (route === "preview") return json({ ok: true, html: emailHtml(bodyHtml(d.body, { name: "Brian", email: "brian@bethemansystem.com", fields: {} }), "#unsubscribe") });
  if (route === "test") {
    if (!d.subject || !d.body) return bad("Add a subject and a body first.");
    const r = await sendTest(env, d, admin);
    return r.ok ? json({ ok: true, to: admin }) : bad(r.error || "Resend didn't accept it.");
  }
  if (route === "tick") return json(await tick(env));

  return json({ ok: false, error: "Not found." }, 404);
}
