const assert=require('node:assert/strict');
const {codexModelArgs}=require('../src/analyze');
assert.deepEqual(codexModelArgs({codexModel:'gpt-6-sol',codexEffort:'high'}),['--model','gpt-6-sol','-c','model_reasoning_effort="high"']);
assert.deepEqual(codexModelArgs({}),['--model','gpt-6-luna','-c','model_reasoning_effort="medium"']);
assert.throws(()=>codexModelArgs({codexEffort:'invalid'}));
console.log('PASS: CLI model and effort arguments, old settings default and invalid effort');
