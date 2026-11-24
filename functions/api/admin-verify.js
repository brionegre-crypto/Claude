// GET /api/admin-verify?t=<token>: the link in the sign-in email.
import { unsign } from "../_club.js";
import { admins, adminCookie } from "../_admin.js";

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const t = await unsign(env, url.searchParams.get("t"));
  if (!t || t.p !== "admin-login" || !admins(env).includes(t.e)) return Response.redirect(new URL("/admin-login/?expired=1", url).toString(), 302);
  return new Response(null, { status: 302, headers: { location: new URL("/admin/", url).toString(), "set-cookie": await adminCookie(env, t.e), "cache-control": "no-store" } });
}
