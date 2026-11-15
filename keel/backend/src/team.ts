import type { Env } from "./index";
import { json } from "./ai";

/**
 * Team boards: shared task boards for a team or family.
 *   POST /team                    create a board (owner's device)            → { id, url }
 *   GET  /team/:id                the board: members, tasks, recent activity (anyone with the link)
 *   POST /team/:id                one change: join, add, update, move, assign, comment, remove, rename
 *   GET  /t/:id                   the board as a web page, for teammates without Keel
 *
 * The 32-character random id is the invitation: anyone with the link can join. Each change is logged in the
 * activity feed, and @mentions in comments are recorded so the mentioned person's Keel can tell them.
 */

export type TeamTask = {
  id: string;
  title: string;
  notes: string;
  status: "todo" | "doing" | "done";
  assignee: string;
  due: string;
  createdBy: string;
  created: number;
  updated: number;
  comments: { id: string; by: string; text: string; at: number; mentions: string[] }[];
};
export type TeamActivity = { at: number; by: string; text: string; task?: string; for?: string[] };
export type TeamBoard = { name: string; owner: string; members: string[]; tasks: TeamTask[]; activity: TeamActivity[]; version: number; updated: number };

const rid = (n = 16) => Array.from(crypto.getRandomValues(new Uint8Array(n)), (b) => b.toString(16).padStart(2, "0")).join("");
const clip = (s: unknown, n: number) => String(s ?? "").slice(0, n);

/** Names mentioned as @First or @"First Last" that match a member, case-insensitive. */
export function mentions(text: string, members: string[]): string[] {
  const out = new Set<string>();
  const lower = text.toLowerCase();
  for (const m of members) {
    const full = "@" + m.toLowerCase();
    const first = "@" + m.split(" ")[0].toLowerCase();
    if (lower.includes(full) || new RegExp(first.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "(?![a-z])").test(lower)) out.add(m);
  }
  return [...out];
}

/** Applies one change to a board. Returns an error message, or null when it worked. */
export function apply(board: TeamBoard, op: Record<string, unknown>): string | null {
  const by = clip(op.by || "Someone", 40);
  const log = (text: string, task?: string, forWhom?: string[]) => {
    board.activity.push({ at: Date.now(), by, text: clip(text, 300), task, for: forWhom && forWhom.length ? forWhom : undefined });
    board.activity = board.activity.slice(-300);
  };
  const find = () => board.tasks.find((t) => t.id === op.id);
  if (by !== "Someone" && !board.members.includes(by) && board.members.length < 100) board.members.push(by);
  switch (op.op) {
    case "join":
      log("joined the board");
      return null;
    case "rename":
      board.name = clip(op.name, 80) || board.name;
      log(`renamed the board to ${board.name}`);
      return null;
    case "add": {
      const title = clip(op.title, 300).trim();
      if (!title) return "A task needs a title.";
      if (board.tasks.length >= 1000) return "This board is full.";
      const t: TeamTask = {
        id: rid(8), title, notes: clip(op.notes, 4000), status: "todo", assignee: clip(op.assignee, 40), due: clip(op.due, 30),
        createdBy: by, created: Date.now(), updated: Date.now(), comments: [],
      };
      if (t.assignee && !board.members.includes(t.assignee)) board.members.push(t.assignee);
      board.tasks.push(t);
      log(`added “${t.title}”${t.assignee ? ` for ${t.assignee}` : ""}`, t.id, t.assignee && t.assignee !== by ? [t.assignee] : undefined);
      return null;
    }
    case "update": {
      const t = find();
      if (!t) return "That task is gone.";
      const changes: string[] = [];
      if (typeof op.title === "string" && op.title.trim() && op.title !== t.title) { t.title = clip(op.title, 300); changes.push("renamed it"); }
      if (typeof op.notes === "string" && op.notes !== t.notes) { t.notes = clip(op.notes, 4000); changes.push("edited the notes"); }
      if (typeof op.due === "string" && op.due !== t.due) { t.due = clip(op.due, 30); changes.push(t.due ? `set it due ${t.due.slice(0, 10)}` : "cleared the due date"); }
      let notify: string[] | undefined;
      if (typeof op.assignee === "string" && op.assignee !== t.assignee) {
        t.assignee = clip(op.assignee, 40);
        if (t.assignee && !board.members.includes(t.assignee)) board.members.push(t.assignee);
        changes.push(t.assignee ? `assigned it to ${t.assignee}` : "unassigned it");
        if (t.assignee && t.assignee !== by) notify = [t.assignee];
      }
      if (op.status === "todo" || op.status === "doing" || op.status === "done") {
        if (op.status !== t.status) {
          t.status = op.status;
          changes.push(op.status === "done" ? "finished it" : op.status === "doing" ? "started it" : "moved it back to To do");
          if (op.status === "done" && t.createdBy && t.createdBy !== by) notify = [...(notify ?? []), t.createdBy];
        }
      }
      if (!changes.length) return null;
      t.updated = Date.now();
      log(`${changes.join(", ")}: “${t.title}”`, t.id, notify);
      return null;
    }
    case "comment": {
      const t = find();
      if (!t) return "That task is gone.";
      const text = clip(op.text, 2000).trim();
      if (!text) return "Empty comment.";
      const who = mentions(text, board.members).filter((m) => m !== by);
      t.comments.push({ id: rid(6), by, text, at: Date.now(), mentions: who });
      t.comments = t.comments.slice(-200);
      t.updated = Date.now();
      const watchers = [t.assignee, t.createdBy].filter((n) => n && n !== by && !who.includes(n));
      log(`commented on “${t.title}”: ${text.slice(0, 120)}`, t.id, [...who, ...watchers]);
      return null;
    }
    case "remove": {
      const t = find();
      if (!t) return null;
      board.tasks = board.tasks.filter((x) => x.id !== t.id);
      log(`deleted “${t.title}”`);
      return null;
    }
    case "leave":
      board.members = board.members.filter((m) => m !== by);
      log("left the board");
      return null;
    default:
      return "Unknown change.";
  }
}

