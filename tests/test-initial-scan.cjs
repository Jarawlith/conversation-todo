const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {run, readJson, writeJson} = require('../src/analyze');

async function main() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'conversation-initial-'));
  const previousClaude = process.env.CLAUDE_CONFIG_DIR;
  process.env.CLAUDE_CONFIG_DIR = path.join(root, 'no-claude');
  try {
    const sessions = path.join(root, 'sessions'); fs.mkdirSync(sessions);
    function conversation(id, count = 1) {
      const records = [{type:'session_meta',payload:{id}}];
      for (let i=0; i<count; i++) records.push({type:'response_item',timestamp:String(i),payload:{id:`${id}-${i}`,type:'message',role:'user',content:[{type:'input_text',text:'待办文字'.repeat(500)}]}});
      fs.writeFileSync(path.join(sessions, id+'.jsonl'), records.map(r=>JSON.stringify(r)).join('\n'));
    }
    for (let i=0; i<9; i++) conversation('c'+i, i===0 ? 12 : 1);
    const data = path.join(root, 'data');
    const seen = new Set(); let calls=0;
    async function analyze(batch) {
      calls++;
      for (const c of batch) for (const key of c.newKeys) {
        assert.ok(!seen.has(key), 'Already analyzed message was resent'); seen.add(key);
      }
      return {answer:{conversations:batch.map(c=>({id:c.id,tasks:[],resolved_ids:[],cancelled_ids:[]}))},usage:[]};
    }
    await run(data, sessions, 2, analyze);
    assert.ok(calls>2, 'Initial scan stopped at the old batch limit');
    assert.equal(seen.size, 20); // All nine conversations, including all chunks of the long one.
    assert.equal(readJson(path.join(data,'state.json')).initialScanComplete, true);
    assert.equal(readJson(path.join(data,'progress.json')).remaining, 0);
    const callsBefore=calls; await run(data,sessions,2,analyze);
    assert.equal(calls,callsBefore,'Unchanged history called the model');

    const resume = path.join(root,'resume'); let attempts=0;
    await assert.rejects(run(resume,sessions,2,async batch=>{
      if (++attempts===2) throw new Error('temporary failure');
      return {answer:{conversations:batch.map(c=>({id:c.id,tasks:[],resolved_ids:[],cancelled_ids:[]}))}};
    }), /temporary failure/);
    assert.ok(!readJson(path.join(resume,'state.json')).initialScanComplete);
    const checkpoint=readJson(path.join(resume,'state.json'));
    await run(resume,sessions,2,async batch=>{
      for (const c of batch) for (const key of c.newKeys) assert.ok(!checkpoint.sources[c.id]?.messageHashes?.[key], 'Resume resent a successful chunk');
      return {answer:{conversations:batch.map(c=>({id:c.id,tasks:[],resolved_ids:[],cancelled_ids:[]}))}};
    });
    assert.equal(readJson(path.join(resume,'state.json')).initialScanComplete,true);

    const paused = path.join(root,'paused');
    await run(paused,sessions,2,async batch=>{
      writeJson(path.join(paused,'settings.json'),{paused:true});
      return {answer:{conversations:batch.map(c=>({id:c.id,tasks:[],resolved_ids:[],cancelled_ids:[]}))}};
    });
    assert.ok(!readJson(path.join(paused,'state.json')).initialScanComplete);
    assert.ok(readJson(path.join(paused,'progress.json')).remaining>0);
    console.log('PASS: full initial queue, long conversation chunks, unchanged scan, failure checkpoint resume and pause');
  } finally {
    if (previousClaude === undefined) delete process.env.CLAUDE_CONFIG_DIR; else process.env.CLAUDE_CONFIG_DIR=previousClaude;
    fs.rmSync(root,{recursive:true,force:true});
  }
}
main().catch(error=>{console.error(error);process.exitCode=1;});
