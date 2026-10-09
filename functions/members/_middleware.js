// Guards everything under /members/: only signed-in Club members get through,
// and a monthly lesson opens only once that month's tools are unlocked.

import { CLUB } from "../_catalog.js";
import { currentMember, monthsOpen, clearCookie } from "../_club.js";

export async function onRequest(context) {
  const { request, env, next } = context;
  const url = new URL(request.url);
  const { member, setCookie, ended } = await currentMember(request, env);
  if (!member) {
    const to = new URL("/club-login/", url);
    to.searchParams.set(ended ? "ended" : "next", ended ? "1" : url.pathname);
    return new Response(null, { status: 302, headers: { location: to.toString(), "set-cookie": clearCookie } });
  }
  const m = url.pathname.match(/^\/members\/([^/]+)\/?/);
  if (m && m[1].startsWith("inner-circle") && !member.ic) {
    return Response.redirect(new URL("/members/?locked=inner-circle", url).toString(), 302);
  }
  const month = m && CLUB.lessons[m[1]];
  if (month && month > monthsOpen(member)) {
    return Response.redirect(new URL("/members/?locked=" + m[1], url).toString(), 302);
  }
  const res = await next();
  const out = new Response(res.body, res);
  out.headers.set("cache-control", "private, no-store");
  out.headers.set("x-robots-tag", "noindex");
  if (setCookie) out.headers.append("set-cookie", setCookie);
  return out;
}
