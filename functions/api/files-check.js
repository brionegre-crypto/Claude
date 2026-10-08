// Cloudflare Pages Function: GET /api/files-check
// Copies every product file into the FILES KV namespace (if not there yet)
// and reports which files are stored. Open it once after adding the FILES
// binding, and before cancelling systeme.io. It never returns file contents.

import { FILES } from "../_catalog.js";
import { getFile } from "./download.js";

export async function onRequestGet({ env }) {
  const out = { binding: !!env.FILES, purchase_check: !!env.STRIPE_KEY, files: {} };
  if (env.FILES) {
    const stored = new Set((await env.FILES.list()).keys.map((k) => k.name));
    for (const key of Object.keys(FILES)) {
      try {
        out.files[key] = stored.has(key) || (await getFile(env, key)) ? "stored" : "MISSING";
      } catch (e) {
        out.files[key] = "error: " + e.message;
      }
    }
  }
  return new Response(JSON.stringify(out, null, 1), {
    headers: { "content-type": "application/json", "cache-control": "no-store", "x-robots-tag": "noindex" },
  });
}
