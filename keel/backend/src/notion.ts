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
    <p>Keel is a personal productivity app for iPhone, iPad, Mac and Apple Watch. It's built so your information stays with you.
    Keel doesn't sell your data, show ads, or track you across apps and websites.</p>

    <h2>On your devices and in your iCloud</h2>
    <p>Your tasks, notes, habits, calendar, health and nutrition entries, and settings are stored on your devices. If you turn on iCloud sync,
    they're also kept in your own private iCloud, which only you can read. Email is downloaded by each device directly from your
    mail provider (Gmail, Outlook, iCloud or another) and stays on that device. Passwords, AI keys and mail sign-ins are kept in your iCloud Keychain.</p>

    <h2>AI</h2>
    <ul>
      <li><b>Apple Intelligence</b> runs on your device; nothing is sent anywhere.</li>
      <li>If you add <b>your own Claude, ChatGPT or Gemini key</b>, the text you ask about goes from your device straight to that company (Anthropic, OpenAI or Google) under their terms. Keel's server isn't involved.</li>
      <li>Features that use <b>your Keel server's Claude</b> (such as meeting notes) send the text to Anthropic through the server. The server keeps only a daily count of requests, not the text.</li>
      <li>Private mode keeps everything on your device.</li>
    </ul>

    <h2>What Keel's server keeps, and when</h2>
    <ul>
      <li><b>Sign in with Apple</b>: an anonymous Apple ID number (and the name and email Apple shares, if any) so your devices stay signed in.</li>
      <li><b>Things you choose to share</b>: shared lists, published pages and shared spaces, until you remove them.</li>
      <li><b>Booking link</b>: the open times your device works out (never your events), and, for each booking, the person's name, email and note until your device picks it up.</li>
      <li><b>Instant mail alerts</b>: your device's push address. Gmail and Outlook only tell the server "new mail arrived"; no email content reaches it.</li>
      <li><b>Claude connector</b> (only if you connect it): a short summary of your day, tasks, notes and promises, so Claude can read it after you approve the connection. Tasks Claude adds wait there until your device picks them up.</li>
      <li><b>Notion import</b>: the one-time sign-in code is exchanged for an access token and handed to your device within five minutes; nothing else is kept. Your pages go straight to your device.</li>
      <li><b>Crash reports</b>: only if you turn on Share crash reports; they describe what code was running, never your content, and are deleted after 30 days.</li>
      <li><b>Support messages</b> you send from the support page, with your email if you give it, for 90 days.</li>
    </ul>

    <h2>Your choices</h2>
    <ul>
      <li><b>Delete your account</b>: Settings → Account → Delete Account removes your sign-ins and everything above that belongs to you (connector summary, booking page and bookings, push addresses, connector access, crash reports). Shared lists and spaces stay for the people you shared them with until you remove them.</li>
      <li>Disconnect Notion at any time in Notion (Settings → Connections) or in Keel; disconnect Claude in Claude's connector settings.</li>
      <li>Questions: <a href="/support">keel support</a>.</li>
    </ul>`);
}

export function termsPage(): Response {
  return html(`
    <h1>Keel terms of use</h1>
    <p>Keel helps you organize your own email, calendar, tasks and notes. Use it only with accounts and content you're allowed to use.
    Features that call AI services use your own keys or your own Keel server, and those services' terms apply.
    Keel is provided as is, without warranty. You can stop using it at any time and delete your account in Settings.</p>`);
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
