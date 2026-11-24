// Text messages through Twilio.
//
// Secrets (Cloudflare -> Pages -> bethemansystem -> Settings -> Variables and secrets):
//   TWILIO_ACCOUNT_SID   starts with AC
//   TWILIO_AUTH_TOKEN
//   TWILIO_FROM          the Be The Man number in +1XXXXXXXXXX form
//                        (or TWILIO_MESSAGING_SERVICE_SID, starts with MG)
//   SMS_DAILY_CAP        optional, list texts per day (default 50)
//
// Rules built in:
// - list texts go only to men who checked the text-consent box (sms.status "subscribed")
// - every list text starts "Be The Man:" and ends "Reply STOP to opt out."
// - list texts only go out between 9 AM and 8 PM Central; outside that they wait
// - STOP, START and HELP replies are handled automatically (functions/api/sms/inbound.js)

export const SMS_CONSENT =
  "Yes, text me Be The Man reminders. By checking this box, you agree to receive recurring automated text messages from Be The Man at the number provided. Consent is not a condition of purchase. Msg frequency varies. Msg & data rates may apply. Reply HELP for help, STOP to cancel. See our Terms and Privacy Policy at bethemansystem.com.";
export const SMS_HELP = "Be The Man: faith-based systems for Black Christian men with ADHD. Help: brian@bethemansystem.com. Msg & data rates may apply. Reply STOP to cancel.";
export const SMS_STOPPED = "Be The Man: you're unsubscribed and won't get more texts. Reply START to rejoin.";
export const SMS_STARTED = "Be The Man: you're subscribed to texts again. Msg frequency varies. Reply HELP for help, STOP to cancel.";

export const STOP_WORDS = ["STOP", "STOPALL", "UNSUBSCRIBE", "CANCEL", "END", "QUIT", "REVOKE", "OPTOUT"];
export const START_WORDS = ["START", "UNSTOP", "YES", "SUBSCRIBE"];
export const HELP_WORDS = ["HELP", "INFO"];

export const smsReady = (env) => !!(env.TWILIO_ACCOUNT_SID && env.TWILIO_AUTH_TOKEN && (env.TWILIO_FROM || env.TWILIO_MESSAGING_SERVICE_SID));
export const smsCap = (env) => Number(env.SMS_DAILY_CAP || 50);

// US numbers to +1XXXXXXXXXX; anything already in +E.164 kept. Returns "" if not usable.
export function toE164(raw) {
  const s = String(raw || "").trim();
  if (/^\+[1-9]\d{7,14}$/.test(s.replace(/[\s().-]/g, ""))) return s.replace(/[\s().-]/g, "");
  const d = s.replace(/\D/g, "");
  if (d.length === 10) return "+1" + d;
  if (d.length === 11 && d[0] === "1") return "+" + d;
  return "";
}

// Central-time hour now (0-23).
export function centralHour(ms = Date.now()) {
  return Number(new Intl.DateTimeFormat("en-US", { timeZone: "America/Chicago", hour: "numeric", hourCycle: "h23" }).format(new Date(ms)));
}
export const inQuietHours = (ms = Date.now()) => { const h = centralHour(ms); return h < 9 || h >= 20; };

// The next moment inside sending hours (9 AM Central), checked hour by hour.
export function nextSendWindow(ms = Date.now()) {
  let t = ms;
  for (let i = 0; i < 30 && inQuietHours(t); i++) t += 3600000;
  return t;
}

export function listText(body) {
  let b = String(body || "").trim();
  if (!/^be the man:/i.test(b)) b = "Be The Man: " + b;
  if (!/reply stop/i.test(b)) b += " Reply STOP to opt out.";
  return b;
}

export async function sendSms(env, { to, body }) {
  if (!smsReady(env)) return { ok: false, error: "Texting isn't connected yet (add the Twilio keys in Cloudflare)." };
  const form = new URLSearchParams({ To: to, Body: body, StatusCallback: "https://bethemansystem.com/api/sms/status" });
  if (env.TWILIO_MESSAGING_SERVICE_SID) form.set("MessagingServiceSid", env.TWILIO_MESSAGING_SERVICE_SID);
  else form.set("From", env.TWILIO_FROM);
  try {
    const r = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${env.TWILIO_ACCOUNT_SID}/Messages.json`, {
      method: "POST",
      headers: { authorization: "Basic " + btoa(`${env.TWILIO_ACCOUNT_SID}:${env.TWILIO_AUTH_TOKEN}`), "content-type": "application/x-www-form-urlencoded" },
      body: form.toString(),
    });
    const d = await r.json().catch(() => ({}));
    return r.ok ? { ok: true, sid: d.sid } : { ok: false, error: d.message || `Twilio ${r.status}`, code: d.code };
  } catch (e) {
    return { ok: false, error: String(e) };
  }
}

// Twilio's request signature: base64(HMAC-SHA1(auth token, url + sorted key+value pairs)).
export async function validTwilio(env, request, params) {
  const sig = request.headers.get("x-twilio-signature") || "";
  if (!env.TWILIO_AUTH_TOKEN || !sig) return false;
  const url = request.url;
  const data = url + Object.keys(params).sort().map((k) => k + params[k]).join("");
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.TWILIO_AUTH_TOKEN), { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data)));
  const b64 = btoa(String.fromCharCode(...mac));
  return b64 === sig;
}

export const twiml = (msg) => new Response(
  `<?xml version="1.0" encoding="UTF-8"?><Response>${msg ? `<Message>${String(msg).replace(/[<&>]/g, (c) => ({ "<": "&lt;", "&": "&amp;", ">": "&gt;" })[c])}</Message>` : ""}</Response>`,
  { headers: { "content-type": "text/xml" } });
