// GET /api/mail/confirm?t=<token>: double opt-in confirmation link.
import { unsign } from "../../_club.js";
import { getContact, getForm, putContact, addEvent, enroll, fireTrigger, runContact, startTriggered, getAutomations, SITE } from "../../_list.js";

export async function onRequestGet({ request, env }) {
  const d = await unsign(env, new URL(request.url).searchParams.get("t"));
  if (!d || d.p !== "confirm") return Response.redirect(SITE + "/step-1/?expired=1", 302);
  const c = await getContact(env, d.e);
  const f = await getForm(env, d.f);
  if (c && c.status === "unconfirmed") {
    c.status = "active";
    addEvent(c, "confirmed", f ? f.name : "");
    const autos = await getAutomations(env);
    for (const t of c.tags) startTriggered(c, autos, "tag", t);
    if (c.sms && c.sms.status === "subscribed") startTriggered(c, autos, "sms", "");
    if (f && f.series) await enroll(env, c, f.series);
    delete c.pending;
    await putContact(env, c);
    if (f) await fireTrigger(env, c, "form", f.id);
    await runContact(env, c, 3);
  }
  return Response.redirect(f && f.redirect ? f.redirect : SITE + "/step-1/thanks/", 302);
}
