// /ledger/?t=<token>: a man reports his weekly Ledger number from the link in his email.
import { page, escH, field } from "../_page.js";
import { readLedgerToken, recordLedger, ledgerWeek } from "../_extras.js";
import { getContact } from "../_list.js";

const label = (w) => new Date(w + "T12:00:00-06:00").toLocaleDateString("en-US", { month: "long", day: "numeric", timeZone: "America/Chicago" });

export async function onRequestGet({ request, env }) {
  const t = new URL(request.url).searchParams.get("t") || "";
  const email = await readLedgerToken(env, t);
  if (!email) return page("Link expired", "<h1>That link has expired.</h1><p class='lead'>Reply to Brian's last email with your number, like 13 of 15.</p>");
  const c = await getContact(env, email);
  const week = ledgerWeek();
  const have = c && c.ledger && c.ledger[week];
  return page("Your Ledger", `<h1>Your Ledger, <span class="grad">week of ${escH(label(week))}.</span></h1>
<p class="lead">Mark each commitment kept, floor or missed. A floor day counts as kept. Then add it up.</p>
<form method="post" class="tile lp-card" style="display:grid;gap:12px">
<input type="hidden" name="t" value="${escH(t)}">
<div style="display:grid;grid-template-columns:1fr auto 1fr;gap:10px;align-items:center"><input name="k" type="number" min="0" max="200" required ${field} placeholder="Kept" value="${have ? have.k : ""}" aria-label="Kept"><span>of</span><input name="tt" type="number" min="1" max="200" required ${field} placeholder="Total" value="${have ? have.t : ""}" aria-label="Total"></div>
<input name="miss" ${field} placeholder="The one miss that keeps coming back (optional)" value="${have && have.miss ? escH(have.miss) : ""}">
<input name="change" ${field} placeholder="One change for Monday (optional)" value="${have && have.change ? escH(have.change) : ""}">
<button class="btn btn-primary btn-lg btn-block" type="submit">${have ? "Update my number" : "Report my number"}</button></form>
<p class="fine center">"One who is faithful in a very little is also faithful in much" (Luke 16:10).</p>`);
}

export async function onRequestPost({ request, env }) {
  const f = await request.formData();
  const email = await readLedgerToken(env, f.get("t"));
  const c = email ? await getContact(env, email) : null;
  const k = Number(f.get("k")), t = Number(f.get("tt"));
  if (!c || !(t > 0) || !(k >= 0) || k > t || t > 200) return page("Check the numbers", "<h1>Check the numbers.</h1><p class='lead'>Kept can't be more than the total. Go back and try again.</p>");
  await recordLedger(env, c, { k, t, miss: f.get("miss"), change: f.get("change") }, "form");
  return page("Got it", `<h1>Got it: <span class="grad">${k} of ${t}.</span></h1><p class="lead">Four out of seven is four out of seven. Take grace for the misses, make one change for Monday, and reset.</p><div class="actions" style="justify-content:center"><a class="btn btn-ghost" href="/downloads/the-ledger-weekly-scorecard.pdf">Print a blank Ledger</a></div>`);
}
