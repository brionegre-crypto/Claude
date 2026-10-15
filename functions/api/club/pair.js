// POST /api/club/pair: a signed-in member opts in (or out) of monthly
// accountability pairs. Opt-ins get the Kit tag "Accountability pair";
// Brian pairs that list on the 1st of each month.

import { currentMember, json } from "../../_club.js";
import { subscribe, untag, TAGS } from "../../_mail.js";

export async function onRequestPost({ request, env }) {
  const { member } = await currentMember(request, env);
  if (!member) return json({ ok: false, error: "Please sign in again." }, 401);
  if (!env.KIT_API_KEY) return json({ ok: false, error: "Email brian@bethemansystem.com to be paired." }, 503);
  let data = {};
  try { data = await request.json(); } catch (e) {}
  if (data.stop) {
    await untag(env, member.email, TAGS.pair);
    return json({ ok: true, paired: false });
  }
  const ok = await subscribe(env, member.email, { tags: [TAGS.pair] });
  return ok ? json({ ok: true, paired: true }) : json({ ok: false, error: "That didn't go through. Please try again." }, 502);
}
