browser.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  browser.runtime.sendNativeMessage("application.id", msg).then(sendResponse).catch(() => sendResponse({ ok: false }));
  return true;
});
