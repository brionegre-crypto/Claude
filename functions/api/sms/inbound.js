// POST /api/sms/inbound: Twilio's "A message comes in" webhook for the Be The Man
// number (Twilio -> Phone Numbers -> the number -> Messaging -> Webhook,
// https://bethemansystem.com/api/sms/inbound, HTTP POST).
// STOP words turn texts off, START words turn them back on, HELP gets the help
// text. Any other reply lands in the dashboard's Texts inbox and is emailed to Brian.
import { validTwilio, twiml, toE164, STOP_WORDS, START_WORDS, HELP_WORDS, SMS_HELP, SMS_STOPPED, SMS_STARTED } from "../../_sms.js";
import { contactByPhone, setSms, addEvent, putContact, logText, emailBrian } from "../../_list.js";
import { parseLedger, recordLedger, getSettings } from "../../_extras.js";

export async function onRequestPost({ request, env, waitUntil }) {
  const form = await request.formData();
  const params = Object.fromEntries(form.entries());
  if (!(await validTwilio(env, request, params))) return new Response("forbidden", { status: 403 });
  const from = toE164(params.From);
  const body = String(params.Body || "").trim();
  const word = body.toUpperCase().replace(/[^A-Z]/g, "");
  const c = from ? await contactByPhone(env, from) : null;
  await logText(env, { e: c ? c.email : "", ph: from, dir: "in", b: body.slice(0, 300), k: "reply", n: c ? c.name : "" });

  if (STOP_WORDS.includes(word)) {
    if (c) await setSms(env, c, "unsubscribed", "replied " + word);
    return twiml(SMS_STOPPED);
  }
  if (START_WORDS.includes(word)) {
    if (c) await setSms(env, c, "subscribed", "replied " + word);
    return twiml(c ? SMS_STARTED : "Be The Man: to get texts, sign up at bethemansystem.com/step-1 and check the text box. Reply HELP for help.");
  }
  if (HELP_WORDS.includes(word)) return twiml(SMS_HELP);

  // A Ledger number ("13/15") from a man in the Ledger group is saved, not sent to the inbox.
  const num = parseLedger(body);
  if (c && num) {
    const settings = await getSettings(env);
    if (settings.ledger.on && c.tags.includes(settings.ledger.tag)) {
      await recordLedger(env, c, num, "text");
      return twiml(`Be The Man: got it, ${num.k} of ${num.t}. Take grace for the misses, pick one change for Monday, and reset.`);
    }
  }
  if (c) { addEvent(c, "text reply", body.slice(0, 120)); await putContact(env, c); }
  waitUntil(emailBrian(env, `Text from ${c ? c.name || c.email : from}`,
    `**${c ? (c.name || "") + " " + c.email : "Unknown number"}** (${from}) texted:\n\n${body}\n\n[[Reply in the dashboard|https://bethemansystem.com/admin/#texts]]`).catch(() => null));
  await env.FILES.put("unread:texts", "1");
  return twiml("");
}
