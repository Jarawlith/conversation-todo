const fs = require('node:fs');
const path = require('node:path');
const {spawn, execFileSync} = require('node:child_process');
function endpoint(value) {
  const u = new URL(value);
  if (u.username || u.password || (u.protocol !== 'https:' && !(u.protocol === 'http:' && ['127.0.0.1','localhost','[::1]'].includes(u.hostname)))) throw new Error('接口必须使用 HTTPS；本机测试可用 HTTP。');
  return u.href.replace(/\/$/, '');
}
function secret(dataDir, name) {
  const file = path.join(dataDir, name + '.secret');
  if (!fs.existsSync(file)) throw new Error('请在设置中填写密钥或服务访问令牌。');
  return execFileSync('powershell.exe', ['-NoProfile','-File',path.join(__dirname,'Secret.ps1'),'-File',file], {windowsHide:true,encoding:'utf8'}).trim();
}
async function post(url, headers, body) {
  const r = await fetch(endpoint(url), {method:'POST',redirect:'error',headers:{'Content-Type':'application/json',...headers},body:JSON.stringify(body),signal:AbortSignal.timeout(180000)});
  if (!r.ok) {
    let body;try {body=await r.json();} catch {}
    const labels={output_limit:'模型输出达到限制，本次进度未保存。',invalid_json:'模型未返回有效 JSON，本次进度未保存。',region_unavailable:'当前分析服务器所在地区不支持这个模型；请选择可用模型或调整服务部署。',upstream_http:'模型供应商拒绝或未完成请求。'};
    const regionDenied=r.status===403 && typeof body?.error?.message==='string' && /(?:not available in your region|unsupported (?:country|region)|country.*not supported)/i.test(body.error.message);
    if(regionDenied) body={error:'region_unavailable'};
    const error=new Error(labels[body?.error] || `分析服务返回 HTTP ${r.status}；请检查账号、模型和额度。`);
    error.code=body?.error in labels?body.error:'upstream_http';error.status=Number.isInteger(body?.upstreamStatus)?body.upstreamStatus:r.status;
    throw error;
  }
  return r.json();
}
async function api(config, prompt, schema, key) {
  if (!config.apiModel?.trim()) throw new Error('请填写 API 模型名称。');
  const base = endpoint(config.apiBase);
  if (config.apiProtocol === 'anthropic') {
    const r = await post(base+'/messages', {'x-api-key':key,'anthropic-version':'2023-06-01'}, {
      model:config.apiModel,max_tokens:4096,messages:[{role:'user',content:prompt}],
      output_config:{format:{type:'json_schema',schema}}
    });
    if (r.stop_reason === 'max_tokens') throw new Error('结果超过输出限制，未保存处理进度。');
    return {answer:JSON.parse(r.content.filter(c=>c.type==='text').map(c=>c.text).join('')),usage:r.usage};
  }
  // JSON mode is more widely supported than strict schema among compatible APIs.
  const r = await post(base+'/chat/completions', {Authorization:'Bearer '+key}, {
    model:config.apiModel,messages:[{role:'user',content:prompt+'\n输出 JSON schema：'+JSON.stringify(schema)}],
    response_format:{type:'json_object'},
    ...(config.jsonMode === false ? {response_format:undefined} : {}),
    ...(new URL(base).hostname === 'openrouter.ai' ? {provider:{allow_fallbacks:false,require_parameters:true,...(config.providerMaxPrice?{sort:'price',max_price:config.providerMaxPrice}:{})}} : {}),
    ...(new URL(base).hostname === 'openrouter.ai' && config.analysisReasoning ? {reasoning:config.analysisReasoning} : {}),
    ...(new URL(base).hostname === 'openrouter.ai' && config.temperatureControl ? {temperature:0} : {}),
    ...(new URL(base).hostname === 'api.openai.com' ? {max_completion_tokens:4096} : {max_tokens:config.outputLimit || 4096})
  });
  if (r.choices?.[0]?.finish_reason !== 'stop') {
    const error=new Error('模型输出未正常结束，未保存处理进度。');error.code='output_limit';
    error.finishReason=r.choices?.[0]?.finish_reason;throw error;
  }
  const content=r.choices[0].message.content;
  const fence=typeof content==='string'?content.match(/^\s*```(?:json)?\s*\n([\s\S]*?)\n```\s*$/i):null;
  let answer;try {answer=JSON.parse(fence?fence[1]:content);} catch {
    const error=new Error('模型未返回有效 JSON，未保存处理进度。');error.code='invalid_json';
    error.outputShape=typeof content!=='string'||!content.trim()?'empty':content.trim().startsWith('```')?'fenced':'other';throw error;
  }
  return {answer,usage:r.usage};
}
async function callProvider(config, prompt, schema, dataDir) {
  if (config.provider === 'byok') return api(config,prompt,schema,secret(dataDir,'byok'));
  if (config.provider === 'hosted') {
    if (!config.serviceUrl) throw new Error('软件提供的 API 尚未配置，请在设置中填写服务地址。');
    if (!config.hostedModel) throw new Error('请在设置中选择具体的 OpenRouter 模型。');
    const edition=JSON.parse(fs.readFileSync(path.join(__dirname,'edition.json'),'utf8')).edition;
    const name=fs.existsSync(path.join(dataDir,'hosted-'+edition+'.secret'))?'hosted-'+edition:'hosted';
    return post(config.serviceUrl, {Authorization:'Bearer '+secret(dataDir,name)}, {prompt,model:config.hostedModel});
  }
  if (config.provider !== 'claude') throw new Error('未知分析方式。');
  const runtime = path.join(dataDir,'runtime'); fs.mkdirSync(runtime,{recursive:true});
  const exe = config.claudePath || path.join(process.env.USERPROFILE,'.local','bin','claude.exe');
  if (!fs.existsSync(exe)) throw new Error('请先安装并登录 Claude Code，或在设置中填写 claude.exe 路径。');
  const args = ['-p','--bare','--tools','','--disallowedTools','mcp__*','--strict-mcp-config','--mcp-config','{"mcpServers":{}}',
    '--no-session-persistence','--output-format','json','--json-schema',JSON.stringify(schema),'--model',config.claudeModel || 'haiku'];
  // Subscription mode must not silently use an inherited API key.
  const env = {...process.env}; delete env.ANTHROPIC_API_KEY; delete env.ANTHROPIC_AUTH_TOKEN; delete env.ANTHROPIC_BASE_URL;
  const raw = await new Promise((resolve,reject)=>{
    const p=spawn(exe,args,{cwd:runtime,env,windowsHide:true,stdio:['pipe','pipe','pipe']}); let out='';
    const timer=setTimeout(()=>{p.kill();reject(new Error('Claude 分析超时。'));},180000);
    p.stdout.on('data',b=>{out+=b;if(out.length>1000000)p.kill();}); p.stderr.resume(); p.stdin.on('error',()=>{});
    p.on('error',e=>{clearTimeout(timer);reject(e);}); p.on('close',code=>{clearTimeout(timer);code===0?resolve(out):reject(new Error('Claude 调用失败；请检查官方工具的登录状态和版本。'));});
    p.stdin.end(prompt);
  });
  const result=JSON.parse(raw); if(result.is_error) throw new Error('Claude 未完成分析。');
  return {answer:result.structured_output || JSON.parse(result.result),usage:result.usage};
}
module.exports={callProvider,api,endpoint};
