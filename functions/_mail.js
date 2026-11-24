// Email for the site. Since Nov 24, 2026 the list lives on this site, not in Kit:
// subscribe(), tagByName() and untag() write to Be The Man's own list
// (functions/_list.js, stored in the FILES KV namespace), and Resend
// (resend.com) sends everything. Kit is no longer called. The Kit ids below
// stay only so the tag names match what was in Kit.
//
// Secrets (Cloudflare -> Pages -> bethemansystem -> Settings -> Variables and secrets):
//   CRON_SECRET     shared with the GitHub Actions job that runs /api/mail/tick
//   MAIL_DAILY_CAP  optional, list emails per day (default 90, inside Resend's free 100)
//   RESEND_API_KEY  Resend API key, with bethemansystem.com verified in Resend

import { upsertContact, removeTag } from "./_list.js";

export const FROM = "Brian Greene <brian@bethemansystem.com>";
export const BRIAN = "brian@bethemansystem.com";

// Kit tag and sequence ids (account "Be The Man System").
export const TAGS = {
  step1: 24600590,
  challenge: 24600591,
  customer: 24600592,
  club: 24600593,
  innerCircle: 24600594,
  workshop: 24600595,
  group: 24600596,
  ministryKit: 24600597,
  couples: 24600598,
  call: 24600599,
  lowSeat: 24600600,
  pair: 24600601,
  speaking: 24937582,
};

export const SEQUENCES = {
  step1Welcome: 2931291, // "Step 1." straight away
  step1FollowUp: 2928502, // Steps 1 to 6, weekly
  challengeWelcome: 2928501, // "You're in: the 7-week challenge"
  lowSeat: 2941421, // Low Seat Check results, then a 7-day plan
};

// The weekly Step 1 follow-up starts for sign-ups from this date. Before it, the
// Thursday emails cover the same steps, so starting both would double up.
export const FOLLOW_UP_FROM = Date.parse("2026-11-06T00:00:00-06:00");


// Kit tag id -> tag name on the site's own list.
const TAG_NAMES = {
  [TAGS.step1]: "Step 1", [TAGS.challenge]: "7-week challenge", [TAGS.customer]: "Customer",
  [TAGS.club]: "Club member", [TAGS.innerCircle]: "Inner Circle", [TAGS.workshop]: "Workshop",
  [TAGS.group]: "6-week group", [TAGS.ministryKit]: "Ministry kit", [TAGS.couples]: "Couples",
  [TAGS.call]: "Free call", [TAGS.lowSeat]: "Low Seat Check", [TAGS.pair]: "Accountability pair",
  [TAGS.speaking]: "Speaking",
};
export const tagName = (t) => (typeof t === "number" ? TAG_NAMES[t] || String(t) : String(t));

// Add or update a contact on the site's own list and apply tags.
// (Series are started by the caller with enroll() from _list.js.)
// Returns true when the contact was saved.
export async function subscribe(env, email, { firstName, tags = [], fields } = {}) {
  const names = tags.map(tagName);
  const c = await upsertContact(env, { email, name: firstName, tags: names, fields, source: names[0] });
  return !!c;
}

// Tag by name (for example "Workshop 2026-11-04").
export async function tagByName(env, email, name) {
  return !!(await upsertContact(env, { email, tags: [name], optIn: false }));
}

export async function untag(env, email, tag) {
  return !!(await removeTag(env, email, tagName(tag)));
}

// One-to-one email through Resend. Returns true when Resend accepted it.
// attachments: [{ filename, content }] with content base64-encoded.
export async function sendEmail(env, { to, subject, html, replyTo = BRIAN, attachments }) {
  if (!env.RESEND_API_KEY) return false;
  try {
    const body = { from: FROM, to: [to], subject, html, reply_to: replyTo };
    if (attachments) body.attachments = attachments;
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    return r.ok;
  } catch (e) {
    return false;
  }
}

const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

// A short alert to Brian for every sign-up and purchase. rows: [[label, value], ...].
// Pass the request context so the email goes out after the visitor's response
// (ctx.waitUntil); never throws, so a failed alert can't break a sign-up.
export function notifyBrian(env, ctx, { subject, rows, replyTo }) {
  const html = `<div style="font:16px/1.5 -apple-system,Segoe UI,Helvetica,Arial,sans-serif;color:#1d1d1f;max-width:520px">` +
    `<p style="margin:0 0 12px;font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#b8730f">Be The Man · new activity</p>` +
    `<table cellpadding="0" cellspacing="0" style="border-collapse:collapse">` +
    rows.filter(([, v]) => v !== undefined && v !== null && v !== "")
      .map(([k, v]) => `<tr><td style="padding:4px 14px 4px 0;color:#6e6e73;vertical-align:top">${esc(k)}</td><td style="padding:4px 0"><strong>${esc(v)}</strong></td></tr>`).join("") +
    `</table></div>`;
  const p = sendEmail(env, { to: BRIAN, subject, html, replyTo: replyTo || BRIAN }).catch(() => false);
  if (ctx && ctx.waitUntil) ctx.waitUntil(p);
  return p;
}

export const firstName = (name) => String(name || "").trim().split(/\s+/)[0].slice(0, 60);
