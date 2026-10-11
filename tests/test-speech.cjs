const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const zlib = require('node:zlib');
const http = require('node:http');
const crypto = require('node:crypto');
const {prepare,pcmSamples,transcribe} = require('../src/speech-worker');
(async () => {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'todo-speech-'));
  const data=Buffer.from('fixture-model');
  let requests=0;
  const server=http.createServer((req,res)=>{ requests++;res.end(zlib.gzipSync(data)); });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const model={file:'model.onnx',compression:'gzip',sha256:crypto.createHash('sha256').update(data).digest('hex'),url:`http://127.0.0.1:${server.address().port}`};
  try {
    await prepare(model,dir);await prepare(model,dir);
    assert.equal(requests,1,'verified cached model must work without network');
    fs.writeFileSync(path.join(dir,model.file),'truncated');await prepare(model,dir);
    assert.equal(requests,2,'corrupt cache must be repaired');
    await assert.rejects(prepare({...model,file:'bad.onnx',sha256:'bad'},dir),/checksum/);
    assert.equal(fs.existsSync(path.join(dir,'bad.onnx')),false);
    assert.equal(fs.existsSync(path.join(dir,'bad.onnx.part')),false);
    assert.deepEqual(Array.from(pcmSamples(Buffer.from([0,0,0,128,255,127]))),[0,-1,32767/32768]);
    let calls=0;
    const engine={transcribe:()=>{calls++;return '记录';}};
    assert.equal(transcribe(engine,new Float32Array(16000)), '');assert.equal(calls,0,'silence must not create invented tasks');
    assert.equal(transcribe(engine,new Float32Array(61*16000).fill(0.1)), '记录\n记录\n记录');assert.equal(calls,3,'long capture uses bounded chunks');
    const {createEngine}=require('../src/speech-engine');
    assert.throws(()=>createEngine({engine:'future',languages:['auto']},dir),/Unsupported speech engine/);
    console.log('PASS: verified downloads, offline reuse, corrupt cache recovery, no partial model, PCM, silence, bounded audio and adapter validation');
  } finally {server.close();fs.rmSync(dir,{recursive:true,force:true});}
})().catch(error=>{console.error(error);process.exitCode=1;});
