// Cloudflare Pages Function: POST /api/purchase  {o: <offer>, s: <checkout session>}
// Called by the thank-you page right after a Stripe purchase. Confirms the
// purchase with Stripe, then adds the buyer to the MailerLite group
// "Customers" with their download page link. Joining that group starts the
// "Your downloads" automation, which emails them the link.
// Needs the STRIPE_KEY and MAILERLITE_API_KEY secrets. Sends at most one
// email per purchase, however many times the page is reloaded.

import { OFFERS } from "../_catalog.js";
import { paidSession } from "./download.js";

const GROUP_ID = "200753890063288036"; // MailerLite group "Customers"
const ML = "https://connect.mailerlite.com/api";

const reply = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

export async function onRequestPost({ request, env }) {
  let data = {};
  try { data = await request.json(); } catch (e) {}
  const offer = OFFERS[data.o];
  if (!offer || !offer.files.length) return reply({ ok: false, error: "unknown product" }, 400);
  if (!env.STRIPE_KEY || !env.MAILERLITE_API_KEY) return reply({ ok: false, error: "not configured" }, 503);

  const session = await paidSession(env, data.s, offer.plink);
  if (!session) return reply({ ok: false, error: "purchase not confirmed" }, 403);
  const email = (session.customer_details || {}).email;
  if (!email) return reply({ ok: false, error: "no email on purchase" }, 422);

  const ml = (path, init = {}) =>
    fetch(ML + path, {
      ...init,
      headers: { authorization: `Bearer ${env.MAILERLITE_API_KEY}`, "content-type": "application/json", accept: "application/json", ...(init.headers || {}) },
    });

  // Already emailed for this purchase? Then do nothing.
  const found = await ml(`/subscribers/${encodeURIComponent(email)}`);
  if (found.ok) {
    const sub = (await found.json()).data || {};
    // Never resubscribe someone who unsubscribed; they still have the download page.
    if (["unsubscribed", "bounced", "junk"].includes(sub.status)) return reply({ ok: true, emailed: false });
    if ((sub.fields || {}).last_order === session.id) return reply({ ok: true, emailed: true });
    // A returning customer must leave and rejoin the group to start the automation again.
    if ((sub.groups || []).some((g) => g.id === GROUP_ID)) {
      await ml(`/subscribers/${sub.id}/groups/${GROUP_ID}`, { method: "DELETE" });
    }
  }

  const name = ((session.customer_details || {}).name || "").split(" ")[0];
  const fields = {
    download_url: `https://bethemansystem.com/get/${offer.slug}/?session_id=${session.id}`,
    product_name: offer.name,
    last_order: session.id,
  };
  if (name) fields.name = name;
  const body = { email, fields, groups: [GROUP_ID] };
  if (!found.ok) body.status = "active";
  const r = await ml("/subscribers", { method: "POST", body: JSON.stringify(body) });
  return r.ok ? reply({ ok: true, emailed: true }) : reply({ ok: false, error: "email service failed" }, 502);
}
