import {groupForURL,originalURL,activeSession,timeText,blocked} from './policy.js';
const $=id=>document.getElementById(id), original=originalURL(location.href,chrome.runtime.getURL('blocked.html'));
let site=null;
let state={},online=false,busy=false,editing=false;
async function call(message){const r=await chrome.runtime.sendMessage(message);if(!r?.ok)throw new Error(r?.error||'无法连接扩展');state=r.state;online=r.online;return r;}
function render(){
 const now=Date.now()/1000,s=activeSession(state,now),p=state.pending;
 site=groupForURL(original,state);
 $('task').textContent=s?.title??'这一轮已结束';$('step').textContent=s?.nextStep?`下一步：${s.nextStep}`:'';
 $('timer').textContent=s?timeText(s.endAt-now):'00:00';
 $('request').disabled=!s||!online||!site;
 const pending=p?.kind==='access'&&p.site===site;
 $('unlock').hidden=!editing&&!pending;
 $('reason').hidden=!!pending;
 $('confirm').textContent=pending?(p.readyAt>now?`还有 ${Math.ceil(p.readyAt-now)} 秒`:'开放这个网站 5 分钟'):'开始等待 30 秒';
 $('confirm').disabled=busy||!online||(pending&&p.readyAt>now);
 $('waitText').textContent=pending?'停一下。你也可以现在回到任务。':'需要暂时打开？等待 30 秒后，只开放这个网站 5 分钟。';
 if(!online)$('error').textContent='本地工具暂时未连接；仍按原截止时间解除。请打开「先做一刻」。';
 if(original&&!blocked(original,state,now))location.replace(original);
}
async function refresh(){try{await call({action:'getState'});render();}catch(e){$('error').textContent=e.message;}}
$('request').onclick=()=>{editing=true;render();};
$('confirm').onclick=async()=>{if(busy)return;busy=true;try{
 const p=state.pending;await call(p?.kind==='access'&&p.site===site?{action:'confirmAccess',requestID:p.id}:{action:'requestAccess',site,reason:$('reason').value});
 $('error').textContent='';
}catch(e){$('error').textContent=e.message;}finally{busy=false;render();}};
$('cancel').onclick=async()=>{try{if(state.pending?.site===site)await call({action:'cancelRequest'});editing=false;render();}catch(e){$('error').textContent=e.message;}};
$('back').onclick=async()=>{const tab=await chrome.tabs.getCurrent();if(tab?.id)await chrome.tabs.remove(tab.id);};
void refresh();setInterval(()=>void refresh(),1000);
