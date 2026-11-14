import type { Env } from "./index";
import { json } from "./ai";

/**
 * Instant new-mail alerts, even when Keel is closed.
 * Gmail (via Google Pub/Sub) and Outlook (via Microsoft Graph) tell this server "new mail arrived";
 * the server sends a silent push so the app wakes up, fetches the mail itself and shows its own alert.
 * The server never sees any email: only "something changed".
 *
 *   POST /push/register   (owner's device) save this device's push token
 *   GET  /push/config     (owner's device) the Gmail topic and Outlook check value the app needs to subscribe
 *   POST /push/gmail?secret=…   Google Pub/Sub push subscription endpoint
 *   POST /push/graph      Microsoft Graph change notifications (answers the validation handshake too)
 *
 * Secrets (Cloudflare → keel-backend → Settings → Variables and Secrets):
 *   APNS_KEY      the .p8 key text from developer.apple.com → Keys (Apple Push Notifications service)
 *   APNS_KEY_ID   that key's 10-character Key ID
 *   APNS_TEAM_ID  your 10-character Team ID
 *   PUSH_SECRET   any long random text (checks that pushes really come from Google/Microsoft for you)
 *   GMAIL_PUBSUB_TOPIC   e.g. projects/your-project/topics/keel-gmail  (only for Gmail)
 */
type Device = { token: string; sandbox: boolean; at: number };
const TOPIC = "com.briangreenejr.keel";

export async function handlePush(req: Request, env: Env, url: URL, device: boolean): Promise<Response | null> {
  const p = url.pathname;

  if (p === "/push/register" && req.method === "POST") {
    if (!device) return json({ error: "unauthorized" }, 401);
    const b = (await req.json()) as { token?: string; sandbox?: boolean };
    if (!b.token || !/^[a-f0-9]{32,200}$/i.test(b.token)) return json({ error: "bad token" }, 400);
    const list = ((await env.KEEL.get("push:devices", "json")) ?? []) as Device[];
    const next = [{ token: b.token, sandbox: !!b.sandbox, at: Date.now() }, ...list.filter((d) => d.token !== b.token)].slice(0, 10);
    await env.KEEL.put("push:devices", JSON.stringify(next));
    return json({ ok: true, ready: apnsReady(env) });
  }

  if (p === "/push/config" && req.method === "GET") {
    if (!device) return json({ error: "unauthorized" }, 401);
    return json({ ready: apnsReady(env), gmailTopic: env.GMAIL_PUBSUB_TOPIC ?? null, clientState: env.PUSH_SECRET ?? null });
  }

  if (p === "/push/gmail" && req.method === "POST") {
    if (!env.PUSH_SECRET || url.searchParams.get("secret") !== env.PUSH_SECRET) return new Response("forbidden", { status: 403 });
    await wake(env);
    return new Response(null, { status: 204 });                 // any 2xx tells Pub/Sub it was delivered
  }

  if (p === "/push/graph" && req.method === "POST") {
    // Microsoft checks the address first by sending a token it wants echoed back as plain text.
    const v = url.searchParams.get("validationToken");
    if (v) return new Response(v, { status: 200, headers: { "content-type": "text/plain" } });
    const b = (await req.json().catch(() => ({}))) as { value?: { clientState?: string }[] };
    if (env.PUSH_SECRET && (b.value ?? []).some((n) => n.clientState === env.PUSH_SECRET)) await wake(env);
    return new Response(null, { status: 202 });
  }
  return null;
}

function apnsReady(env: Env): boolean {
  return !!(env.APNS_KEY && env.APNS_KEY_ID && env.APNS_TEAM_ID);
}

/** Silent push to every registered device (at most one every 20 seconds, so a burst of mail is one wake-up). */
async function wake(env: Env): Promise<void> {
  if (!apnsReady(env)) return;
  const last = Number((await env.KEEL.get("push:last")) ?? 0);
  if (Date.now() - last < 20_000) return;
  await env.KEEL.put("push:last", String(Date.now()));
  const devices = ((await env.KEEL.get("push:devices", "json")) ?? []) as Device[];
  const jwt = await providerToken(env);
  const keep: Device[] = [];
  for (const d of devices) {
    const host = d.sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    const r = await fetch(`https://${host}/3/device/${d.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": TOPIC,
        "apns-push-type": "background",
        "apns-priority": "5",
        "content-type": "application/json",
      },
      body: JSON.stringify({ aps: { "content-available": 1 }, keel: "mail" }),
    }).catch(() => null);
    // 410 = the app was deleted from that device: forget it.
    if (r?.status !== 410) keep.push(d);
  }
  if (keep.length !== devices.length) await env.KEEL.put("push:devices", JSON.stringify(keep));
}

/** APNs sign-in token (ES256 JWT), reused for 50 minutes as Apple asks. */
async function providerToken(env: Env): Promise<string> {
  const cached = await env.KEEL.get("push:jwt");
  if (cached) return cached;
  const b64url = (b: ArrayBuffer | Uint8Array) =>
    btoa(String.fromCharCode(...new Uint8Array(b instanceof Uint8Array ? b : new Uint8Array(b))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const enc = new TextEncoder();
  const header = b64url(enc.encode(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID })));
  const claims = b64url(enc.encode(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) })));
  const pem = (env.APNS_KEY ?? "").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(`${header}.${claims}`));
  const jwt = `${header}.${claims}.${b64url(sig)}`;
  await env.KEEL.put("push:jwt", jwt, { expirationTtl: 3000 });
  return jwt;
}
