// The men's portal API: /api/portal/<route>.
// A man signs in with an emailed link or a text code. Brian (signed in to the dashboard)
// uses the portal as himself ("My system"), or opens a man's portal read-only with ?as=<email> (Coach view).

import {
  COOKIE, STEPS, today, addDays, dow, weekOf, weekDays, getRecord, putRecord, ensureRecord, allRecords, stepStates, stepState,
  scorecardOn, setCommitments, scheduledOn, weekScore, canMark, streak, forMan, safetyCheck, CRISIS, portalCookie, clearPortalCookie,
  portalUser, sendSignInLink, sendSignInCode, checkSignInCode, calendarUrl, setShare, getLibrary, getSessions, lessonOpen, nextSession,
  inCheckInWindow, addMessage, thread, WEEK_STEP,
} from "../../_portal.js";
import { adminFrom } from "../../_admin.js";
import { getContact, putContact, addEvent, emailBrian, cleanEmail, validEmail, SITE, BRIAN } from "../../_list.js";
import { COHORT_DATES } from "../../_booking.js";
import { toE164 } from "../../_sms.js";
import { MEET } from "../../_sequences.js";

const json = (b, s = 200, h = {}) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json", "cache-control": "no-store", ...h } });
const bad = (msg, s = 400) => json({ ok: false, error: msg }, s);
const str = (v, n = 2000) => String(v ?? "").slice(0, n);
const SENT = { ok: true, message: "If that address has a portal, a sign-in link is on its way. It works for 30 minutes." };
const first = (name, email) => (name ? String(name).split(/\s+/)[0] : String(email || "").split("@")[0]);

// Which week the Sunday review is for: on Sunday it's this week, otherwise last week.
const reviewWeek = () => (dow(today()) === 0 ? today() : addDays(weekOf(today()), -7));

// Who is this, and may they write?
async function who(request, env, url) {
  const admin = await adminFrom(request, env);
  const as = url.searchParams.get("as");
  if (admin && as) return { email: cleanEmail(as), coach: true, admin };
  const email = await portalUser(request, env);
  if (email) return { email, coach: false, admin };
  if (admin) { await ensureRecord(env, admin, { role: "admin", name: "Brian Greene" }); return { email: admin, coach: false, admin }; }
  return null;
}

// Men who may get a portal on sign-in even if no record was made yet.
async function eligibleRole(env, email) {
  const c = await getContact(env, email);
  if (!c) return null;
  if (c.tags.includes("Founding Cohort")) return "cohort";
  if (c.tags.includes("Club member")) return "club";
  if (c.tags.includes("Step 1")) return "step1";
  return null;
}

