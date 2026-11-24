// /results/?t=<token>: a cohort man shares his result. Nothing is published unless he
// checks the permission box AND Brian approves it in the dashboard.
import { page, escH, field } from "../_page.js";
import { readResultsToken } from "../_extras.js";
import { getContact, putContact, addEvent } from "../_list.js";

export async function onRequestGet({ request, env }) {
  const t = new URL(request.url).searchParams.get("t") || "";
  const email = await readResultsToken(env, t);
  if (!email) return page("Link expired", "<h1>That link has expired.</h1><p class='lead'>Reply to Brian's email and he'll send a new one.</p>");
  const c = await getContact(env, email);
  const weeks = c && c.ledger ? Object.keys(c.ledger).sort() : [];
  const first = weeks.length ? c.ledger[weeks[0]] : null, last = weeks.length ? c.ledger[weeks[weeks.length - 1]] : null;
  const prev = await env.FILES.get("result:" + email, "json");
  return page("Your result", `<h1>Your six weeks, <span class="grad">in your words.</span></h1>
<p class="lead">This helps the next man decide. Only your first name is ever used, and only if you say yes below.</p>
<form method="post" class="tile lp-card" style="display:grid;gap:12px;text-align:left">
<input type="hidden" name="t" value="${escH(t)}">
<label style="display:grid;gap:6px">First name<input name="name" ${field} value="${escH((prev && prev.name) || (c && c.name ? c.name.split(/\s+/)[0] : ""))}" required></label>
<label style="display:grid;gap:6px">Your first week's number<input name="before" ${field} placeholder="for example 6 of 15" value="${escH((prev && prev.before) || (first ? first.k + " of " + first.t : ""))}"></label>
<label style="display:grid;gap:6px">Your latest number<input name="after" ${field} placeholder="for example 13 of 15" value="${escH((prev && prev.after) || (last ? last.k + " of " + last.t : ""))}"></label>
<label style="display:grid;gap:6px">What changed, in two sentences<textarea name="quote" maxlength="300" rows="4" ${field} required>${escH(prev ? prev.quote : "")}</textarea></label>
<label style="display:grid;grid-template-columns:auto 1fr;gap:10px;align-items:start;font-size:14px;color:var(--muted)"><input type="checkbox" name="permission" value="1" style="margin-top:4px"${prev && prev.permission ? " checked" : ""}><span>Be The Man may share my first name, my numbers and these words on its website and social media. I can ask for them to be removed at any time.</span></label>
<button class="btn btn-primary btn-lg btn-block" type="submit">Send</button></form>`);
}

export async function onRequestPost({ request, env }) {
  const f = await request.formData();
  const email = await readResultsToken(env, f.get("t"));
  if (!email) return page("Link expired", "<h1>That link has expired.</h1>");
  const s = (k, n) => String(f.get(k) || "").trim().slice(0, n);
  const prev = (await env.FILES.get("result:" + email, "json")) || {};
  const r = { email, name: s("name", 40), before: s("before", 30), after: s("after", 30), quote: s("quote", 300), permission: f.get("permission") === "1", at: Date.now(), approved: false, was: prev.approved ? "changed after approval" : undefined };
  if (!r.quote) return page("Add a few words", "<h1>Add a few words.</h1><p class='lead'>Go back and write what changed.</p>");
  await env.FILES.put("result:" + email, JSON.stringify(r));
  const c = await getContact(env, email);
  if (c) { addEvent(c, "shared result", r.permission ? "may publish" : "private"); await putContact(env, c); }
  return page("Thank you", `<h1>Thank you, <span class="grad">${escH(r.name || "brother")}.</span></h1><p class="lead">${r.permission ? "Brian reads every one before anything is shared." : "This stays private. Brian will read it."}</p>`);
}
