import { handleAI, json } from "./ai";
import { handleMCP } from "./mcp";

export interface Env {
  KEEL: KVNamespace;
  ANTHROPIC_API_KEY: string;
  KEEL_DEVICE_TOKEN: string;
  KEEL_MCP_TOKEN: string;
  DAILY_AI_LIMIT: string;
}

/**
 * Keel light backend (Cloudflare Worker — free tier covers personal use).
 *   POST /v1/messages   AI proxy: holds the Claude key, routes model/effort, enforces a daily cap.   [device token]
 *   POST /snapshot      iPhone uploads a small JSON snapshot for the Claude connector.            [device token]
 *   GET  /actions       iPhone pulls actions Claude queued (add_task, start_focus), then clears. [device token]
 *   POST /mcp           Remote MCP server for Claude / Claude Duet custom connectors.             [MCP token]
 *   POST /push/gmail    Gmail Pub/Sub push → silent APNs to wake the app.        (TODO: APNs key)
 *   POST /push/graph    Microsoft Graph change notifications → silent APNs.      (TODO: APNs key)
 */
export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    const bearer = req.headers.get("authorization")?.replace(/^Bearer /, "");
    const device = bearer === env.KEEL_DEVICE_TOKEN;

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
      return bearer === env.KEEL_MCP_TOKEN ? handleMCP(req, env) : unauthorized();
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
