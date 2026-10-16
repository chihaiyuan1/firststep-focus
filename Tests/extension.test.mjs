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
 assert.equal(originalURL(page+'#https://work.com',page),null);
 assert.equal(originalURL('https://evil.com#https://x.com',page),null);
});
import {Controller} from '../extension/controller.js';
test('already open information feeds are replaced, then restored without touching work tabs',async()=>{
 let now=1100;const tabs=[{id:1,url:'https://x.com/home#top'},{id:2,url:'https://work.com/report'}];let applied=[];
 const api={runtime:{getURL:path=>'chrome-extension://abcdefghijklmnop/'+path},
  declarativeNetRequest:{updateDynamicRules:async value=>{applied=value.addRules;}},
  tabs:{query:async()=>tabs.map(t=>({...t})),get:async id=>({...tabs.find(t=>t.id===id)}),update:async(id,change)=>Object.assign(tabs.find(t=>t.id===id),change)},
  action:{setBadgeText:async()=>{},setBadgeBackgroundColor:async()=>{},setTitle:async()=>{}},
  alarms:{create:async()=>{},clear:async()=>{}}};
 const c=new Controller(api,()=>now);await c.setState(state);
 assert.equal(tabs[0].url,page+'#https://x.com/home#top');assert.equal(tabs[1].url,'https://work.com/report');assert.equal(applied.length,3);
 now=1900;await c.reconcile();
 assert.equal(tabs[0].url,'https://x.com/home#top');assert.equal(applied.length,0);
});
