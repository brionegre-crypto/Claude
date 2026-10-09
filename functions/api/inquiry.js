// Cloudflare Pages Function: POST /api/inquiry
// Inquiries from the site: couples counseling (/couples/) and free 15-minute
// call requests (/call/), chosen by the "type" field.
// 1. Saves the person in that type's MailerLite group.
// 2. Alerts Brian: his own subscriber record (brian@bethemansystem.com) gets the
//    inquiry details and rejoins group "Inquiry alerts (Brian only)", which
//    starts the "New inquiry alert (to Brian)" automation.
// Needs the MAILERLITE_API_KEY secret. If MailerLite fails, the visitor is sent
// to a fallback (the old systeme form, or an email to Brian) so nothing is lost.

const ML = "https://connect.mailerlite.com/api";
const ALERTS = "200754210963195398"; // "Inquiry alerts (Brian only)"
const BRIAN = "brian@bethemansystem.com";
const TYPES = {
  couples: { group: "200754210229192006", thanks: "/couples/thanks/", fallback: "https://5e95-brian.systeme.io/0d29fa39" },
  call: { group: "200858440125384132", thanks: "/call/thanks/", fallback: "mailto:brian@bethemansystem.com?subject=Free%2015-minute%20call" },
};

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

  const kind = Object.hasOwn(TYPES, data.type) ? data.type : "couples";
  const { group: INQUIRIES, thanks: THANKS, fallback: FALLBACK } = TYPES[kind];
  if (data.company) return done(request, true, THANKS); // honeypot: quietly drop bots
  const name = clean(data.name, 120);
  const email = clean(data.email, 200).toLowerCase();
  const phone = clean(data.phone, 40);
  const note = clean(data.note, 500);
  if (!name || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
    return new Response(JSON.stringify({ ok: false, error: kind === "couples" ? "Please add your names and a valid email." : "Please add your name and a valid email." }), {
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
    // The note also rides on the phone line, so the live alert email shows it without a redesign.
    const phoneLine = note ? `${phone || "none given"} · Note: ${note}` : phone;
    const fields = { inquiry_name: name, inquiry_phone: phoneLine, inquiry_type: kind === "call" ? "free call" : "couples", inquiry_note: note };
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
