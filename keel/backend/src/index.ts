import { handleAI, json } from "./ai";
import { handleMCP } from "./mcp";
import { handleNotion, infoPage, privacyPage, termsPage } from "./notion";
import { handleAppleAuth, isSession } from "./auth";
import { handleShare } from "./share";

export interface Env {
  KEEL: KVNamespace;
  ANTHROPIC_API_KEY: string;
  KEEL_DEVICE_TOKEN: string;
  KEEL_MCP_TOKEN: string;
  DAILY_AI_LIMIT: string;
  NOTION_CLIENT_ID: string;      // public integration (Sign in with Notion)
  NOTION_CLIENT_SECRET: string;
  OWNER_APPLE_SUB?: string;      // optional: pin the owner's Apple account (otherwise the first sign-in claims it)
}

/**
 * Keel light backend (Cloudflare Worker — free tier covers personal use).
 *   GET  /health        Checks the device access code (no AI call).                       [device token]
 *   POST /v1/messages   AI proxy: holds the Claude key, routes model/effort, enforces a daily cap.   [device token]
 *   POST /snapshot      iPhone uploads a small JSON snapshot for the Claude connector.            [device token]
 *   GET  /actions       iPhone pulls actions Claude queued (add_task, start_focus), then clears. [device token]
 *   POST /mcp           Remote MCP server for Claude / Claude Duet custom connectors.             [MCP token]
 *   POST /push/gmail    Gmail Pub/Sub push → silent APNs to wake the app.        (TODO: APNs key)
 *   POST /push/graph    Microsoft Graph change notifications → silent APNs.      (TODO: APNs key)
 *   GET  /              Status page: what's set up, and the Notion redirect URI to copy.          [public]
 *   GET  /privacy /terms Pages Notion asks public integrations to link to.                       [public]
 *   /notion/start, /notion/callback, /notion/redeem, /notion/refresh   Sign in with Notion.     [public, see notion.ts]
 */
export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    const bearer = req.headers.get("authorization")?.replace(/^Bearer /, "");
    // Never match when a secret is unset (undefined === undefined would otherwise let anyone in).
    const device = (!!env.KEEL_DEVICE_TOKEN && bearer === env.KEEL_DEVICE_TOKEN) || (await isSession(bearer, env));
    const mcp = !!env.KEEL_MCP_TOKEN && bearer === env.KEEL_MCP_TOKEN;

    if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/setup")) return infoPage(req, env);
    if (req.method === "GET" && url.pathname === "/privacy") return privacyPage();
    if (req.method === "GET" && url.pathname === "/terms") return termsPage();
    if (url.pathname.startsWith("/notion/")) return handleNotion(req, env);
    if (url.pathname === "/auth/apple" && req.method === "POST") return handleAppleAuth(req, env);
    if (/^\/(share|l|publish|p|diagnostics)(\/|$)/.test(url.pathname)) {
      const r = await handleShare(req, env, url, device);
      if (r) return r;
    }

    // Lets the app check its access code without spending AI credits.
    if (url.pathname === "/health") {
      return device ? json({ ok: true }) : unauthorized();
    }
    if (url.pathname === "/v1/messages" && req.method === "POST") {
      return device ? handleAI(req, env) : unauthorized();
    }
    if (url.pathname === "/snapshot" && req.method === "POST") {
      if (!device) return unauthorized();
      await env.KEEL.put("snapshot", await req.text());
      return json({ ok: true });
    }
    if (url.pathname === "/actions" && req.method === "GET") {
      if (!device) return unauthorized();
      const actions = (await env.KEEL.get("actions")) ?? "[]";
      await env.KEEL.put("actions", "[]");
      return new Response(actions, { headers: { "content-type": "application/json" } });
    }
    if (url.pathname === "/mcp" && req.method === "POST") {
      return mcp ? handleMCP(req, env) : unauthorized();
    }
    if (url.pathname === "/push/gmail" || url.pathname === "/push/graph") {
      // Graph validation handshake: echo validationToken.
      const v = url.searchParams.get("validationToken");
      if (v) return new Response(v, { headers: { "content-type": "text/plain" } });
      // TODO: send a silent APNs push (content-available: 1) to the device so it runs SyncEngine.syncAll().
      // Requires an APNs auth key (.p8) from developer.apple.com stored as a secret, and the device token.
      return new Response(null, { status: 202 });
    }
    return json({ error: "not found" }, 404);
  },
};

const unauthorized = () => json({ error: "unauthorized" }, 401);
