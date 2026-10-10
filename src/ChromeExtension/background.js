const HOST = 'com.codextodo.capture';
let port = null;
const pending = [];
function request(payload, callback) {
  if (!port) {
    port = chrome.runtime.connectNative(HOST);
    port.onMessage.addListener(result => { const next = pending.shift(); if (next) next(result); });
    port.onDisconnect.addListener(() => {
      const error = chrome.runtime.lastError?.message || '本机连接已断开'; port = null;
      for (const callback of pending.splice(0)) callback({ ok: false, error });
    });
  }
  pending.push(callback); port.postMessage(payload);
}
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (!sender.tab || !/^https:\/\/(chatgpt\.com|claude\.ai)\//.test(sender.tab.url || '')) return;
  const payload = message.type === 'policy' ? { type: 'status' } : message.capture;
  if (!payload) return;
  request(payload, async result => {
    const status = result || { ok: false, error: '本机程序没有响应' };
    if (message.type !== 'policy' || !status.ok) {
      await chrome.storage.local.set({ lastStatus: { ...status, at: new Date().toISOString() } });
      chrome.action.setBadgeText({ text: status.ok ? '' : '!' });
      chrome.action.setBadgeBackgroundColor({ color: '#AD4949' });
    }
    reply(status);
  });
  return true;
});
