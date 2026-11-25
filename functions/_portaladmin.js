// Brian's side of the men's portal: /api/admin/<route> routes for the Men, Library and Sessions screens.
// Called from functions/api/admin/[[path]].js after the admin check. Returns a Response, or null if the route isn't ours.

import {
  STEPS, today, addDays, weekOf, getRecord, putRecord, ensureRecord, allRecords, stepStates, insights, setCommitments, weekScore,
  sendSignInLink, getLibrary, saveLibrary, getSessions, saveSessions, addMessage, thread, inbox, graduate, setShare, nextSession,
} from "./_portal.js";
import { getContact, putContact, addEvent, allContacts, cleanEmail, validEmail, emailHtml, bodyHtml, SITE, uid } from "./_list.js";
import { sendEmail } from "./_mail.js";
import { COHORT_DATES } from "./_booking.js";

const json = (b, s = 200, h = {}) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json", "cache-control": "no-store", ...h } });
const bad = (msg) => json({ ok: false, error: msg }, 400);
const str = (v, n = 2000) => String(v ?? "").slice(0, n);
const PORTAL = `${SITE}/portal/`;

// An email to one man from Brian (no unsubscribe link: it's about his own portal).
export async function manEmail(env, c, subject, body) {
  return sendEmail(env, { to: c.email, subject, html: emailHtml(bodyHtml(body, c), null) });
}
const firstOf = (c) => (c && c.name ? c.name.split(/\s+/)[0] : "Brother");

async function privateNotes(env, email) { return (await env.FILES.get("pn:" + email, "json")) || []; }

export async function deletePortal(env, email) {
  const pd = await getRecord(env, email);
  if (pd && pd.share && pd.share.token) await env.FILES.delete("sh:" + pd.share.token);
  if (pd && pd.partner) { const p = await getRecord(env, pd.partner); if (p && p.partner === email) { p.partner = ""; await putRecord(env, p); } }
  for (const prefix of [`msg:${email}:`, `up:${email}:`]) {
    const page = await env.FILES.list({ prefix });
    for (const k of page.keys) await env.FILES.delete(k.name);
  }
  await env.FILES.delete("pn:" + email);
  await env.FILES.delete("pd:" + email);
}

export async function buildBackup(env) {
  const out = { at: new Date().toISOString(), portal: [], contacts: [] };
  for (const r of await allRecords(env)) { const pd = await getRecord(env, r.email); if (pd) out.portal.push({ ...pd, messages: await thread(env, r.email), privateNotes: await privateNotes(env, r.email) }); }
  for (const x of await allContacts(env)) { const c = await getContact(env, x.email); if (c) out.contacts.push(c); }
  out.library = await getLibrary(env);
  out.sessions = await getSessions(env);
  return out;
}

