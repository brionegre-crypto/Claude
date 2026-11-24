// GET /api/cohort-status: whether the Founding Cohort checkout is open (seats left, not started).
// ?check=1 adds a short Stripe connection check (no key details, no customer data).
import { cohortStatus } from "../_extras.js";
import { OFFERS } from "../_catalog.js";

async function check(env) {
  if (!env.STRIPE_KEY) return { key: "missing" };
  const h = { authorization: `Bearer ${env.STRIPE_KEY}` };
  const out = { mode: env.STRIPE_KEY.includes("_live_") ? "live" : env.STRIPE_KEY.includes("_test_") ? "test" : "unknown", type: env.STRIPE_KEY.slice(0, 3) };
  const one = async (path) => { const r = await fetch("https://api.stripe.com/v1" + path, { headers: h }); const d = await r.json().catch(() => ({})); return { status: r.status, code: d.error ? d.error.code || d.error.type : undefined, data: d.data }; };
  const links = await one("/payment_links?limit=100");
  out.paymentLinks = links.status === 200 ? { count: links.data.length, hasCohort: links.data.some((l) => l.id === OFFERS.cohort.plink), hasOlder: links.data.some((l) => l.id === OFFERS.group.plink) } : { status: links.status, code: links.code };
  const s = await one("/checkout/sessions?limit=1");
  out.checkoutSessions = s.status === 200 ? "ok" : { status: s.status, code: s.code };
  const sub = await one("/subscriptions?limit=1");
  out.subscriptions = sub.status === 200 ? "ok" : { status: sub.status, code: sub.code };
  return out;
}

export async function onRequestGet({ env, request }) {
  let s = { open: true };
  try { s = await cohortStatus(env); } catch (e) {}
  if (new URL(request.url).searchParams.get("check")) { try { s.check = await check(env); } catch (e) { s.check = String(e); } }
  return new Response(JSON.stringify(s), { headers: { "content-type": "application/json", "cache-control": "no-store" } });
}
