import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
function event(){const listeners=[];return {addListener:f=>listeners.push(f),emit:(...args)=>listeners.forEach(f=>f(...args))};}
async function until(fn){const end=Date.now()+8000;while(!fn()){if(Date.now()>end)throw Error('condition timed out');await new Promise(r=>setTimeout(r,25));}}
test('worker talks to real native binary, redirects/restores, rejects early unlock and untrusted sender',async()=>{
 const dir=await mkdtemp(path.join(tmpdir(),'firststep-worker-'));
 const now=Date.now()/1000;
 const initial={schema:1,tasks:[],history:[],session:{id:'focus',taskID:'task',title:'worker test',nextStep:'one step',startAt:now,endAt:now+900,allowances:[]}};
 await writeFile(path.join(dir,'state.json'),JSON.stringify(initial));
 const children=[],intervals=[],realSetInterval=globalThis.setInterval;
 let cache={},rules=[],badge='';const tabs=[{id:1,url:'https://x.com/home'},{id:2,url:'https://example.com/work'}];
 const onMessage=event(),onAlarm=event();
 globalThis.setInterval=(fn,ms,...args)=>{const id=realSetInterval(fn,ms,...args);intervals.push(id);return id;};
 globalThis.chrome={runtime:{id:'testextension',getURL:p=>'chrome-extension://testextension/'+p,onMessage,onStartup:event(),onInstalled:event(),connectNative:name=>{
  assert.equal(name,'com.dayuan.firststep');
  const child=spawn(path.join(root,'dist/先做一刻.app/Contents/MacOS/FirstStepNative'),[],{env:{...process.env,FIRSTSTEP_DATA_DIR:dir},stdio:['pipe','pipe','pipe']});children.push(child);
  const port={onMessage:event(),onDisconnect:event(),postMessage:message=>{const body=Buffer.from(JSON.stringify(message)),header=Buffer.alloc(4);header.writeUInt32LE(body.length);child.stdin.write(Buffer.concat([header,body]));}};
  let incoming=Buffer.alloc(0);child.stdout.on('data',chunk=>{incoming=Buffer.concat([incoming,chunk]);while(incoming.length>=4){const n=incoming.readUInt32LE();if(incoming.length<4+n)break;port.onMessage.emit(JSON.parse(incoming.subarray(4,n+4)));incoming=incoming.subarray(n+4);}});
  child.on('exit',()=>port.onDisconnect.emit());return port;
 }},storage:{local:{get:async()=>cache,set:async obj=>Object.assign(cache,obj)}},
 declarativeNetRequest:{updateDynamicRules:async value=>{rules=value.addRules;}},
 tabs:{query:async()=>tabs.map(t=>({...t})),get:async id=>({...tabs.find(t=>t.id===id)}),update:async(id,change)=>Object.assign(tabs.find(t=>t.id===id),change),onUpdated:event()},
 action:{setBadgeText:async({text})=>{badge=text;},setBadgeBackgroundColor:async()=>{},setTitle:async()=>{}},alarms:{create:async()=>{},clear:async()=>{},onAlarm}};
 try{
  await import('../extension/background.js');
  await until(()=>rules.length===3&&tabs[0].url.startsWith('chrome-extension:'));
  assert.equal(tabs[1].url,'https://example.com/work');assert.equal(badge,'15');
  const send=message=>new Promise(resolve=>onMessage.emit(message,{id:'testextension',url:'chrome-extension://testextension/blocked.html'},resolve));
  let r=await send({action:'requestAccess',site:'x.com'});assert.equal(r.ok,true);const requestID=r.state.pending.id;
  r=await send({action:'confirmAccess',requestID});assert.equal(r.ok,false);assert.match(r.error,/30/);
  let replied=false;onMessage.emit({action:'requestAccess',site:'x.com'},{id:'testextension',url:'https://x.com/'},()=>{replied=true;});assert.equal(replied,false);
  // Simulate persisted deadline crossing; no production data or browser involved.
  const current=JSON.parse(await readFile(path.join(dir,'state.json'),'utf8'));current.session.endAt=Date.now()/1000-1;
  await writeFile(path.join(dir,'state.json'),JSON.stringify(current));onAlarm.emit({name:'boundary'});
  await until(()=>rules.length===0&&tabs[0].url==='https://x.com/home');
  assert.equal((await send({action:'getState'})).online,true);
 }finally{
  intervals.forEach(clearInterval);globalThis.setInterval=realSetInterval;
  for(const child of children){child.stdin.end();}
  await Promise.all(children.map(child=>child.exitCode===null?new Promise(resolve=>child.once('exit',resolve)):Promise.resolve()));
  delete globalThis.chrome;await rm(dir,{recursive:true,force:true});
 }
});
