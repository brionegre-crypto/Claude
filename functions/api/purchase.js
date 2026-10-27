// Cloudflare Pages Function: POST /api/purchase  {o: <offer>, s: <checkout session>}
// Called by the thank-you page right after a Stripe purchase. Confirms the
// purchase with Stripe, emails the buyer their download page link (Resend),
// and adds them to Kit with the tag "Customer" plus the product's own tag
// (workshop, 6-week group, ministry kit).
// Needs STRIPE_KEY; the email needs RESEND_API_KEY and the tags KIT_API_KEY.
// Sends at most one email per purchase, however many times the page is reloaded.

import { OFFERS } from "../_catalog.js";
import { paidSession, boughtPrices } from "./download.js";
import { sign } from "../_club.js";
import { subscribe, sendEmail, tagByName, notifyBrian, TAGS, firstName } from "../_mail.js";
import { nextSession } from "../_workshop.js";
import { downloadsEmail } from "../_emails.js";

const reply = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

export async function onRequestPost(context) {
  const { request, env } = context;
  let data = {};
  try { data = await request.json(); } catch (e) {}
  const offer = OFFERS[data.o];
  if (!offer || !offer.files.length) return reply({ ok: false, error: "unknown product" }, 400);
  if (!env.STRIPE_KEY) return reply({ ok: false, error: "not configured" }, 503);

  const session = await paidSession(env, data.s, offer.plink);
  if (!session) return reply({ ok: false, error: "purchase not confirmed" }, 403);

  // Add-ons bought at checkout, and a cookie that opens a product's online guide (ministry kit).
  const prices = boughtPrices(session);
  const addons = (offer.addons || []).map((a) => a.price).filter((p) => prices.includes(p));
  const headers = {};
  if (offer.guide) {
    const token = await sign(env, { o: data.o, x: Math.floor(Date.now() / 1000) + 400 * 86400 });
    headers["set-cookie"] = `btm_buy_${data.o.replace(/[^a-z0-9-]/g, "")}=${token}; Path=/get/; Max-Age=${400 * 86400}; HttpOnly; Secure; SameSite=Lax`;
  }
  // Workshop tickets are for the next session after the time of purchase.
  const ws = data.o === "workshop" ? nextSession((session.created || Date.now() / 1000) * 1000) : null;
  const when = ws ? `${ws.label}, 7:00 PM Central` : undefined;
  const replyWith = (body, status = 200) =>
    new Response(JSON.stringify({ addons, when, ...body }), { status, headers: { "content-type": "application/json", "cache-control": "no-store", ...headers } });

  const email = (session.customer_details || {}).email;
  if (!email) return reply({ ok: false, error: "no email on purchase" }, 422);

  // Already handled this purchase? Then do nothing.
  const doneKey = `order:${session.id}`;
  if (env.FILES && (await env.FILES.get(doneKey))) return replyWith({ ok: true, emailed: true });

  const name = firstName((session.customer_details || {}).name);
  const tags = offer.tag ? [TAGS.customer, offer.tag] : [TAGS.customer];
  try { await subscribe(env, email, { firstName: name, tags }); } catch (e) {}
  if (ws) { try { await tagByName(env, email, ws.tag); } catch (e) {} }

  const emailed = await sendEmail(env, {
    to: email,
    subject: `Your downloads: ${offer.name}`,
    html: downloadsEmail({
      product_name: ws ? `${offer.name}, ${when}` : offer.name,
      download_url: `https://bethemansystem.com/get/${offer.slug}/?session_id=${session.id}`,
    }),
  });
  if (emailed && env.FILES) await env.FILES.put(doneKey, "1", { expirationTtl: 400 * 86400 });
  // Alert Brian once per purchase (the done key above stops repeats on reload).
  if (emailed || !env.FILES) {
    const total = typeof session.amount_total === "number" ? `$${(session.amount_total / 100).toFixed(2)}` : undefined;
    notifyBrian(env, context, {
      subject: `New purchase: ${offer.name}${total ? ` (${total})` : ""}`,
      replyTo: email,
      rows: [["Bought", offer.name], ["Total paid", total], ["Add-on", (offer.addons || []).filter((x) => addons.includes(x.price)).map((x) => x.label).join(", ")],
        ["Workshop session", when], ["Name", (session.customer_details || {}).name], ["Email", email]],
    });
  }
  return replyWith({ ok: true, emailed });
}