export async function handleTeam(req: Request, env: Env, url: URL, device: boolean): Promise<Response | null> {
  const p = url.pathname;
  if (p === "/team" && req.method === "POST") {
    if (!device) return json({ error: "unauthorized" }, 401);
    const b = (await req.json()) as { name?: string; by?: string };
    const id = rid();
    const owner = clip(b.by || "Owner", 40);
    const board: TeamBoard = { name: clip(b.name, 80) || "Team", owner, members: [owner], tasks: [], activity: [], version: 1, updated: Date.now() };
    board.activity.push({ at: Date.now(), by: owner, text: `created the board` });
    await env.KEEL.put(`team:${id}`, JSON.stringify(board));
    return json({ id, url: `${url.origin}/t/${id}` });
  }
  const m = p.match(/^\/team\/([a-f0-9]{32})$/);
  if (m) {
    const key = `team:${m[1]}`;
    const raw = await env.KEEL.get(key);
    if (!raw) return json({ error: "not found" }, 404);
    const board = JSON.parse(raw) as TeamBoard;
    if (req.method === "GET") return json(board);
    if (req.method === "POST") {
      const op = (await req.json()) as Record<string, unknown>;
      if (op.op === "delete") {
        if (!device || op.by !== board.owner) return json({ error: "Only the owner can delete the board." }, 403);
        await env.KEEL.delete(key);
        return json({ ok: true });
      }
      const err = apply(board, op);
      if (err) return json({ error: err }, 400);
      board.version += 1;
      board.updated = Date.now();
      await env.KEEL.put(key, JSON.stringify(board));
      return json(board);
    }
  }
  const wm = p.match(/^\/t\/([a-f0-9]{32})$/);
  if (wm && req.method === "GET") return new Response(boardPage(wm[1]), { headers: { "content-type": "text/html; charset=utf-8" } });
  return null;
}

