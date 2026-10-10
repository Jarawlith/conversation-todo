// Pilot relay. Run behind HTTPS; use a distinct revocable token per tester.
const http = require('node:http');
const crypto = require('node:crypto');
const path = require('node:path');
const {api} = require('./providers');
const {schema, readJson, writeJson} = require('./analyze');
const {fetchCatalog, allowed} = require('./catalog');
const policy = require('./hosted-policy.json');
function createServer(config) {
  const usageFile = path.join(config.dataDir,'usage.json');
  const usage = readJson(usageFile, {}); let busy = 0;
  let catalog = config.catalog || readJson(path.join(__dirname,'models.json'),null);
  let refresh;
  async function models() {
    if (!catalog || Date.now()-Date.parse(catalog.updated)>86400000) {
      if(!refresh) refresh=fetchCatalog().then(c=>{catalog=c;}).finally(()=>{refresh=null;});
      try {await refresh;} catch {if(!catalog) throw new Error('catalog_unavailable');}
    }
    return catalog.models;
  }
  return http.createServer(async (req,res) => {
    const send = (code,value) => {res.writeHead(code,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(value));};
    if (!((req.method==='POST' && req.url==='/analyze') || (req.method==='GET' && req.url==='/models'))) return send(404,{error:'not_found'});
    const token = (req.headers.authorization || '').replace(/^Bearer /,'');
    const entry = Object.entries(config.clients).find(([,record])=>{
      const expected=typeof record==='string'?record:record.token;
      if(typeof expected!=='string') return false;
      const a=Buffer.from(token),b=Buffer.from(expected); return a.length===b.length && crypto.timingSafeEqual(a,b);
    });
    if (!entry) return send(401,{error:'unauthorized'});
    const [user,account]=entry;
    const edition=typeof account==='string'?'mainland':account.edition;
    if(!['mainland','overseas'].includes(edition)) return send(403,{error:'invalid_account_edition'});
    if(req.method==='GET') {
      try {const list=await models();return send(200,{edition,updated:catalog.updated,models:list.filter(m=>allowed(m,edition))});}
      catch {return send(503,{error:'catalog_unavailable'});}
    }
    if (busy >= config.concurrency) return send(429,{error:'busy'});
    busy++;
    try {
      let size=0;const chunks=[];
      for await (const chunk of req) {size+=chunk.length;if(size>200000) {send(413,{error:'input_too_large'});req.destroy();return;} chunks.push(chunk);}
      const body=JSON.parse(Buffer.concat(chunks));
      if(typeof body.prompt!=='string'||!body.prompt.trim()||body.prompt.length>60000) return send(400,{error:'invalid_input'});
      if(typeof body.model!=='string') return send(400,{error:'model_required'});
      const model=(await models()).find(m=>m.id===body.model);
      if(!model || !allowed(model,edition)) return send(403,{error:'model_not_allowed'});
      if(!config.key && !config.request) return send(503,{error:'api_not_configured'});
      const day=new Date().toISOString().slice(0,10);const id=day+':'+user;
      const current=usage[id]||{requests:0,inputChars:0};
      if(current.requests>=config.dailyRequests||current.inputChars+body.prompt.length>config.dailyChars) return send(429,{error:'daily_limit'});
      // Reserve before calling; never retry automatically or log conversation text.
      usage[id]={requests:current.requests+1,inputChars:current.inputChars+body.prompt.length};writeJson(usageFile,usage);
      const result=await (config.request || api)({...config,apiModel:model.id,providerMaxPrice:edition==='mainland'?policy.maxPrice:undefined,jsonMode:model.jsonMode,analysisReasoning:model.analysisReasoning,temperatureControl:model.temperatureControl,outputLimit:8192},body.prompt,schema,config.key);
      result.model=model.id;
      send(200,result);
    } catch (error) {
      const code=['upstream_http','output_limit','invalid_json','region_unavailable'].includes(error.code)?error.code:'analysis_failed';
      console.warn(JSON.stringify({error:code,upstreamStatus:error.status,finishReason:error.finishReason,outputShape:error.outputShape}));
      if(!res.headersSent) send(502,{error:code,upstreamStatus:error.status});
    }
    finally {busy--;}
  });
}
if(require.main===module) {
  const clients=JSON.parse(process.env.TODO_CLIENT_TOKENS || '{}');
  if(!Object.keys(clients).length || Object.values(clients).some(t=>typeof (typeof t==='string'?t:t.token)!=='string'||(typeof t==='string'?t:t.token).length<32)) throw new Error('请设置每个用户的访问令牌（至少 32 字符）。');
  const config={clients,key:process.env.TODO_API_KEY,apiModel:process.env.TODO_API_MODEL,
    apiProtocol:'openai',apiBase:'https://openrouter.ai/api/v1',
    dataDir:process.env.TODO_DATA_DIR || path.join(__dirname,'server-data'),
    concurrency:Number(process.env.TODO_CONCURRENCY || 2),dailyRequests:Number(process.env.TODO_DAILY_REQUESTS || 60),dailyChars:Number(process.env.TODO_DAILY_CHARS || 300000)};
  for(const k of ['concurrency','dailyRequests','dailyChars']) if(!Number.isInteger(config[k])||config[k]<1) throw new Error('服务端额度必须为正整数。');
  createServer(config).listen(Number(process.env.PORT || 18788),'127.0.0.1',()=>console.log('Conversation Todo relay listening on localhost'));
}
module.exports={createServer};
