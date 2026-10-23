// Cloudflare Pages Function: /api/booking
// GET  -> the open free-call times (ISO, UTC) with their Central-time labels.
// POST {t, name, email, phone, note} -> books the time: saves it in the FILES KV
// namespace, emails Brian and the man a calendar invite (Resend), and tags the
// man "Call request" in Kit. A time can only be booked once.
// Needs the FILES binding and RESEND_API_KEY.

import { openTimes, label, icsFile } from "../_booking.js";
import { subscribe, sendEmail, TAGS, BRIAN, firstName } from "../_mail.js";

const FAIL_MSG = "We couldn't book that time just now. Please try again in a minute, or email brian@bethemansystem.com.";
const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
const clean = (v, n) => String(v || "").replace(/[\r\n\t]+/g, " ").trim().slice(0, n);
const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

export async function booked(env) {
  const out = new Set();
  let cursor;
  do {
    const page = await env.FILES.list({ prefix: "booking:", cursor });
    page.keys.forEach((k) => out.add(k.name.slice(8)));
    cursor = page.list_complete ? null : page.cursor;
  } while (cursor);
  return out;
}

export async function onRequestGet({ env }) {
  if (!env.FILES) return json({ ok: false, error: FAIL_MSG }, 503);
  const taken = await booked(env);
  return json({ ok: true, slots: openTimes().filter((t) => !taken.has(t)).map((t) => ({ t, label: label(t) })) });
}

const shell = (inner) =>
  `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;padding:0;background:#f4f2ee"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f2ee"><tr><td align="center" style="padding:32px 16px"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:16px"><tr><td style="padding:36px 32px;font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;color:#1d1d1f;font-size:17px;line-height:1.55">${inner}</td></tr></table><p style="font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:12px;color:#8e8e93;margin:18px 0 0">Be The Man · bethemansystem.com</p></td></tr></table></body></html>`;

export async function onRequestPost({ request, env }) {
  let data = {};
  try { data = await request.json(); } catch (e) {}
  if (data.company) return json({ ok: true, redirect: "/call/thanks/" }); // honeypot
  const t = String(data.t || "");
  const name = clean(data.name, 120);
  const email = clean(data.email, 200).toLowerCase();
  const phone = clean(data.phone, 40);
  const note = clean(data.note, 500);
  if (!name || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return json({ ok: false, error: "Please add your name and a valid email." }, 400);
  if (phone.replace(/\D/g, "").length < 7) return json({ ok: false, error: "Please add the phone number Brian should call." }, 400);
  if (!env.FILES || !env.RESEND_API_KEY) return json({ ok: false, error: FAIL_MSG }, 503);
  if (!openTimes().includes(t)) return json({ ok: false, error: "That time isn't available any more. Please pick another." }, 409);
  const key = "booking:" + t;
  if (await env.FILES.get(key)) return json({ ok: false, error: "Someone just booked that time. Please pick another." }, 409);

  const cancel = crypto.randomUUID();
  const when = label(t);
  // Kept until a month after the call.
  await env.FILES.put(key, JSON.stringify({ name, email, phone, note, cancel, at: new Date().toISOString() }), {
    expiration: Math.floor(Date.parse(t) / 1000) + 30 * 86400,
  });

  const origin = new URL(request.url).origin;
  const cancelUrl = `${origin}/api/booking/cancel?t=${encodeURIComponent(t)}&k=${cancel}`;
  const sentBrian = await sendEmail(env, {
    to: BRIAN,
    replyTo: email,
    subject: `Free call booked: ${name}, ${when}`,
    html: shell(`<p style="margin:0 0 6px;font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#b8730f">Free call booked</p><h1 style="margin:0 0 18px;font-size:24px;line-height:1.25">${esc(name)}</h1><p style="margin:0 0 6px"><strong>When:</strong> ${esc(when)}</p><p style="margin:0 0 6px"><strong>Call:</strong> <a href="tel:${esc(phone)}" style="color:#b8730f">${esc(phone)}</a></p><p style="margin:0 0 6px"><strong>Email:</strong> <a href="mailto:${esc(email)}" style="color:#b8730f">${esc(email)}</a></p><p style="margin:0 0 22px"><strong>On his mind:</strong> ${esc(note || "nothing given")}</p><p style="margin:0;font-size:14px;color:#6e6e73">Open the attached invite to add it to your calendar. Reply to this email to reach him.</p>`),
    attachments: [icsFile({ start: t, uid: cancel, summary: `Free call: ${name} (${phone})`, description: `Call ${name} at ${phone}. ${email}. ${note}` })],
  });
  if (!sentBrian) {
    await env.FILES.delete(key);
    return json({ ok: false, error: FAIL_MSG }, 502);
  }
  await sendEmail(env, {
    to: email,
    subject: `Your call with Brian: ${when}`,
    html: shell(`<p style="margin:0 0 6px;font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#b8730f">You're booked</p><h1 style="margin:0 0 18px;font-size:24px;line-height:1.25">${esc(when)}</h1><p style="margin:0 0 14px">${esc(firstName(name))}, Brian will call you at <strong>${esc(phone)}</strong> for fifteen minutes. Open the attached invite to put it on your calendar.</p><p style="margin:0 0 14px">Before the call, do Step 1 if you haven't: <a href="${origin}/step-1/" style="color:#b8730f">it's free</a> and takes twenty minutes. It gives the call somewhere to start.</p><p style="margin:0 0 22px">Can't make it? <a href="${cancelUrl}" style="color:#b8730f">Cancel this time</a> and book another, or reply to this email.</p><p style="margin:0">Brian</p>`),
    attachments: [icsFile({ start: t, uid: cancel, summary: "Free call with Brian Greene (Be The Man)", description: `Brian calls you at ${phone}. To cancel: ${cancelUrl}` })],
  });
  await subscribe(env, email, { firstName: firstName(name), tags: [TAGS.call] }).catch(() => false);
  return json({ ok: true, redirect: "/call/thanks/?t=" + encodeURIComponent(t) });
}
