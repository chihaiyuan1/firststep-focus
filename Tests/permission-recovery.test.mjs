import test from 'node:test';
import assert from 'node:assert/strict';

function event(){const handlers=[];return {addListener:fn=>handlers.push(fn),emit:(...args)=>handlers.forEach(fn=>fn(...args))};}
async function until(fn){const end=Date.now()+1000;while(!fn()){if(Date.now()>end)throw Error('permission recovery did not synchronize');await new Promise(resolve=>setTimeout(resolve,10));}}

test('worker recovers from missing startup host permission and reads the latest native list',async()=>{
 let permitted=false,permissionChecks=0,connections=0,rules=[];
 const now=Date.now()/1000;
 const state={schema:2,tasks:[],history:[],blockedSites:[{site:'bilibili.com',name:'B',domains:['bilibili.com']}],session:{id:'s',title:'work',startAt:now,endAt:now+900,allowances:[]}};
 const callbacks=[],realSetInterval=globalThis.setInterval;
 globalThis.setInterval=fn=>{callbacks.push(fn);return 0;};
 globalThis.chrome={runtime:{id:'test',getURL:p=>'chrome-extension://test/'+p,onMessage:event(),onStartup:event(),onInstalled:event(),connectNative:()=>{
  connections++;const port={onMessage:event(),onDisconnect:event(),postMessage:request=>queueMicrotask(()=>{
   if(request.command.action==='heartbeat'){state.extensionProtocol=request.command.protocolVersion;state.extensionError=request.command.reason??null;}
   port.onMessage.emit({id:request.id,ok:true,state:structuredClone(state)});
  })};return port;
 }},storage:{local:{get:async()=>({snapshot:{}}),set:async()=>{}}},permissions:{contains:async()=>{permissionChecks++;return permitted;}},
 declarativeNetRequest:{getDynamicRules:async()=>rules,updateDynamicRules:async value=>{rules=value.addRules;}},
 tabs:{query:async()=>[],onUpdated:event()},
 action:{setBadgeText:async()=>{},setBadgeBackgroundColor:async()=>{},setTitle:async()=>{}},
 alarms:{create:async()=>{},clear:async()=>{},onAlarm:event()}};
 try {
  await import('../extension/background.js');
  await until(()=>permissionChecks>0);
  await new Promise(resolve=>setTimeout(resolve,20));
  permitted=true;callbacks[0]();
  await until(()=>connections>0&&rules.length===1);
  assert.deepEqual(rules[0].condition.requestDomains,['bilibili.com']);
  await until(()=>state.extensionProtocol===2&&state.extensionError===null);
 } finally {globalThis.setInterval=realSetInterval;delete globalThis.chrome;}
});
