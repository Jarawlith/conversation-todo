'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const zlib = require('node:zlib');
const {Readable} = require('node:stream');
const {pipeline} = require('node:stream/promises');
const {createEngine} = require('./speech-engine');
const models = require('./speech-models.json');
function writeJson(file, value) {
  fs.writeFileSync(file + '.tmp', JSON.stringify(value));
  for (let attempt=0;;attempt++) {
    try { fs.renameSync(file + '.tmp', file); return; }
    catch (error) {
      if (!['EPERM','EBUSY'].includes(error.code) || attempt >= 20) throw error;
      // Windows readers can briefly hold a handle without FILE_SHARE_DELETE.
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 10);
    }
  }
}
async function hashFile(file) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}
async function prepare(model, directory, report = () => {}) {
  fs.mkdirSync(directory, {recursive: true});
  const file = path.join(directory, model.file);
  if (fs.existsSync(file) && await hashFile(file) === model.sha256) return file;
  const response = await fetch(model.url, {signal: AbortSignal.timeout(600000)});
  if (!response.ok || !response.body) throw new Error('Model download HTTP ' + response.status);
  const temporary = file + '.part';
  let bytes = 0, lastReport = 0;
  const total = Number(response.headers.get('content-length'));
  const input = Readable.fromWeb(response.body);
  input.on('data', chunk => {
    bytes += chunk.length;
    if (Date.now() - lastReport > 500) {
      lastReport = Date.now(); report({status:'downloading', bytes, total});
    }
  });
  try {
    if (model.compression === 'gzip') await pipeline(input, zlib.createGunzip(), fs.createWriteStream(temporary));
    else await pipeline(input, fs.createWriteStream(temporary));
    if (await hashFile(temporary) !== model.sha256) throw new Error('Model checksum mismatch');
    fs.renameSync(temporary, file);
    return file;
  } finally { fs.rmSync(temporary, {force:true}); }
}
function pcmSamples(buffer) {
  if (buffer.length % 2) throw new Error('Invalid PCM audio');
  const samples = new Float32Array(buffer.length / 2);
  for (let i = 0; i < samples.length; i++) samples[i] = buffer.readInt16LE(i * 2) / 32768;
  return samples;
}
function transcribe(engine, samples) {
  if (samples.length < 1600) return '';
  let power = 0;
  for (const sample of samples) power += sample * sample;
  if (Math.sqrt(power / samples.length) < 0.001) return '';
  // Keep inference bounded even when a key is held for a long time.
  const texts = [];
  for (let start = 0; start < samples.length; start += 30 * 16000) {
    const text = engine.transcribe(samples.subarray(start, start + 30 * 16000));
    if (text) texts.push(text);
  }
  return texts.join('\n');
}
async function run(requestFile) {
  const request = JSON.parse(fs.readFileSync(requestFile, 'utf8').replace(/^\uFEFF/, ''));
  const model = models.find(m => m.id === request.model);
  if (!model) throw new Error('Unknown speech model');
  const report = value => writeJson(request.result, value);
  let engine;
  try {
    await prepare(model, request.directory, report);
    if (request.operation === 'prepare') { report({status:'ready'}); return; }
    report({status:'recognizing'});
    const start = performance.now();
    engine = createEngine(model, request.directory, request.language);
    const samples = pcmSamples(fs.readFileSync(request.audio));
    const text = transcribe(engine, samples);
    report({status:'done', text, duration:samples.length / 16000,
      elapsedMs:Math.round(performance.now() - start)});
  } catch (error) { report({status:'error', error:error.message}); process.exitCode = 1; }
  finally {
    if (engine) engine.dispose();
    if (request.audio) fs.rmSync(request.audio, {force:true});
  }
}
module.exports = {prepare, pcmSamples, transcribe, hashFile};
if (require.main === module) run(process.argv[2]).catch(() => {process.exitCode = 1;});
