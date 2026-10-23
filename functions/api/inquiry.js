// Cloudflare Pages Function: POST /api/inquiry
// Inquiries from the site: couples counseling (/couples/), free 15-minute
// call requests (/call/) and speaking requests (/speaking/), chosen by the "type" field.
// 1. Saves the person in Kit with that type's tag ("Couples inquiry", "Call request" or "Speaking inquiry").
// 2. Emails Brian the details through Resend.
// Needs RESEND_API_KEY (and KIT_API_KEY for the tag). If the alert can't be sent,
// the visitor sees a "please try again, or email Brian" message on this site.

import { subscribe, sendEmail, TAGS, BRIAN, firstName } from "../_mail.js";
import { inquiryAlertEmail } from "../_emails.js";

const TYPES = {
  couples: { tag: TAGS.couples, thanks: "/couples/thanks/" },
  call: { tag: TAGS.call, thanks: "/call/thanks/" },
  speaking: { tag: TAGS.speaking, thanks: "/speaking/thanks/" },
};

const FAIL_MSG = "We couldn't send your message just now. Please try again in a minute, or email brian@bethemansystem.com directly.";

// On failure the visitor stays on this site and sees FAIL_MSG (no more systeme fallback).
function done(request, ok, url) {
  if ((request.headers.get("accept") || "").includes("application/json")) {
    return new Response(JSON.stringify(ok ? { ok, redirect: url } : { ok, error: FAIL_MSG }), {
      status: ok ? 200 : 502,
      headers: { "content-type": "application/json" },
    });
  }
  if (ok) return Response.redirect(new URL(url, request.url).toString(), 303);
  return new Response(
    `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>Please try again</title>` +
      `<body style="font:18px/1.5 -apple-system,system-ui,sans-serif;background:#0b0b0c;color:#f2eee6;max-width:560px;margin:12vh auto;padding:0 20px">` +
      `<h1 style="font-size:32px">That didn't go through.</h1><p style="color:#c9c3b8">${FAIL_MSG}</p>` +
      `<p><a style="color:#e18b1f" href="javascript:history.back()">Go back</a></p></body>`,
    { status: 502, headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } }
  );
}

const clean = (v, n) => String(v || "").replace(/[\r\n\t]+/g, " ").trim().slice(0, n);

export async function onRequestPost({ request, env }) {
  let data = {};
  const type = request.headers.get("content-type") || "";
  try {
    data = type.includes("application/json")
      ? await request.json()
      : Object.fromEntries((await request.formData()).entries());
  } catch (e) {}

  const kind = Object.hasOwn(TYPES, data.type) ? data.type : "couples";
  const { tag, thanks: THANKS } = TYPES[kind];
  if (data.company) return done(request, true, THANKS); // honeypot: quietly drop bots
  const name = clean(data.name, 120);
  const email = clean(data.email, 200).toLowerCase();
  const phone = clean(data.phone, 40);
  // Speaking requests also carry the organization and the event date and place.
  const extra = kind === "speaking"
    ? [["Organization", clean(data.org, 160)], ["Event", clean(data.event, 160)]].filter(([, v]) => v).map(([k, v]) => `${k}: ${v}`)
    : [];
  const note = [...extra, clean(data.note, 500)].filter(Boolean).join(" · ");
  if (!name || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
    return new Response(JSON.stringify({ ok: false, error: kind === "couples" ? "Please add your names and a valid email." : "Please add your name and a valid email." }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }
  if (!env.RESEND_API_KEY) return done(request, false);

  try {
    // Saved for follow-up only; an inquiry is not a newsletter sign-up, so no sequence starts.
    await subscribe(env, email, { firstName: firstName(name), tags: [tag] }).catch(() => false);
    const typeLabel = { call: "free call", speaking: "speaking", couples: "couples" }[kind];
    const sent = await sendEmail(env, {
      to: BRIAN,
      replyTo: email,
      subject: `New ${typeLabel} inquiry: ${name}`,
      html: inquiryAlertEmail({
        inquiry_name: name,
        inquiry_type: typeLabel,
        inquiry_email: email,
        inquiry_phone: note ? `${phone || "none given"} · Note: ${note}` : phone || "none given",
      }),
    });
    return done(request, sent, THANKS);
  } catch (e) {
    return done(request, false);
  }
}

export async function onRequestGet({ request }) {
  return Response.redirect(new URL("/couples/#inquire", request.url).toString(), 302);
}
