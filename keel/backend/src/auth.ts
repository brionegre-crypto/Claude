import type { Env } from "./index";
import { json } from "./ai";

/**
 * Sign in with Apple. The app sends Apple's identity token; we check Apple's signature and claims,
 * then give the device its own access key (stored in KV) so Claude works without typing a code.
 * Only the owner gets one: the first Apple Account to sign in claims the server (or set OWNER_APPLE_SUB).
 */
const APPLE_ISSUER = "https://appleid.apple.com";
const BUNDLE_IDS = ["com.briangreenejr.keel"];

type JWK = { kid: string; kty: string; alg: string; n: string; e: string; use: string };

function b64urlToBytes(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  const bin = atob(b64);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

async function verifyAppleToken(token: string): Promise<{ sub: string; email?: string } | null> {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const header = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[0]))) as { kid: string; alg: string };
  const payload = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[1]))) as {
    iss: string; aud: string; exp: number; sub: string; email?: string;
  };
  if (header.alg !== "RS256") return null;
  if (payload.iss !== APPLE_ISSUER || !BUNDLE_IDS.includes(payload.aud) || payload.exp * 1000 < Date.now()) return null;

  const keys = (await (await fetch("https://appleid.apple.com/auth/keys")).json()) as { keys: JWK[] };
  const jwk = keys.keys.find((k) => k.kid === header.kid);
  if (!jwk) return null;
  const key = await crypto.subtle.importKey("jwk", jwk as JsonWebKey, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, b64urlToBytes(parts[2]), new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
  return ok ? { sub: payload.sub, email: payload.email } : null;
}

export async function handleAppleAuth(req: Request, env: Env): Promise<Response> {
  let body: { identityToken?: string; device?: string };
  try { body = await req.json(); } catch { return json({ error: "bad request" }, 400); }
  if (!body.identityToken) return json({ error: "missing token" }, 400);

  const who = await verifyAppleToken(body.identityToken);
  if (!who) return json({ error: "invalid sign in" }, 401);

  let owner = env.OWNER_APPLE_SUB || (await env.KEEL.get("owner_sub"));
  let claimed = false;
  if (!owner) {
    await env.KEEL.put("owner_sub", who.sub);      // first sign-in claims this server
    owner = who.sub;
    claimed = true;
  }
  if (who.sub !== owner) return json({ error: "not the owner" }, 403);

  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const token = "ks_" + Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
  await env.KEEL.put(`session:${token}`, JSON.stringify({ sub: who.sub, device: (body.device ?? "").slice(0, 60), at: Date.now() }));
  return json({ token, claimed });
}

/** True when the bearer is a device key handed out by Sign in with Apple. */
export async function isSession(bearer: string | undefined, env: Env): Promise<boolean> {
  if (!bearer || !bearer.startsWith("ks_")) return false;
  return (await env.KEEL.get(`session:${bearer}`)) !== null;
}
