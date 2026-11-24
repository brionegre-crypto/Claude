// GET /api/cohort-status: whether the Founding Cohort checkout is open (seats left, not started).
import { cohortStatus } from "../_extras.js";
export async function onRequestGet({ env }) {
  let s = { open: true };
  try { s = await cohortStatus(env); } catch (e) {}
  return new Response(JSON.stringify(s), { headers: { "content-type": "application/json", "cache-control": "public, max-age=60" } });
}
