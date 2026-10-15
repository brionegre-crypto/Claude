// Email for the site: Kit (kit.com) holds the list and sends the newsletters and
// email series; Resend (resend.com) sends one-to-one emails (download links,
// Club sign-in links, inquiry alerts to Brian).
//
// Secrets (Cloudflare -> Pages -> bethemansystem -> Settings -> Variables and secrets):
//   KIT_API_KEY     Kit v4 API key (Kit -> Settings -> Developer)
//   RESEND_API_KEY  Resend API key, with bethemansystem.com verified in Resend

const KIT = "https://api.kit.com/v4";

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
};

export const SEQUENCES = {
  step1Welcome: 2931291, // "Step 1." straight away
  step1FollowUp: 2928502, // Steps 1 to 6, weekly
  challengeWelcome: 2928501, // "You're in: the 7-week challenge"
};

// The weekly Step 1 follow-up starts for sign-ups from this date. Before it, the
// Thursday emails cover the same steps, so starting both would double up.
export const FOLLOW_UP_FROM = Date.parse("2026-11-06T00:00:00-06:00");

function kit(env, path, body, method = "POST") {
  return fetch(KIT + path, {
    method,
    headers: { "x-kit-api-key": env.KIT_API_KEY, "content-type": "application/json", accept: "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
}

// Add or update a subscriber, then apply tags and start sequences.
// Never resubscribes someone who unsubscribed: Kit keeps their state as is.
// Returns true when Kit accepted the subscriber.
export async function subscribe(env, email, { firstName, tags = [], sequences = [], fields } = {}) {
  if (!env.KIT_API_KEY) return false;
  const body = { email_address: email };
  if (firstName) body.first_name = firstName;
  if (fields) body.fields = fields;
  const r = await kit(env, "/subscribers", body);
  if (!r.ok) return false;
  const add = [
    ...tags.map((id) => kit(env, `/tags/${id}/subscribers`, { email_address: email })),
    ...sequences.map((id) => kit(env, `/sequences/${id}/subscribers`, { email_address: email })),
  ];
  await Promise.all(add.map((p) => p.catch(() => null)));
  return true;
}

export async function untag(env, email, tagId) {
  if (!env.KIT_API_KEY) return false;
  const r = await kit(env, `/tags/${tagId}/subscribers`, { email_address: email }, "DELETE");
  return r.ok;
}

// One-to-one email through Resend. Returns true when Resend accepted it.
export async function sendEmail(env, { to, subject, html, replyTo = BRIAN }) {
  if (!env.RESEND_API_KEY) return false;
  try {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({ from: FROM, to: [to], subject, html, reply_to: replyTo }),
    });
    return r.ok;
  } catch (e) {
    return false;
  }
}

export const firstName = (name) => String(name || "").trim().split(/\s+/)[0].slice(0, 60);
