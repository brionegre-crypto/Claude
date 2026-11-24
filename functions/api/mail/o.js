// GET /api/mail/o?t=<token>: the 1x1 open pixel in list emails.
// (Apple Mail and some others load images automatically, so opens run high.)
import { readToken, recordOpen } from "../../_list.js";

const GIF = Uint8Array.from(atob("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"), (c) => c.charCodeAt(0));

export async function onRequestGet({ request, env, waitUntil }) {
  const t = await readToken(env, new URL(request.url).searchParams.get("t"));
  if (t && env.FILES) waitUntil(recordOpen(env, t).catch(() => null));
  return new Response(GIF, { headers: { "content-type": "image/gif", "cache-control": "no-store, max-age=0" } });
}
