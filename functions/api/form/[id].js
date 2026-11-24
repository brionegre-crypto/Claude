// POST /api/form/<id>: a sign-up through a dashboard form. Tags the man, records
// text consent if he checked the box, starts the form's series and any automation
// triggered by this form, and alerts Brian. Double opt-in forms email a confirm
// link first and do nothing else until he clicks it.
import { getForm, upsertContact, enroll, runContact, fireTrigger, putContact, emailHtml, bodyHtml, SITE } from "../../_list.js";
import { readToken } from "../../_list.js";
import { sign } from "../../_club.js";
import { sendEmail, notifyBrian, firstName } from "../../_mail.js";
import { toE164 } from "../../_sms.js";
import { attribute } from "../../_extras.js";

const json = (b, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json", "cache-control": "no-store" } });

export async function onRequestPost(context) {
  const { request, env, params } = context;
  const f = env.FILES ? await getForm(env, params.id) : null;
  if (!f || f.archived) return json({ ok: false, error: "This form is closed." }, 404);
  let d = {};
  try { d = await request.json(); } catch (e) {}
  if (d.company) return json({ ok: true, message: f.success || "You're in." });
  const email = String(d.email || "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return json({ ok: false, error: "Please enter a valid email address." }, 400);
  const phone = f.phone ? toE164(d.phone) : "";
  if (f.phone && d.phone && !phone) return json({ ok: false, error: "Please enter a valid US mobile number." }, 400);
  if (d.sms && !phone) return json({ ok: false, error: "Add your mobile number to get texts." }, 400);
  const name = String(d.name || "").trim().slice(0, 80);
  const ip = request.headers.get("cf-connecting-ip") || "";
  const c = await upsertContact(env, {
    email, name, tags: f.tag ? [f.tag] : [], source: "Form: " + f.name, phone,
    smsConsent: f.sms && d.sms ? { source: "Form: " + f.name, ip } : null,
    status: f.doubleOptIn ? "unconfirmed" : undefined, run: !f.doubleOptIn,
  });
  if (!c) return json({ ok: false, error: "Please try again." }, 500);
  await attribute(env, c, { src: d.src, ref: d.ref });

  if (c.status === "unconfirmed") {
    c.pending = { form: f.id };
    await putContact(env, c);
    const t = await sign(env, { p: "confirm", e: email, f: f.id, x: Math.floor(Date.now() / 1000) + 7 * 86400 });
    await sendEmail(env, { to: email, subject: "Please confirm: Be The Man",
      html: emailHtml(bodyHtml(`${firstName(name) || "Friend"}, one click to confirm you want emails from Be The Man.\n\n[[Yes, confirm|${SITE}/api/mail/confirm?t=${t}]]\n\nIf you didn't sign up, ignore this and you won't hear from us.`, c), null) });
    return json({ ok: true, message: "Check your email and click the confirm link." });
  }
  if (f.series) { await enroll(env, c, f.series); await putContact(env, c); }
  await fireTrigger(env, c, "form", f.id);
  await runContact(env, c, 3);
  notifyBrian(env, context, { subject: `New sign-up: ${f.name}${name ? `, ${firstName(name)}` : ""}`, replyTo: email,
    rows: [["Form", f.name], ["Name", name], ["Email", email], ["Mobile", phone], ["Texts", d.sms && phone ? "Opted in" : ""]] });
  return f.redirect ? json({ ok: true, redirect: f.redirect }) : json({ ok: true, message: f.success || "You're in. Check your email." });
}
