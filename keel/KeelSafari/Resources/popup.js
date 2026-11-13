async function page() {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  return tab;
}
async function selection(tab) {
  try {
    const [r] = await browser.scripting.executeScript({ target: { tabId: tab.id }, func: () => String(window.getSelection() || "") });
    return (r && r.result) || "";
  } catch (e) { return ""; }
}
async function send(extra) {
  const tab = await page();
  const msg = Object.assign({ url: tab.url, title: tab.title }, extra || {});
  const res = await browser.runtime.sendNativeMessage("application.id", msg).catch(() => ({ ok: false }));
  document.getElementById("msg").textContent = res && res.ok ? "Saved. It's in Keel next time you open it." : "Couldn't save. Open Keel once, then try again.";
}
document.getElementById("save").onclick = () => send();
document.getElementById("hl").onclick = async () => {
  const tab = await page();
  const text = await selection(tab);
  if (!text.trim()) { document.getElementById("msg").textContent = "Select some text on the page first."; return; }
  send({ highlight: text });
};
