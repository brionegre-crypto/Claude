import type { Env } from "./index";

/**
 * "Sign in" for the Claude connector (OAuth 2.1 with PKCE and dynamic client registration, as Claude expects).
 *   GET  /.well-known/oauth-protected-resource[/mcp]   which sign-in service protects /mcp
 *   GET  /.well-known/oauth-authorization-server       where to register, approve and get tokens
 *   POST /oauth/register     Claude registers itself (gets a client id)
 *   GET  /oauth/authorize    the approval page: you type your connector password (KEEL_MCP_TOKEN) to say yes
 *   POST /oauth/authorize    checks it and sends Claude back with a one-time code
 *   POST /oauth/token        code (or refresh token) → access token for /mcp
 * Access tokens last 1 hour and renew themselves; refresh tokens last 90 days. Turning access off:
 * change KEEL_MCP_TOKEN in Cloudflare (old approvals stop at their next renewal).
 */
type Client = { redirect_uris: string[]; name: string; at: number };
type Grant = { client_id: string; redirect_uri: string; challenge: string; gen: string };

const rid = (n = 24) => Array.from(crypto.getRandomValues(new Uint8Array(n)), (b) => b.toString(16).padStart(2, "0")).join("");
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
const cors = { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, content-type, mcp-protocol-version", "access-control-allow-methods": "GET, POST, OPTIONS" };
const j = (o: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json", "cache-control": "no-store", ...cors, ...extra } });

/** Changes whenever KEEL_MCP_TOKEN changes, so changing it revokes every earlier approval. */
async function generation(env: Env): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode("keel-mcp:" + (env.KEEL_MCP_TOKEN ?? "")));
  return Array.from(new Uint8Array(d).slice(0, 8), (b) => b.toString(16).padStart(2, "0")).join("");
}

