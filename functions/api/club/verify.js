// GET /api/club/verify?t=<token>  (the link in the sign-in email)

import { unsign, clubSubscription, sessionCookie } from "../../_club.js";

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const t = await unsign(env, url.searchParams.get("t"));
  const fail = Response.redirect(new URL("/club-login/?expired=1", url).toString(), 302);
  if (!t || t.p !== "login") return fail;
  const sub = await clubSubscription(env, t.c);
  if (!sub) return Response.redirect(new URL("/club-login/?ended=1", url).toString(), 302);
  const next = (url.searchParams.get("next") || "").startsWith("/members/") ? url.searchParams.get("next") : "/members/";
  const cookie = await sessionCookie(env, { email: t.e, customer: t.c, start: sub.start, yearly: sub.yearly });
  return new Response(null, { status: 302, headers: { location: new URL(next, url).toString(), "set-cookie": cookie, "cache-control": "no-store" } });
}
