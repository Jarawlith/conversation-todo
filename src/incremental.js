const crypto = require('node:crypto');
const fingerprint = m => crypto.createHash('sha256').update(JSON.stringify([m.role, m.time, m.text])).digest('hex');
function prepare(c, previous) {
  const seen = previous?.messageHashes || {};
  const pending = c.messages.map((m, i) => ({m, i})).filter(({m}) => seen[m.key] !== fingerprint(m));
  if (!pending.length) return null;
  const picked = []; let chars = 0;
  for (const item of pending) {
    if (picked.length && chars + item.m.text.length > 10000) break;
    picked.push(item); chars += item.m.text.length;
  }
  const context = c.messages.slice(Math.max(0, picked[0].i - 2), picked[0].i)
    .map(m => ({...m, text: m.text.slice(-1200)}));
  const messageHashes = {...seen};
  for (const {m} of picked) messageHashes[m.key] = fingerprint(m);
  const more = picked.length < pending.length;
  return {...c, messages: [...context, ...picked.map(x => x.m)], newKeys: picked.map(x => x.m.key),
    messageHashes, signature: more ? '' : c.signature, digest: more ? '' : c.digest, backlog: more};
}
module.exports = {prepare, fingerprint};
