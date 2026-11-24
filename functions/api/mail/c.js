// GET /api/mail/c?t=<token>: a tracked link in a list email. Records the click
// (and starts any automation set to "clicked a link"), then goes to the link.
import { readToken, recordClick } from "../../_list.js";

export async function onRequestGet({ request, env, waitUntil }) {
  const t = await readToken(env, new URL(request.url).searchParams.get("t"));
  if (!t || t.p !== "click" || !/^https?:/i.test(t.u || "")) return Response.redirect("https://bethemansystem.com/", 302);
  if (env.FILES) waitUntil(recordClick(env, t).catch(() => null));
  return Response.redirect(t.u, 302);
}
