// POST /api/admin-login {email}: emails a dashboard sign-in link to an admin.
// The reply is the same for any address.
import { admins } from "../_admin.js";
import { sign } from "../_club.js";
import { sendEmail } from "../_mail.js";
import { emailHtml, bodyHtml } from "../_list.js";

const SENT = { ok: true, message: "If that address can use the dashboard, a sign-in link is on its way. It works for 30 minutes." };
const json = (b, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json", "cache-control": "no-store" } });

export async function onRequestPost({ request, env }) {
  let d = {};
  try { d = await request.json(); } catch (e) {}
  const email = String(d.email || "").trim().toLowerCase();
  if (!admins(env).includes(email)) return json(SENT);
  const t = await sign(env, { p: "admin-login", e: email, x: Math.floor(Date.now() / 1000) + 1800 });
  const url = `https://bethemansystem.com/api/admin-verify?t=${t}`;
  await sendEmail(env, { to: email, subject: "Your Be The Man dashboard sign-in link",
    html: emailHtml(bodyHtml(`Here is your sign-in link for the Be The Man dashboard. It works for 30 minutes.\n\n[[Open the dashboard|${url}]]\n\nIf you didn't ask for this, ignore it.`, { name: "Brian" }), null) });
  return json(SENT);
}