export async function onRequest(context) {
  const { request, env, params, waitUntil } = context;
  const url = new URL(request.url);
  const route = (params.path || []).join("/");
  let d = {};
  if (request.method === "POST" && (request.headers.get("content-type") || "").includes("application/json")) { try { d = await request.json(); } catch (e) {} }

  // ---------- sign-in (no session needed) ----------

  if (route === "login" && request.method === "POST") {
    const email = cleanEmail(d.email);
    if (!validEmail(email)) return bad("Please enter a valid email.");
    let pd = await getRecord(env, email);
    if (!pd) { const role = await eligibleRole(env, email); if (role) pd = (await ensureRecord(env, email, { role })).pd; }
    if (pd) { const p = sendSignInLink(env, email, str(d.next, 200)).catch(() => null); waitUntil ? waitUntil(p) : await p; }
    return json(SENT);
  }
  if (route === "verify") {
    const { unsign } = await import("../../_club.js");
    const t = await unsign(env, url.searchParams.get("t"));
    if (!t || t.p !== "plogin") return Response.redirect(new URL("/portal/login/?expired=1", url).toString(), 302);
    const next = url.searchParams.get("next");
    const to = next && next.startsWith("/portal/") ? next : "/portal/";
    return new Response(null, { status: 302, headers: { location: new URL(to, url).toString(), "set-cookie": await portalCookie(env, t.e), "cache-control": "no-store" } });
  }
  if (route === "code-send" && request.method === "POST") {
    const ok = await sendSignInCode(env, d.phone);
    if (!ok) return bad("Text sign-in isn't available right now. Use your email instead.");
    return json({ ok: true, message: "If that number is on a portal, a 6-digit code is on its way." });
  }
  if (route === "code-check" && request.method === "POST") {
    const email = await checkSignInCode(env, d.phone, d.code);
    if (!email) return bad("That code didn't work. Check it, or ask for a new one.");
    return json({ ok: true }, 200, { "set-cookie": await portalCookie(env, email) });
  }
  if (route === "logout") return json({ ok: true }, 200, { "set-cookie": clearPortalCookie });

  // ---------- signed in ----------

  const u = await who(request, env, url);
  if (!u) return json({ ok: false, signedIn: false }, 401);
  const pd = await getRecord(env, u.email);
  if (!pd) return json({ ok: false, signedIn: false, error: "No portal for this account yet." }, 401);
  const contact = (await getContact(env, pd.email)) || { email: pd.email, name: "", tags: [], fields: {} };
  const name = contact.name || "";
  const readonly = u.coach || pd.access === "readonly";
  const write = request.method === "POST";
  // Writes Brian's coach view and read-only accounts can still make.
  const ALWAYS = ["export", "delete-request", "profile", "message", "logout"];
  if (write && readonly && !ALWAYS.includes(route)) return bad(u.coach ? "Coach view is read-only." : "Your portal is read-only now. Join the Club to keep tracking.", 403);
  if (write && u.coach) return bad("Coach view is read-only.", 403);
  if (!u.coach) pd.lastActive = Date.now();
  const save = async () => { await putRecord(env, pd); };
  const notify = (subject, text) => { const p = emailBrian(env, subject, text).catch(() => null); waitUntil ? waitUntil(p) : null; return p; };
  const label = `${name || pd.email}`;

  if (route === "me") {
    if (!u.coach) await save();
    return json({ ok: true, ...(await state(env, pd, contact, u)) });
  }

  if (route === "profile") {
    if (d.name !== undefined && d.name.trim()) { contact.name = str(d.name.trim(), 80); }
    if (d.phone !== undefined) {
      const p = d.phone ? toE164(d.phone) : "";
      if (d.phone && !p) return bad("That mobile number doesn't look right.");
      if (p && p !== contact.phone) { await env.FILES.put("p:" + p, pd.email); if (contact.phone) await env.FILES.delete("p:" + contact.phone); contact.phone = p; }
    }
    if (d.reminders) pd.reminders = { on: !!d.reminders.on, hour: Math.min(21, Math.max(6, Number(d.reminders.hour) || 20)), channel: d.reminders.channel === "sms" ? "sms" : "email" };
    if (d.large !== undefined) pd.large = !!d.large;
    if (contact.created || contact.tags) await putContact(env, contact);
    await save();
    return json({ ok: true });
  }

  // A step's worksheet: save, or save and submit to Brian.
  if (route === "step") {
    const n = Number(d.n);
    if (!STEPS[n]) return bad("Unknown step.");
    const st = stepState(pd, n);
    if (st.status === "locked") return bad("That step isn't open yet.");
    const s = pd.steps[n] = pd.steps[n] || {};
    if (n === 1) {
      const data = d.data || {};
      s.data = {
        roles: (data.roles || []).slice(0, 8).map((r) => ({ role: str(r.role, 60), expects: str(r.expects, 600), tuesday: str(r.tuesday, 600), bad: str(r.bad, 400) })),
        sentence: str(data.sentence, 400), scripture: str(data.scripture, 200),
      };
    } else if (n === 2 || n === 3) {
      if (Array.isArray(d.commitments)) setCommitments(pd, d.commitments, "him");
    } else if (n === 4) {
      const data = d.data || {};
      s.data = { reviewTime: str(data.reviewTime, 60), partner: str(data.partner, 120), where: str(data.where, 200) };
    }
    if (d.submit) {
      if (n === 1 && !(s.data && s.data.sentence)) return bad("Write your sentence before you send it.");
      if ((n === 2 || n === 3) && !pd.commitments.length) return bad("Add at least one commitment first.");
      if (n === 3 && pd.commitments.some((c) => !c.floor || !c.time)) return bad("Each commitment needs a time and a bad-day version first.");
      s.status = "submitted"; s.submittedAt = Date.now(); delete s.note;
      notify(`${label} sent you Step ${n} to approve`, `**${label}** finished Step ${n}, ${STEPS[n]}, and sent it to you.\n\n[[Open his page|${SITE}/admin/#man/${encodeURIComponent(pd.email)}]]`);
    } else if (!s.status || s.status === "locked") s.status = "open";
    const flagged = await safetyCheck(env, waitUntil, pd, name, JSON.stringify(s.data || "") + " " + pd.commitments.map((c) => c.what + " " + c.breaks).join(" "), `Step ${n}`);
    await save();
    return json({ ok: true, status: s.status, crisis: flagged ? CRISIS : null });
  }

  // Edit commitments any time (every version is kept).
  if (route === "commitments") {
    if (!Array.isArray(d.list)) return bad("Nothing to save.");
    const changed = setCommitments(pd, d.list, "him");
    await save();
    return json({ ok: true, changed, commitments: pd.commitments });
  }

  // Daily tap: k kept, f floor, m missed, "" clear. Today and two days back.
  if (route === "mark") {
    const date = str(d.date, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !canMark(date)) return bad("That day is locked. You can mark today and the two days before it.");
    const c = pd.commitments.find((x) => x.id === d.id);
    if (!c) return bad("Unknown commitment.");
    pd.marks[date] = pd.marks[date] || {};
    if (["k", "f", "m"].includes(d.v)) pd.marks[date][c.id] = d.v; else delete pd.marks[date][c.id];
    for (const k of Object.keys(pd.marks)) if (k < addDays(today(), -120)) delete pd.marks[k];
    await save();
    return json({ ok: true, week: weekScore(pd, weekOf(date)) });
  }

  if (route === "hard") {
    const w = weekOf(today());
    if (d.on) {
      pd.hard[w] = { at: Date.now(), note: str(d.note, 600) };
      notify(`${label} is in a hard week`, `**${label}** tapped "I'm in a hard week" in his portal. His commitments are on their floor versions until Sunday.${d.note ? `\n\nHe wrote: "${str(d.note, 600)}"` : ""}\n\nA short text or call this week would mean a lot.`);
      await safetyCheck(env, waitUntil, pd, name, d.note, "hard week");
    } else delete pd.hard[w];
    await save();
    return json({ ok: true });
  }

  // Sunday review: the number plus four questions.
  if (route === "review") {
    const w = reviewWeek();
    const sc = weekScore(pd, w);
    let k = Number(d.k), t = Number(d.t);
    if (!(t > 0)) { k = sc.k; t = sc.t; }
    if (!(t > 0) || !(k >= 0) || k > t) return bad("Enter your number: kept out of the total.");
    pd.reviews[w] = { k, t, miss: str(d.miss, 400), change: str(d.change, 400), grace: str(d.grace, 400), reported: str(d.reported, 120), paper: !!d.paper, at: Date.now() };
    contact.ledger = contact.ledger || {};
    contact.ledger[w] = { k, t, at: Date.now(), via: d.paper ? "portal-paper" : "portal", miss: str(d.miss, 200), change: str(d.change, 200) };
    addEvent(contact, "ledger", `${k} of ${t} (portal review)`);
    await putContact(env, contact);
    const flagged = await safetyCheck(env, waitUntil, pd, name, `${d.miss} ${d.change} ${d.grace}`, "Sunday review");
    await save();
    return json({ ok: true, week: w, streak: streak(pd, contact.ledger), crisis: flagged ? CRISIS : null });
  }

  // Before Thursday's call: what he wants help with.
  if (route === "callprep") {
    const s = nextSession();
    if (!s) return bad("There are no more sessions on the calendar.");
    pd.callPrep[s] = { text: str(d.text, 1200), at: Date.now() };
    const flagged = await safetyCheck(env, waitUntil, pd, name, d.text, "call prep");
    await save();
    return json({ ok: true, session: s, crisis: flagged ? CRISIS : null });
  }

  // One tap "I'm here" during the call.
  if (route === "checkin") {
    const s = inCheckInWindow();
    if (!s) return bad("Check-in opens during the Thursday session.");
    pd.attendance[s] = Date.now();
    contact.cohort = contact.cohort || {};
    contact.cohort.att = { ...(contact.cohort.att || {}), [s]: true };
    await putContact(env, contact);
    await save();
    return json({ ok: true, session: s });
  }

  // Lesson action checkbox and reflection.
  if (route === "reflect") {
    const id = str(d.id, 20);
    if (!id) return bad("Unknown lesson.");
    pd.reflections[id] = { text: str(d.text, 3000), done: !!d.done, at: Date.now() };
    const flagged = await safetyCheck(env, waitUntil, pd, name, d.text, "lesson reflection");
    await save();
    return json({ ok: true, crisis: flagged ? CRISIS : null });
  }

  // "Next step" assignments from Brian: he marks them done.
  if (route === "next-done") {
    const n = pd.next.find((x) => x.id === d.id);
    if (!n) return bad("Not found.");
    n.done = d.done === false ? 0 : Date.now();
    if (n.done) notify(`${label} finished a next step`, `**${label}** marked this done: "${n.text}"`);
    await save();
    return json({ ok: true });
  }

  // Messages and prayer requests to Brian.
  if (route === "messages" && request.method === "GET") return json({ ok: true, messages: await thread(env, pd.email) });
  if (route === "message") {
    if (u.coach) return bad("Coach view is read-only.", 403);
    const text = str(d.text, 3000).trim();
    if (!text) return bad("Write something first.");
    const type = d.type === "prayer" ? "prayer" : "message";
    const m = await addMessage(env, pd.email, "him", type, text);
    pd.unreadBrian = (pd.unreadBrian || 0) + 1;
    const flagged = await safetyCheck(env, waitUntil, pd, name, text, type === "prayer" ? "prayer request" : "message");
    if (!flagged) notify(type === "prayer" ? `Prayer request from ${label}` : `Message from ${label}`, `**${label}** wrote in his portal:\n\n"${text}"\n\n[[Reply in the dashboard|${SITE}/admin/#man/${encodeURIComponent(pd.email)}]]`);
    await env.FILES.put("unread:portal", "1");
    await save();
    return json({ ok: true, message: m, crisis: flagged ? CRISIS : null });
  }

  // A photo of his paper Ledger.
  if (route === "upload" && request.method === "POST") {
    let form;
    try { form = await request.formData(); } catch (e) { return bad("Choose a photo first."); }
    const f = form.get("photo");
    if (!f || typeof f === "string") return bad("Choose a photo first.");
    if (!/^image\//.test(f.type || "")) return bad("That file isn't a photo.");
    if (f.size > 6 * 1024 * 1024) return bad("That photo is too large (6 MB at most).");
    const id = Date.now().toString(36) + Math.random().toString(36).slice(2, 5);
    await env.FILES.put(`up:${pd.email}:${id}`, await f.arrayBuffer(), { metadata: { type: f.type, size: f.size } });
    pd.uploads.unshift({ id, week: reviewWeek(), at: Date.now(), note: str(form.get("note"), 300) });
    if (pd.uploads.length > 40) { const old = pd.uploads.pop(); await env.FILES.delete(`up:${pd.email}:${old.id}`); }
    notify(`${label} uploaded his paper Ledger`, `**${label}** uploaded a photo of his paper Ledger.\n\n[[See it|${SITE}/admin/#man/${encodeURIComponent(pd.email)}]]`);
    await save();
    return json({ ok: true, id });
  }
  if (route.startsWith("upload/")) {
    const id = route.slice(7).replace(/[^a-z0-9]/g, "");
    const v = await env.FILES.getWithMetadata(`up:${pd.email}:${id}`, "arrayBuffer");
    if (!v || !v.value) return new Response("Not found", { status: 404 });
    return new Response(v.value, { headers: { "content-type": (v.metadata && v.metadata.type) || "image/jpeg", "cache-control": "private, max-age=3600" } });
  }

  if (route === "share") {
    await setShare(env, pd, !!d.on);
    await save();
    return json({ ok: true, on: pd.share.on, url: pd.share.on ? `${SITE}/share/${pd.share.token}` : "" });
  }

  // Everything we hold about him, as a file.
  if (route === "export") {
    const out = { exported: new Date().toISOString(), contact: { name: contact.name, email: contact.email, phone: contact.phone || "", tags: contact.tags, ledger: contact.ledger || {} }, portal: forMan(pd), messages: await thread(env, pd.email) };
    return new Response(JSON.stringify(out, null, 2), { headers: { "content-type": "application/json", "content-disposition": `attachment; filename="be-the-man-portal-${today()}.json"`, "cache-control": "no-store" } });
  }
  if (route === "delete-request") {
    if (u.coach) return bad("Coach view is read-only.", 403);
    pd.deleteRequested = Date.now();
    await save();
    await notify(`${label} asked to delete his data`, `**${label}** asked for his portal data to be deleted.${d.reason ? `\n\nHe wrote: "${str(d.reason, 600)}"` : ""}\n\nOpen his page in the dashboard and use "Delete portal" to remove it.\n\n[[Open his page|${SITE}/admin/#man/${encodeURIComponent(pd.email)}]]`);
    return json({ ok: true, message: "Brian has your request. Your data will be deleted within 7 days, and you'll get an email when it's done." });
  }

  return bad("Unknown route.", 404);
}

// Everything the portal screens need in one answer.
async function state(env, pd, contact, u) {
  const t = today();
  const lib = await getLibrary(env);
  const sessions = await getSessions(env);
  const ledger = contact.ledger || {};
  const thisWeek = weekOf(t);
  const rw = reviewWeek();
  const days = [addDays(t, -2), addDays(t, -1), t].map((date) => ({
    date, dow: dow(date),
    items: pd.commitments.filter((c) => scheduledOn(c, date)).map((c) => ({ id: c.id, v: (pd.marks[date] || {})[c.id] || "" })),
  }));
  const weeks = [];
  for (let i = 7; i >= 0; i--) {
    const w = addDays(thisWeek, -7 * i);
    const s = weekScore(pd, w), r = pd.reviews[w], L = ledger[w];
    weeks.push({ week: w, k: r ? r.k : s.t ? s.k : L ? L.k : null, t: r ? r.t : s.t ? s.t : L ? L.t : null, reviewed: !!(r || L) });
  }
  // Anonymous group average for last week (no names).
  let group = null;
  if (pd.role === "cohort" || pd.role === "admin") {
    const lw = addDays(thisWeek, -7);
    const all = await allRecords(env);
    const pcts = all.filter((x) => x.r === "cohort" && x.wk).map((x) => { const [k, tt] = x.wk.split("/").map(Number); return tt ? k / tt : null; }).filter((x) => x != null);
    if (pcts.length >= 3) group = { week: lw, pct: Math.round((100 * pcts.reduce((a, b) => a + b, 0)) / pcts.length), men: pcts.length };
  }
  // Partner: only when both are paired with each other.
  let partner = null;
  if (pd.partner) {
    const p = await getRecord(env, pd.partner);
    if (p && p.partner === pd.email) {
      const pc = await getContact(env, p.email);
      const pw = [];
      for (let i = 3; i >= 0; i--) {
        const w = addDays(rw, -7 * i);
        const r = p.reviews[w], s = weekScore(p, w), L = pc && pc.ledger ? pc.ledger[w] : null;
        pw.push({ week: w, k: r ? r.k : L ? L.k : s.t ? s.k : null, t: r ? r.t : L ? L.t : s.t ? s.t : null, review: r ? { miss: r.miss, change: r.change, grace: r.grace } : null });
      }
      partner = { name: (pc && pc.name) || p.email.split("@")[0], email: p.email, phone: (pc && pc.phone) || "", weeks: pw };
    }
  }
  const lessons = lib.lessons.map((l) => {
    const open = lessonOpen(pd, l.week);
    const date = COHORT_DATES[l.week - 1];
    const sess = sessions[date] || {};
    const missed = pd.role === "cohort" && date < t && !pd.attendance[date];
    return { id: l.id, week: l.week, step: l.step, title: l.title, scripture: l.scripture, open, date,
      ...(open ? { body: l.body, video: l.video, action: l.action, reflection: l.reflection, pdf: l.pdf || "", recording: sess.video || "", catchup: missed ? sess.note || "" : "", missed } : {}),
      mine: pd.reflections[l.id] || null };
  });
  const msgs = await thread(env, pd.email);
  const next = nextSession(t);
  return {
    me: { email: pd.email, name: contact.name || "", first: (contact.name || "").split(/\s+/)[0] || "", phone: contact.phone || "", role: pd.role, access: pd.access, large: !!pd.large },
    coach: !!u.coach, admin: !!u.admin, today: t, thisWeek, reviewWeek: rw, isSunday: dow(t) === 0,
    record: forMan(pd), steps: stepStates(pd), stepNames: STEPS, scorecard: scorecardOn(pd), days,
    score: weekScore(pd, thisWeek), lastScore: weekScore(pd, addDays(thisWeek, -7)), weeks, streak: streak(pd, ledger),
    hardWeek: !!pd.hard[thisWeek], review: pd.reviews[rw] || null, group, partner, lessons, materials: lib.materials, examples: lib.examples,
    sessions: COHORT_DATES, nextSession: next, callPrep: next ? pd.callPrep[next] || null : null, checkIn: inCheckInWindow(),
    meet: pd.role === "cohort" || pd.role === "admin" ? MEET : "", messages: msgs, calendar: await calendarUrl(env, pd.email),
    share: pd.share.on ? `${SITE}/share/${pd.share.token}` : "", crisis: "Thinking about harming yourself? Call or text 988, any time. In danger right now? Call 911.",
    weekStep: WEEK_STEP,
  };
}
