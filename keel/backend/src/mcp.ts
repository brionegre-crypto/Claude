import type { Env } from "./index";
import { json } from "./ai";

/**
 * Remote MCP server ("custom connector") so Claude — claude.ai, the Claude apps, and Claude Duet
 * if/when it accepts custom connectors — can read your Keel tasks, habits, notes and today's plan,
 * and add tasks / start focus. Data comes from a snapshot the iPhone uploads after each sync
 * (POST /snapshot); writes are queued and the app applies them on next sync (GET /actions).
 *
 * Minimal Streamable-HTTP JSON-RPC implementation (no SSE needed for these tools).
 * Add in Claude: Settings → Connectors → Add custom connector → https://<worker>/mcp
 */
const TOOLS = [
  {
    name: "get_today",
    description: "Today's plan, the user's single next action, top emails needing a reply, and active habit stacks.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "list_tasks",
    description: "Open tasks with due dates, energy level and micro-steps. Optional list filter.",
    inputSchema: { type: "object", properties: { list: { type: "string" } }, additionalProperties: false },
  },
  {
    name: "search_notes",
    description: "Full-text search across Keel notes. Returns titles and matching text.",
    inputSchema: { type: "object", properties: { query: { type: "string" } }, required: ["query"], additionalProperties: false },
  },
  {
    name: "list_promises",
    description: "Open commitments the user made in emails they sent (e.g. 'I'll send the deck Friday'), with recipient, quote and due date.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "add_task",
    description: "Add a task to Keel (syncs to Apple Reminders). Due date optional, ISO 8601.",
    inputSchema: {
      type: "object",
      properties: { title: { type: "string" }, due: { type: "string" }, list: { type: "string" } },
      required: ["title"],
      additionalProperties: false,
    },
  },
  {
    name: "start_focus",
    description: "Ask the user's iPhone to start a Keel focus session (they confirm on the phone).",
    inputSchema: { type: "object", properties: { minutes: { type: "integer" } }, required: ["minutes"], additionalProperties: false },
  },
  {
    name: "get_calendar",
    description: "The user's calendar for today and the next 7 days: title, start/end (ISO 8601), location and who else is invited. Optional ISO date to show just that day.",
    inputSchema: { type: "object", properties: { day: { type: "string" } }, additionalProperties: false },
  },
  {
    name: "get_inbox",
    description: "Recent email in the user's Keel inbox (newest first): sender, subject, a one-line summary, unread flag, category and priority (0–1). Use unread_only to list just unread mail.",
    inputSchema: { type: "object", properties: { unread_only: { type: "boolean" }, limit: { type: "integer" } }, additionalProperties: false },
  },
  {
    name: "search_mail",
    description: "Search recent email by sender, subject or summary text.",
    inputSchema: { type: "object", properties: { query: { type: "string" } }, required: ["query"], additionalProperties: false },
  },
  {
    name: "get_note",
    description: "The full text of one Keel note by title (exact or partial match).",
    inputSchema: { type: "object", properties: { title: { type: "string" } }, required: ["title"], additionalProperties: false },
  },
  {
    name: "get_body",
    description: "Today's body scores from Apple Health: recovery (Tide, 0–100%), effort (Swell, 0–100) and sleep (Anchor, 0–100), with advice for the day.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "get_medications",
    description: "Today's medications: name, dose, each scheduled time and whether it has been taken, and pills left.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "list_people",
    description: "People the user keeps in touch with: name, email, when they were last in touch and whether they're due a catch-up.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "get_top3",
    description: "The user's Top 3 for today and which are done.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "complete_task",
    description: "Mark an open Keel task done, by title (exact or partial match).",
    inputSchema: { type: "object", properties: { title: { type: "string" } }, required: ["title"], additionalProperties: false },
  },
  {
    name: "create_note",
    description: "Create a Keel note. Markdown-style text (headings, lists, checkboxes) is kept.",
    inputSchema: { type: "object", properties: { title: { type: "string" }, text: { type: "string" } }, required: ["title", "text"], additionalProperties: false },
  },
  {
    name: "append_to_note",
    description: "Add text to the end of an existing Keel note, found by title.",
    inputSchema: { type: "object", properties: { title: { type: "string" }, text: { type: "string" } }, required: ["title", "text"], additionalProperties: false },
  },
  {
    name: "draft_email",
    description: "Draft an email. It is NOT sent: it opens in Keel on the user's iPhone for them to check and send.",
    inputSchema: {
      type: "object",
      properties: { to: { type: "string" }, subject: { type: "string" }, body: { type: "string" } },
      required: ["to", "subject", "body"],
      additionalProperties: false,
    },
  },
  {
    name: "draft_text",
    description: "Draft a text message (iMessage/SMS) to a person (name, phone or email). It is NOT sent: it opens in Messages on the user's iPhone for them to send.",
    inputSchema: { type: "object", properties: { to: { type: "string" }, message: { type: "string" } }, required: ["to", "message"], additionalProperties: false },
  },
  {
    name: "add_event",
    description: "Add an event to the user's calendar. start is ISO 8601 with a time zone offset; minutes defaults to 60.",
    inputSchema: {
      type: "object",
      properties: { title: { type: "string" }, start: { type: "string" }, minutes: { type: "integer" } },
      required: ["title", "start"],
      additionalProperties: false,
    },
  },
  {
    name: "log_medication",
    description: "Record that the user took a medication now (by name). Counts as the closest scheduled dose not yet taken.",
    inputSchema: { type: "object", properties: { name: { type: "string" } }, required: ["name"], additionalProperties: false },
  },
  {
    name: "add_to_top3",
    description: "Add something to today's Top 3 (if there's a free slot).",
    inputSchema: { type: "object", properties: { text: { type: "string" } }, required: ["text"], additionalProperties: false },
  },
  {
    name: "log_drink",
    description: "Log a drink for caffeine and water tracking. kind: water, coffee, espresso, tea, energy or cola.",
    inputSchema: {
      type: "object",
      properties: { kind: { type: "string", enum: ["water", "coffee", "espresso", "tea", "energy", "cola"] } },
      required: ["kind"],
      additionalProperties: false,
    },
  },
  {
    name: "save_idea",
    description: "Save an idea to the user's Idea vault in Keel.",
    inputSchema: { type: "object", properties: { text: { type: "string" } }, required: ["text"], additionalProperties: false },
  },
];