function boardPage(id: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Team board</title><style>
:root{color-scheme:light dark}body{font:16px/1.5 -apple-system,system-ui,sans-serif;margin:0;padding:20px}
h1{font-size:26px;margin:0 0 4px}.sub{color:#888;font-size:13px;margin-bottom:16px}
.cols{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:14px}
.col{background:#8881;border-radius:14px;padding:12px}.col h2{font-size:14px;text-transform:uppercase;letter-spacing:.04em;color:#888;margin:0 0 8px}
.card{background:Canvas;border:1px solid #8883;border-radius:12px;padding:10px;margin-bottom:8px}.card .meta{font-size:12px;color:#888}
.card button{font-size:12px;padding:4px 8px;margin:6px 6px 0 0;border-radius:8px;border:1px solid #8885;background:transparent;color:inherit}
form{display:flex;gap:8px;margin:14px 0;flex-wrap:wrap}input,select{font:inherit;padding:9px;border-radius:10px;border:1px solid #8885;background:transparent;color:inherit}
input[name=title]{flex:1;min-width:180px}.go{background:#5b6bfa;color:#fff;border:0;border-radius:10px;padding:9px 14px;font:inherit}
.feed{margin-top:22px;font-size:14px}.feed div{padding:6px 0;border-bottom:1px solid #8882}.foot{margin-top:30px;color:#888;font-size:12px}
</style></head><body>
<h1 id="name">Team board</h1><div class="sub" id="members"></div>
<form id="me"><input id="who" placeholder="Your name"><button class="go">Save name</button></form>
<form id="add"><input name="title" placeholder="New task"><select name="assignee" id="assignee"><option value="">Anyone</option></select><input name="due" type="date"><button class="go">Add</button></form>
<div class="cols"><div class="col"><h2>To do</h2><div id="todo"></div></div><div class="col"><h2>Doing</h2><div id="doing"></div></div><div class="col"><h2>Done</h2><div id="done"></div></div></div>
<div class="feed"><h2 style="font-size:16px">Activity</h2><div id="feed"></div></div>
<p class="foot">A Keel team board. Anyone with this link can see and edit it.</p>
<script>
const api="/team/${id}";let who=localStorage.getItem("keel.name")||"";document.getElementById("who").value=who;
const esc=s=>String(s).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
async function load(){const r=await fetch(api);if(!r.ok){document.body.innerHTML="<p>This board isn't available.</p>";return}render(await r.json())}
async function post(b){if(!who){alert("Add your name first.");return}b.by=who;const r=await fetch(api,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify(b)});const j=await r.json();if(j.error)alert(j.error);else render(j)}
function render(b){document.getElementById("name").textContent=b.name;document.getElementById("members").textContent=b.members.join(" · ");
const sel=document.getElementById("assignee");const cur=sel.value;sel.innerHTML='<option value="">Anyone</option>'+b.members.map(m=>'<option>'+esc(m)+'</option>').join("");sel.value=cur;
for(const s of ["todo","doing","done"]){const box=document.getElementById(s);box.innerHTML="";
for(const t of b.tasks.filter(t=>t.status===s)){const d=document.createElement("div");d.className="card";
d.innerHTML='<div>'+esc(t.title)+'</div><div class="meta">'+(t.assignee?esc(t.assignee):"Anyone")+(t.due?' · due '+esc(t.due.slice(0,10)):'')+(t.comments.length?' · '+t.comments.length+' comments':'')+'</div>';
const mv=(label,st)=>{const x=document.createElement("button");x.textContent=label;x.onclick=()=>post({op:"update",id:t.id,status:st});d.append(x)};
if(s!=="todo")mv("To do","todo");if(s!=="doing")mv("Doing","doing");if(s!=="done")mv("Done","done");
const c=document.createElement("button");c.textContent="Comment";c.onclick=()=>{const v=prompt("Comment (use @Name to mention)");if(v)post({op:"comment",id:t.id,text:v})};d.append(c);
const a=document.createElement("button");a.textContent="Take it";a.onclick=()=>post({op:"update",id:t.id,assignee:who});d.append(a);box.append(d)}}
document.getElementById("feed").innerHTML=b.activity.slice(-25).reverse().map(a=>'<div><b>'+esc(a.by)+'</b> '+esc(a.text)+' <span style="color:#888">'+new Date(a.at).toLocaleString()+'</span></div>').join("")}
document.getElementById("me").onsubmit=e=>{e.preventDefault();who=document.getElementById("who").value.trim();localStorage.setItem("keel.name",who);if(who)post({op:"join"})};
document.getElementById("add").onsubmit=e=>{e.preventDefault();const f=new FormData(e.target);const title=f.get("title").trim();if(!title)return;post({op:"add",title,assignee:f.get("assignee"),due:f.get("due")});e.target.reset()};
load();setInterval(load,15000);
</script></body></html>`;
}
