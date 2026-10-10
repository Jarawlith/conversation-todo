const path = require('node:path');
const fs = require('node:fs');
const { saveCapture } = require('./sources');
const dataDir = path.join(process.env.LOCALAPPDATA, 'CodexTodo');
let buffer = Buffer.alloc(0);
function respond(value) {
  const data = Buffer.from(JSON.stringify(value)), header = Buffer.alloc(4);
  header.writeUInt32LE(data.length); process.stdout.write(Buffer.concat([header, data]));
}
process.stdin.on('data', chunk => {
  buffer = Buffer.concat([buffer, chunk]);
  while (buffer.length >= 4) {
    const size = buffer.readUInt32LE();
    if (size > 2 * 1024 * 1024) { process.exitCode = 1; process.stdin.destroy(); return; }
    if (buffer.length < size + 4) return;
    const frame = buffer.subarray(4, size + 4); buffer = buffer.subarray(size + 4);
    try {
      const value = JSON.parse(frame.toString('utf8'));
      if (value.type === 'status') {
        const file = path.join(dataDir, 'settings.json');
        const config = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')) : {};
        respond({ ok: true, paused: Boolean(config.paused) || config.running === false || config.setupComplete === false, excluded: config.excluded || [] });
      } else respond(saveCapture(value, dataDir));
    }
    catch (error) { respond({ ok: false, error: error.message }); }
  }
});
