// /r/<code>: a man's referral link. Goes to Step 1 with the code, which the site keeps
// and sends with the sign-up so he gets the credit.
export function onRequestGet({ params, request }) {
  const code = String(params.code || "").replace(/[^a-z0-9]/gi, "").slice(0, 12);
  return Response.redirect(new URL(`/step-1/?ref=${code}`, request.url).toString(), 302);
}
