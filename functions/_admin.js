// Dashboard sign-in: only brian@bethemansystem.com (or ADMIN_EMAILS, comma-separated)
// can sign in. A sign-in link is emailed (valid 30 minutes); the session cookie
// lasts 30 days.

import { sign, unsign } from "./_club.js";

export const ADMIN_COOKIE = "btm_admin";
export const admins = (env) => (env.ADMIN_EMAILS || "brian@bethemansystem.com").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);

export async function adminFrom(request, env) {
  const m = (request.headers.get("cookie") || "").match(new RegExp(`(?:^|;\\s*)${ADMIN_COOKIE}=([^;]+)`));
  const d = m ? await unsign(env, m[1]) : null;
  return d && d.p === "admin" && admins(env).includes(d.e) ? d.e : null;
}

export async function adminCookie(env, email) {
  const t = await sign(env, { p: "admin", e: email, x: Math.floor(Date.now() / 1000) + 30 * 86400 });
  return `${ADMIN_COOKIE}=${t}; Path=/; Max-Age=${30 * 86400}; HttpOnly; Secure; SameSite=Lax`;
}
