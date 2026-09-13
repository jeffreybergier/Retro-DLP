"""Verify shipped app resources, architecture slices, and archive freshness."""
from pathlib import Path
import hashlib
import plistlib
import re
import stat
import subprocess
import zipfile

ROOT=Path(__file__).resolve().parents[3]
for platform,archive_name,exe_relative,plist_relative,resources,architectures in [
    ('macOS','RetroDLP.zip','Contents/MacOS/RetroDLP','Contents/Info.plist','Contents/Resources',{'ppc','i386','x86_64','arm64'}),
    ('iOS','RetroDLP.ipa','RetroDLP','Info.plist','',{'armv7','arm64'}),
]:
    directory=ROOT/'build/apps'/platform
    bundle=directory/'RetroDLP.app'
    exe=bundle/exe_relative
    found=set(subprocess.check_output(['/osxcross/modern/bin/lipo','-archs',str(exe)],text=True).split())
    assert found==architectures,(platform,found)
    minimums={'ppc':'10.4','i386':'10.4','x86_64':'10.9','arm64':'11.0'} if platform=='macOS' else {'armv7':'5.0','arm64':'7.0'}
    for architecture,minimum in minimums.items():
        load_commands=subprocess.check_output(['/osxcross/modern/bin/otool','-arch',architecture,'-l',str(exe)],text=True)
        commands=re.split(r'Load command \d+',load_commands)
        deployment=[block for block in commands if re.search(r'cmd LC_(?:VERSION_MIN_MACOSX|VERSION_MIN_IPHONEOS|BUILD_VERSION)\b',block)]
        assert len(deployment)==1,(platform,architecture,'Missing or ambiguous deployment command')
        actual=re.search(r'(?:version|minos)\s+([0-9.]+)',deployment[0]).group(1)
        assert actual==minimum,(platform,architecture,actual,minimum)
        if architecture in ('ppc','i386'):
            undefined=subprocess.check_output(['/osxcross/modern/bin/nm','-arch',architecture,'-u',str(exe)],text=True)
            assert '$UNIX2003' not in undefined,(architecture,'Tiger-incompatible libc symbols')
        if platform=='iOS':
            avkit=[block for block in commands if 'AVKit.framework/AVKit' in block]
            assert len(avkit)==1 and 'cmd LC_LOAD_WEAK_DYLIB' in avkit[0],'AVKit must be weak-linked'

    plist=plistlib.loads((bundle/plist_relative).read_bytes())
    assert 'RetroDLPTestDirectory' not in plist,'Test directory leaked into release'
    assert plist['CFBundleIdentifier']=='com.altivecintelligence.RetroDLP'
    if platform=='iOS':
        assert plist['MinimumOSVersion']=='5.0'
        assert plist['UIFileSharingEnabled']
        assert not plist.get('UIBackgroundModes')
        entitlements=subprocess.check_output(['ldid','-e',str(exe)])
        assert b'no-sandbox' not in entitlements and b'platform-application' not in entitlements
    with zipfile.ZipFile(directory/archive_name) as archive:
        prefix=('Payload/' if platform=='iOS' else '')+'RetroDLP.app/'
        assert archive.read(prefix+exe_relative)==exe.read_bytes(),platform+' archive has stale executable'
        assert archive.read(prefix+plist_relative)==(bundle/plist_relative).read_bytes()
        mode=archive.getinfo(prefix+exe_relative).external_attr>>16
        assert mode & stat.S_IXUSR,'Executable mode was lost'
        for filename in ['cacert.pem','ejs/core.min.js','ejs/lib.min.js','ejs/NOTICE.txt']:
            relative='/'.join(p for p in [resources,filename] if p)
            data=(bundle/relative).read_bytes()
            assert data and archive.read(prefix+relative)==data
            mode=archive.getinfo(prefix+relative).external_attr>>16
            assert mode & stat.S_IROTH,platform+' resource is unreadable after installation: '+relative
            if filename.startswith('ejs/'):
                assert hashlib.sha256(data).digest()==hashlib.sha256((ROOT/'build/apps/resources'/filename).read_bytes()).digest()
    print('PASS:',platform,'architectures, resources, package freshness, and application metadata')
