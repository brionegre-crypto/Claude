// POST /api/sms/status: Twilio's delivery report for each text. A number that
// can't receive texts (landline, opted out at the carrier) stops getting them.
import { validTwilio, toE164 } from "../../_sms.js";
import { contactByPhone, setSms, logText } from "../../_list.js";

const DEAD = ["21610", "21614", "30003", "30005", "30006", "30004"];

export async function onRequestPost({ request, env }) {
  const params = Object.fromEntries((await request.formData()).entries());
  if (!(await validTwilio(env, request, params))) return new Response("forbidden", { status: 403 });
  if ((params.MessageStatus === "failed" || params.MessageStatus === "undelivered") && DEAD.includes(String(params.ErrorCode))) {
    const c = await contactByPhone(env, toE164(params.To));
    if (c && c.sms && c.sms.status === "subscribed") await setSms(env, c, "unsubscribed", "undeliverable (" + params.ErrorCode + ")");
    await logText(env, { e: c ? c.email : "", ph: toE164(params.To), dir: "out", b: "Delivery failed, error " + params.ErrorCode, k: "status", ok: 0 });
  }
  return new Response("ok");
}