async function s256(verifier: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  return btoa(String.fromCharCode(...new Uint8Array(d))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** True when the bearer is an access token Claude got by signing in. */
export async function isMcpAccess(bearer: string | undefined, env: Env): Promise<boolean> {
  if (!bearer || !bearer.startsWith("kat_")) return false;
  const gen = await env.KEEL.get(`oauth:at:${bearer}`);
  return gen !== null && gen === (await generation(env));
}

/** The 401 that tells Claude where to sign in. */
export function mcpUnauthorized(url: URL): Response {
  return j({ error: "unauthorized" }, 401, {
    "www-authenticate": `Bearer resource_metadata="${url.origin}/.well-known/oauth-protected-resource"`,
  });
}

export async function handleOAuth(req: Request, env: Env, url: URL): Promise<Response | null> {
  const p = url.pathname;
  const origin = url.origin;
  if (req.method === "OPTIONS" && (p.startsWith("/.well-known/") || p.startsWith("/oauth/") || p === "/mcp")) {
    return new Response(null, { status: 204, headers: cors });
  }

  if (p === "/.well-known/oauth-protected-resource" || p === "/.well-known/oauth-protected-resource/mcp") {
    return j({ resource: `${origin}/mcp`, authorization_servers: [origin], bearer_methods_supported: ["header"], resource_name: "Keel" });
  }
  if (p === "/.well-known/oauth-authorization-server" || p === "/.well-known/openid-configuration") {
    return j({
      issuer: origin,
      authorization_endpoint: `${origin}/oauth/authorize`,
      token_endpoint: `${origin}/oauth/token`,
      registration_endpoint: `${origin}/oauth/register`,
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none", "client_secret_post", "client_secret_basic"],
      scopes_supported: ["keel"],
    });
  }

  if (p === "/oauth/register" && req.method === "POST") {
    const b = (await req.json().catch(() => ({}))) as { redirect_uris?: string[]; client_name?: string };
    const uris = (b.redirect_uris ?? []).filter((u) => /^https:\/\//.test(u) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?\//.test(u)).slice(0, 10);
    if (!uris.length) return j({ error: "invalid_redirect_uri", error_description: "Give at least one https redirect_uri." }, 400);
    const id = "kc_" + rid(12);
    const client: Client = { redirect_uris: uris, name: (b.client_name ?? "Claude").slice(0, 80), at: Date.now() };
    await env.KEEL.put(`oauth:client:${id}`, JSON.stringify(client), { expirationTtl: 365 * 86_400 });
    return j({ client_id: id, client_id_issued_at: Math.floor(Date.now() / 1000), redirect_uris: uris, client_name: client.name,
               token_endpoint_auth_method: "none", grant_types: ["authorization_code", "refresh_token"], response_types: ["code"] }, 201);
  }

  if (p === "/oauth/authorize") {
    const q = req.method === "POST" ? new URLSearchParams(await req.text()) : url.searchParams;
    const clientId = q.get("client_id") ?? "", redirect = q.get("redirect_uri") ?? "", state = q.get("state") ?? "";
    const challenge = q.get("code_challenge") ?? "", method = q.get("code_challenge_method") ?? "S256";
    const raw = await env.KEEL.get(`oauth:client:${clientId}`);
    const client = raw ? (JSON.parse(raw) as Client) : null;
    if (!client || !client.redirect_uris.includes(redirect)) return page("Can't connect", `<p>This sign-in link isn't valid. Start again from the app that sent you here.</p>`, 400);
    if (!challenge || method !== "S256") return page("Can't connect", `<p>This app didn't send a secure sign-in request (PKCE S256).</p>`, 400);
    if (!env.KEEL_MCP_TOKEN) return page("Not set up yet", `<p>Add a <b>KEEL_MCP_TOKEN</b> secret to your Keel server in Cloudflare first, then try again.</p>`, 503);

    const hidden = (["client_id", "redirect_uri", "state", "code_challenge", "code_challenge_method", "scope", "resource"] as const)
      .map((k) => `<input type="hidden" name="${k}" value="${esc(q.get(k) ?? "")}">`).join("");
    const form = (err = "") => page("Connect Keel", `
      <h1>Connect ${esc(client.name)} to Keel?</h1>
      <p>It will be able to read your tasks, today's plan, notes and promises, and add tasks or suggest a focus session.</p>
      ${err ? `<p class="err">${err}</p>` : ""}
      <form method="post">${hidden}
        <label>Your Keel connector password<input name="password" type="password" autocomplete="current-password" required autofocus></label>
        <p class="muted">It's the KEEL_MCP_TOKEN you saved in Cloudflare (keel-backend → Settings → Variables and Secrets).</p>
        <button type="submit" name="decision" value="allow">Allow</button>
        <button type="submit" name="decision" value="deny" class="secondary" formnovalidate>Cancel</button>
      </form>`);

    if (req.method === "GET") return form();

    const back = new URL(redirect);
    if (q.get("decision") !== "allow") {
      back.searchParams.set("error", "access_denied");
      if (state) back.searchParams.set("state", state);
      return Response.redirect(back.toString(), 302);
    }
    // A few wrong guesses an hour at most.
    const ip = req.headers.get("cf-connecting-ip") ?? "x";
    const tries = Number((await env.KEEL.get(`oauth:tries:${ip}`)) ?? 0);
    if (tries >= 8) return form("Too many tries. Wait an hour and try again.");
    if ((q.get("password") ?? "") !== env.KEEL_MCP_TOKEN) {
      await env.KEEL.put(`oauth:tries:${ip}`, String(tries + 1), { expirationTtl: 3600 });
      return form("That password doesn't match. Check KEEL_MCP_TOKEN in Cloudflare.");
    }
    const code = "kcode_" + rid();
    const grant: Grant = { client_id: clientId, redirect_uri: redirect, challenge, gen: await generation(env) };
    await env.KEEL.put(`oauth:code:${code}`, JSON.stringify(grant), { expirationTtl: 300 });
    back.searchParams.set("code", code);
    if (state) back.searchParams.set("state", state);
    return Response.redirect(back.toString(), 302);
  }

  if (p === "/oauth/token" && req.method === "POST") {
    const ct = req.headers.get("content-type") ?? "";
    const f = ct.includes("application/json")
      ? new URLSearchParams(Object.entries((await req.json().catch(() => ({}))) as Record<string, string>))
      : new URLSearchParams(await req.text());
    const gen = await generation(env);
    const issue = async (clientId: string) => {
      const access = "kat_" + rid(), refresh = "krt_" + rid();
      await env.KEEL.put(`oauth:at:${access}`, gen, { expirationTtl: 3600 });
      await env.KEEL.put(`oauth:rt:${refresh}`, JSON.stringify({ client_id: clientId, gen }), { expirationTtl: 90 * 86_400 });
      return j({ access_token: access, token_type: "Bearer", expires_in: 3600, refresh_token: refresh, scope: "keel" });
    };

    if (f.get("grant_type") === "authorization_code") {
      const code = f.get("code") ?? "";
      const raw = await env.KEEL.get(`oauth:code:${code}`);
      if (!raw) return j({ error: "invalid_grant" }, 400);
      await env.KEEL.delete(`oauth:code:${code}`);                       // one use only
      const g = JSON.parse(raw) as Grant;
      if (f.get("redirect_uri") && f.get("redirect_uri") !== g.redirect_uri) return j({ error: "invalid_grant" }, 400);
      if (f.get("client_id") && f.get("client_id") !== g.client_id) return j({ error: "invalid_client" }, 400);
      if ((await s256(f.get("code_verifier") ?? "")) !== g.challenge) return j({ error: "invalid_grant", error_description: "PKCE check failed" }, 400);
      if (g.gen !== gen) return j({ error: "invalid_grant" }, 400);
      return issue(g.client_id);
    }
    if (f.get("grant_type") === "refresh_token") {
      const rt = f.get("refresh_token") ?? "";
      const raw = await env.KEEL.get(`oauth:rt:${rt}`);
      if (!raw) return j({ error: "invalid_grant" }, 400);
      const r = JSON.parse(raw) as { client_id: string; gen: string };
      if (r.gen !== gen) { await env.KEEL.delete(`oauth:rt:${rt}`); return j({ error: "invalid_grant" }, 400); }
      await env.KEEL.delete(`oauth:rt:${rt}`);                            // rotate
      return issue(r.client_id);
    }
    return j({ error: "unsupported_grant_type" }, 400);
  }
  return null;
}

function page(title: string, body: string, status = 200): Response {
  return new Response(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title><meta name="robots" content="noindex"><style>
:root{color-scheme:light dark;--a:#5b5bd6}body{font:16px/1.55 -apple-system,system-ui,sans-serif;max-width:480px;margin:0 auto;padding:40px 20px}
h1{font-size:24px}form{display:grid;gap:12px;margin-top:16px}label{display:grid;gap:6px;font-size:14px}
input{font:inherit;padding:12px;border-radius:10px;border:1px solid #8886}.muted{opacity:.6;font-size:13px;margin:0}.err{color:#d33}
button{background:var(--a);color:#fff;border:0;border-radius:12px;padding:12px;font:inherit;font-weight:600}button.secondary{background:transparent;color:inherit;border:1px solid #8886}
</style></head><body>${body}</body></html>`, { status, headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } });
}
