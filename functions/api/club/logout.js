// GET /api/club/logout
import { clearCookie } from "../../_club.js";

export async function onRequestGet({ request }) {
  return new Response(null, { status: 302, headers: { location: new URL("/club-login/?out=1", request.url).toString(), "set-cookie": clearCookie } });
}
