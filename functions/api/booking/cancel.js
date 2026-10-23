// Cloudflare Pages Function: GET /api/booking/cancel?t=<time>&k=<cancel key>
// The cancel link in a free-call confirmation. Frees the time and tells Brian.

import { label } from "../../_booking.js";
import { sendEmail, BRIAN } from "../../_mail.js";

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const t = url.searchParams.get("t") || "";
  const k = url.searchParams.get("k") || "";
  const back = (q) => Response.redirect(new URL("/call/?" + q, url).toString(), 303);
  if (!env.FILES || !k) return back("cancel=failed");
  const raw = await env.FILES.get("booking:" + t);
  if (!raw) return back("cancel=done");
  const b = JSON.parse(raw);
  if (b.cancel !== k) return back("cancel=failed");
  await env.FILES.delete("booking:" + t);
  await sendEmail(env, {
    to: BRIAN,
    replyTo: b.email,
    subject: `Free call cancelled: ${b.name}, ${label(t)}`,
    html: `<p>${String(b.name).replace(/[<>&]/g, "")} cancelled the free call on ${label(t)}. The time is open again. Delete it from your calendar.</p>`,
  });
  return back("cancel=done");
}
