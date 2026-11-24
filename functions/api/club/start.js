// POST /api/club/start  {s: <checkout session id>}
// Called by /the-club/welcome/ right after checkout. Confirms the new Club
// subscription with Stripe, signs the member in and tags him in Kit
// ("Club member", plus "Inner Circle" for Inner Circle members).

import { CLUB } from "../../_catalog.js";
import { stripe, clubSubscription, sessionCookie, json } from "../../_club.js";
import { subscribe, notifyBrian, TAGS, firstName } from "../../_mail.js";
import { ensureRecord, sendWelcome, getRecord, putRecord } from "../../_portal.js";

export async function onRequestPost(context) {
  const { request, env } = context;
  if (!env.STRIPE_KEY) return json({ ok: false, error: "not configured" }, 503);
  let data = {};
  try { data = await request.json(); } catch (e) {}
  if (!/^cs_(live|test)_[A-Za-z0-9]+$/.test(data.s || "")) return json({ ok: false }, 400);
  const s = await stripe(env, `/checkout/sessions/${data.s}`);
  if (!s || !CLUB.plinks.includes(s.payment_link) || s.status !== "complete" || !s.customer) {
    return json({ ok: false, error: "We couldn't confirm that membership." }, 403);
  }
  const sub = await clubSubscription(env, s.customer);
  if (!sub) return json({ ok: false, error: "We couldn't confirm that membership." }, 403);
  const email = (s.customer_details || {}).email;
  const member = { email, customer: s.customer, start: sub.start, yearly: sub.yearly, ic: sub.ic };

  if (email) {
    const tags = sub.ic ? [TAGS.club, TAGS.innerCircle] : [TAGS.club];
    try { await subscribe(env, email, { firstName: firstName((s.customer_details || {}).name), tags }); } catch (e) {}
    // Portal: a new account, or full access again for a graduate who joins.
    try {
      const had = await getRecord(env, email.toLowerCase());
      const { pd, created } = await ensureRecord(env, email, { role: "club", name: (s.customer_details || {}).name });
      if (!created && pd.access === "readonly") { pd.access = "full"; await putRecord(env, pd); }
      if (created || (had && had.role === "step1")) await sendWelcome(env, email.toLowerCase(), "club");
    } catch (e) {}
    // Alert Brian once per new membership (this page can be reloaded).
    const seen = env.FILES ? await env.FILES.get(`joined:${s.id}`) : null;
    if (!seen) {
      if (env.FILES) await env.FILES.put(`joined:${s.id}`, "1", { expirationTtl: 400 * 86400 });
      const plan = sub.ic ? "Inner Circle" : sub.yearly ? "Club, yearly ($149)" : "Club, monthly ($19)";
      notifyBrian(env, context, {
        subject: `New member: ${plan}`,
        replyTo: email,
        rows: [["Joined", plan], ["Name", (s.customer_details || {}).name], ["Email", email]],
      });
    }
  }
  return json({ ok: true, redirect: "/members/" }, 200, { "set-cookie": await sessionCookie(env, member) });
}
