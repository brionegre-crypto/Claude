// POST /api/mail/webhook: Resend's webhook (Resend -> Webhooks -> Add endpoint:
// https://bethemansystem.com/api/mail/webhook, events email.bounced and
// email.complained). Needs RESEND_WEBHOOK_SECRET (the "whsec_..." signing secret).
// A hard bounce or a spam complaint stops all list email to that address.
import { recordBounce } from "../../_list.js";

async function verify(env, request, body) {
  const id = request.headers.get("svix-id"), ts = request.headers.get("svix-timestamp"), sigs = request.headers.get("svix-signature") || "";
  if (!env.RESEND_WEBHOOK_SECRET || !id || !ts) return false;
  if (Math.abs(Date.now() / 1000 - Number(ts)) > 600) return false;
  const secret = Uint8Array.from(atob(env.RESEND_WEBHOOK_SECRET.replace(/^whsec_/, "")), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("raw", secret, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${id}.${ts}.${body}`)))));
  return sigs.split(" ").some((s) => s.split(",")[1] === mac);
}

export async function onRequestPost({ request, env }) {
  const body = await request.text();
  if (!(await verify(env, request, body))) return new Response("bad signature", { status: 401 });
  let e = {};
  try { e = JSON.parse(body); } catch (x) {}
  const to = (e.data && e.data.to) || [];
  if (e.type === "email.bounced" && (!e.data.bounce || e.data.bounce.type !== "Transient")) for (const a of to) await recordBounce(env, a, "bounced");
  if (e.type === "email.complained") for (const a of to) await recordBounce(env, a, "complained");
  return new Response("ok");
}
