import type { Env } from "./index";
import { json } from "./ai";

/**
 * GET  /support            The App Store "Support URL": answers to common questions, plus how to reach you.
 * POST /support            The contact form: messages are kept on this server (90 days).
 * GET  /support/messages   (owner's device) read them.
 * Set SUPPORT_EMAIL (Cloudflare → keel-backend → Settings → Variables) to also show an email address.
 */
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
const html = (body: string, status = 200) => new Response(body, { status, headers: { "content-type": "text/html; charset=utf-8" } });

export async function handleSupport(req: Request, env: Env, url: URL, device: boolean): Promise<Response | null> {
  if (url.pathname === "/support/messages" && req.method === "GET") {
    if (!device) return json({ error: "unauthorized" }, 401);
    return new Response((await env.KEEL.get("support:messages")) ?? "[]", { headers: { "content-type": "application/json" } });
  }
  if (url.pathname !== "/support") return null;
  if (req.method === "POST") {
    const f = Object.fromEntries((await req.formData()).entries()) as Record<string, string>;
    const msg = (f.message ?? "").trim().slice(0, 4000), email = (f.email ?? "").trim().slice(0, 120);
    if (!msg || (f.website ?? "") !== "") return html(page(`<p>Please write a message. <a href="/support">Back</a></p>`), 400);   // "website" is a spam trap
    const list = JSON.parse((await env.KEEL.get("support:messages")) ?? "[]") as unknown[];
    if (list.length >= 300) return html(page(`<p>Our inbox is full right now. Please try again tomorrow.</p>`), 429);
    list.push({ email, message: msg, at: Date.now() });
    await env.KEEL.put("support:messages", JSON.stringify(list), { expirationTtl: 90 * 86_400 });
    return html(page(`<h1>Thanks!</h1><p>We got your message${email ? " and will reply to " + esc(email) : ""}.</p><p><a href="/support">Back to support</a></p>`));
  }
  const mail = env.SUPPORT_EMAIL ? `<p>Email: <a href="mailto:${esc(env.SUPPORT_EMAIL)}">${esc(env.SUPPORT_EMAIL)}</a></p>` : "";
  return html(page(`
    <h1>Keel support</h1>
    <p>Keel is a calm planner for ADHD brains: email, calendar, tasks, notes and focus in one place. Here are answers to common questions.</p>
    <h2>Getting started</h2>
    <details><summary>Do I need an account?</summary><p>No. Every feature works without one. Signing in with Apple keeps Keel the same on your iPhone, iPad and Mac.</p></details>
    <details><summary>How do I add my email?</summary><p>Settings → Mail Accounts → Add Account. Gmail and Outlook sign in with their own pages; iCloud and other mail use an app password.</p></details>
    <details><summary>How do I use my own Claude, ChatGPT or Gemini?</summary><p>Settings → AI &amp; Privacy → AI Model. Pick one, open its Key row, paste your API key and tap Test &amp; Save. Apple Intelligence needs no key.</p></details>
    <h2>Privacy</h2>
    <details><summary>Where is my data?</summary><p>On your devices and in your own iCloud. Mail is downloaded by each device directly from your provider. See the <a href="/privacy">privacy policy</a>.</p></details>
    <details><summary>How do I delete my account?</summary><p>Settings → Account → Delete Account. Everything stored for your account on Keel's server is removed.</p></details>
    <h2>Troubleshooting</h2>
    <details><summary>Something looks wrong or Keel crashed</summary><p>Settings → Crash reports → Send the latest report, then tell us what you were doing using the form below.</p></details>
    <details><summary>My settings aren't on my Mac</summary><p>Use the same Apple Account on both, with iCloud Keychain on (Settings → your name → iCloud → Passwords and Keychain). Give it a minute after opening Keel.</p></details>
    <h2>Contact us</h2>
    ${mail}
    <form method="post">
      <label>Your email (so we can reply)<input name="email" type="email" maxlength="120"></label>
      <label>How can we help?<textarea name="message" required maxlength="4000"></textarea></label>
      <input name="website" tabindex="-1" autocomplete="off" style="position:absolute;left:-9999px" aria-hidden="true">
      <button type="submit">Send</button>
    </form>`));
}

function page(body: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Keel support</title><style>
:root{color-scheme:light dark;--a:#5b5bd6}body{font:16px/1.55 -apple-system,system-ui,sans-serif;max-width:640px;margin:0 auto;padding:28px 18px 60px}
h1{font-size:28px;margin:0 0 8px}h2{font-size:18px;margin:28px 0 8px}details{border-bottom:1px solid #8883;padding:10px 0}summary{cursor:pointer;font-weight:600}
form{display:grid;gap:12px;margin-top:12px}label{display:grid;gap:4px;font-size:14px}input,textarea{font:inherit;padding:10px;border-radius:10px;border:1px solid #8886}
textarea{min-height:120px}button{background:var(--a);color:#fff;border:0;border-radius:12px;padding:12px;font:inherit;font-weight:600}a{color:var(--a)}
</style></head><body>${body}</body></html>`;
}
