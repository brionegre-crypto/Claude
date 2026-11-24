// GET /f/<id>: a hosted sign-up page for a form built in the dashboard.
// ?embed=1 shows just the form (for an iframe on another site).
import { getForm, SITE } from "../_list.js";
import { SMS_CONSENT } from "../_sms.js";

const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const input = 'style="width:100%;font:inherit;font-size:17px;color:var(--fg);background:var(--bg);border:1px solid var(--line-2);border-radius:14px;padding:15px 16px"';

export async function onRequestGet({ request, env, params }) {
  const f = env.FILES ? await getForm(env, params.id) : null;
  if (!f || f.archived) return Response.redirect(SITE + "/step-1/", 302);
  const embed = new URL(request.url).searchParams.get("embed");
  const form = `<form class="tile lp-card signup" id="bf" novalidate style="display:grid;gap:10px">
      <input name="name" ${input} placeholder="First name" autocomplete="given-name" aria-label="First name">
      <input name="email" type="email" ${input} placeholder="Email address" autocomplete="email" required aria-label="Email">
      ${f.phone ? `<input name="phone" type="tel" ${input} placeholder="Mobile number${f.sms ? "" : " (optional)"}" autocomplete="tel" aria-label="Mobile number">` : ""}
      ${f.phone && f.sms ? `<label style="display:grid;grid-template-columns:auto 1fr;gap:10px;align-items:start;font-size:13px;color:var(--muted);text-align:left"><input type="checkbox" name="sms" value="1" style="margin-top:3px"><span>${esc(SMS_CONSENT)}</span></label>` : ""}
      <div style="position:absolute;left:-9999px" aria-hidden="true"><input name="company" tabindex="-1" autocomplete="off"></div>
      <button class="btn btn-primary btn-lg btn-block" type="submit">${esc(f.button || "Sign up")}</button>
      <p class="fine" id="bm" role="status">No card. Leave in one click.</p>
    </form>`;
  const page = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(f.headline || f.name)} | Be The Man</title><meta name="robots" content="${embed ? "noindex" : "index, follow"}"><meta name="description" content="${esc((f.text || "").slice(0, 160))}">
<link rel="icon" type="image/png" href="/assets/favicon.png"><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&display=swap"><link rel="stylesheet" href="/assets/site.css"></head>
<body${embed ? ' style="background:transparent"' : ""}><main class="wrap"><div class="lp">
${embed ? "" : `<a class="logo" href="/">BE <span>THE MAN</span></a><h1>${esc(f.headline || f.name)}</h1>${f.text ? `<p class="lead">${esc(f.text).replace(/\n/g, "<br>")}</p>` : ""}`}
${form}
${embed ? "" : `<p class="fine center">Be The Man is a faith-based coaching and consistency system, not medical treatment, diagnosis, or clinical therapy for ADHD. <a class="textlink" href="/privacy/">Privacy</a> · <a class="textlink" href="/terms/">Terms</a></p>`}
</div></main>
<script>
(function(){var f=document.getElementById('bf'),m=document.getElementById('bm'),b=f.querySelector('button'),label=b.textContent;
f.addEventListener('submit',function(e){e.preventDefault();var d={};new FormData(f).forEach(function(v,k){d[k]=v});if(window.btmAttr){var at=window.btmAttr();d.src=at.src;d.ref=at.ref;}
if(!/^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$/.test((d.email||'').trim())){m.textContent='Please enter a valid email address.';return}
b.disabled=true;b.textContent='Sending…';
fetch('/api/form/${encodeURIComponent(f.id)}',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(d)}).then(function(r){return r.json()}).then(function(x){
 if(x.redirect){(window.top||window).location.href=x.redirect;return}
 b.disabled=false;b.textContent=label;m.textContent=x.ok?(x.message||'Done.'):(x.error||'Please try again.');if(x.ok)f.reset();
}).catch(function(){b.disabled=false;b.textContent=label;m.textContent='Please try again.'})});})();
</script><script src="/assets/site.js" defer></script></body></html>`;
  return new Response(page, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", ...(embed ? {} : { "x-frame-options": "SAMEORIGIN" }) } });
}
