// GET /share/<token>: a read-only view of a man's weekly numbers that he chose to share.
// It shows his sentence, his commitments and his weekly numbers. Never his notes, messages or answers.
import { getRecord, weekScore, weekOf, addDays, today, streak } from "../_portal.js";
import { getContact } from "../_list.js";
import { page, escH } from "../_page.js";

export async function onRequestGet({ params, env }) {
  const token = String(params.token || "").replace(/[^a-z0-9]/g, "");
  const email = token ? await env.FILES.get("sh:" + token) : null;
  const pd = email ? await getRecord(env, email) : null;
  if (!pd || !pd.share || !pd.share.on || pd.share.token !== token) return page("Not shared", `<h1>This link isn't shared <span class="grad">right now.</span></h1><p class="lead">The man who sent it may have turned sharing off.</p>`);
  const c = (await getContact(env, email)) || {};
  const first = c.name ? c.name.split(/\s+/)[0] : "This man";
  const ledger = c.ledger || {};
  const rows = [];
  let w = addDays(weekOf(today()), -7);
  for (let i = 0; i < 8; i++) {
    const r = pd.reviews[w], s = weekScore(pd, w), L = ledger[w];
    const k = r ? r.k : L ? L.k : s.t ? s.k : null, t = r ? r.t : L ? L.t : s.t ? s.t : null;
    if (t) rows.push(`<tr><td>Week ending ${escH(new Date(w + "T12:00:00Z").toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" }))}</td><td><strong>${k} of ${t}</strong></td></tr>`);
    w = addDays(w, -7);
  }
  const sentence = pd.steps[1] && pd.steps[1].data ? pd.steps[1].data.sentence : "";
  const commits = pd.commitments.filter((x) => x.active !== false).map((x) => `<li>${escH(x.what)}</li>`).join("");
  return page(`${first}'s Ledger`, `<h1>${escH(first)}'s <span class="grad">Ledger.</span></h1>
${sentence ? `<p class="lead">"${escH(sentence)}"</p>` : ""}
<div class="tile lp-card" style="text-align:left">
${commits ? `<h2 style="font-size:20px">His commitments</h2><ul>${commits}</ul>` : ""}
<h2 style="font-size:20px">Weekly numbers</h2>
${rows.length ? `<table style="width:100%;border-collapse:collapse">${rows.join("")}</table>` : `<p class="muted">No weeks counted yet.</p>`}
<p class="muted">Weeks reported in a row: ${streak(pd, ledger)}</p>
</div>
<p class="muted center">Shared from his Be The Man portal. Read-only.</p>`);
}
