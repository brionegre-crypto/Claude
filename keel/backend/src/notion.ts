import type { Env } from "./index";
import { json } from "./ai";

/**
 * "Sign in with Notion" for Keel.
 *
 * Notion's OAuth needs a client secret, which can't live inside an app. This server holds it, swaps
 * the one-time code for an access token, and hands the token to the app through a short-lived,
 * single-use handoff (never in a URL):
 *
 *   1. App opens   GET  /notion/start?state=<random 64 hex>        → redirects to Notion's consent screen
 *   2. Notion calls GET  /notion/callback?code&state                 → token exchanged, parked for 5 minutes
 *                                                                     → redirects to com.keel.app://notion-connected?state=…
 *   3. App calls   POST /notion/redeem {state}                       → gets the token once; it's deleted here
 *   (POST /notion/refresh {refresh_token} renews a token if Notion issued a refresh token.)
 *
 * The app generates `state` itself and keeps it secret, so only the phone that started sign-in can redeem.
 * Tokens are never logged or kept beyond the 5-minute handoff.
 */

const NOTION = "https://api.notion.com/v1";
const APP_RETURN = "com.keel.app://notion-connected";
const STATE_RE = /^[0-9a-f]{64}$/;

export function notionConfigured(env: Env): boolean {
  return !!env.NOTION_CLIENT_ID && !!env.NOTION_CLIENT_SECRET;
}

export function callbackURL(req: Request): string {
  return new URL("/notion/callback", req.url).toString();
}

export async function handleNotion(req: Request, env: Env): Promise<Response> {
  const url = new URL(req.url);

  if (url.pathname === "/notion/start" && req.method === "GET") {
    const state = url.searchParams.get("state") ?? "";
    if (!STATE_RE.test(state)) return page("That sign-in link isn't valid. Go back to Keel and try again.", 400);
    if (!notionConfigured(env)) return page("Notion sign-in isn't set up on this server yet. In Keel, use an integration secret instead, or finish the server setup.", 503);
    const auth = new URL("https://api.notion.com/v1/oauth/authorize");
    auth.searchParams.set("client_id", env.NOTION_CLIENT_ID);
    auth.searchParams.set("response_type", "code");
    auth.searchParams.set("owner", "user");
    auth.searchParams.set("redirect_uri", callbackURL(req));
    auth.searchParams.set("state", state);
    return Response.redirect(auth.toString(), 302);
  }

  if (url.pathname === "/notion/callback" && req.method === "GET") {
    const state = url.searchParams.get("state") ?? "";
    const code = url.searchParams.get("code");
    const error = url.searchParams.get("error");
    if (!STATE_RE.test(state)) return page("This sign-in can't be matched to Keel. Try again from the app.", 400);
    if (error || !code) return Response.redirect(`${APP_RETURN}?state=${state}&error=${encodeURIComponent(error ?? "cancelled")}`, 302);

    const res = await fetch(`${NOTION}/oauth/token`, {
      method: "POST",
      headers: {
        "Authorization": "Basic " + btoa(`${env.NOTION_CLIENT_ID}:${env.NOTION_CLIENT_SECRET}`),
        "Content-Type": "application/json",
        "Notion-Version": "2022-06-28",
      },
      body: JSON.stringify({ grant_type: "authorization_code", code, redirect_uri: callbackURL(req) }),
    });
    const data = (await res.json().catch(() => ({}))) as Record<string, unknown>;
    if (!res.ok || typeof data.access_token !== "string") {
      const why = typeof data.error === "string" ? data.error : `exchange_failed_${res.status}`;
      return Response.redirect(`${APP_RETURN}?state=${state}&error=${encodeURIComponent(why)}`, 302);
    }
    const handoff = {
      access_token: data.access_token,
      refresh_token: typeof data.refresh_token === "string" ? data.refresh_token : null,
      workspace_name: typeof data.workspace_name === "string" ? data.workspace_name : null,
      workspace_icon: typeof data.workspace_icon === "string" ? data.workspace_icon : null,
      workspace_id: typeof data.workspace_id === "string" ? data.workspace_id : null,
    };
    await env.KEEL.put(`notion:handoff:${state}`, JSON.stringify(handoff), { expirationTtl: 300 });
    return Response.redirect(`${APP_RETURN}?state=${state}`, 302);
  }

  if (url.pathname === "/notion/redeem" && req.method === "POST") {
    const body = (await req.json().catch(() => ({}))) as { state?: string };
    const state = body.state ?? "";
    if (!STATE_RE.test(state)) return json({ error: "invalid_state" }, 400);
    const key = `notion:handoff:${state}`;
    const stored = await env.KEEL.get(key);
    if (!stored) return json({ error: "expired" }, 404);
    await env.KEEL.delete(key);                       // single use
    return new Response(stored, { headers: { "content-type": "application/json", "cache-control": "no-store" } });
  }

  if (url.pathname === "/notion/refresh" && req.method === "POST") {
    if (!notionConfigured(env)) return json({ error: "not_configured" }, 503);
    const body = (await req.json().catch(() => ({}))) as { refresh_token?: string };
    if (!body.refresh_token) return json({ error: "missing_refresh_token" }, 400);
    const res = await fetch(`${NOTION}/oauth/token`, {
      method: "POST",
      headers: {
        "Authorization": "Basic " + btoa(`${env.NOTION_CLIENT_ID}:${env.NOTION_CLIENT_SECRET}`),
        "Content-Type": "application/json",
        "Notion-Version": "2022-06-28",
      },
      body: JSON.stringify({ grant_type: "refresh_token", refresh_token: body.refresh_token }),
    });
    const data = await res.json().catch(() => ({}));
    return json(data, res.ok ? 200 : 400);
  }

  return json({ error: "not found" }, 404);
}

