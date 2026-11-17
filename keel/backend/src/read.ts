import type { Env } from "./index";
import { json } from "./ai";

/**
 * Read statuses (opt-in, per email): a 1×1 image in an email you send; when it loads, Keel counts an open.
 *   POST /r/new            { id }                  register an email you're about to send     [device]
 *   GET  /r/<id>.gif                               the invisible image (records an open)     [public]
 *   GET  /r/status?ids=a,b                         opens for your emails                     [device]
 * Only registered ids are recorded, nothing about the reader is kept beyond the time and which mail
 * app's image proxy fetched it, and records expire after 90 days.
 */
const GIF = Uint8Array.from(atob("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"), (c) => c.charCodeAt(0));
const TTL = 90 * 86400;
const ID = /^[A-Za-z0-9-]{16,64}$/;

interface Record { created: number; opens: number[]; via: string[] }

function via(ua: string): string {
  if (/GoogleImageProxy/i.test(ua)) return "Gmail";
  if (/YahooMailProxy/i.test(ua)) return "Yahoo";
  if (/Outlook|Microsoft Office/i.test(ua)) return "Outlook";
  if (/iPhone|iPad|Macintosh/i.test(ua)) return "Apple Mail";
  return "Mail app";
}

function pixel(): Response {
  return new Response(GIF, {
    headers: { "content-type": "image/gif", "cache-control": "no-store, no-cache, must-revalidate, max-age=0", pragma: "no-cache" },
  });
}

export async function handleRead(req: Request, env: Env, url: URL, device: boolean): Promise<Response> {
  const path = url.pathname.replace(/^\/r\/?/, "");

  if (path === "new" && req.method === "POST") {
    if (!device) return json({ error: "unauthorized" }, 401);
    const body = (await req.json().catch(() => null)) as { id?: string } | null;
    if (!body?.id || !ID.test(body.id)) return json({ error: "bad id" }, 400);
    const rec: Record = { created: Date.now(), opens: [], via: [] };
    await env.KEEL.put("read:" + body.id, JSON.stringify(rec), { expirationTtl: TTL });
    return json({ ok: true });
  }

  if (path === "status" && req.method === "GET") {
    if (!device) return json({ error: "unauthorized" }, 401);
    const ids = (url.searchParams.get("ids") ?? "").split(",").filter((i) => ID.test(i)).slice(0, 100);
    const out: { [id: string]: { opens: number[]; via: string[] } } = {};
    await Promise.all(ids.map(async (id) => {
      const raw = await env.KEEL.get("read:" + id);
      if (raw) { const r = JSON.parse(raw) as Record; out[id] = { opens: r.opens, via: r.via }; }
    }));
    return json(out);
  }

  const m = path.match(/^([A-Za-z0-9-]{16,64})\.gif$/);
  if (m && req.method === "GET") {
    const key = "read:" + m[1];
    const raw = await env.KEEL.get(key);
    if (raw) {
      const r = JSON.parse(raw) as Record;
      const now = Date.now();
      // The first seconds after sending are the sender's own mail servers scanning it, not the reader.
      const last = r.opens[r.opens.length - 1] ?? 0;
      if (now - r.created > 20_000 && now - last > 60_000 && r.opens.length < 50) {
        r.opens.push(now);
        r.via.push(via(req.headers.get("user-agent") ?? ""));
        await env.KEEL.put(key, JSON.stringify(r), { expirationTtl: TTL });
      }
    }
    return pixel();
  }
  return json({ error: "not found" }, 404);
}
