import type { Env } from "./index";
import { json } from "./ai";

/**
 * Sharing without accounts for the other person:
 *   Shared lists   POST /share/list (owner's device) → a link anyone can open in Keel or a browser to check off and add items.
 *                  GET/POST /share/list/:id (anyone with the link; the id is long and random).
 *                  GET /l/:id  the list as a web page.
 *   Published pages POST /publish (owner's device) → GET /p/:id read-only page; DELETE /publish/:id to take it down.
 *   Diagnostics    POST /diagnostics (owner's device): crash and hang reports, kept 30 days.
 */
type Item = { id: string; text: string; done: boolean; by?: string };
type SharedList = { title: string; items: Item[]; comments: { text: string; by: string; at: number }[]; updated: number };

const rid = (n = 16) => Array.from(crypto.getRandomValues(new Uint8Array(n)), (b) => b.toString(16).padStart(2, "0")).join("");
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
const html = (body: string, status = 200) => new Response(body, { status, headers: { "content-type": "text/html; charset=utf-8" } });

export async function handleShare(req: Request, env: Env, url: URL, device: boolean): Promise<Response | null> {
  const p = url.pathname;

  // ---- Shared lists
  if (p === "/share/list" && req.method === "POST") {
    if (!device) return json({ error: "unauthorized" }, 401);
    const body = (await req.json()) as { title?: string; items?: Item[] };
    const id = rid();
    const list: SharedList = { title: (body.title ?? "List").slice(0, 120), items: (body.items ?? []).slice(0, 500), comments: [], updated: Date.now() };
    await env.KEEL.put(`list:${id}`, JSON.stringify(list));
    return json({ id, url: `${url.origin}/l/${id}` });
  }
  const m = p.match(/^\/share\/list\/([a-f0-9]{32})$/);
  if (m) {
    const key = `list:${m[1]}`;
    const raw = await env.KEEL.get(key);
    if (!raw) return json({ error: "not found" }, 404);
    const list = JSON.parse(raw) as SharedList;
    if (req.method === "GET") return json(list);
    if (req.method === "POST") {
      const op = (await req.json()) as { op: string; id?: string; text?: string; by?: string; items?: Item[]; title?: string };
      const by = (op.by ?? "Someone").slice(0, 40);
      if (op.op === "toggle") list.items = list.items.map((i) => (i.id === op.id ? { ...i, done: !i.done } : i));
      else if (op.op === "add" && op.text) list.items.push({ id: rid(6), text: op.text.slice(0, 300), done: false, by });
      else if (op.op === "remove") list.items = list.items.filter((i) => i.id !== op.id);
      else if (op.op === "comment" && op.text) list.comments.push({ text: op.text.slice(0, 500), by, at: Date.now() });
      else if (op.op === "replace" && device && op.items) { list.items = op.items.slice(0, 500); if (op.title) list.title = op.title.slice(0, 120); }
      else if (op.op === "delete" && device) { await env.KEEL.delete(key); return json({ ok: true }); }
      list.comments = list.comments.slice(-100);
      list.updated = Date.now();
      await env.KEEL.put(key, JSON.stringify(list));
      return json(list);
    }
  }
  const lm = p.match(/^\/l\/([a-f0-9]{32})$/);
  if (lm && req.method === "GET") return html(listPage(lm[1]));

  // ---- Published pages
  if (p === "/publish" && req.method === "POST") {
    if (!device) return json({ error: "unauthorized" }, 401);
    const body = (await req.json()) as { title?: string; html?: string; id?: string };
    const id = body.id && /^[a-f0-9]{24}$/.test(body.id) ? body.id : rid(12);
    await env.KEEL.put(`page:${id}`, JSON.stringify({ title: (body.title ?? "Page").slice(0, 200), html: (body.html ?? "").slice(0, 400_000), at: Date.now() }));
    return json({ id, url: `${url.origin}/p/${id}` });
  }
  const dm = p.match(/^\/publish\/([a-f0-9]{24})$/);
  if (dm && req.method === "DELETE") {
    if (!device) return json({ error: "unauthorized" }, 401);
    await env.KEEL.delete(`page:${dm[1]}`);
    return json({ ok: true });
  }
  const pm = p.match(/^\/p\/([a-f0-9]{24})$/);
  if (pm && req.method === "GET") {
    const raw = await env.KEEL.get(`page:${pm[1]}`);
    if (!raw) return html(shell("Not found", "<p>This page isn't published anymore.</p>"), 404);
    const page = JSON.parse(raw) as { title: string; html: string };
    return html(shell(esc(page.title), `<h1>${esc(page.title)}</h1>${page.html}`));
  }

  // ---- Diagnostics
  if (p === "/diagnostics" && req.method === "POST") {
    if (!device) return json({ error: "unauthorized" }, 401);
    const text = (await req.text()).slice(0, 200_000);
    await env.KEEL.put(`diag:${Date.now()}`, text, { expirationTtl: 30 * 86_400 });
    return json({ ok: true });
  }
  return null;
}

function shell(title: string, body: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title><style>
:root{color-scheme:light dark}body{font:17px/1.55 -apple-system,system-ui,sans-serif;max-width:720px;margin:0 auto;padding:28px 20px 60px}
h1{font-size:30px;line-height:1.2}img{max-width:100%;border-radius:10px}blockquote{border-left:3px solid #8884;margin:0;padding-left:14px;color:#888}
table{border-collapse:collapse}td,th{border:1px solid #8884;padding:6px 10px}.foot{margin-top:40px;color:#888;font-size:13px}
.item{display:flex;gap:10px;align-items:center;padding:10px 0;border-bottom:1px solid #8882}.item.done span{text-decoration:line-through;color:#888}
input[type=text]{flex:1;font:inherit;padding:10px;border-radius:10px;border:1px solid #8885;background:transparent}button{font:inherit;padding:10px 14px;border-radius:10px;border:0;background:#5b6bfa;color:#fff}
</style></head><body>${body}<p class="foot">Shared from Keel</p></body></html>`;
}

function listPage(id: string): string {
  return shell("Shared list", `<h1 id="t">Shared list</h1><div id="items"></div>
<form id="f" style="display:flex;gap:8px;margin-top:16px"><input type="text" id="new" placeholder="Add an item"><button>Add</button></form>
<script>
const api="/share/list/${id}";
const who=localStorage.getItem("keel.name")||"";
async function load(){const r=await fetch(api);if(!r.ok){document.body.innerHTML="<p>This list isn't shared anymore.</p>";return}render(await r.json())}
function render(l){document.getElementById("t").textContent=l.title;const box=document.getElementById("items");box.innerHTML="";
for(const i of l.items){const d=document.createElement("label");d.className="item"+(i.done?" done":"");const c=document.createElement("input");c.type="checkbox";c.checked=i.done;
c.onchange=()=>post({op:"toggle",id:i.id});const s=document.createElement("span");s.textContent=i.text;d.append(c,s);box.append(d)}}
async function post(b){b.by=who||"Someone";const r=await fetch(api,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify(b)});render(await r.json())}
document.getElementById("f").onsubmit=e=>{e.preventDefault();const v=document.getElementById("new").value.trim();if(v){post({op:"add",text:v});document.getElementById("new").value=""}};
load();setInterval(load,15000);
</script>`);
}
