import test from 'node:test';
import assert from 'node:assert/strict';
import {groupForURL, blocked, rulesFor, originalURL} from '../extension/policy.js';
const page='chrome-extension://abcdefghijklmnop/blocked.html';
const state={session:{id:'s1',title:'写文章',nextStep:'三句话',startAt:1000,endAt:1900,allowances:[]}};
test('subdomains and mobile domains are blocked without overmatching work URLs',()=>{
 for(const [url,want] of [['https://x.com/home','x.com'],['https://mobile.twitter.com/a','x.com'],['https://weibo.cn/','weibo.com'],['https://xueqiu.com/a','xueqiu.com'],['https://x.com.evil.com/',null],['https://work.com/?next=x.com',null],['chrome://extensions/',null]]) assert.equal(groupForURL(url),want,url);
});
test('deadline releases sites even with an offline stale snapshot',()=>{
 assert.equal(blocked('https://x.com',state,1899),true);
 assert.equal(blocked('https://x.com',state,1900),false);
 assert.equal(blocked('https://x.com',{},1000),false);
});
test('temporary access only releases its site and reblocks at five minutes',()=>{
 const s=structuredClone(state);s.session.allowances=[{site:'x.com',startAt:1040,endAt:1340}];
 assert.equal(blocked('https://twitter.com/',s,1040),false);
 assert.equal(blocked('https://weibo.com/',s,1040),true);
 assert.equal(blocked('https://x.com/',s,1340),true);
});
test('DNR redirects only blocked groups and clears all at session expiry',()=>{
 const rules=rulesFor(state,1100,page);
 assert.equal(rules.length,3);
 assert.deepEqual(rules.flatMap(r=>r.condition.requestDomains).sort(),['twitter.com','weibo.cn','weibo.com','x.com','xueqiu.com']);
 for(const r of rules) {assert.equal(r.action.type,'redirect');assert.equal(r.action.redirect.regexSubstitution,page+'#\\1');assert.deepEqual(r.condition.resourceTypes,['main_frame']);}
 assert.deepEqual(rulesFor(state,1900,page),[]);
});
test('original URL recovery preserves queries and fragments without arbitrary redirects',()=>{
 assert.equal(originalURL(page+'#https://x.com/home?q=a%20b#topic',page),'https://x.com/home?q=a%20b#topic');
 assert.equal(originalURL(page+'#javascript:alert(1)',page),null);
 assert.equal(originalURL(page+'#https://work.com',page),'https://work.com');
 assert.equal(originalURL(page+'#https://user:pass@example.com',page),null);
 assert.equal(originalURL('https://evil.com#https://x.com',page),null);
});
import {Controller} from '../extension/controller.js';
test('already open information feeds are replaced, then restored without touching work tabs',async()=>{
 let now=1100;const tabs=[{id:1,url:'https://x.com/home#top'},{id:2,url:'https://work.com/report'}];let applied=[];
 const api={runtime:{getURL:path=>'chrome-extension://abcdefghijklmnop/'+path},
  declarativeNetRequest:{getDynamicRules:async()=>applied,updateDynamicRules:async value=>{applied=value.addRules;}},
  tabs:{query:async()=>tabs.map(t=>({...t})),get:async id=>({...tabs.find(t=>t.id===id)}),update:async(id,change)=>Object.assign(tabs.find(t=>t.id===id),change)},
  action:{setBadgeText:async()=>{},setBadgeBackgroundColor:async()=>{},setTitle:async()=>{}},
  alarms:{create:async()=>{},clear:async()=>{}}};
 const c=new Controller(api,()=>now);await c.setState(state);
 assert.equal(tabs[0].url,page+'#https://x.com/home#top');assert.equal(tabs[1].url,'https://work.com/report');assert.equal(applied.length,3);
 now=1900;await c.reconcile();
 assert.equal(tabs[0].url,'https://x.com/home#top');assert.equal(applied.length,0);
});

