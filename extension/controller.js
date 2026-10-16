import {blocked,rulesFor,originalURL,activeSession,timeText} from './policy.js';
export class Controller {
 constructor(api,clock=()=>Date.now()/1000) {
  this.api=api;this.clock=clock;this.state={};this.signature=null;this.alarmAt=null;this.queue=Promise.resolve();
  this.page=api.runtime.getURL('blocked.html');
 }
 async setState(state) { this.state=state??{};return this.reconcile(); }
 reconcile() {
  this.queue=this.queue.catch(()=>{}).then(()=>this.run());return this.queue;
 }
 async run() {
  const api=this.api,now=this.clock(),s=activeSession(this.state,now),rules=rulesFor(this.state,now,this.page),signature=JSON.stringify(rules);
  if(signature!==this.signature){await api.declarativeNetRequest.updateDynamicRules({removeRuleIds:[1,2,3],addRules:rules});this.signature=signature;}
  const deadlines=s?[s.endAt,...(s.allowances??[]).map(a=>a.endAt).filter(t=>t>now)]:[];
  const next=deadlines.length?Math.min(...deadlines):null;
  if(next!==this.alarmAt){if(next)await api.alarms.create('boundary',{when:next*1000});else await api.alarms.clear('boundary');this.alarmAt=next;}
  for(const tab of await api.tabs.query({})) {
   if(!tab.url&&!tab.pendingUrl)continue;
   try {
    const current=await api.tabs.get(tab.id),url=current.pendingUrl||current.url;
    const original=originalURL(url,this.page);
    if(blocked(url,this.state,now))await api.tabs.update(tab.id,{url:this.page+'#'+url});
    else if(original&&!blocked(original,this.state,now))await api.tabs.update(tab.id,{url:original});
   } catch { /* Tab may close or navigate while reconciliation is in progress. */ }
  }
  await api.action.setBadgeText({text:s?String(Math.ceil((s.endAt-now)/60)):''});
  await api.action.setBadgeBackgroundColor({color:'#6C6252'});
  await api.action.setTitle({title:s?`先做一刻 · ${s.title} · ${timeText(s.endAt-now)}`:'先做一刻 · 当前没有专注'});
 }
}
