// Cloudflare Pages Function: POST /api/subscribe
// Adds a sign-up to Kit. Default list is Step 1 (tag "Step 1", the "Step 1."
// email straight away, and from Nov 6 the weekly Step 1 follow-up); list
// "challenge" is the free 7-week challenge (tag "7-week challenge" and its
// welcome email); list "lowseat" emails a Low Seat Check result (tag "Low Seat
// Check", score and posture fields, and the 7-day plan). Needs the KIT_API_KEY secret. If the key is missing or Kit
// fails, the visitor sees a "please try again" message on this site.

import { subscribe, TAGS, SEQUENCES, FOLLOW_UP_FROM, firstName } from "../_mail.js";

const LISTS = {
  step1: { tag: TAGS.step1, sequences: [SEQUENCES.step1Welcome], thanks: "/step-1/thanks/" },
  challenge: { tag: TAGS.challenge, sequences: [SEQUENCES.challengeWelcome], thanks: "/7-week-challenge/thanks/" },
  lowseat: { tag: TAGS.lowSeat, sequences: [SEQUENCES.lowSeat], thanks: "/humility/#sent" },
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

export async function onRequestPost({ request, env }) {
  let data = {};
  const type = request.headers.get("content-type") || "";
  try {
    data = type.includes("application/json")
      ? await request.json()
      : Object.fromEntries((await request.formData()).entries());
  } catch (e) {}
  return handle(request, env, data);
}

async function handle(request, env, data) {
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
  if (!env.KIT_API_KEY) return done(request, false);
  const sequences = [...list.sequences];
  if (list === LISTS.step1 && Date.now() >= FOLLOW_UP_FROM) sequences.push(SEQUENCES.step1FollowUp);
  try {
    const fields = list === LISTS.lowseat ? lowSeatFields(data) : undefined;
    const ok = await subscribe(env, email, { firstName: firstName(name), tags: [list.tag], sequences, fields });
    return done(request, ok, THANKS);
  } catch (e) {
    return done(request, false);
  }
}

export function onRequestGet() {
  return Response.redirect("https://bethemansystem.com/step-1/", 302);
}
