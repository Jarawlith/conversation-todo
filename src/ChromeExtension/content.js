(() => {
  let previous = '', stable = '', inFlight = false;
  function source() {
    const platform = location.hostname === 'chatgpt.com' ? 'chatgpt' : 'claude';
    const match = location.pathname.match(platform === 'chatgpt' ? /^\/c\/([\w-]+)$/ : /^\/chat\/([\w-]+)$/);
    return match ? { platform, id: platform + ':' + match[1], url: location.origin + location.pathname } : null;
  }
  function collect(info) {
    const selector = info.platform === 'chatgpt' ? '[data-message-author-role="user"], [data-message-author-role="assistant"]'
      : '[data-testid="user-message"], .font-claude-response';
    const nodes = [...document.querySelectorAll(selector)].filter(n => !n.parentElement?.closest(selector));
    const messages = nodes.map(node => {
      const role = info.platform === 'chatgpt' ? node.getAttribute('data-message-author-role') : node.matches('[data-testid="user-message"]') ? 'user' : 'assistant';
      const body = node.querySelector(role === 'assistant' ? '.markdown, .standard-markdown' : '.whitespace-pre-wrap') || node;
      const clone = body.cloneNode(true);
      clone.querySelectorAll('button, script, style, [aria-hidden="true"], .sr-only').forEach(n => n.remove());
      clone.querySelectorAll('p, li, pre, h1, h2, h3, blockquote').forEach(n => n.appendChild(document.createTextNode('\n')));
      const key = node.getAttribute('data-message-id') || node.closest('[data-message-id]')?.getAttribute('data-message-id') || '';
      return { key, role, text: (clone.textContent || '').trim().slice(0, 12000) };
    }).filter(m => m.text).slice(-120);
    const streaming = Boolean(document.querySelector('[data-is-streaming="true"], button[data-testid="stop-button"]'));
    const title = document.querySelector('[data-testid="chat-title-button"]')?.textContent || document.title;
    return { platform: info.platform, url: info.url, title, messages, streaming };
  }
  async function tick() {
    if (inFlight) return;
    const info = source(); if (!info) return;
    inFlight = true;
    try {
      const policy = await chrome.runtime.sendMessage({ type: 'policy' });
      if (!policy?.ok || policy.paused || policy.excluded?.includes(info.id)) { previous = ''; stable = ''; return; }
      const capture = collect(info);
      if (capture.streaming || !capture.messages.length) return;
      const signature = JSON.stringify(capture);
      if (signature !== stable) { stable = signature; return; }
      if (signature === previous) return;
      const result = await chrome.runtime.sendMessage({ type: 'capture', capture });
      if (result?.ok && !result.skipped) previous = signature;
    } catch { /* The extension popup reports bridge errors; retry after reconnect. */ }
    finally { inFlight = false; }
  }
  setInterval(tick, 5000); tick();
})();
