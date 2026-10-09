// Locks product guides under /get/<slug>/guide/ (the ministry kit leader guide)
// to buyers. /api/purchase sets the cookie when the buyer's thank-you page
// confirms the purchase with Stripe; the link in the download email does the same.

import { OFFERS } from "../_catalog.js";
import { unsign } from "../_club.js";

export async function onRequest(context) {
  const { request, env, next } = context;
  const url = new URL(request.url);
  const m = url.pathname.match(/^\/get\/([^/]+)\/guide(\/|$)/);
  if (!m) return next();
  const key = Object.keys(OFFERS).find((k) => OFFERS[k].slug === m[1] && OFFERS[k].guide);
  if (!key) return next();
  const c = (request.headers.get("cookie") || "").match(new RegExp(`(?:^|;\\s*)btm_buy_${key}=([^;]+)`));
  const data = c && (await unsign(env, c[1]));
  if (!data || data.o !== key) {
    return Response.redirect(new URL(`/get/${m[1]}/?guide=locked`, url).toString(), 302);
  }
  const res = await next();
  const out = new Response(res.body, res);
  out.headers.set("cache-control", "private, no-store");
  out.headers.set("x-robots-tag", "noindex");
  return out;
}
