const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {originalEvidence, run, readJson} = require('../src/analyze');

async function main() {
  const messages = [{text:'前文😀 请在明天\n完成 ＡＢＣ 报告。后文'}];
  assert.equal(originalEvidence(messages,'请在明天完成 ABC 报告。'),'请在明天\n完成 ＡＢＣ 报告。');
  assert.equal(originalEvidence(messages,'😀请在明天'),'😀 请在明天');
  assert.equal(originalEvidence(messages,'明天交付总结报告'),null);
  assert.equal(originalEvidence([{text:'准备报告'},{text:'明天提交'}],'准备报告明天提交'),null);
  assert.equal(originalEvidence(messages,'   '),null);
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'conversation-evidence-'));
  const previousClaude=process.env.CLAUDE_CONFIG_DIR;
  process.env.CLAUDE_CONFIG_DIR=path.join(root,'no-claude');
  try {
    const sessions=path.join(root,'sessions');fs.mkdirSync(sessions);
    for(let i=0;i<8;i++) fs.writeFileSync(path.join(sessions,`c${i}.jsonl`),[
      {type:'session_meta',payload:{id:`c${i}`}},
      {type:'response_item',payload:{id:`m${i}`,type:'message',role:'user',content:[{type:'input_text',text:'明天整理测试报告并提交给团队。'}]}}
    ].map(r=>JSON.stringify(r)).join('\n'));
    function answer(batch,bad=false){return {answer:{conversations:batch.map(c=>({id:c.id,tasks:[{title:'整理测试报告',kind:'explicit',priority:2,reason:'明确行动',evidence:bad&&c.id==='c0'?'用户计划撰写报告':'明天整理测试报告',due:'',existing_id:''}],resolved_ids:[],cancelled_ids:[]}))},usage:[]};}
    const repaired=path.join(root,'repaired');let repairs=0;
    await run(repaired,sessions,2,async(batch,state,data,repair)=>{
      if(repair){repairs++;assert.equal(batch.length,1);assert.equal(batch[0].id,'c0');return answer(batch);}
      return answer(batch,true);
    });
    assert.equal(repairs,1);
    assert.equal(Object.keys(readJson(path.join(repaired,'state.json')).tasks).length,8);
    assert.equal(readJson(path.join(repaired,'state.json')).initialScanComplete,true);

    const failed=path.join(root,'failed');let failedRepairs=0;
    await run(failed,sessions,2,async(batch,state,data,repair)=>{
      if(repair)failedRepairs++;
      return answer(batch,true);
    });
    const checkpoint=readJson(path.join(failed,'state.json'));
    assert.equal(failedRepairs,1,'Invalid quote retried repeatedly');
    assert.equal(Object.keys(checkpoint.tasks).length,7,'Bad conversation prevented other results');
    assert.ok(!checkpoint.initialScanComplete);
    assert.ok(!checkpoint.sources.c0.messageHashes,'Failed conversation checkpoint advanced');
    assert.equal(readJson(path.join(failed,'progress.json')).remaining,1);
    let retried=0;
    await run(failed,sessions,2,async batch=>{
      retried+=batch.length;assert.equal(batch[0].id,'c0');return answer(batch);
    });
    assert.equal(retried,1);
    assert.equal(readJson(path.join(failed,'state.json')).initialScanComplete,true);
    console.log('PASS: original whitespace/full-width quotes, fabricated and cross-message quotes rejected, targeted bounded repair, other conversations saved, failed checkpoint resumed');
  } finally {
    if(previousClaude===undefined)delete process.env.CLAUDE_CONFIG_DIR;else process.env.CLAUDE_CONFIG_DIR=previousClaude;
    fs.rmSync(root,{recursive:true,force:true});
  }
}
main().catch(error=>{console.error(error);process.exitCode=1;});
