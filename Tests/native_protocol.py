#!/usr/bin/env python3
import json, os, select, struct, subprocess, tempfile, time
from pathlib import Path
root=Path(__file__).resolve().parents[1]
binary=root/'dist/先做一刻.app/Contents/MacOS/FirstStepNative'
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
            response=json.loads(read_exact(size));assert response['id']=='test';return response
        first=request({'action':'getState'},True)
        assert first['ok'] and first['state']['tasks']==[]
        assert not request({'action':'addTask','title':'禁止从扩展写入'})['ok']
        now=time.time();s=first['state'];s['session']={'id':'focus','taskID':'task','title':'协议测试','nextStep':'一步','startAt':now,'endAt':now+900,'allowances':[]}
        file=Path(temp)/'state.json';file.write_text(json.dumps(s))
        r=request({'action':'requestAccess','site':'x.com'});assert r['ok']
        req=r['state']['pending'];assert req['readyAt']>=now+30
        assert not request({'action':'confirmAccess','requestID':req['id']})['ok']
        s=json.loads(file.read_text());s['pending']['readyAt']=time.time()-1;file.write_text(json.dumps(s))
        r=request({'action':'confirmAccess','requestID':req['id']});assert r['ok']
        a=r['state']['session']['allowances'][0];assert a['site']=='x.com' and 299<a['endAt']-time.time()<=300
        s=r['state'];s['session']['endAt']=time.time()-1;file.write_text(json.dumps(s))
        r=request({'action':'heartbeat'});assert r['ok'] and 'session' not in r['state'] and len(r['state']['history'])==1
        assert request({'action':'getState'})['ok']
        print('PASS: native binary framing, fragmented reads, command restrictions, delayed access, deadline release')
    finally:
        p.stdin.close();p.wait(timeout=5)
        assert p.returncode==0,p.stderr.read().decode()
