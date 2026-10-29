#!/usr/bin/env python3
import json, os, select, struct, subprocess, tempfile, time
from pathlib import Path
root=Path(__file__).resolve().parents[1]
binary=Path(os.environ.get('FIRSTSTEP_TEST_NATIVE_BINARY',str(root/'dist/先做一刻.app/Contents/MacOS/FirstStepNative')))
with tempfile.TemporaryDirectory() as temp:
    p=subprocess.Popen([str(binary)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env={**os.environ,'FIRSTSTEP_DATA_DIR':temp})
    try:
        def read_exact(n):
            data=b''
            while len(data)<n:
                if not select.select([p.stdout],[],[],5)[0]:raise AssertionError('native response timeout')
                chunk=os.read(p.stdout.fileno(),n-len(data))
                assert chunk,'unexpected EOF';data+=chunk
            return data
        def request(command, fragmented=False):
            data=json.dumps({'id':'test','command':command}).encode();frame=struct.pack('<I',len(data))+data
            if fragmented:
                for part in [frame[:2],frame[2:7],frame[7:]]:p.stdin.write(part);p.stdin.flush();time.sleep(.02)
            else:p.stdin.write(frame);p.stdin.flush()
            size=struct.unpack('<I',read_exact(4))[0];assert size<1048576
            response=json.loads(read_exact(size));assert response['id']=='test'
            assert 'private-habit-do-not-send' not in json.dumps(response)
            assert habits.read_bytes()==private_habits,'native host must not touch habit data'
            return response
        reflections=Path(temp)/'focus-reflections.json'
        private_notes=b'{"schema":1,"reflections":[{"recordID":"private","text":"private-reflection-do-not-send","draft":"private-draft-do-not-send","updatedAt":1,"savedAt":1}]}'
        reflections.write_bytes(private_notes)
        habits=Path(temp)/'habits.json'
        private_habits=b'{"schema":1,"private":"private-habit-do-not-send"}'
        habits.write_bytes(private_habits)
        first=request({'action':'getState'},True)
        assert 'private-reflection-do-not-send' not in json.dumps(first) and 'private-draft-do-not-send' not in json.dumps(first)
        assert reflections.read_bytes()==private_notes
        assert first['ok'] and first['state']['tasks']==[]
        assert first['state']['schema']==6
        assert 'completionRecords' not in first['state']
        assert not request({'action':'addTask','title':'禁止从扩展写入'})['ok']
        assert not request({'action':'addBlockedSite','site':'example.com'})['ok']
        assert not request({'action':'addInbox','title':'禁止从扩展写入收集箱'})['ok']
        assert not request({'action':'appendSubtasks','taskID':'task','subtaskTitles':['禁止从扩展添加']})['ok']
        now=time.time();s=first['state'];s['session']={'id':'focus','taskID':'task','title':'协议测试','nextStep':'一步','startAt':now,'endAt':now+900,'allowances':[]}
        s['tasks']=[{'id':'task','title':'协议测试','nextStep':'一步','day':time.strftime('%Y-%m-%d'),'completed':False,'createdAt':now,'scheduledDay':'2030-01-01','reminderAt':now+1234,'subtasks':[{'id':'step','title':'仅本机小任务','completed':False}]}]
        s['inboxItems']=[{'id':'inbox-test','title':'本机暂存标题','createdAt':now}]
        file=Path(temp)/'state.json';file.write_text(json.dumps(s))
        r=request({'action':'requestAccess','site':'x.com'});assert r['ok']
        assert 'subtasks' not in r['state']['tasks'][0]
        assert 'scheduledDay' not in r['state']['tasks'][0] and 'reminderAt' not in r['state']['tasks'][0]
        assert json.loads(file.read_text())['tasks'][0]['scheduledDay']=='2030-01-01'
        assert json.loads(file.read_text())['tasks'][0]['subtasks'][0]['id']=='step'
        req=r['state']['pending'];assert req['readyAt']>=now+30
        assert not request({'action':'confirmAccess','requestID':req['id']})['ok']
        s=json.loads(file.read_text());s['pending']['readyAt']=time.time()-1;file.write_text(json.dumps(s))
        r=request({'action':'confirmAccess','requestID':req['id']});assert r['ok']
        a=r['state']['session']['allowances'][0];assert a['site']=='x.com' and 299<a['endAt']-time.time()<=300
        s=json.loads(file.read_text());s['session']['endAt']=time.time()-1;s['session']['startAt']=s['session']['endAt']-900;file.write_text(json.dumps(s))
        r=request({'action':'heartbeat','protocolVersion':2});assert r['ok'] and 'session' not in r['state'] and len(r['state']['history'])==1
        assert r['state']['extensionProtocol']==2
        assert 'inboxItems' not in r['state']
        assert json.loads(file.read_text())['inboxItems'][0]['id']=='inbox-test'
        assert request({'action':'getState'})['ok']
        s=json.loads(file.read_text());template=s['history'][0]
        s['history']=[{**template,'id':f'past-{i}'} for i in range(600)]
        file.write_text(json.dumps(s))
        r=request({'action':'getState'})
        assert r['ok'] and len(r['state']['history'])==500,'bridge snapshot must be bounded to 500 records'
        assert len(json.loads(file.read_text())['history'])==600,'bridge must not trim local forest history'
        s=json.loads(file.read_text())
        s.pop('completionRecords',None)
        s['tasks'][0]['completed']=True;s['tasks'][0]['completedAt']=time.time()
        s['tasks'][0]['subtasks'][0]['completed']=True
        s['tasks'][0]['subtasks'][0]['completedAt']=time.time()
        file.write_text(json.dumps(s))
        r=request({'action':'getState'})
        assert r['ok'] and 'completionRecords' not in r['state'],'completion archive must remain local: '+str(r.get('error'))
        archived=json.loads(file.read_text())['completionRecords']
        assert len(archived)==2,'main and child completions must remain on disk'
        assert any(c['title']=='仅本机小任务' for c in archived)
        assert len(json.loads(file.read_text())['history'])==600
        print('PASS: native framing, fragmented reads, restrictions, expiry, bounded bridge, local completion archive and preserved forest history')
    finally:
        p.stdin.close();p.wait(timeout=5)
        assert p.returncode==0,p.stderr.read().decode()
