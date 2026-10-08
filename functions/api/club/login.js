// POST /api/club/login  {email}
// Emails an active member a sign-in link (valid 30 minutes) through the
// MailerLite automation "Club sign-in link". The reply is the same whether
// or not the email belongs to a member.

import { CLUB } from "../../_catalog.js";
import { memberByEmail, sign, rejoinGroup, json } from "../../_club.js";

const SENT = { ok: true, message: "If that email has an active Club membership, a sign-in link is on its way. It works for 30 minutes." };

export async function onRequestPost({ request, env }) {
  if (!env.STRIPE_KEY || !env.MAILERLITE_API_KEY) return json({ ok: false, error: "Sign-in isn't switched on yet. Email brian@bethemansystem.com." }, 503);
  let data = {};
  try { data = await request.json(); } catch (e) {}
  const email = String(data.email || "").trim().toLowerCase().slice(0, 200);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return json({ ok: false, error: "Please enter a valid email address." }, 400);

  const member = await memberByEmail(env, email);
  if (!member) return json(SENT);
  const token = await sign(env, { e: member.email, c: member.customer, p: "login", x: Math.floor(Date.now() / 1000) + 1800 });
  const next = typeof data.next === "string" && data.next.startsWith("/members/") ? data.next : "/members/";
  const login_url = `https://bethemansystem.com/api/club/verify?t=${token}&next=${encodeURIComponent(next)}`;
  await rejoinGroup(env, email, CLUB.mailerlite.signin, { login_url });
  return json(SENT);
}
