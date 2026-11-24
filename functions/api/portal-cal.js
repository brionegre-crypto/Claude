// GET /api/portal-cal?t=<token>: a man's commitments as a calendar he can subscribe to.
import { readCalToken, getRecord, calendarFile } from "../_portal.js";
import { getContact } from "../_list.js";

export async function onRequestGet({ request, env }) {
  const email = await readCalToken(env, new URL(request.url).searchParams.get("t"));
  const pd = email ? await getRecord(env, email) : null;
  if (!pd) return new Response("This calendar link isn't valid.", { status: 404 });
  const c = await getContact(env, email);
  const first = c && c.name ? c.name.split(/\s+/)[0] : "";
  return new Response(calendarFile(pd, first), { headers: { "content-type": "text/calendar; charset=utf-8", "content-disposition": 'inline; filename="be-the-man.ics"', "cache-control": "no-store" } });
}
