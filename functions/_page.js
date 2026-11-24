// A simple on-brand page for function-rendered screens (Ledger, results).
export const escH = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
export const field = 'style="width:100%;font:inherit;font-size:17px;color:var(--fg);background:var(--bg);border:1px solid var(--line-2);border-radius:14px;padding:15px 16px"';
export function page(title, inner) {
  return new Response(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex">
<title>${escH(title)} | Be The Man</title><link rel="icon" type="image/png" href="/assets/favicon.png">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&display=swap"><link rel="stylesheet" href="/assets/site.css"></head>
<body><main class="wrap"><div class="lp"><a class="logo" href="/">BE <span>THE MAN</span></a>${inner}
<p class="fine center">Be The Man is a faith-based coaching and consistency system, not medical treatment, diagnosis, or clinical therapy for ADHD.</p></div></main></body></html>`,
    { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-robots-tag": "noindex" } });
}
