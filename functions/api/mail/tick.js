// POST /api/mail/tick  (header x-cron-secret: CRON_SECRET)
// Sends the series emails and broadcasts that are due. Called every hour by the
// GitHub Actions job .github/workflows/mail-tick.yml, and also nudged by sign-ups
// and by the dashboard, so mail keeps flowing even if the job is late.

import { tick } from "../../_list.js";

export async function onRequestPost({ request, env }) {
  const secret = request.headers.get("x-cron-secret") || "";
  if (!env.CRON_SECRET || secret !== env.CRON_SECRET) return new Response("forbidden", { status: 403 });
  const r = await tick(env);
  return new Response(JSON.stringify(r), { headers: { "content-type": "application/json" } });
}
