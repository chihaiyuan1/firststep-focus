import {activeSession,timeText} from './policy.js';
async function render(){try{
 const r=await chrome.runtime.sendMessage({action:'getState'}),s=activeSession(r.state,Date.now()/1000);
 document.getElementById('status').textContent=r.online&&!r.error?'已连接 Mac 工具':'等待连接';
 document.getElementById('task').textContent=s?.title??'从一个小步骤开始。';
 document.getElementById('step').textContent=s?.nextStep??'在「先做一刻」里选一个任务，开始 15 分钟。';
 document.getElementById('timer').textContent=s?timeText(s.endAt-Date.now()/1000):'';
 document.getElementById('error').textContent=r.error?'请打开 Mac 工具；如果尚未安装，请先运行安装脚本。':'';
}catch(e){document.getElementById('error').textContent=e.message;}}
void render();setInterval(()=>void render(),1000);
