#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -x 'dist/先做一刻.app/Contents/MacOS/FirstStep' ]; then ./scripts/build.sh; fi
python3 - <<'PY'
import base64, hashlib, json, os, shutil, subprocess
from datetime import datetime
from pathlib import Path
root=Path.cwd(); app_dir=Path.home()/'Applications'; app_dir.mkdir(exist_ok=True)
app=app_dir/'先做一刻.app'; support=Path.home()/'Library/Application Support/FirstStep'; support.mkdir(parents=True,exist_ok=True);support.chmod(0o700)
source=root/'dist/先做一刻.app'
shutil.copy2(root/'安装说明.md',support/'安装说明.md')
if app.exists():
    old_id=subprocess.run(['/usr/libexec/PlistBuddy','-c','Print :CFBundleIdentifier',str(app/'Contents/Info.plist')],capture_output=True,text=True).stdout.strip()
    if old_id!='com.dayuan.firststep':raise SystemExit('发现其他同名应用，已停止，未覆盖。')
    backup=support/'Backups'/('先做一刻-'+datetime.now().strftime('%Y%m%d-%H%M%S-%f')+'.app');backup.parent.mkdir(exist_ok=True)
    shutil.move(app,backup)
subprocess.run(['/usr/bin/ditto',str(source),str(app)],check=True)
extension=support/'ChromeExtension';extension.mkdir(exist_ok=True)
for f in (root/'extension').iterdir():
    if f.is_file() and f.name!='package.json':shutil.copy2(f,extension/f.name)
manifest=json.loads((extension/'manifest.json').read_text())
public=base64.b64decode(manifest['key']);digest=hashlib.sha256(public).hexdigest()[:32]
extension_id=''.join(chr(ord('a')+int(c,16)) for c in digest)
host_dir=Path.home()/'Library/Application Support/Google/Chrome/NativeMessagingHosts';host_dir.mkdir(parents=True,exist_ok=True)
host={'name':'com.dayuan.firststep','description':'先做一刻本地专注状态','path':str(app/'Contents/MacOS/FirstStepNative'),'type':'stdio','allowed_origins':['chrome-extension://'+extension_id+'/']}
host_file=host_dir/'com.dayuan.firststep.json'
if host_file.exists():
    old=json.loads(host_file.read_text())
    if old.get('name')!=host['name']:raise SystemExit('发现冲突的本地主机配置，未覆盖。')
host_file.write_text(json.dumps(host,ensure_ascii=False,indent=2)+'\n');host_file.chmod(0o600)
print('应用：'+str(app));print('扩展文件夹：'+str(extension));print('扩展 ID：'+extension_id)
print('安装说明：'+str(support/'安装说明.md'))
print('首次使用请按安装说明加载 Chrome 扩展；已安装扩展无需重复加载。')
subprocess.run(['/usr/bin/open',str(app)],check=True)
PY
