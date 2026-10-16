import {Controller} from './controller.js';
const controller=new Controller(chrome);
const waiting=new Map();let port=null,lastSuccess=0,connectionError='',syncing=false;
const initialized=chrome.storage.local.get('snapshot').then(async saved=>{await controller.setState(saved.snapshot??{});});
function connect() {
 if(port)return;
 try {
  const p=chrome.runtime.connectNative('com.dayuan.firststep');port=p;
  p.onMessage.addListener(message=>{
   const item=waiting.get(message.id);if(!item)return;waiting.delete(message.id);clearTimeout(item.timeout);
   if(message.ok){lastSuccess=Date.now();connectionError='';item.resolve(message.state);}
   else {connectionError=message.error||'本地工具返回错误';item.reject(new Error(connectionError));}
  });
  p.onDisconnect.addListener(()=>{
   connectionError=chrome.runtime.lastError?.message||'本地工具连接已断开';if(port===p)port=null;
   for(const item of waiting.values()){clearTimeout(item.timeout);item.reject(new Error(connectionError));}waiting.clear();
  });
 }catch(error){connectionError=error.message;}
}
function native(command) {
 connect();if(!port)return Promise.reject(new Error('请先打开「先做一刻」并完成安装'));
 const id=crypto.randomUUID();
 return new Promise((resolve,reject)=>{
  const timeout=setTimeout(()=>{waiting.delete(id);reject(new Error('连接本地工具超时'));},5000);
  waiting.set(id,{resolve,reject,timeout});
  try{port.postMessage({id,command});}catch(error){clearTimeout(timeout);waiting.delete(id);reject(error);}
 });
}
async function accept(state) {
 await controller.setState(state);await chrome.storage.local.set({snapshot:state});
}
async function sync() {
 if(syncing)return;syncing=true;
 try {
  await initialized;
  const state=await native({action:'getState'});
  try {await accept(state);await native({action:'heartbeat'});}
  catch(error){await native({action:'heartbeat',reason:error.message});throw error;}
 }catch(error){connectionError=error.message;await controller.reconcile().catch(()=>{});}
 finally{syncing=false;}
}
chrome.runtime.onMessage.addListener((message,sender,reply)=>{
 // Only extension pages may issue requests; web pages never receive a bridge.
 if(sender.id!==chrome.runtime.id||!sender.url?.startsWith(chrome.runtime.getURL('')))return false;
 (async()=>{
  await initialized;
  if(message.action==='getState') {
   await controller.reconcile();
   return {ok:true,state:controller.state,online:!!port&&Date.now()-lastSuccess<8000,error:connectionError};
  }
  if(!['requestAccess','confirmAccess','cancelRequest'].includes(message.action))throw new Error('不支持的操作');
  const state=await native(message);await accept(state);return {ok:true,state,online:true};
 })().then(reply,error=>reply({ok:false,error:error.message}));
 return true;
});
chrome.alarms.onAlarm.addListener(()=>{void sync();});
chrome.tabs.onUpdated.addListener((_id,change)=>{if(change.url||change.status==='complete')void initialized.then(()=>controller.reconcile()).catch(()=>{});});
chrome.runtime.onStartup.addListener(()=>void sync());
chrome.runtime.onInstalled.addListener(()=>void sync());
chrome.alarms.create('reconnect',{periodInMinutes:0.5});
setInterval(()=>void sync(),2000);
void sync();
