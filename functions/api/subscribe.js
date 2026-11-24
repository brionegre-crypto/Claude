// Cloudflare Pages Function: POST /api/subscribe
// Adds a sign-up to Kit. Default list is Step 1 (tag "Step 1", the "Step 1."
// email straight away, and from Nov 6 the weekly Step 1 follow-up); list
// "challenge" is the free 7-week challenge (tag "7-week challenge" and its
// welcome email); list "lowseat" emails a Low Seat Check result (tag "Low Seat
// Check", score and posture fields, and the 7-day plan). Needs the KIT_API_KEY secret.
// If Kit is unavailable (missing key, lapsed plan, outage), Step 1 and Low Seat Check
// sign-ups still go through: the email is sent directly with Resend, the visitor
// reaches the thank-you page, and Brian's alert says "Not in Kit yet" so he can add
// the person to Kit later. Only if Resend also fails does the visitor see "please try again".

import { subscribe, sendEmail, notifyBrian, TAGS, SEQUENCES, FOLLOW_UP_FROM, firstName } from "../_mail.js";

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


const escH = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const wrap = (inner) => `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>` +
  `<body style="margin:0;padding:0;background:#f4f2ee"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f2ee"><tr><td align="center" style="padding:32px 16px">` +
  `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:16px"><tr><td style="padding:36px 32px;font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;color:#1d1d1f;font-size:17px;line-height:1.55">` +
  `<p style="margin:0 0 6px;font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#b8730f">Be The Man</p>${inner}` +
  `<p style="margin:24px 0 0;font-size:13px;color:#6e6e73">Be The Man is a faith-based coaching and consistency system, not medical treatment, diagnosis, or clinical therapy for ADHD.</p>` +
  `</td></tr></table></td></tr></table></body></html>`;
const btn = (href, label) => `<p style="margin:0 0 14px"><a href="${href}" style="display:inline-block;background:#e18b1f;color:#0b0b0c;font-weight:700;text-decoration:none;padding:14px 26px;border-radius:12px">${label}</a></p>`;

// Sent directly (Resend) when Kit can't take the sign-up.
function directEmail(list, name, fields) {
  const hi = name ? `${escH(firstName(name))}, here` : "Here";
  if (list === LISTS.lowseat) {
    return {
      subject: "Your Low Seat Check result",
      html: wrap(`<h1 style="margin:0 0 18px;font-size:26px;line-height:1.2">${hi} is your Low Seat Check result.</h1>` +
        (fields.low_seat_score ? `<p style="margin:0 0 10px">Your score: <strong>${escH(fields.low_seat_score)}</strong></p>` : "") +
        (fields.low_seat_posture ? `<p style="margin:0 0 20px">Your thinnest posture: <strong>${escH(fields.low_seat_posture)}</strong>. Pick one decision in that posture, give it a day and a time this week, and put it on your Ledger.</p>` : "") +
        btn("https://bethemansystem.com/humility/", "Take it again or send it to a witness") +
        `<p style="margin:16px 0 0">Brian</p>`),
    };
  }
  return {
    subject: "Step 1: The Calling",
    html: wrap(`<h1 style="margin:0 0 18px;font-size:26px;line-height:1.2">${hi} is Step 1.</h1>` +
      `<p style="margin:0 0 14px">Step 1 is The Calling: one sentence on who God has called you to be. List your roles, ask what God expects of you in each, make it a Tuesday, and write the sentence. Twenty minutes, or four five-minute pieces.</p>` +
      btn("https://bethemansystem.com/step-1/worksheet/", "Open the worksheet") +
      `<p style="margin:0 0 20px;font-size:15px">Rather print it? <a href="https://bethemansystem.com/downloads/step-1-the-calling.pdf" style="color:#b8730f">Download the PDF</a>.</p>` +
      `<p style="margin:0 0 14px">When your sentence is written, the next three steps build the plan around it. The Founding Cohort builds them with you, live, with other men: <a href="https://bethemansystem.com/cohort/" style="color:#b8730f">bethemansystem.com/cohort</a>.</p>` +
      `<p style="margin:0">Reply any time. It comes straight to me.</p><p style="margin:16px 0 0">Brian</p>`),
  };
}

const LIST_NAMES = { step1: "Step 1 (free worksheet)", challenge: "7-week challenge", lowseat: "Low Seat Check results" };

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
  const sequences = [...list.sequences];
  if (list === LISTS.step1 && Date.now() >= FOLLOW_UP_FROM) sequences.push(SEQUENCES.step1FollowUp);
  const fields = list === LISTS.lowseat ? lowSeatFields(data) : {};
  let inKit = false;
  try {
    inKit = await subscribe(env, email, { firstName: firstName(name), tags: [list.tag], sequences, fields: list === LISTS.lowseat ? fields : undefined });
  } catch (e) {}
  let sent = false;
  if (!inKit && list !== LISTS.challenge) {
    const m = directEmail(list, name, fields);
    sent = await sendEmail(env, { to: email, subject: m.subject, html: m.html });
  }
  const ok = inKit || sent;
  if (ok) {
    notifyBrian(env, context, {
      subject: `New sign-up: ${LIST_NAMES[key]}${name ? `, ${firstName(name)}` : ""}${inKit ? "" : " (not in Kit yet)"}`,
      replyTo: email,
      rows: [["Signed up for", LIST_NAMES[key]], ["Name", name], ["Email", email],
        ["Low Seat score", fields.low_seat_score], ["Thinnest posture", fields.low_seat_posture],
        ["Kit", inKit ? "Added" : "Not in Kit yet: Kit refused the sign-up, so the email went out directly. Add this person to Kit once it is renewed."]],
    });
  }
  return done(request, ok, THANKS);
}

export function onRequestGet() {
  return Response.redirect("https://bethemansystem.com/step-1/", 302);
}
