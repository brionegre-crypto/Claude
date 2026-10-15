// POST /api/club/start  {s: <checkout session id>}
// Called by /the-club/welcome/ right after checkout. Confirms the new Club
// subscription with Stripe, signs the member in and tags him in Kit
// ("Club member", plus "Inner Circle" for Inner Circle members).

import { CLUB } from "../../_catalog.js";
import { stripe, clubSubscription, sessionCookie, json } from "../../_club.js";
import { subscribe, TAGS, firstName } from "../../_mail.js";

export async function onRequestPost({ request, env }) {
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
  }
  return json({ ok: true, redirect: "/members/" }, 200, { "set-cookie": await sessionCookie(env, member) });
}
