// GET /api/club/me: who is signed in and which months are open.

import { CLUB } from "../../_catalog.js";
import { currentMember, monthsOpen, opensAt, json, clearCookie } from "../../_club.js";

export async function onRequestGet({ request, env }) {
  const { member, setCookie, ended } = await currentMember(request, env);
  if (!member) return json({ member: false, ended: !!ended }, 401, ended ? { "set-cookie": clearCookie } : {});
  const open = monthsOpen(member);
  const months = {};
  for (let m = 1; m <= 6; m++) months[m] = { open: m <= open, opens: opensAt(member, m) };
  return json(
    { member: true, email: member.email, plan: member.yearly ? "yearly" : "monthly", months, portal: CLUB.portal },
    200,
    setCookie ? { "set-cookie": setCookie } : {}
  );
}
