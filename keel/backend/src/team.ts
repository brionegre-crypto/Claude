import type { Env } from "./index";
import { json } from "./ai";
import { verifyAppleToken } from "./auth";
import { apnsReady, providerToken } from "./push";

/**
 * Team boards: shared task boards for a team or family.
 *
 * Two kinds:
 *   • Private boards (the default in Keel): members sign in with Apple, join by invitation, and have a role
 *     (owner, admin, member, viewer). Every request is checked against the signed-in member.
 *   • Link boards: anyone with the link can open and edit, in Keel or a browser (no sign-in).
 *
 *   POST   /team/auth             Sign in with Apple for teams → { token, name }        (any Apple Account)
 *   DELETE /team/auth             delete your team account on this server (sessions, push addresses, memberships)
 *   POST   /team/push             register this device for instant team notifications
 *   POST   /team                  create a board (private if signed in; link board from the owner's device)
 *   GET    /team/:id              the board (private: members only)
 *   POST   /team/:id              one change: add, update, comment, remove, chat, event_add, event_remove,
 *                                 invite, set_role, remove_member, rename, leave, delete, join (link boards)
 *   POST   /team/join             accept an invitation { code }                          (signed in)
 *   GET    /join/:code            invitation page (opens Keel)
 *   GET    /t/:id                 link board as a web page
 */

export type Role = "owner" | "admin" | "member" | "viewer";
export type TeamTask = {
  id: string; title: string; notes: string; status: "todo" | "doing" | "done"; assignee: string; due: string;
  createdBy: string; created: number; updated: number;
  comments: { id: string; by: string; text: string; at: number; mentions: string[] }[];
};
export type TeamActivity = { at: number; by: string; text: string; task?: string; for?: string[] };
export type TeamChat = { id: string; by: string; text: string; at: number; mentions: string[] };
export type TeamEvent = { id: string; title: string; start: string; end: string; notes: string; by: string };
export type TeamBoard = {
  name: string; owner: string; members: string[]; tasks: TeamTask[]; activity: TeamActivity[]; version: number; updated: number;
  secure?: boolean; roles?: Record<string, Role>; names?: Record<string, string>; chat?: TeamChat[]; events?: TeamEvent[];
};
type Who = { sub: string; name: string };

const rid = (n = 16) => Array.from(crypto.getRandomValues(new Uint8Array(n)), (b) => b.toString(16).padStart(2, "0")).join("");
const clip = (s: unknown, n: number) => String(s ?? "").slice(0, n);
const rank: Record<Role, number> = { viewer: 0, member: 1, admin: 2, owner: 3 };

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

/** What each role may do. */
export function allowed(role: Role, op: string, isOwnTask = false): boolean {
  switch (op) {
    case "comment": case "chat": case "leave": return true;
    case "add": case "update": case "event_add": case "event_remove": return rank[role] >= rank.member;
    case "remove": return rank[role] >= rank.admin || (role === "member" && isOwnTask);
    case "invite": case "remove_member": case "rename": case "set_role": return rank[role] >= rank.admin;
    case "delete": return role === "owner";
    default: return false;
  }
}

