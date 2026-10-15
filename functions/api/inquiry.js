// Cloudflare Pages Function: POST /api/inquiry
// Inquiries from the site: couples counseling (/couples/) and free 15-minute
// call requests (/call/), chosen by the "type" field.
// 1. Saves the person in Kit with that type's tag ("Couples inquiry" or "Call request").
// 2. Emails Brian the details through Resend.
// Needs RESEND_API_KEY (and KIT_API_KEY for the tag). If the alert can't be sent,
// the visitor is sent to a fallback (the old systeme form, or an email to Brian)
// so nothing is lost.

import { subscribe, sendEmail, TAGS, BRIAN, firstName } from "../_mail.js";
import { inquiryAlertEmail } from "../_emails.js";

const TYPES = {
  couples: { tag: TAGS.couples, thanks: "/couples/thanks/", fallback: "https://5e95-brian.systeme.io/0d29fa39" },
  call: { tag: TAGS.call, thanks: "/call/thanks/", fallback: "mailto:brian@bethemansystem.com?subject=Free%2015-minute%20call" },
};

function done(request, ok, url) {
  if ((request.headers.get("accept") || "").includes("application/json")) {
    return new Response(JSON.stringify({ ok, redirect: url }), {
      status: ok ? 200 : 502,
      headers: { "content-type": "application/json" },
    });
  }
  return Response.redirect(new URL(url, request.url).toString(), 303);
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
  const { tag, thanks: THANKS, fallback: FALLBACK } = TYPES[kind];
  if (data.company) return done(request, true, THANKS); // honeypot: quietly drop bots
  const name = clean(data.name, 120);
  const email = clean(data.email, 200).toLowerCase();
  const phone = clean(data.phone, 40);
  const note = clean(data.note, 500);
  if (!name || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
    return new Response(JSON.stringify({ ok: false, error: kind === "couples" ? "Please add your names and a valid email." : "Please add your name and a valid email." }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }
  if (!env.RESEND_API_KEY) return done(request, false, FALLBACK);

  try {
    // Saved for follow-up only; an inquiry is not a newsletter sign-up, so no sequence starts.
    await subscribe(env, email, { firstName: firstName(name), tags: [tag] }).catch(() => false);
    const typeLabel = kind === "call" ? "free call" : "couples";
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
    return done(request, sent, sent ? THANKS : FALLBACK);
  } catch (e) {
    return done(request, false, FALLBACK);
  }
}

export async function onRequestGet({ request }) {
  return Response.redirect(new URL("/couples/#inquire", request.url).toString(), 302);
}
