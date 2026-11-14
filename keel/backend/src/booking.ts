import type { Env } from "./index";
import { json } from "./ai";

/**
 * Booking link (like a scheduling page): people pick one of your free times and it lands on your calendar.
 * The server never sees your calendar. Your iPhone sends only the open times it computed.
 *   POST /booking                (owner's device) publish or update: title, minutes, open slots → { id, url }
 *   DELETE /booking              (owner's device) turn the link off
 *   GET  /booking/requests       (owner's device) bookings made since last time (then cleared)
 *   GET  /b/:id                  the public page
 *   POST /b/:id                  a visitor books a slot { start, name, email, note }
 */
type Slot = { start: string; end: string };
type Booking = { title: string; minutes: number; owner: string; note: string; slots: Slot[]; updated: number };
type Request_ = { start: string; end: string; name: string; email: string; note: string; at: number };

const rid = (n = 16) => Array.from(crypto.getRandomValues(new Uint8Array(n)), (b) => b.toString(16).padStart(2, "0")).join("");
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
const html = (body: string, status = 200) => new Response(body, { status, headers: { "content-type": "text/html; charset=utf-8" } });

export async function handleBooking(req: Request, env: Env, url: URL, device: boolean): Promise<Response | null> {
  const p = url.pathname;

  if (p === "/booking" && req.method === "POST") {
    if (!device) return json({ error: "unauthorized" }, 401);
    const b = (await req.json()) as { title?: string; minutes?: number; owner?: string; note?: string; slots?: Slot[] };
    const id = (await env.KEEL.get("booking:id")) ?? rid();
    await env.KEEL.put("booking:id", id);
    const booking: Booking = {
      title: (b.title ?? "Meet").slice(0, 100),
      minutes: Math.max(10, Math.min(240, Number(b.minutes) || 30)),
      owner: (b.owner ?? "").slice(0, 60),
      note: (b.note ?? "").slice(0, 400),
      slots: (b.slots ?? []).filter((s) => typeof s.start === "string" && typeof s.end === "string").slice(0, 400),
      updated: Date.now(),
    };
    await env.KEEL.put(`book:${id}`, JSON.stringify(booking));
    return json({ id, url: `${url.origin}/b/${id}` });
  }
  if (p === "/booking" && req.method === "DELETE") {
    if (!device) return json({ error: "unauthorized" }, 401);
    const id = await env.KEEL.get("booking:id");
    if (id) await env.KEEL.delete(`book:${id}`);
    await env.KEEL.delete("booking:id");
    return json({ ok: true });
  }
  if (p === "/booking/requests" && req.method === "GET") {
    if (!device) return json({ error: "unauthorized" }, 401);
    const raw = (await env.KEEL.get("booking:requests")) ?? "[]";
    await env.KEEL.put("booking:requests", "[]");
    return new Response(raw, { headers: { "content-type": "application/json" } });
  }

  const m = p.match(/^\/b\/([a-f0-9]{32})$/);
  if (!m) return null;
  const key = `book:${m[1]}`;
  const raw = await env.KEEL.get(key);
  if (!raw) return html(page("Not available", `<p>This booking link is turned off.</p>`), 404);
  const booking = JSON.parse(raw) as Booking;
  const now = Date.now();
  const open = booking.slots.filter((s) => Date.parse(s.start) > now + 30 * 60_000);

  if (req.method === "POST") {
    const form = req.headers.get("content-type")?.includes("application/json")
      ? ((await req.json()) as Record<string, string>)
      : Object.fromEntries((await req.formData()).entries()) as Record<string, string>;
    const slot = open.find((s) => s.start === form.start);
    const name = (form.name ?? "").trim().slice(0, 80);
    const email = (form.email ?? "").trim().slice(0, 120);
    if (!slot || !name || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return html(page("Couldn't book", `<p>That time was just taken or something was missing. <a href="/b/${m[1]}">Pick another time</a>.</p>`), 400);
    }
    const reqs = JSON.parse((await env.KEEL.get("booking:requests")) ?? "[]") as Request_[];
    if (reqs.length >= 50) return html(page("Busy", `<p>Too many pending requests right now. Please try again later.</p>`), 429);
    reqs.push({ start: slot.start, end: slot.end, name, email, note: (form.note ?? "").slice(0, 600), at: now });
    await env.KEEL.put("booking:requests", JSON.stringify(reqs));
    // Take the slot (and anything overlapping it) off the page straight away.
    const s0 = Date.parse(slot.start), e0 = Date.parse(slot.end);
    booking.slots = booking.slots.filter((s) => Date.parse(s.end) <= s0 || Date.parse(s.start) >= e0);
    await env.KEEL.put(key, JSON.stringify(booking));
    return html(page("You're booked", `<p>Thanks, ${esc(name)}. <b>${esc(booking.title)}</b> is booked.</p>
      <p class="when" data-start="${esc(slot.start)}"></p><p class="muted">It's been added to ${esc(booking.owner || "their")} calendar.</p>
      <script>document.querySelectorAll('.when').forEach(e=>{const d=new Date(e.dataset.start);e.textContent=d.toLocaleString([], {weekday:'long',month:'long',day:'numeric',hour:'numeric',minute:'2-digit'})})</script>`));
  }

  const slotsJSON = JSON.stringify(open.map((s) => s.start));
  return html(page(booking.title, `
    <h1>${esc(booking.title)}</h1>
    <p class="muted">${booking.minutes} minutes${booking.owner ? " with " + esc(booking.owner) : ""}. Times are shown in your time zone.</p>
    ${booking.note ? `<p>${esc(booking.note)}</p>` : ""}
    <div id="days">${open.length ? "" : "<p>No open times right now. Check back soon.</p>"}</div>
    <form id="f" method="post" hidden>
      <h2 id="picked"></h2>
      <input type="hidden" name="start" id="start">
      <label>Your name<input name="name" required maxlength="80"></label>
      <label>Your email<input name="email" type="email" required maxlength="120"></label>
      <label>Anything to share? (optional)<textarea name="note" maxlength="600"></textarea></label>
      <button type="submit">Book it</button>
    </form>
    <script>
      const starts=${slotsJSON};const days={};
      for(const s of starts){const d=new Date(s);const k=d.toLocaleDateString([], {weekday:'long',month:'long',day:'numeric'});(days[k]=days[k]||[]).push(s)}
      const box=document.getElementById('days');
      for(const [k,list] of Object.entries(days)){const h=document.createElement('h3');h.textContent=k;box.appendChild(h);const row=document.createElement('div');row.className='slots';
        for(const s of list){const b=document.createElement('button');b.type='button';b.textContent=new Date(s).toLocaleTimeString([], {hour:'numeric',minute:'2-digit'});
          b.onclick=()=>{document.getElementById('start').value=s;document.getElementById('picked').textContent=k+' at '+b.textContent;const f=document.getElementById('f');f.hidden=false;f.scrollIntoView({behavior:'smooth'})};row.appendChild(b)}
        box.appendChild(row)}
    </script>`));
}

function page(title: string, body: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title><meta name="robots" content="noindex">
<style>
:root{color-scheme:light dark;--a:#5b5bd6}
body{font:16px/1.5 -apple-system,system-ui,sans-serif;max-width:560px;margin:0 auto;padding:28px 18px 60px}
h1{font-size:26px;margin:0 0 4px}h3{margin:22px 0 8px;font-size:15px}
.muted{opacity:.65}.slots{display:flex;flex-wrap:wrap;gap:8px}
.slots button{border:1px solid var(--a);color:var(--a);background:transparent;border-radius:10px;padding:8px 14px;font:inherit;cursor:pointer}
.slots button:hover{background:var(--a);color:#fff}
form{margin-top:28px;display:grid;gap:12px}label{display:grid;gap:4px;font-size:14px}
input,textarea{font:inherit;padding:10px;border-radius:10px;border:1px solid #8886}textarea{min-height:80px}
button[type=submit]{background:var(--a);color:#fff;border:0;border-radius:12px;padding:12px;font:inherit;font-weight:600}
footer{margin-top:40px;font-size:12px;opacity:.5}
</style></head><body>${body}<footer>Scheduled with Keel</footer></body></html>`;
}