/** Applies one change to a board. Returns an error message, or null when it worked. `by` is the person's name. */
export function apply(board: TeamBoard, op: Record<string, unknown>, by: string): string | null {
  const log = (text: string, task?: string, forWhom?: string[]) => {
    board.activity.push({ at: Date.now(), by, text: clip(text, 300), task, for: forWhom && forWhom.length ? [...new Set(forWhom)] : undefined });
    board.activity = board.activity.slice(-300);
  };
  const find = () => board.tasks.find((t) => t.id === op.id);
  if (!board.secure && by !== "Someone" && !board.members.includes(by) && board.members.length < 100) board.members.push(by);
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
      if (t.assignee && !board.members.includes(t.assignee)) {
        if (board.secure) return "Assign tasks to members of this board.";
        board.members.push(t.assignee);
      }
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
      let notify: string[] = [];
      if (typeof op.assignee === "string" && op.assignee !== t.assignee) {
        const a = clip(op.assignee, 40);
        if (a && !board.members.includes(a)) {
          if (board.secure) return "Assign tasks to members of this board.";
          board.members.push(a);
        }
        t.assignee = a;
        changes.push(a ? `assigned it to ${a}` : "unassigned it");
        if (a && a !== by) notify.push(a);
      }
      if ((op.status === "todo" || op.status === "doing" || op.status === "done") && op.status !== t.status) {
        t.status = op.status;
        changes.push(op.status === "done" ? "finished it" : op.status === "doing" ? "started it" : "moved it back to To do");
        if (op.status === "done" && t.createdBy && t.createdBy !== by) notify.push(t.createdBy);
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
      const watchers = [t.assignee, t.createdBy].filter((n) => n && n !== by);
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
    case "chat": {
      const text = clip(op.text, 2000).trim();
      if (!text) return "Empty message.";
      const who = mentions(text, board.members).filter((m) => m !== by);
      board.chat = [...(board.chat ?? []), { id: rid(6), by, text, at: Date.now(), mentions: who }].slice(-500);
      return null;
    }
    case "event_add": {
      const title = clip(op.title, 200).trim();
      const start = clip(op.start, 40), end = clip(op.end, 40) || start;
      if (!title || !start || isNaN(Date.parse(start))) return "An event needs a title and a start time.";
      const e: TeamEvent = { id: rid(6), title, start, end, notes: clip(op.notes, 2000), by };
      board.events = [...(board.events ?? []), e].sort((a, b) => a.start.localeCompare(b.start)).slice(-500);
      log(`added an event: ${title} (${start.slice(0, 10)})`, undefined, board.members.filter((m) => m !== by));
      return null;
    }
    case "event_remove": {
      const e = (board.events ?? []).find((x) => x.id === op.id);
      if (!e) return null;
      board.events = (board.events ?? []).filter((x) => x.id !== e.id);
      log(`removed the event ${e.title}`);
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

// ---- Sessions

async function whoIs(req: Request, env: Env): Promise<Who | null> {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer /, "") ?? "";
  if (!bearer.startsWith("tm_")) return null;
  const raw = await env.KEEL.get(`tmsession:${bearer}`);
  return raw ? (JSON.parse(raw) as Who) : null;
}

async function pushTo(env: Env, subs: string[], title: string, body: string, boardId: string): Promise<void> {
  if (!apnsReady(env) || !subs.length) return;
  const jwt = await providerToken(env);
  for (const sub of [...new Set(subs)].slice(0, 50)) {
    const devices = ((await env.KEEL.get(`tpush:${sub}`, "json")) ?? []) as { token: string; sandbox: boolean }[];
    const keep: typeof devices = [];
    for (const d of devices) {
      const host = d.sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
      const r = await fetch(`https://${host}/3/device/${d.token}`, {
        method: "POST",
        headers: { authorization: `bearer ${jwt}`, "apns-topic": "com.briangreenejr.keel", "apns-push-type": "alert", "apns-priority": "10", "content-type": "application/json" },
        body: JSON.stringify({ aps: { alert: { title: clip(title, 120), body: clip(body, 240) }, sound: "default", "thread-id": `team.${boardId}` },
                               deeplink: `com.keel.app://team?id=${boardId}` }),
      }).catch(() => null);
      if (r?.status !== 410) keep.push(d);
    }
    if (keep.length !== devices.length) await env.KEEL.put(`tpush:${sub}`, JSON.stringify(keep));
  }
}

/** The people (by Apple account) a change should reach: named in the activity, or everyone for chat. */
function recipients(board: TeamBoard, names: string[], except: string): string[] {
  const subs = Object.entries(board.names ?? {}).filter(([, n]) => names.includes(n)).map(([s]) => s);
  return subs.filter((s) => s !== except);
}

export async function handleTeam(req: Request, env: Env, url: URL, device: boolean): Promise<Response | null> {
  const p = url.pathname;

  // ---- Team sign-in (anyone with an Apple Account; only grants access to boards they're invited to)
  if (p === "/team/auth" && req.method === "POST") {
    const b = (await req.json().catch(() => ({}))) as { identityToken?: string; name?: string };
    if (!b.identityToken) return json({ error: "missing token" }, 400);
    const who = await verifyAppleToken(b.identityToken);
    if (!who) return json({ error: "invalid sign in" }, 401);
    const saved = await env.KEEL.get(`tmname:${who.sub}`);
    const name = clip((b.name ?? "").trim() || saved || "Teammate", 40);
    await env.KEEL.put(`tmname:${who.sub}`, name);
    const token = "tm_" + rid(32);
    await env.KEEL.put(`tmsession:${token}`, JSON.stringify({ sub: who.sub, name }), { expirationTtl: 180 * 86_400 });
    return json({ token, name });
  }
  if (p === "/team/auth" && req.method === "DELETE") {
    const me = await whoIs(req, env);
    if (!me) return json({ deleted: true });
    let cursor: string | undefined;
    do {
      const page = await env.KEEL.list({ prefix: "tmsession:", cursor });
      for (const k of page.keys) {
        const v = await env.KEEL.get(k.name);
        if (v && (JSON.parse(v) as Who).sub === me.sub) await env.KEEL.delete(k.name);
      }
      cursor = page.list_complete ? undefined : page.cursor;
    } while (cursor);
    await env.KEEL.delete(`tpush:${me.sub}`);
    await env.KEEL.delete(`tmname:${me.sub}`);
    return json({ deleted: true });
  }
  if (p === "/team/push" && req.method === "POST") {
    const me = await whoIs(req, env);
    if (!me) return json({ error: "sign in first" }, 401);
    const b = (await req.json()) as { token?: string; sandbox?: boolean };
    if (!b.token || !/^[a-f0-9]{32,200}$/i.test(b.token)) return json({ error: "bad token" }, 400);
    const list = ((await env.KEEL.get(`tpush:${me.sub}`, "json")) ?? []) as { token: string; sandbox: boolean }[];
    await env.KEEL.put(`tpush:${me.sub}`, JSON.stringify([{ token: b.token, sandbox: !!b.sandbox }, ...list.filter((d) => d.token !== b.token)].slice(0, 10)));
    return json({ ok: true, ready: apnsReady(env) });
  }

  // ---- Create
  if (p === "/team" && req.method === "POST") {
    const b = (await req.json()) as { name?: string; by?: string; secure?: boolean };
    const me = await whoIs(req, env);
    const id = rid();
    let board: TeamBoard;
    if (me && b.secure !== false) {
      board = { name: clip(b.name, 80) || "Team", owner: me.name, members: [me.name], tasks: [], activity: [], version: 1, updated: Date.now(),
                secure: true, roles: { [me.sub]: "owner" }, names: { [me.sub]: me.name }, chat: [], events: [] };
    } else {
      if (!device) return json({ error: "unauthorized" }, 401);
      const owner = clip(b.by || "Owner", 40);
      board = { name: clip(b.name, 80) || "Team", owner, members: [owner], tasks: [], activity: [], version: 1, updated: Date.now(), chat: [], events: [] };
    }
    board.activity.push({ at: Date.now(), by: board.owner, text: "created the board" });
    await env.KEEL.put(`team:${id}`, JSON.stringify(board));
    if (me) await addBoardToMember(env, me.sub, id);
    return json({ id, url: `${url.origin}/t/${id}`, secure: !!board.secure });
  }

  // ---- Accept an invitation
  if (p === "/team/join" && req.method === "POST") {
    const me = await whoIs(req, env);
    if (!me) return json({ error: "sign in first" }, 401);
    const b = (await req.json()) as { code?: string };
    const inv = await env.KEEL.get(`tinvite:${clip(b.code, 64)}`);
    if (!inv) return json({ error: "This invitation has expired or was already used up." }, 404);
    const invite = JSON.parse(inv) as { board: string; role: Role; uses: number };
    const raw = await env.KEEL.get(`team:${invite.board}`);
    if (!raw) return json({ error: "That board no longer exists." }, 404);
    const board = JSON.parse(raw) as TeamBoard;
    board.roles = board.roles ?? {};
    board.names = board.names ?? {};
    if (!board.roles[me.sub]) {
      board.roles[me.sub] = invite.role === "owner" ? "member" : invite.role;
      // Two people with the same name: add a number so tasks and mentions stay clear.
      let name = me.name, n = 2;
      while (Object.entries(board.names).some(([s, nm]) => nm === name && s !== me.sub)) name = `${me.name} ${n++}`;
      board.names[me.sub] = name;
      if (!board.members.includes(name)) board.members.push(name);
      board.activity.push({ at: Date.now(), by: name, text: `joined as ${board.roles[me.sub]}` });
      board.version += 1; board.updated = Date.now();
      await env.KEEL.put(`team:${invite.board}`, JSON.stringify(board));
      await addBoardToMember(env, me.sub, invite.board);
      await pushTo(env, Object.keys(board.roles).filter((s) => s !== me.sub && rank[board.roles![s]] >= rank.admin), board.name, `${name} joined`, invite.board);
      invite.uses -= 1;
      if (invite.uses <= 0) await env.KEEL.delete(`tinvite:${clip(b.code, 64)}`);
      else await env.KEEL.put(`tinvite:${clip(b.code, 64)}`, JSON.stringify(invite), { expirationTtl: 7 * 86_400 });
    }
    return json({ id: invite.board, board: view(board, me) });
  }
  // My private boards (so a new device finds them).
  if (p === "/team/mine" && req.method === "GET") {
    const me = await whoIs(req, env);
    if (!me) return json({ error: "sign in first" }, 401);
    const ids = ((await env.KEEL.get(`tboards:${me.sub}`, "json")) ?? []) as string[];
    const out: { id: string; name: string }[] = [];
    for (const id of ids) {
      const raw = await env.KEEL.get(`team:${id}`);
      if (!raw) continue;
      const b = JSON.parse(raw) as TeamBoard;
      if (b.roles?.[me.sub]) out.push({ id, name: b.name });
    }
    return json(out);
  }

  const jm = p.match(/^\/join\/([a-f0-9]{24})$/);
  if (jm && req.method === "GET") {
    const keel = `com.keel.app://join?code=${jm[1]}&host=${encodeURIComponent(url.origin)}`;
    return new Response(page("Join a Keel board", `<h1>You're invited to a Keel board</h1>
<p>Open this invitation in Keel on your iPhone, iPad or Mac, then sign in with Apple to join.</p>
<p><a class="go" href="${keel}">Open in Keel</a></p>
<p style="color:#888;font-size:14px">Don't have Keel yet? Ask the person who invited you for a TestFlight link, then tap the invitation again.</p>`),
      { headers: { "content-type": "text/html; charset=utf-8" } });
  }

  // ---- A board
  const m = p.match(/^\/team\/([a-f0-9]{32})$/);
  if (m) {
    const id = m[1];
    const key = `team:${id}`;
    const raw = await env.KEEL.get(key);
    if (!raw) return json({ error: "not found" }, 404);
    const board = JSON.parse(raw) as TeamBoard;
    const me = board.secure ? await whoIs(req, env) : null;
    const role: Role | null = board.secure ? (me ? board.roles?.[me.sub] ?? null : null) : "member";
    if (board.secure && !role) return json({ error: "This board is private. Ask for an invitation." }, 403);
    if (req.method === "GET") return json(view(board, me));
    if (req.method !== "POST") return null;

    const op = (await req.json()) as Record<string, unknown>;
    const opName = String(op.op ?? "");
    const by = board.secure ? board.names![me!.sub] : clip(op.by || "Someone", 40);

    if (!board.secure) {
      if (opName === "delete") {
        if (!device || op.by !== board.owner) return json({ error: "Only the owner can delete the board." }, 403);
        await env.KEEL.delete(key);
        return json({ ok: true });
      }
      if (["invite", "set_role", "remove_member"].includes(opName)) return json({ error: "Link boards don't have roles. Create a private board for that." }, 400);
    } else {
      const own = opName === "remove" && board.tasks.find((t) => t.id === op.id)?.createdBy === by;
      if (!allowed(role!, opName, own)) return json({ error: `As ${role === "admin" || role === "owner" ? "an" : "a"} ${role}, you can't do that here.` }, 403);
      if (opName === "delete") {
        await env.KEEL.delete(key);
        return json({ ok: true });
      }
      if (opName === "invite") {
        const r = (["admin", "member", "viewer"].includes(String(op.role)) ? op.role : "member") as Role;
        if (r === "admin" && role !== "owner") return json({ error: "Only the owner can invite admins." }, 403);
        const code = rid(12);
        const uses = Math.min(50, Math.max(1, Number(op.uses) || 10));
        await env.KEEL.put(`tinvite:${code}`, JSON.stringify({ board: id, role: r, uses }), { expirationTtl: 7 * 86_400 });
        board.activity.push({ at: Date.now(), by, text: `created an invitation (${r})` });
        await env.KEEL.put(key, JSON.stringify(board));
        return json({ code, url: `${url.origin}/join/${code}`, role: r, expires: Date.now() + 7 * 86_400_000 });
      }
      if (opName === "set_role" || opName === "remove_member") {
        const targetName = clip(op.name, 40);
        const target = Object.entries(board.names ?? {}).find(([, n]) => n === targetName)?.[0];
        if (!target) return json({ error: "No member by that name." }, 404);
        const tRole = board.roles![target];
        if (tRole === "owner") return json({ error: "The owner can't be changed or removed." }, 403);
        if (role !== "owner" && rank[tRole] >= rank.admin) return json({ error: "Only the owner can change admins." }, 403);
        if (opName === "set_role") {
          const r = String(op.role) as Role;
          if (!["admin", "member", "viewer"].includes(r) || (r === "admin" && role !== "owner")) return json({ error: "Not allowed." }, 403);
          board.roles![target] = r;
          board.activity.push({ at: Date.now(), by, text: `made ${targetName} ${r === "admin" ? "an admin" : `a ${r}`}`, for: [targetName] });
        } else {
          delete board.roles![target];
          board.members = board.members.filter((n) => n !== targetName);
          board.activity.push({ at: Date.now(), by, text: `removed ${targetName} from the board` });
        }
        board.version += 1; board.updated = Date.now();
        await env.KEEL.put(key, JSON.stringify(board));
        return json(view(board, me));
      }
      if (opName === "leave") {
        if (role === "owner") return json({ error: "The owner can't leave. Delete the board instead." }, 400);
        delete board.roles![me!.sub];
      }
    }

    const before = board.activity.length, chatBefore = (board.chat ?? []).length;
    const err = apply(board, op, by);
    if (err) return json({ error: err }, 400);
    board.version += 1;
    board.updated = Date.now();
    await env.KEEL.put(key, JSON.stringify(board));

    // Instant notifications to the people this is news for.
    if (board.secure) {
      for (const a of board.activity.slice(before)) if (a.for?.length) await pushTo(env, recipients(board, a.for, me!.sub), `${a.by} · ${board.name}`, a.text, id);
      for (const c of (board.chat ?? []).slice(chatBefore)) {
        const everyone = Object.keys(board.roles ?? {}).filter((s) => s !== me!.sub);
        await pushTo(env, everyone, `${c.by} in ${board.name}`, c.text, id);
      }
    }
    return json(view(board, me));
  }

  const wm = p.match(/^\/t\/([a-f0-9]{32})$/);
  if (wm && req.method === "GET") {
    const raw = await env.KEEL.get(`team:${wm[1]}`);
    if (raw && (JSON.parse(raw) as TeamBoard).secure) {
      return new Response(page("Private board", "<h1>This board is private</h1><p>Open it in Keel and sign in with Apple. If you're new, ask a member for an invitation.</p>"),
        { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    return new Response(boardPage(wm[1]), { headers: { "content-type": "text/html; charset=utf-8" } });
  }
  return null;
}

/** The board as a member sees it: roles by name (never anyone's Apple account id) and your own role. */
function view(board: TeamBoard, me: Who | null) {
  const { roles, names, ...rest } = board;
  const byName: Record<string, Role> = {};
  for (const [sub, r] of Object.entries(roles ?? {})) if (names?.[sub]) byName[names[sub]] = r;
  return { ...rest, roles: byName, me: me && names?.[me.sub] ? { name: names[me.sub], role: roles?.[me.sub] ?? "member" } : null };
}

async function addBoardToMember(env: Env, sub: string, id: string) {
  const ids = ((await env.KEEL.get(`tboards:${sub}`, "json")) ?? []) as string[];
  if (!ids.includes(id)) await env.KEEL.put(`tboards:${sub}`, JSON.stringify([id, ...ids].slice(0, 200)));
}

function page(title: string, body: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>
<style>:root{color-scheme:light dark}body{font:17px/1.55 -apple-system,system-ui,sans-serif;max-width:560px;margin:0 auto;padding:40px 20px}
.go{display:inline-block;background:#5b6bfa;color:#fff;padding:12px 18px;border-radius:12px;text-decoration:none}</style></head><body>${body}</body></html>`;
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
