#!/usr/bin/env python3
from pathlib import Path
import hashlib, plistlib, shutil, stat, subprocess, tempfile, zipfile
source=Path(__file__).resolve().parents[1]; output=source.parent; app=output/'NovaVPS.app'
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='local.novavps.mac' and info['CFBundleVersion']=='3'
pkg=output/'NovaVPS-Installer.pkg'
with tempfile.TemporaryDirectory(prefix='novavps-package-') as temporary:
    root=Path(temporary)/'payload'; root.mkdir()
    shutil.copytree(app,root/app.name,symlinks=True)
    subprocess.run(['pkgbuild','--root',str(root),'--identifier','local.novavps.installer','--version','0.1.1.3','--install-location','/Applications','--ownership','recommended',str(pkg)],check=True)
archive=output/'NovaVPS-macOS.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for item in [source,app]:
        for file in [item]+sorted(item.rglob('*')):
            relative=file.relative_to(output)
            if any(part in ['.git','.DS_Store','__pycache__','node_modules'] or part.startswith('.build') for part in relative.parts): continue
            z.write(file,str(relative))
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    names=z.namelist()
    assert not any(Path(n).name in ['servers.json','known_hosts','arguments.json','node.xray.json','node.vless.txt','node-qr.png'] for n in names)
    for name in ['NovaVPS.app/Contents/MacOS/NovaVPS','NovaVPS.app/Contents/Resources/xray']:
        assert (z.getinfo(name).external_attr>>16)&stat.S_IXUSR
    assert plistlib.loads(z.read('NovaVPS.app/Contents/Info.plist'))==info
    assert z.read('NovaVPS/Resources/panel-manager.py')==z.read('NovaVPS.app/Contents/Resources/panel-manager.py')

def sha(path):
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''): digest.update(block)
    return digest.hexdigest()
files=[pkg,archive,app/'Contents/MacOS/NovaVPS',app/'Contents/Resources/xray']
(output/'NovaVPS-SHA256SUMS.txt').write_text(''.join('%s  %s\n'%(sha(path),path.relative_to(output)) for path in files))
print('PASS package signatures, version, ZIP integrity, executable permissions, source parity and no personal export files')
