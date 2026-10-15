// Cloudflare Pages Function: POST /api/subscribe
// Adds a sign-up to Kit. Default list is Step 1 (tag "Step 1", the "Step 1."
// email straight away, and from Nov 6 the weekly Step 1 follow-up); list
// "challenge" is the free 7-week challenge (tag "7-week challenge" and its
// welcome email). Needs the KIT_API_KEY secret. If the key is missing or Kit
// fails, the visitor is sent to the old systeme.io sign-up so no sign-up is lost.

import { subscribe, TAGS, SEQUENCES, FOLLOW_UP_FROM, firstName } from "../_mail.js";

const LISTS = {
  step1: { tag: TAGS.step1, sequences: [SEQUENCES.step1Welcome], thanks: "/step-1/thanks/", fallback: "https://go.bethemansystem.com/framework" },
  challenge: { tag: TAGS.challenge, sequences: [SEQUENCES.challengeWelcome], thanks: "/7-week-challenge/thanks/", fallback: "https://go.bethemansystem.com/42f82c9e" },
};

function done(request, ok, url) {
  const wantsJson = (request.headers.get("accept") || "").includes("application/json");
  if (wantsJson) {
    return new Response(JSON.stringify({ ok, redirect: url }), {
      status: ok ? 200 : 502,
      headers: { "content-type": "application/json" },
    });
  }
  return Response.redirect(new URL(url, request.url).toString(), 303);
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
  const { thanks: THANKS, fallback: FALLBACK } = list;
  const email = String(data.email || "").trim().toLowerCase();
  const name = String(data.name || "").trim().slice(0, 80);
  // Honeypot: real people never fill this hidden field.
  if (data.company) return done(request, true, THANKS);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
    return new Response(JSON.stringify({ ok: false, error: "Please enter a valid email address." }), {
      status: 400, headers: { "content-type": "application/json" },
    });
  }
  if (!env.KIT_API_KEY) return done(request, false, FALLBACK);
  const sequences = [...list.sequences];
  if (list === LISTS.step1 && Date.now() >= FOLLOW_UP_FROM) sequences.push(SEQUENCES.step1FollowUp);
  try {
    const ok = await subscribe(env, email, { firstName: firstName(name), tags: [list.tag], sequences });
    return done(request, ok, ok ? THANKS : FALLBACK);
  } catch (e) {
    return done(request, false, FALLBACK);
  }
}

export function onRequestGet() {
  return Response.redirect("https://bethemansystem.com/step-1/", 302);
}
