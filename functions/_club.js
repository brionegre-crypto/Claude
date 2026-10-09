// Shared helpers for the Be The Man Club members area.
//
// Membership is whatever Stripe says: a man is a member while he has an
// active (or trialing / past-due) subscription to a Club price. Signed-in
// members carry a signed cookie; it is re-checked against Stripe once a day,
// so a cancelled membership stops working within 24 hours of ending.
//
// Signing key: CLUB_SECRET if set, otherwise derived from STRIPE_KEY.

import { CLUB } from "./_catalog.js";

export const COOKIE = "btm_club";
const DAY = 86400;
const SESSION_DAYS = 30;
const RECHECK = DAY;
const ML = "https://connect.mailerlite.com/api";

const enc = new TextEncoder();
const b64u = (buf) =>
  btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const unb64u = (s) => atob(s.replace(/-/g, "+").replace(/_/g, "/"));

async function hmacKey(env) {
  const secret = env.CLUB_SECRET || (env.STRIPE_KEY ? "btm-club|" + env.STRIPE_KEY : "");
  if (!secret) return null;
  return crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

export async function sign(env, payload) {
  const key = await hmacKey(env);
  if (!key) return null;
  const body = b64u(enc.encode(JSON.stringify(payload)));
  const sig = b64u(await crypto.subtle.sign("HMAC", key, enc.encode(body)));
  return `${body}.${sig}`;
}

export async function unsign(env, token) {
  const key = await hmacKey(env);
  if (!key || !token || !token.includes(".")) return null;
  const [body, sig] = token.split(".");
  let raw;
  try {
    raw = Uint8Array.from(unb64u(sig), (c) => c.charCodeAt(0));
  } catch (e) {
    return null;
  }
  if (!(await crypto.subtle.verify("HMAC", key, raw, enc.encode(body)))) return null;
  try {
    const data = JSON.parse(unb64u(body));
    if (!data.x || data.x < Date.now() / 1000) return null;
    return data;
  } catch (e) {
    return null;
  }
}

const now = () => Math.floor(Date.now() / 1000);

export async function stripe(env, path) {
  const r = await fetch("https://api.stripe.com/v1" + path, { headers: { authorization: `Bearer ${env.STRIPE_KEY}` } });
  return r.ok ? r.json() : null;
}

// The Club subscription for a Stripe customer, or null.
export async function clubSubscription(env, customerId) {
  const list = await stripe(env, `/subscriptions?customer=${encodeURIComponent(customerId)}&status=all&limit=20`);
  for (const s of (list && list.data) || []) {
    if (!["active", "trialing", "past_due"].includes(s.status)) continue;
    const items = (s.items && s.items.data) || [];
    const icItem = items.find((i) => i.price && (CLUB.ic_prices || []).includes(i.price.id));
    if (icItem) return { id: s.id, start: s.start_date, yearly: true, ic: true };
    const item = items.find((i) => i.price && Object.values(CLUB.prices).includes(i.price.id));
    if (item) return { id: s.id, start: s.start_date, yearly: item.price.id === CLUB.prices.yearly, ic: false };
  }
  return null;
}

// Look up an active member by email. Returns {customer, email, start, yearly} or null.
export async function memberByEmail(env, email) {
  const list = await stripe(env, `/customers?email=${encodeURIComponent(email)}&limit=10`);
  for (const c of (list && list.data) || []) {
    const sub = await clubSubscription(env, c.id);
    if (sub) return { customer: c.id, email: c.email || email, start: sub.start, yearly: sub.yearly, ic: sub.ic };
  }
  return null;
}

export function readCookie(request) {
  const m = (request.headers.get("cookie") || "").match(new RegExp(`(?:^|;\\s*)${COOKIE}=([^;]+)`));
  return m ? m[1] : null;
}

export async function sessionCookie(env, member) {
  const token = await sign(env, {
    e: member.email,
    c: member.customer,
    s: member.start,
    y: member.yearly ? 1 : 0,
    i: member.ic ? 1 : 0,
    k: now(),
    x: now() + SESSION_DAYS * DAY,
  });
  return `${COOKIE}=${token}; Path=/; Max-Age=${SESSION_DAYS * DAY}; HttpOnly; Secure; SameSite=Lax`;
}

export const clearCookie = `${COOKIE}=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Lax`;

// Current member from the cookie. Re-checks Stripe once a day.
// Returns {member, setCookie} or {member: null, ended?: true}.
export async function currentMember(request, env) {
  const data = await unsign(env, readCookie(request));
  if (!data) return { member: null };
  let member = { email: data.e, customer: data.c, start: data.s, yearly: !!data.y, ic: !!data.i };
  if (now() - data.k < RECHECK) return { member };
  const sub = await clubSubscription(env, data.c);
  if (!sub) return { member: null, ended: true };
  member = { ...member, start: sub.start, yearly: sub.yearly, ic: sub.ic };
  return { member, setCookie: await sessionCookie(env, member) };
}

// How many monthly sets are open: all six for yearly members, otherwise one per 30 days.
export function monthsOpen(member, at = now()) {
  if (member.yearly) return 6;
  return Math.max(1, Math.min(6, 1 + Math.floor((at - member.start) / (30 * DAY))));
}

export function opensAt(member, month) {
  return member.yearly ? member.start : member.start + (month - 1) * 30 * DAY;
}

export function mailerlite(env) {
  return (path, init = {}) =>
    fetch(ML + path, {
      ...init,
      headers: {
        authorization: `Bearer ${env.MAILERLITE_API_KEY}`,
        "content-type": "application/json",
        accept: "application/json",
      },
    });
}

// Put a subscriber (back) into a group so a "joins group" automation runs again.
export async function rejoinGroup(env, email, groupId, fields, extra = {}) {
  const ml = mailerlite(env);
  const found = await ml(`/subscribers/${encodeURIComponent(email)}`);
  let sub = null;
  if (found.ok) {
    sub = (await found.json()).data || {};
    if ((sub.groups || []).some((g) => g.id === groupId)) {
      await ml(`/subscribers/${sub.id}/groups/${groupId}`, { method: "DELETE" });
    }
  }
  const body = { email, fields, groups: [groupId], ...extra };
  const r = await ml("/subscribers", { method: "POST", body: JSON.stringify(body) });
  return { ok: r.ok, existing: sub };
}

export const json = (body, status = 200, headers = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", ...headers },
  });
