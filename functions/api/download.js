// Cloudflare Pages Function: GET /api/download?o=<offer>&f=<file>&s=<checkout session>
// Serves a purchased file from bethemansystem.com.
//
// Purchase check: when the STRIPE_KEY secret is set (a restricted key with
// read access to Checkout Sessions), the session id Stripe adds to the
// thank-you page URL must be a paid checkout from that product's Payment Link.
// Without STRIPE_KEY the check is skipped, which matches how downloads
// worked before.
//
// Storage: files live in the FILES KV namespace. The first time a file is
// asked for, it is copied there from its original systeme.io URL, so nothing
// has to be uploaded by hand. Without the FILES binding, the visitor is sent
// to the original URL.

import { OFFERS, FILES } from "../_catalog.js";

const html = (status, title, msg) =>
  new Response(
    `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>${title}</title>` +
      `<body style="font:18px/1.5 -apple-system,system-ui,sans-serif;background:#0b0b0c;color:#f2eee6;max-width:560px;margin:12vh auto;padding:0 20px">` +
      `<h1 style="font-size:32px">${title}</h1><p style="color:#c9c3b8">${msg}</p>` +
      `<p style="color:#c9c3b8">Email <a style="color:#e18b1f" href="mailto:brian@bethemansystem.com">brian@bethemansystem.com</a> and you'll get your files the same day.</p></body>`,
    { status, headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } }
  );

export async function verifySession(env, sessionId, plink) {
  if (!env.STRIPE_KEY) return true;
  if (!/^cs_(live|test)_[A-Za-z0-9]+$/.test(sessionId || "")) return false;
  const r = await fetch(`https://api.stripe.com/v1/checkout/sessions/${sessionId}`, {
    headers: { authorization: `Bearer ${env.STRIPE_KEY}` },
  });
  if (!r.ok) return false;
  const s = await r.json();
  return s.payment_link === plink && ["paid", "no_payment_required"].includes(s.payment_status);
}

export async function getFile(env, key) {
  const file = FILES[key];
  if (!env.FILES) return null;
  let hit = await env.FILES.getWithMetadata(key, { type: "arrayBuffer" });
  if (hit && hit.value) return { body: hit.value, type: (hit.metadata || {}).type };
  const r = await fetch(file.url);
  if (!r.ok) return null;
  const body = await r.arrayBuffer();
  const type = r.headers.get("content-type") || "application/octet-stream";
  // KV holds up to 25 MiB per file; anything bigger is served without storing.
  if (body.byteLength < 25 * 1024 * 1024) {
    await env.FILES.put(key, body, { metadata: { type, copied: new Date().toISOString() } });
  }
  return { body, type };
}

export async function onRequestGet({ request, env }) {
  const q = new URL(request.url).searchParams;
  const offer = OFFERS[q.get("o")];
  const key = q.get("f");
  if (!offer || !offer.files.includes(key) || !FILES[key]) {
    return html(404, "That file isn't here.", "The download link looks incomplete.");
  }
  if (!(await verifySession(env, q.get("s"), offer.plink))) {
    return html(403, "We couldn't confirm that purchase.", "Open the download page from the link you were sent to right after checkout.");
  }
  const file = FILES[key];
  const got = await getFile(env, key);
  if (!got) return Response.redirect(file.url, 302);
  return new Response(got.body, {
    headers: {
      "content-type": got.type || "application/octet-stream",
      "content-disposition": `attachment; filename="${file.name}"`,
      "cache-control": "private, no-store",
      "x-robots-tag": "noindex",
    },
  });
}
