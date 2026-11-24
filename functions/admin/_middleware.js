// Guards the dashboard pages under /admin/.
import { adminFrom } from "../_admin.js";

export async function onRequest(context) {
  const { request, env, next } = context;
  if (!(await adminFrom(request, env))) return Response.redirect(new URL("/admin-login/", request.url).toString(), 302);
  const res = await next();
  const out = new Response(res.body, res);
  out.headers.set("cache-control", "private, no-store");
  out.headers.set("x-robots-tag", "noindex");
  return out;
}