test('custom configured sites and empty list replace the legacy default groups',()=>{
 const custom={...state,blockedSites:[{site:'bilibili.com',name:'bilibili.com',domains:['bilibili.com']}]};
 assert.equal(groupForURL('https://live.bilibili.com/a',custom),'bilibili.com');
 assert.equal(blocked('https://live.bilibili.com/a',custom,1100),true);
 assert.equal(blocked('https://bilibili.com.evil.com/a',custom,1100),false);
 assert.equal(blocked('https://x.com/home',custom,1100),false);
 assert.equal(blocked('https://bilibili.com/a',{...custom,blockedSites:[]},1100),false);
 custom.session=structuredClone(state.session);
 custom.session.allowances=[{site:'bilibili.com',startAt:1100,endAt:1400}];
 assert.equal(blocked('https://live.bilibili.com/a',custom,1100),false);
 assert.equal(blocked('https://live.bilibili.com/a',custom,1400),true);
 assert.equal(rulesFor({...custom,blockedSites:[]},1100,page).length,0);
 assert.equal(originalURL(page+'#https://bilibili.com/a?q=1#part',page),'https://bilibili.com/a?q=1#part');
});

test('clears persisted rules beyond the old three IDs and restores custom tab at expiry',async()=>{
 let now=1100;
 const ruleMap=new Map([[41,{id:41}]]),tabs=[{id:1,url:'https://bilibili.com/a?q=1#part'},{id:2,url:'https://work.example.org'}];
 const api={runtime:{getURL:()=>page},permissions:{contains:async()=>true},
  declarativeNetRequest:{getDynamicRules:async()=>[...ruleMap.values()],updateDynamicRules:async value=>{for(const id of value.removeRuleIds)ruleMap.delete(id);for(const r of value.addRules)ruleMap.set(r.id,r);}},
  tabs:{query:async()=>tabs.map(t=>({...t})),get:async id=>({...tabs.find(t=>t.id===id)}),update:async(id,change)=>Object.assign(tabs.find(t=>t.id===id),change)},
  action:{setBadgeText:async()=>{},setBadgeBackgroundColor:async()=>{},setTitle:async()=>{}},alarms:{create:async()=>{},clear:async()=>{}}};
 const c=new Controller(api,()=>now),custom={...state,blockedSites:[{site:'bilibili.com',name:'B',domains:['bilibili.com']}]};
 await c.setState(custom);
 assert.equal(ruleMap.has(41),false);
 assert.equal(tabs[0].url,page+'#https://bilibili.com/a?q=1#part');
 assert.equal(tabs[1].url,'https://work.example.org');
 now=1900;await c.reconcile();
 assert.equal(ruleMap.size,0);assert.equal(tabs[0].url,'https://bilibili.com/a?q=1#part');
});

test('missing host permission is reported rather than claiming custom blocking is active',async()=>{
 const api={runtime:{getURL:()=>page},permissions:{contains:async()=>false},
  declarativeNetRequest:{getDynamicRules:async()=>[],updateDynamicRules:async()=>{}},tabs:{query:async()=>[]},
  action:{setBadgeText:async()=>{},setBadgeBackgroundColor:async()=>{},setTitle:async()=>{}},alarms:{create:async()=>{},clear:async()=>{}}};
 const c=new Controller(api,()=>1100);
 await assert.rejects(c.setState(state),/权限|授权/);
});

test('revoked permission does not prevent expiry from clearing old rules and restoring blocked pages',async()=>{
 let now=1100,permitted=true,rules=[];
 const tabs=[{id:1,url:'https://x.com/home'}];
 const api={runtime:{getURL:()=>page},permissions:{contains:async()=>permitted},
  declarativeNetRequest:{getDynamicRules:async()=>rules,updateDynamicRules:async value=>{rules=value.addRules;}},
  tabs:{query:async()=>tabs.map(t=>({...t})),get:async id=>({...tabs.find(t=>t.id===id)}),update:async(id,value)=>Object.assign(tabs.find(t=>t.id===id),value)},
  action:{setBadgeText:async()=>{},setBadgeBackgroundColor:async()=>{},setTitle:async()=>{}},alarms:{create:async()=>{},clear:async()=>{}}};
 const c=new Controller(api,()=>now);await c.setState(state);assert.equal(rules.length,3);
 now=1900;permitted=false;
 await assert.rejects(c.reconcile(),/权限|授权/);
 assert.equal(rules.length,0);assert.equal(tabs[0].url,'https://x.com/home');
});
