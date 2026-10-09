// Cloudflare Pages Function: POST /api/subscribe
// Adds a sign-up to MailerLite. Default list is Step 1 (group "Step 1", which
// starts the "Step 1 welcome" automation); list "challenge" is the free
// 7-week challenge (group "7-week challenge", "7-week challenge welcome"). Needs the MAILERLITE_API_KEY secret set in
// Cloudflare (Workers & Pages -> bethemansystem -> Settings -> Variables and Secrets).
// If the key is missing or MailerLite fails, the visitor is sent to the old
// systeme.io sign-up so no sign-up is ever lost.

const LISTS = {
  step1: { group: "200695507810518732", thanks: "/step-1/thanks/", fallback: "https://go.bethemansystem.com/framework" },
  challenge: { group: "200854988516230789", thanks: "/7-week-challenge/thanks/", fallback: "https://go.bethemansystem.com/42f82c9e" },
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
  const { group: GROUP_ID, thanks: THANKS, fallback: FALLBACK } = Object.hasOwn(LISTS, data.list) ? LISTS[data.list] : LISTS.step1;
  const email = String(data.email || "").trim().toLowerCase();
  const name = String(data.name || "").trim().slice(0, 80);
  // Honeypot: real people never fill this hidden field.
  if (data.company) return done(request, true, THANKS);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
    return new Response(JSON.stringify({ ok: false, error: "Please enter a valid email address." }), {
      status: 400, headers: { "content-type": "application/json" },
    });
  }
  if (!env.MAILERLITE_API_KEY) return done(request, false, FALLBACK);
  try {
    const res = await fetch("https://connect.mailerlite.com/api/subscribers", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        accept: "application/json",
        authorization: `Bearer ${env.MAILERLITE_API_KEY}`,
      },
      body: JSON.stringify({ email, fields: { name }, groups: [GROUP_ID], status: "active" }),
    });
    if (!res.ok) return done(request, false, FALLBACK);
    return done(request, true, THANKS);
  } catch (e) {
    return done(request, false, FALLBACK);
  }
}

export function onRequestGet() {
  return Response.redirect("https://bethemansystem.com/step-1/", 302);
}
