const fs = require('node:fs');
const path = require('node:path');
const policy = require('./hosted-policy.json');
function normalize(rows) {
  return rows.filter(m => /^(deepseek|openai|anthropic)\//.test(m.id || ''))
    .map(m => ({id:m.id,name:m.name || m.id,family:m.id.split('/')[0],context:m.context_length || 0,
      supported:(m.architecture?.input_modalities || []).includes('text') && (m.architecture?.output_modalities || []).includes('text'),
      jsonMode:(m.supported_parameters || []).includes('response_format'),
      structured:(m.supported_parameters || []).includes('structured_outputs'),
      analysisReasoning:m.reasoning ? (m.reasoning.mandatory ? (m.reasoning.supported_efforts?.length ? {effort:m.reasoning.supported_efforts.filter(e=>e!=='none').at(-1),exclude:true} : undefined) : {enabled:false}) : undefined,
      temperatureControl:(m.supported_parameters || []).includes('temperature'),
      inputPrice:Number(m.pricing?.prompt)*1000000,outputPrice:Number(m.pricing?.completion)*1000000}))
    .sort((a,b)=>a.name.localeCompare(b.name));
}
async function fetchCatalog() {
  const r=await fetch('https://openrouter.ai/api/v1/models',{signal:AbortSignal.timeout(15000)});
  if(!r.ok) throw new Error('OpenRouter 模型目录暂不可用。');
  const body=await r.json();if(!Array.isArray(body.data)) throw new Error('模型目录格式错误。');
  return {updated:new Date().toISOString(),models:normalize(body.data)};
}
function allowed(model,edition) {return model.supported && (edition==='overseas' || model.id===policy.mainlandModel);}
module.exports={normalize,fetchCatalog,allowed};
if(require.main===module) fetchCatalog().then(c=>{
  fs.writeFileSync(process.argv[2] || path.join(__dirname,'models.json'),JSON.stringify(c,null,2),'utf8');
  console.log(JSON.stringify({updated:c.updated,count:c.models.length}));
}).catch(e=>{console.error(e.message);process.exitCode=1});
