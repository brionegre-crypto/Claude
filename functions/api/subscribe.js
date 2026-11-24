// Cloudflare Pages Function: POST /api/subscribe
// Adds a sign-up to Be The Man's own list (functions/_list.js). Default list is
// Step 1: tag "Step 1" and the Step 1 welcome series, whose first email goes
// out straight away. List "lowseat" emails a Low Seat Check result (tag "Low
// Seat Check" with score and posture). Brian gets an alert for every sign-up.
// If the email can't be sent, the visitor sees a "please try again" message.

import { notifyBrian, firstName } from "../_mail.js";
import { upsertContact, enroll, runContact, sendToContact, getSequence, tick } from "../_list.js";

const LISTS = {
  step1: { tag: "Step 1", series: "step1", thanks: "/step-1/thanks/" },
  lowseat: { tag: "Low Seat Check", thanks: "/humility/#sent" },
};

const POSTURES = ["Teachable", "Owned", "Unseen", "Credit", "Dependent"];

// Score and thinnest posture for the Low Seat Check emails. Bad values are dropped, not stored.
function lowSeatFields(data) {
  const fields = {};
  const score = Number(data.score);
  if (Number.isInteger(score) && score >= 0 && score <= 100) fields.low_seat_score = String(score);
  if (POSTURES.includes(data.posture)) fields.low_seat_posture = data.posture;
  return fields;
}

const FAIL_MSG = "We couldn't sign you up just now. Please try again in a minute, or email brian@bethemansystem.com and he'll send it to you.";

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


// The Low Seat Check result email.
function lowSeatEmail(fields) {
  return {
    subject: "Your Low Seat Check result",
    body: `{{first_name}}, here is your Low Seat Check result.` +
      (fields.low_seat_score ? `\n\nYour score: **${fields.low_seat_score}**` : "") +
      (fields.low_seat_posture ? `\n\nYour thinnest posture: **${fields.low_seat_posture}**. Pick one decision in that posture, give it a day and a time this week, and put it on your Ledger.` : "") +
      `\n\n[[Take it again or send it to a witness|https://bethemansystem.com/humility/]]\n\nBrian`,
  };
}

const LIST_NAMES = { step1: "Step 1 (free worksheet)", lowseat: "Low Seat Check results" };

export async function onRequestPost(context) {
  const { request, env } = context;
  let data = {};
  const type = request.headers.get("content-type") || "";
  try {
    data = type.includes("application/json")
      ? await request.json()
      : Object.fromEntries((await request.formData()).entries());
  } catch (e) {}
  return handle(request, env, data, context);
}

async function handle(request, env, data, context) {
  const list = Object.hasOwn(LISTS, data.list) ? LISTS[data.list] : LISTS.step1;
  const { thanks: THANKS } = list;
  const email = String(data.email || "").trim().toLowerCase();
  const name = String(data.name || "").trim().slice(0, 80);
  // Honeypot: real people never fill this hidden field.
  if (data.company) return done(request, true, THANKS);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
    return new Response(JSON.stringify({ ok: false, error: "Please enter a valid email address." }), {
      status: 400, headers: { "content-type": "application/json" },
    });
  }
  const key = Object.keys(LISTS).find((k) => LISTS[k] === list);
  const fields = list === LISTS.lowseat ? lowSeatFields(data) : {};
  let ok = false;
  try {
    const c = await upsertContact(env, { email, name, tags: [list.tag], fields, source: list.tag });
    if (c && list.series && !(c.seq && c.seq[list.series])) {
      await enroll(env, c, list.series);
      ok = (await runContact(env, c)) > 0;
    } else if (c && list.series) {
      // Already in the series (signed up before): resend the first email only.
      const def = await getSequence(env, list.series);
      ok = (await sendToContact(env, c, def.emails[0], "series:" + list.series)).ok;
    } else if (c) {
      ok = (await sendToContact(env, c, lowSeatEmail(fields), "result")).ok;
    }
  } catch (e) {}
  if (ok) {
    notifyBrian(env, context, {
      subject: `New sign-up: ${LIST_NAMES[key]}${name ? `, ${firstName(name)}` : ""}`,
      replyTo: email,
      rows: [["Signed up for", LIST_NAMES[key]], ["Name", name], ["Email", email],
        ["Low Seat score", fields.low_seat_score], ["Thinnest posture", fields.low_seat_posture]],
    });
    if (context.waitUntil) context.waitUntil(tick(env, { max: 10 }).catch(() => null));
  }
  return done(request, ok, THANKS);
}

export function onRequestGet() {
  return Response.redirect("https://bethemansystem.com/step-1/", 302);
}
