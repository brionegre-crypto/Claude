// /api/mail/unsub?t=<signed token>  (the link in every list email)
// GET shows a confirm button; POST unsubscribes. Gmail and Apple Mail's one-click
// unsubscribe (List-Unsubscribe-Post) POSTs here directly.

import { verifyUnsub, recordUnsub, getContact } from "../../_list.js";

const page = (title, msg, form = "") => new Response(
  `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>${title}</title>` +
  `<body style="font:18px/1.5 -apple-system,system-ui,sans-serif;background:#0b0b0c;color:#f2eee6;max-width:560px;margin:12vh auto;padding:0 20px">` +
  `<p style="font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#e18b1f">Be The Man</p><h1 style="font-size:32px;line-height:1.15">${title}</h1><p style="color:#c9c3b8">${msg}</p>${form}</body>`,
  { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } });

export async function onRequestGet({ request, env }) {
  const t = new URL(request.url).searchParams.get("t") || "";
  const d = await verifyUnsub(env, t);
  if (!d) return page("That link has expired.", "Reply to any email from Brian and say \"unsubscribe\", and he'll take you off the list.");
  const email = d.e;
  const c = await getContact(env, email);
  if (c && c.status === "unsubscribed") return page("You're unsubscribed.", "You won't get list emails from Be The Man. If you ever want them again, sign up for Step 1 at bethemansystem.com.");
  return page("Unsubscribe?", `Stop all list emails to <b>${email.replace(/</g, "&lt;")}</b>?`,
    `<form method="post"><input type="hidden" name="t" value="${t.replace(/"/g, "&quot;")}"><button style="font:inherit;font-weight:700;background:#e18b1f;color:#0b0b0c;border:0;border-radius:12px;padding:14px 26px;cursor:pointer">Unsubscribe</button></form>`);
}

export async function onRequestPost({ request, env }) {
  const url = new URL(request.url);
  let t = url.searchParams.get("t") || "";
  try { const f = await request.formData(); if (f.get("t")) t = f.get("t"); } catch (e) {}
  const d = await verifyUnsub(env, t);
  if (!d) return page("That link has expired.", "Reply to any email from Brian and say \"unsubscribe\", and he'll take you off the list.");
  await recordUnsub(env, d);
  return page("You're unsubscribed.", "You won't get list emails from Be The Man anymore. Receipts for anything you buy still come through.");
}
