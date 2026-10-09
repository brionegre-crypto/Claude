// Old systeme.io links (go.bethemansystem.com/...) keep working after systeme
// is cancelled: once go.bethemansystem.com is added to this Pages project as a
// custom domain, every old path is sent to its page on bethemansystem.com.
// Requests to any other host pass straight through.

const OLD = {
  "/framework": "/step-1/", "/check-your-email": "/step-1/thanks/", "/school": "/members/",
  "/7ccfe2c8": "/", "/085b95e4": "/call/", "/782480a3": "/training/", "/28016a3c": "/step-1/",
  "/42f82c9e": "/7-week-challenge/", "/a27908db": "/7-week-challenge/thanks/",
  "/f0217426": "/workshop/", "/04e81fbc": "/workshop/", "/5f29075e": "/group/", "/19a83007": "/the-club/",
  "/b1c774c0": "/group/", "/d1271f91": "/group/",
  "/6aa4411c": "/ministry-kit/", "/5d2dbb3f": "/ministry-kit/",
  "/d6dd7931": "/the-club/", "/c24bf36b": "/the-club/", "/f05699c8": "/the-club/",
  "/3b3e5ba2": "/inner-circle/", "/7d78815c": "/products/#the-system", "/9dd8db8c": "/products/",
  "/60edb131": "/products/", "/1745f8e9": "/products/", "/9ffe8144": "/workshop/",
  "/4b9241c3": "/products/#your-marriage", "/1d991719": "/products/#your-marriage", "/e533d404": "/products/#your-marriage",
  "/96078b04": "/products/#fatherhood", "/0476a5cf": "/products/#fatherhood",
  "/fe06b4ca": "/products/#your-faith", "/42ecffa1": "/products/#your-faith", "/227a8255": "/products/#your-faith",
  "/47a09e06": "/products/#your-faith",
};

export async function onRequest(context) {
  const url = new URL(context.request.url);
  if (url.hostname !== "go.bethemansystem.com") return context.next();
  const path = url.pathname.replace(/\/+$/, "") || "/";
  const to = OLD[path] || (path.startsWith("/school") ? "/members/" : "/");
  return Response.redirect("https://bethemansystem.com" + to, 301);
}
