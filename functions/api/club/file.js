// GET /api/club/file?f=<file key>: a Club file for a signed-in member,
// once the month that includes it is open.

import { CLUB, FILES } from "../../_catalog.js";
import { currentMember, monthsOpen } from "../../_club.js";
import { getFile } from "../download.js";

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const key = url.searchParams.get("f");
  const month = CLUB.files[key];
  if (!month || !FILES[key]) return new Response("Not found", { status: 404 });
  const { member } = await currentMember(request, env);
  if (!member) return Response.redirect(new URL("/club-login/?next=/members/", url).toString(), 302);
  if (month > monthsOpen(member)) return Response.redirect(new URL("/members/?locked=file", url).toString(), 302);
  const got = await getFile(env, key);
  if (!got) return Response.redirect(FILES[key].url, 302);
  return new Response(got.body, {
    headers: {
      "content-type": got.type || "application/octet-stream",
      "content-disposition": `attachment; filename="${FILES[key].name}"`,
      "cache-control": "private, no-store",
      "x-robots-tag": "noindex",
    },
  });
}
