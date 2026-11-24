// POST /api/mail/tick  (header x-cron-secret: CRON_SECRET)
// Sends the series emails and broadcasts that are due. Called every hour by the
// GitHub Actions job .github/workflows/mail-tick.yml, and also nudged by sign-ups
// and by the dashboard, so mail keeps flowing even if the job is late.

import { runAll } from "../../_extras.js";

export async function onRequestPost({ request, env }) {
  const secret = request.headers.get("x-cron-secret") || "";
  if (!env.CRON_SECRET) return new Response("CRON_SECRET is not set on the website (Cloudflare), or the site wasn't redeployed after adding it.", { status: 503 });
  if (!secret) return new Response("The request carried no secret (GitHub's CRON_SECRET is empty).", { status: 401 });
  if (secret !== env.CRON_SECRET) return new Response("The secret doesn't match: GitHub's CRON_SECRET and Cloudflare's CRON_SECRET are different.", { status: 403 });
  const r = await runAll(env);
  return new Response(JSON.stringify(r), { headers: { "content-type": "application/json" } });
}
