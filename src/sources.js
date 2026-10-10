const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const digest = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
function select(messages) {
  return messages.map(m => ({...m, text:m.text.slice(0,12000)}));
}

function readClaude(file) {
  const stat = fs.statSync(file), start = Math.max(0, stat.size - 4 * 1024 * 1024);
  const buffer = Buffer.alloc(stat.size - start), fd = fs.openSync(file, 'r');
  try { fs.readSync(fd, buffer, 0, buffer.length, start); } finally { fs.closeSync(fd); }
  let text = buffer.toString('utf8'); if (start) text = text.slice(text.indexOf('\n') + 1);
  const messages = []; let sessionId = path.basename(file, '.jsonl');
  for (const line of text.split('\n')) {
    let r; try { r = JSON.parse(line); } catch { continue; }
    if (r.sessionId) sessionId = r.sessionId;
    if (r.isSidechain || r.isMeta || !['user', 'assistant'].includes(r.type)) continue;
    const content = r.message?.content;
    const body = typeof content === 'string' ? content : Array.isArray(content)
      ? content.filter(c => c.type === 'text').map(c => c.text || '').join('\n') : '';
    if (!body.trim() || /^<(?:system-reminder|local-command|command-name)/.test(body)) continue;
    messages.push({ key: r.uuid || digest([r.timestamp, r.type, body]), role: r.type, time: r.timestamp || '', text: body.trim() });
  }
  const selected = select(messages);
  return { id: 'claude-code:' + sessionId, sourceType: 'Claude Code', title: (messages.find(m => m.role === 'user')?.text || sessionId).replace(/\s+/g, ' ').slice(0, 70), file,
    modified: stat.mtimeMs, signature: stat.size + ':' + stat.mtimeMs, digest: digest(selected), messages: selected, truncated: start > 0 || selected.length < messages.length };
}
function validateCapture(value) {
  if (!value || !['chatgpt', 'claude'].includes(value.platform)) throw new Error('不支持的来源');
  const url = new URL(value.url);
  const host = value.platform === 'chatgpt' ? 'chatgpt.com' : 'claude.ai';
  const route = value.platform === 'chatgpt' ? /^\/c\/([\w-]+)$/ : /^\/chat\/([\w-]+)$/;
  const match = url.pathname.match(route);
  if (url.protocol !== 'https:' || url.hostname !== host || !match || url.port || url.username || url.password) throw new Error('无效的对话网址');
  if (!Array.isArray(value.messages) || !value.messages.length || value.messages.length > 120) throw new Error('无效的消息数量');
  const messages = value.messages.map(m => {
    if (!m || !['user', 'assistant'].includes(m.role) || typeof m.text !== 'string' || !m.text.trim() || m.text.length > 12000) throw new Error('无效的对话消息');
    return { key: typeof m.key === 'string' && /^[\w:-]{1,160}$/.test(m.key) ? m.key : digest([m.role, m.text]), role: m.role, text: m.text.trim(), time: '' };
  });
  return { id: value.platform + ':' + match[1], sourceType: value.platform === 'chatgpt' ? 'ChatGPT 网页' : 'Claude 网页', url: url.origin + url.pathname,
    title: String(value.title || host).slice(0, 100), messages, capturedAt: new Date().toISOString(), partial: true };
}
function saveCapture(value, dataDir) {
  const capture = validateCapture(value);
  const config = readJson(path.join(dataDir, 'settings.json'), {});
  if (config.paused || config.running === false || config.setupComplete === false || (config.excluded || []).includes(capture.id)) return { ok: true, skipped: true, reason: config.paused || config.running === false || config.setupComplete === false ? 'paused' : 'excluded' };
  const file = path.join(dataDir, 'browser', digest(capture.id) + '.json');
  const previous = readJson(file, null);
  const merged = new Map((previous?.messages || []).map(m => [m.key, m]));
  for (const m of capture.messages) merged.set(m.key, m);
  capture.messages = [...merged.values()].slice(-200);
  if (previous && digest(previous.messages) === digest(capture.messages) && previous.title === capture.title) return { ok: true, unchanged: true };
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = file + '.' + process.pid + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(capture)); fs.renameSync(temporary, file);
  return { ok: true, sourceId: capture.id };
}
function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')); } catch (e) { if (e.code === 'ENOENT') return fallback; throw e; }
}
function readBrowser(file) {
  const stat = fs.statSync(file), capture = readJson(file, null), selected = select(capture.messages);
  return { ...capture, file, messages: selected, modified: stat.mtimeMs, signature: stat.size + ':' + stat.mtimeMs, digest: digest(selected), truncated: true };
}
module.exports = { readClaude, readBrowser, saveCapture, validateCapture, select };