/** Tools that change something: queued for the iPhone, which applies them on its next sync. */
const QUEUED = new Set([
  "add_task", "start_focus", "complete_task", "create_note", "append_to_note", "draft_email", "draft_text",
  "add_event", "log_medication", "add_to_top3", "log_drink", "save_idea",
]);

type Snapshot = {
  today?: unknown;
  tasks?: { title: string; list: string; due?: string; energy: string; steps: string[] }[];
  notes?: { title: string; text: string }[];
  promises?: { promise: string; to: string; quote: string; due: string; overdue: boolean }[];
  calendar?: { title: string; start: string; end: string; allDay: boolean; location: string; calendar: string; with: string[] }[];
  emails?: { id: string; from: string; subject: string; summary: string; received: string; unread: boolean; category: string; priority: number }[];
  body?: Record<string, unknown>;
  meds?: unknown[];
  people?: unknown[];
  top3?: { items?: string[]; done?: boolean[] };
};

const emptyNote = "No snapshot yet: open Keel on the iPhone once (with Settings → Claude connector on).";

export async function handleMCP(req: Request, env: Env): Promise<Response> {
  const msg = (await req.json()) as { id?: number | string; method: string; params?: any };
  const reply = (result: unknown) => json({ jsonrpc: "2.0", id: msg.id, result });

  // Notifications (no id) just need an OK.
  if (msg.id === undefined || msg.id === null) return new Response(null, { status: 202 });
  switch (msg.method) {
    case "ping":
      return reply({});
    case "initialize":
      return reply({
        protocolVersion: typeof msg.params?.protocolVersion === "string" ? msg.params.protocolVersion : "2025-06-18",
        capabilities: { tools: {} },
        serverInfo: { name: "keel", version: "0.1.0" },
      });
    case "notifications/initialized":
      return new Response(null, { status: 202 });
    case "tools/list":
      return reply({ tools: TOOLS });
    case "tools/call": {
      const snap = ((await env.KEEL.get("snapshot", "json")) ?? {}) as Snapshot;
      const args = msg.params?.arguments ?? {};
      const text = (t: unknown) => reply({ content: [{ type: "text", text: typeof t === "string" ? t : JSON.stringify(t, null, 2) }] });
      switch (msg.params?.name) {
        case "get_today":
          return text(snap.today ?? "No snapshot yet — open Keel on the iPhone once.");
        case "list_tasks":
          return text((snap.tasks ?? []).filter((t) => !args.list || t.list === args.list));
        case "list_promises":
          return text(snap.promises ?? []);
        case "search_notes": {
          const q = String(args.query).toLowerCase();
          return text((snap.notes ?? []).filter((n) => (n.title + n.text).toLowerCase().includes(q)).slice(0, 10));
        }
        case "get_calendar": {
          const day = typeof args.day === "string" ? args.day.slice(0, 10) : "";
          return text((snap.calendar ?? []).filter((e) => !day || e.start.slice(0, 10) === day));
        }
        case "get_inbox": {
          const limit = Math.min(100, Math.max(1, Number(args.limit) || 25));
          return text((snap.emails ?? []).filter((e) => !args.unread_only || e.unread).slice(0, limit));
        }
        case "search_mail": {
          const q = String(args.query).toLowerCase();
          return text((snap.emails ?? []).filter((e) => (e.from + " " + e.subject + " " + e.summary).toLowerCase().includes(q)).slice(0, 20));
        }
        case "get_note": {
          const q = String(args.title).toLowerCase();
          const notes = snap.notes ?? [];
          const hit = notes.find((n) => n.title.toLowerCase() === q) ?? notes.find((n) => n.title.toLowerCase().includes(q));
          return text(hit ?? `No note titled "${args.title}".`);
        }
        case "get_body":
          return text(snap.body && Object.keys(snap.body).length ? snap.body : "No body scores yet today (Apple Health hasn't given Keel last night's data).");
        case "get_medications":
          return text(snap.meds ?? emptyNote);
        case "list_people":
          return text(snap.people ?? emptyNote);
        case "get_top3":
          return text(snap.top3 && snap.top3.items ? snap.top3 : "No Top 3 picked today.");
        default: {
          if (QUEUED.has(msg.params?.name)) {
            const queue = ((await env.KEEL.get("actions", "json")) ?? []) as unknown[];
            queue.push({ type: msg.params.name, args, at: new Date().toISOString() });
            await env.KEEL.put("actions", JSON.stringify(queue.slice(-200)));
            const sendNote = msg.params.name === "draft_email" || msg.params.name === "draft_text"
              ? " It won't be sent: the user checks and sends it on their iPhone."
              : "";
            return text(`Queued. Keel will apply it on the iPhone's next sync.${sendNote}`);
          }
          return json({ jsonrpc: "2.0", id: msg.id, error: { code: -32601, message: "unknown tool" } });
        }
      }
    }
    default:
      return json({ jsonrpc: "2.0", id: msg.id, error: { code: -32601, message: "method not found" } });
  }
}
