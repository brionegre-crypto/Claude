// GET /api/results: approved, permissioned results for the home page (first name, numbers, words).
import { publicResults } from "../_extras.js";
export async function onRequestGet({ env }) {
  const list = env.FILES ? await publicResults(env) : [];
  return new Response(JSON.stringify({ results: list }), { headers: { "content-type": "application/json", "cache-control": "public, max-age=300" } });
}