export async function portalAdmin(route, d, request, env, url, waitUntil) {
  const bg = (p) => { if (waitUntil) waitUntil(p.catch(() => null)); return p; };

  if (route === "men") {
    const recs = await allRecords(env);
    const box = await inbox(env);
    const out = [];
    for (const r of recs) {
      const pd = await getRecord(env, r.email);
      if (!pd) continue;
      const c = await getContact(env, r.email);
      const ins = insights(pd, c);
      const m = box.find((x) => x.email === r.email);
      out.push({ email: r.email, name: (c && c.name) || "", role: pd.role, access: pd.access, pace: pd.pace.mode, steps: stepStates(pd), last: ins.weeks[ins.weeks.length - 2], now: ins.weeks[ins.weeks.length - 1],
        flags: ins.flags.concat(pd.flags && pd.flags.safety && Date.now() - pd.flags.safety < 14 * 86400000 ? ["Safety alert"] : []).concat(pd.deleteRequested ? ["Asked to delete his data"] : []),
        lastActive: pd.lastActive, partner: pd.partner, graduated: pd.graduated, unread: pd.unreadBrian || 0, lastMsg: m ? m.last : 0, streak: ins.streak });
    }
    out.sort((a, b) => (b.unread - a.unread) || (b.flags.length - a.flags.length) || String(a.name || a.email).localeCompare(b.name || b.email));
    return json({ ok: true, men: out, steps: STEPS });
  }

  if (route === "man" && request.method === "GET") {
    const email = cleanEmail(url.searchParams.get("email"));
    const pd = await getRecord(env, email);
    if (!pd) return bad("No portal for that address.");
    const c = (await getContact(env, email)) || { email, name: "", tags: [], fields: {} };
    const lib = await getLibrary(env);
    return json({ ok: true, record: pd, steps: stepStates(pd), stepNames: STEPS, insights: insights(pd, c), notes: await privateNotes(env, email), messages: await thread(env, email),
      contact: { name: c.name, email: c.email, phone: c.phone || "", tags: c.tags || [], ledger: c.ledger || {}, cohort: c.cohort || {} },
      lessons: lib.lessons.map((l) => ({ id: l.id, week: l.week, title: l.title, reflection: l.reflection, action: l.action, questions: l.questions || [], days: (l.days || []).map((x) => ({ t: x.t, q: x.q })) })), sessions: COHORT_DATES,
      men: (await allRecords(env)).map((x) => x.email).filter((e) => e !== email), week: weekOf(today()) });
  }

  if (route === "man-upload") {
    const email = cleanEmail(url.searchParams.get("email")), id = String(url.searchParams.get("id") || "").replace(/[^a-z0-9]/g, "");
    const v = await env.FILES.getWithMetadata(`up:${email}:${id}`, "arrayBuffer");
    if (!v || !v.value) return new Response("Not found", { status: 404 });
    return new Response(v.value, { headers: { "content-type": (v.metadata && v.metadata.type) || "image/jpeg", "cache-control": "private, max-age=3600" } });
  }

  if (route === "man-create") {
    const email = cleanEmail(d.email);
    if (!validEmail(email)) return bad("Enter a valid email.");
    const role = ["cohort", "club", "step1", "admin"].includes(d.role) ? d.role : "cohort";
    const { pd, created } = await ensureRecord(env, email, { role, name: str(d.name, 80) });
    if (d.name) { const c = await getContact(env, email); if (c && !c.name) { c.name = str(d.name, 80); await putContact(env, c); } }
    if (d.invite) await sendSignInLink(env, email);
    return json({ ok: true, created, email: pd.email });
  }

  if (route === "man-update") {
    const email = cleanEmail(d.email);
    const pd = await getRecord(env, email);
    if (!pd) return bad("No portal for that address.");
    const c = (await getContact(env, email)) || { email, name: "", tags: [], fields: {} };
    const op = d.op;
    const n = Number(d.n);
    let msg = "Saved.";

    if (op === "approve") {
      if (!STEPS[n]) return bad("Unknown step.");
      pd.steps[n] = { ...(pd.steps[n] || {}), status: "approved", approvedAt: Date.now() };
      delete pd.steps[n].note;
      if (d.note) pd.shared.unshift({ text: str(d.note, 1500), at: Date.now(), step: n });
      const nextSt = n < 4 ? stepStates(pd)[n + 1] : null;
      const nextLine = nextSt ? (nextSt.status === "open" ? `Step ${n + 1}, ${STEPS[n + 1]}, is open now.` : nextSt.opens ? `Step ${n + 1}, ${STEPS[n + 1]}, opens ${new Date(nextSt.opens + "T12:00:00Z").toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric", timeZone: "UTC" })}.` : "") : "That's all four steps. Keep the Ledger going every week.";
      if (d.tell !== false) bg(manEmail(env, c, `Step ${n} approved`, `${firstOf(c)}, I approved Step ${n}, ${STEPS[n]}. Well done.${d.note ? `\n\n${str(d.note, 1500)}` : ""}\n\n${nextLine}\n\n[[Open my portal|${PORTAL}]]\n\nBrian`));
      msg = `Step ${n} approved.`;
    } else if (op === "revisit") {
      if (!STEPS[n]) return bad("Unknown step.");
      pd.steps[n] = { ...(pd.steps[n] || {}), status: "revisit", note: str(d.note, 1500), revisitAt: Date.now() };
      bg(manEmail(env, c, `Take another look at Step ${n}`, `${firstOf(c)}, I read your Step ${n}, ${STEPS[n]}. Take another look at this:\n\n${str(d.note, 1500)}\n\nThen send it to me again.\n\n[[Open Step ${n}|${PORTAL}#step-${n}]]\n\nBrian`));
      msg = `Sent back with your note.`;
    } else if (op === "open-step") {
      if (!STEPS[n]) return bad("Unknown step.");
      pd.steps[n] = { ...(pd.steps[n] || {}), forced: !!d.on };
      if (!d.on && pd.steps[n].status === "open") delete pd.steps[n].status;
    } else if (op === "pace") {
      const mode = ["cohort", "self", "custom"].includes(d.mode) ? d.mode : "cohort";
      const dates = {};
      for (const k of [2, 3, 4]) if (/^\d{4}-\d{2}-\d{2}$/.test((d.dates || {})[k] || "")) dates[k] = d.dates[k];
      pd.pace = { mode, dates };
    } else if (op === "partner") {
      const p = cleanEmail(d.partner);
      if (pd.partner && pd.partner !== p) { const old = await getRecord(env, pd.partner); if (old && old.partner === email) { old.partner = ""; await putRecord(env, old); } }
      if (p) {
        const other = await getRecord(env, p);
        if (!other) return bad("That man doesn't have a portal yet.");
        if (other.partner && other.partner !== email) { const o2 = await getRecord(env, other.partner); if (o2 && o2.partner === p) { o2.partner = ""; await putRecord(env, o2); } }
        other.partner = email; await putRecord(env, other);
      }
      pd.partner = p;
      msg = p ? "Partners set. They now see each other's weekly number and Sunday answers." : "Partner removed.";
    } else if (op === "role") {
      if (["cohort", "club", "step1", "admin"].includes(d.role)) pd.role = d.role;
      if (["full", "readonly"].includes(d.access)) pd.access = d.access;
    } else if (op === "shared-note") {
      const text = str(d.text, 2000).trim();
      if (!text) return bad("Write a note first.");
      pd.shared.unshift({ text, at: Date.now() });
      pd.shared = pd.shared.slice(0, 50);
      if (d.tell) bg(manEmail(env, c, "A note from Brian", `${firstOf(c)},\n\n${text}\n\n[[Open my portal|${PORTAL}]]\n\nBrian`));
      msg = "Note added. He sees it on his Today screen.";
    } else if (op === "shared-delete") {
      pd.shared = pd.shared.filter((x) => x.at !== Number(d.at));
    } else if (op === "private-note") {
      const text = str(d.text, 3000).trim();
      if (!text) return bad("Write a note first.");
      const notes = await privateNotes(env, email);
      notes.unshift({ text, at: Date.now() });
      await env.FILES.put("pn:" + email, JSON.stringify(notes.slice(0, 200)));
      return json({ ok: true, message: "Private note saved. Only you see it." });
    } else if (op === "private-delete") {
      const notes = (await privateNotes(env, email)).filter((x) => x.at !== Number(d.at));
      await env.FILES.put("pn:" + email, JSON.stringify(notes));
      return json({ ok: true });
    } else if (op === "next") {
      const text = str(d.text, 600).trim();
      if (!text) return bad("Write the next step first.");
      pd.next.unshift({ id: uid(), text, due: /^\d{4}-\d{2}-\d{2}$/.test(d.due || "") ? d.due : "", at: Date.now(), done: 0 });
      pd.next = pd.next.slice(0, 40);
      bg(manEmail(env, c, "Your next step", `${firstOf(c)}, here's your next step:\n\n**${text}**${d.due ? `\n\nBy ${new Date(d.due + "T12:00:00Z").toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric", timeZone: "UTC" })}.` : ""}\n\nMark it done in your portal when it's done.\n\n[[Open my portal|${PORTAL}]]\n\nBrian`));
      msg = "Next step assigned. He got an email.";
    } else if (op === "next-delete") {
      pd.next = pd.next.filter((x) => x.id !== d.id);
    } else if (op === "commitments") {
      setCommitments(pd, d.list, "brian");
    } else if (op === "graduate") {
      await graduate(env, pd);
      if (d.tell !== false) bg(manEmail(env, c, "You finished the Founding Cohort", `${firstOf(c)}, you did it. Six weeks ago you wrote one sentence. Since then you've kept a real Ledger.\n\nYour graduate badge is on your portal. Your record stays there for you to read any time.\n\nIf you want to keep going with the brothers, the Club is where graduates keep the Ledger running: a monthly call, a partner and your portal.\n\n[[See the Club|${SITE}/club/]]\n\nProud of you.\n\nBrian`));
      msg = pd.access === "readonly" ? "Graduated. His portal is read-only until he joins the Club." : "Graduated.";
    } else if (op === "message") {
      const text = str(d.text, 3000).trim();
      if (!text) return bad("Write something first.");
      await addMessage(env, email, "brian", "message", text);
      bg(manEmail(env, c, "Brian replied in your portal", `${firstOf(c)},\n\n${text}\n\n[[Reply in your portal|${PORTAL}#messages]]\n\nBrian`));
      pd.unreadBrian = 0;
      msg = "Sent. He got an email too.";
    } else if (op === "read") {
      pd.unreadBrian = 0;
      const box = await inbox(env);
      if (!box.some((x) => x.email !== email && x.from === "him")) await env.FILES.delete("unread:portal");
    } else if (op === "share-off") {
      await setShare(env, pd, false);
    } else if (op === "invite") {
      await sendSignInLink(env, email);
      return json({ ok: true, message: "Sign-in link sent." });
    } else if (op === "delete") {
      await deletePortal(env, email);
      if (c.created || c.tags) { addEvent(c, "portal deleted", ""); c.tags = (c.tags || []).filter((t) => t !== "Portal"); await putContact(env, c); }
      if (d.tell) await manEmail(env, c, "Your portal data is deleted", `${firstOf(c)}, as you asked, your Be The Man portal data has been deleted.\n\nBrian`);
      return json({ ok: true, message: "Portal deleted." });
    } else return bad("Unknown action.");

    await putRecord(env, pd);
    return json({ ok: true, message: msg });
  }

  if (route === "portal-inbox") {
    const box = await inbox(env);
    const out = [];
    for (const m of box.slice(0, 100)) { const c = await getContact(env, m.email); out.push({ ...m, name: (c && c.name) || "" }); }
    return json({ ok: true, inbox: out });
  }

  if (route === "library" && request.method === "GET") return json({ ok: true, ...(await getLibrary(env)) });
  if (route === "library" && request.method === "POST") {
    const lessons = (d.lessons || []).slice(0, 30).map((l, i) => ({
      id: str(l.id, 20) || "x" + uid(), week: Math.min(6, Math.max(1, Number(l.week) || i + 1)), step: Math.min(4, Math.max(1, Number(l.step) || 1)),
      title: str(l.title, 160), scripture: str(l.scripture, 120), video: str(l.video, 300), body: str(l.body, 30000), action: str(l.action, 400), reflection: str(l.reflection, 400), pdf: str(l.pdf, 300),
      intro: str(l.intro, 600), verse: str(l.verse, 600), prayer: str(l.prayer, 600),
      questions: (Array.isArray(l.questions) ? l.questions : []).slice(0, 5).map((q) => str(q, 300)).filter(Boolean),
      learn: (Array.isArray(l.learn) ? l.learn : []).slice(0, 4).map((x) => ({ t: str(x && x.t, 120), b: str(x && x.b, 1500) })).filter((x) => x.t && x.b),
      adhd: l.adhd && l.adhd.t ? { t: str(l.adhd.t, 120), b: str(l.adhd.b, 1500) } : null,
      tool: l.tool && l.tool.t ? { t: str(l.tool.t, 120), b: str(l.tool.b, 1500) } : null,
      days: (Array.isArray(l.days) ? l.days : []).slice(0, 7).map((x) => ({ t: str(x && x.t, 120), do: str(x && x.do, 600), q: str(x && x.q, 300) })).filter((x) => x.t),
    })).filter((l) => l.title);
    const materials = (d.materials || []).slice(0, 40).map((m) => ({ id: str(m.id, 20) || uid(), title: str(m.title, 160), url: str(m.url, 400), kind: m.kind === "pdf" ? "pdf" : "link" })).filter((m) => m.title && /^https?:\/\/|^\//.test(m.url));
    await saveLibrary(env, { lessons, materials });
    return json({ ok: true });
  }
  if (route === "library-reset") { await env.FILES.delete("lessons"); return json({ ok: true }); }

  if (route === "sessions" && request.method === "GET") return json({ ok: true, sessions: await getSessions(env), dates: COHORT_DATES });
  if (route === "sessions" && request.method === "POST") {
    const s = {};
    for (const date of COHORT_DATES) { const x = (d.sessions || {})[date] || {}; if (x.video || x.note) s[date] = { video: str(x.video, 300), note: str(x.note, 2000) }; }
    await saveSessions(env, s);
    return json({ ok: true });
  }

  // Before a call: every man's note, number and flags on one sheet.
  if (route === "callsheet") {
    const date = /^\d{4}-\d{2}-\d{2}$/.test(url.searchParams.get("date") || "") ? url.searchParams.get("date") : nextSession() || COHORT_DATES[COHORT_DATES.length - 1];
    const recs = await allRecords(env);
    const rows = [];
    for (const r of recs) {
      if (r.r !== "cohort") continue;
      const pd = await getRecord(env, r.email);
      const c = await getContact(env, r.email);
      const ins = insights(pd, c);
      const prev = addDays(weekOf(date), -7);
      rows.push({ email: r.email, name: (c && c.name) || r.email, prep: pd.callPrep[date] || null, last: ins.weeks.find((w) => w.week === prev) || null,
        hard: !!pd.hard[weekOf(date)] || !!pd.hard[prev], flags: ins.flags, mostMissed: ins.mostMissed, review: pd.reviews[prev] || null, here: !!pd.attendance[date] });
    }
    rows.sort((a, b) => (b.prep ? 1 : 0) - (a.prep ? 1 : 0) || b.flags.length - a.flags.length);
    return json({ ok: true, date, rows });
  }

  // Cohort-wide view: no new data, just the men's records added up.
  if (route === "portal-insights") {
    const recs = (await allRecords(env)).filter((r) => r.r === "cohort");
    const weeks = {};
    const steps = { 1: {}, 2: {}, 3: {}, 4: {} };
    const att = {};
    const misses = [];
    let flagged = 0, active7 = 0;
    for (const r of recs) {
      const pd = await getRecord(env, r.email);
      const c = await getContact(env, r.email);
      const ins = insights(pd, c);
      if (ins.flags.length) flagged++;
      if (pd.lastActive && Date.now() - pd.lastActive < 7 * 86400000) active7++;
      for (const w of ins.weeks) { if (!w.t) continue; const x = weeks[w.week] = weeks[w.week] || { k: 0, t: 0, men: 0, reviewed: 0 }; x.k += w.k; x.t += w.t; x.men++; if (w.reviewed) x.reviewed++; }
      const st = stepStates(pd);
      for (const n of [1, 2, 3, 4]) steps[n][st[n].status] = (steps[n][st[n].status] || 0) + 1;
      for (const dt of COHORT_DATES) if (pd.attendance[dt] || (c && c.cohort && c.cohort.att && c.cohort.att[dt])) att[dt] = (att[dt] || 0) + 1;
      for (const [w, rv] of Object.entries(pd.reviews)) if (rv.miss) misses.push({ week: w, text: rv.miss });
      if (ins.mostMissed) misses.push({ week: "", text: "Most missed: " + ins.mostMissed.what });
    }
    return json({ ok: true, men: recs.length, flagged, active7, weeks, steps, attendance: att, sessions: COHORT_DATES, misses: misses.sort((a, b) => (b.week || "").localeCompare(a.week || "")).slice(0, 60) });
  }

  // Everything, as one file.
  if (route === "backup") {
    return new Response(JSON.stringify(await buildBackup(env), null, 1), { headers: { "content-type": "application/json", "content-disposition": `attachment; filename="be-the-man-backup-${today()}.json"`, "cache-control": "no-store" } });
  }

  return null;
}
