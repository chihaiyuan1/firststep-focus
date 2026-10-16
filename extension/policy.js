export const groups = [
 {site:'xueqiu.com', name:'雪球', domains:['xueqiu.com']},
 {site:'x.com', name:'X', domains:['x.com','twitter.com']},
 {site:'weibo.com', name:'微博', domains:['weibo.com','weibo.cn']}
];
export function groupForURL(url) {
 try { const u=new URL(url); if(!['http:','https:'].includes(u.protocol)) return null;
  const host=u.hostname.toLowerCase().replace(/\.$/,'');
  return groups.find(g=>g.domains.some(d=>host===d||host.endsWith('.'+d)))?.site??null;
 } catch { return null; }
}
export function activeSession(state, now) { const s=state?.session; return s && Number.isFinite(s.endAt) && s.endAt>now ? s : null; }
export function blocked(url,state,now) {
 const site=groupForURL(url), s=activeSession(state,now);
 return !!(site && s && !(s.allowances??[]).some(a=>a.site===site&&a.startAt<=now&&a.endAt>now));
}
export function rulesFor(state,now,pageURL) {
 return groups.flatMap((g,i)=>blocked('https://'+g.site+'/',state,now)?[{
  id:i+1,priority:1,action:{type:'redirect',redirect:{regexSubstitution:pageURL+'#\\1'}},
  condition:{regexFilter:'^(https?://.*)$',requestDomains:g.domains,resourceTypes:['main_frame']}
 }]:[]);
}
export function originalURL(url,pageURL) {
 if(!url?.startsWith(pageURL+'#'))return null;
 const original=url.slice(pageURL.length+1);
 return groupForURL(original)?original:null;
}
export function timeText(seconds) {const n=Math.max(0,Math.ceil(seconds));return `${Math.floor(n/60).toString().padStart(2,'0')}:${(n%60).toString().padStart(2,'0')}`;}
