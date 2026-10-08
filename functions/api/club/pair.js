// POST /api/club/pair: a signed-in member opts in (or out) of monthly
// accountability pairs. Opt-ins go to the MailerLite group
// "Accountability pairs"; Brian pairs that list on the 1st of each month.

import { CLUB } from "../../_catalog.js";
import { currentMember, mailerlite, json } from "../../_club.js";

export async function onRequestPost({ request, env }) {
  const { member } = await currentMember(request, env);
  if (!member) return json({ ok: false, error: "Please sign in again." }, 401);
  if (!env.MAILERLITE_API_KEY) return json({ ok: false, error: "Email brian@bethemansystem.com to be paired." }, 503);
  let data = {};
  try { data = await request.json(); } catch (e) {}
  const ml = mailerlite(env);
  if (data.stop) {
    const found = await ml(`/subscribers/${encodeURIComponent(member.email)}`);
    if (found.ok) {
      const sub = (await found.json()).data || {};
      await ml(`/subscribers/${sub.id}/groups/${CLUB.mailerlite.pairs}`, { method: "DELETE" });
    }
    return json({ ok: true, paired: false });
  }
  const r = await ml("/subscribers", { method: "POST", body: JSON.stringify({ email: member.email, groups: [CLUB.mailerlite.pairs] }) });
  return r.ok ? json({ ok: true, paired: true }) : json({ ok: false, error: "That didn't go through. Please try again." }, 502);
}