// MARK: - Pages Notion asks public integrations for

export function infoPage(req: Request, env: Env): Response {
  const cb = callbackURL(req);
  const ready = notionConfigured(env);
  return html(`
    <h1>Keel server</h1>
    <p class="ok">✓ Running</p>
    <h2>Notion sign-in</h2>
    <p>${ready ? '<span class="ok">✓ Ready.</span> In Keel: Move to Keel → Notion → Sign in with Notion.'
                : '<span class="warn">Not set up yet.</span> Create a public integration in Notion and add its keys (see below).'}</p>
    <p>Redirect URI to paste into Notion:</p>
    <pre>${cb}</pre>
    <p>Privacy policy URL: <code>${new URL("/privacy", req.url)}</code><br>
       Terms of use URL: <code>${new URL("/terms", req.url)}</code></p>
    <h2>Server address for the app</h2>
    <pre>${new URL("/", req.url).origin}</pre>`);
}

export function privacyPage(): Response {
  return html(`
    <h1>Keel privacy policy</h1>
    <p>Keel is a personal productivity app. When you connect Notion, Keel reads the pages and databases you choose to share,
    only to copy them into Keel on your iPhone.</p>
    <ul>
      <li>Your Notion content is downloaded directly to your iPhone and stored there. This server never stores your pages.</li>
      <li>This server only exchanges the one-time sign-in code for an access token and passes it to your iPhone within five minutes. It keeps nothing afterwards.</li>
      <li>The access token is stored in your iPhone's Keychain. You can disconnect at any time in Notion (Settings → Connections) or in Keel.</li>
      <li>Keel doesn't sell, share or use your data for advertising.</li>
    </ul>`);
}

export function termsPage(): Response {
  return html(`
    <h1>Keel terms of use</h1>
    <p>Keel's Notion import copies content you choose into the Keel app on your device. Use it only with workspaces you're allowed to export.
    The service is provided as is, without warranty. You can stop using it at any time by disconnecting Keel in Notion.</p>`);
}

function page(message: string, status = 200): Response {
  return html(`<h1>Keel</h1><p>${message}</p>`, status);
}

function html(body: string, status = 200): Response {
  return new Response(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Keel</title><style>
body{font:17px -apple-system,system-ui,sans-serif;max-width:640px;margin:40px auto;padding:0 20px;color:#1d1d1f;line-height:1.5}
pre,code{background:#f2f2f7;border-radius:8px;padding:2px 6px;word-break:break-all;white-space:pre-wrap}
pre{padding:12px}.ok{color:#1a7f37}.warn{color:#b26a00}h1{font-size:28px}
@media(prefers-color-scheme:dark){body{background:#000;color:#f5f5f7}pre,code{background:#1c1c1e}}
</style></head><body>${body}</body></html>`, { status, headers: { "content-type": "text/html; charset=utf-8" } });
}
