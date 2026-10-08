// Cloudflare Pages Function: POST /api/inquiry
// Couples counseling inquiries from bethemansystem.com/couples/.
// 1. Saves the couple in MailerLite group "Couples inquiries".
// 2. Alerts Brian: his own subscriber record (brian@bethemansystem.com) gets the
//    inquiry details and rejoins group "Inquiry alerts (Brian only)", which
//    starts the "New inquiry alert (to Brian)" automation.
// Needs the MAILERLITE_API_KEY secret. If MailerLite fails, the visitor is sent
// to the old systeme.io inquiry form so no inquiry is lost.

const ML = "https://connect.mailerlite.com/api";
const INQUIRIES = "200754210229192006"; // "Couples inquiries"
const ALERTS = "200754210963195398"; // "Inquiry alerts (Brian only)"
const BRIAN = "brian@bethemansystem.com";
const FALLBACK = "https://5e95-brian.systeme.io/0d29fa39";
const THANKS = "/couples/thanks/";

function done(request, ok, url) {
  if ((request.headers.get("accept") || "").includes("application/json")) {
    return new Response(JSON.stringify({ ok, redirect: url }), {
      status: ok ? 200 : 502,
      headers: { "content-type": "application/json" },
    });
  }
  return Response.redirect(new URL(url, request.url).toString(), 303);
}

const clean = (v, n) => String(v || "").replace(/[\r\n\t]+/g, " ").trim().slice(0, n);

export async function onRequestPost({ request, env }) {
  let data = {};
  const type = request.headers.get("content-type") || "";
  try {
    data = type.includes("application/json")
      ? await request.json()
      : Object.fromEntries((await request.formData()).entries());
  } catch (e) {}

  if (data.company) return done(request, true, THANKS); // honeypot: quietly drop bots
  const name = clean(data.name, 120);
  const email = clean(data.email, 200).toLowerCase();
  const phone = clean(data.phone, 40);
  if (!name || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
    return new Response(JSON.stringify({ ok: false, error: "Please add your names and a valid email." }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }
  if (!env.MAILERLITE_API_KEY) return done(request, false, FALLBACK);

  const ml = (path, init = {}) =>
    fetch(ML + path, {
      ...init,
      headers: { authorization: `Bearer ${env.MAILERLITE_API_KEY}`, "content-type": "application/json", accept: "application/json" },
    });

  try {
    const fields = { inquiry_name: name, inquiry_phone: phone, inquiry_type: "couples" };
    const saved = await ml("/subscribers", { method: "POST", body: JSON.stringify({ email, fields, groups: [INQUIRIES] }) });
    if (!saved.ok) return done(request, false, FALLBACK);

    // Alert Brian. Leave and rejoin the alerts group so the automation runs every time.
    const me = await ml(`/subscribers/${encodeURIComponent(BRIAN)}`);
    if (me.ok) {
      const sub = (await me.json()).data || {};
      if ((sub.groups || []).some((g) => g.id === ALERTS)) {
        await ml(`/subscribers/${sub.id}/groups/${ALERTS}`, { method: "DELETE" });
      }
    }
    await ml("/subscribers", {
      method: "POST",
      // status "active" so the alert reaches Brian even if his address was ever unsubscribed.
      body: JSON.stringify({ email: BRIAN, fields: { ...fields, inquiry_email: email }, groups: [ALERTS], status: "active" }),
    });
    return done(request, true, THANKS);
  } catch (e) {
    return done(request, false, FALLBACK);
  }
}

export async function onRequestGet({ request }) {
  return Response.redirect(new URL("/couples/#inquire", request.url).toString(), 302);
}
