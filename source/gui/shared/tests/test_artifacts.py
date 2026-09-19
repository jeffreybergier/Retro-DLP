"""Verify shipped app resources, architecture slices, and archive freshness."""
from pathlib import Path
import hashlib
import plistlib
import re
import stat
import struct
import subprocess
import zipfile

ROOT=Path(__file__).resolve().parents[4]
IPHONE_LAUNCH_IMAGES={
    'Default.png': (320,480),
    'Default@2x.png': (640,960),
    'Default-568h@2x.png': (640,1136),
    'Default-667h@2x.png': (750,1334),
    'Default-736h@3x.png': (1242,2208),
    'Default-Landscape-736h@3x.png': (2208,1242),
}
for platform,archive_name,exe_relative,plist_relative,resources,architectures in [
    ('macOS','RetroDLP.zip','Contents/MacOS/RetroDLP','Contents/Info.plist','Contents/Resources',{'ppc','i386'}),
    ('iOS','RetroDLP.ipa','RetroDLP','Info.plist','',{'armv7','arm64'}),
]:
    directory=ROOT/'build/apps'/platform
    bundle=directory/'RetroDLP.app'
    exe=bundle/exe_relative
    found=set(subprocess.check_output(['/osxcross/modern/bin/lipo','-archs',str(exe)],text=True).split())
    assert found==architectures,(platform,found)
    minimums={'ppc':'10.4','i386':'10.4'} if platform=='macOS' else {'armv7':'5.0','arm64':'7.0'}
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
            assert not avkit,'Legacy-only playback must not link AVKit'

    plist=plistlib.loads((bundle/plist_relative).read_bytes())
    assert 'RetroDLPTestDirectory' not in plist,'Test directory leaked into release'
    assert plist['CFBundleIdentifier']=='com.altivecintelligence.RetroDLP'
    if platform=='macOS':
        assert plist['LSMinimumSystemVersionByArchitecture']==minimums
    if platform=='iOS':
        assert plist['MinimumOSVersion']=='5.0'
        assert plist['UIFileSharingEnabled']
        assert plist.get('UIBackgroundModes')==['audio']
        entitlements=subprocess.check_output(['ldid','-e',str(exe)])
        assert b'no-sandbox' not in entitlements and b'platform-application' not in entitlements
    with zipfile.ZipFile(directory/archive_name) as archive:
        prefix=('Payload/' if platform=='iOS' else '')+'RetroDLP.app/'
        assert archive.read(prefix+exe_relative)==exe.read_bytes(),platform+' archive has stale executable'
        assert archive.read(prefix+plist_relative)==(bundle/plist_relative).read_bytes()
        mode=archive.getinfo(prefix+exe_relative).external_attr>>16
        assert mode & stat.S_IXUSR,'Executable mode was lost'
        if platform=='iOS':
            for filename,dimensions in IPHONE_LAUNCH_IMAGES.items():
                data=(bundle/filename).read_bytes()
                assert data[:8]==b'\x89PNG\r\n\x1a\n',filename+' is not a PNG'
                assert struct.unpack('>II',data[16:24])==dimensions,filename+' has incorrect dimensions'
                assert data==(ROOT/'source/gui/iOS/Resources'/filename).read_bytes(),filename+' is stale in bundle'
                assert archive.read(prefix+filename)==data,filename+' is stale in IPA'
                assert (archive.getinfo(prefix+filename).external_attr>>16) & stat.S_IROTH,filename+' is unreadable'
        for filename in ['cacert.pem','ejs/core.min.js','ejs/lib.min.js','ejs/NOTICE.txt']:
            relative='/'.join(p for p in [resources,filename] if p)
            data=(bundle/relative).read_bytes()
            assert data and archive.read(prefix+relative)==data
            mode=archive.getinfo(prefix+relative).external_attr>>16
            assert mode & stat.S_IROTH,platform+' resource is unreadable after installation: '+relative
            if filename.startswith('ejs/'):
                assert hashlib.sha256(data).digest()==hashlib.sha256((ROOT/'build/apps/resources'/filename).read_bytes()).digest()
        if platform=='iOS':
            icons=set(plist['CFBundleIconFiles'])
            source=ROOT/'source/gui/iOS/Resources'
            assert icons=={p.name for p in source.glob('AppIcon*.png')}
            assert plist['CFBundleIconFile']=='AppIcon57x57.png'
            assert plist['UIPrerenderedIcon'] is False
            for key in ('CFBundleIcons','CFBundleIcons~ipad'):
                primary=plist[key]['CFBundlePrimaryIcon']
                assert set(primary['CFBundleIconFiles']) <= icons
                assert primary['UIPrerenderedIcon'] is False
            for filename in icons:
                data=(source/filename).read_bytes()
                match=re.fullmatch(r'AppIcon([\d.]+)x([\d.]+)(?:@(\d)x)?(?:~ipad)?\.png',filename)
                assert match and match[1]==match[2],filename
                size=int(float(match[1])*int(match[3] or 1))
                assert data[:8]==b'\x89PNG\r\n\x1a\n'
                assert struct.unpack('>II',data[16:24])==(size,size),filename
                assert data[25]==2,filename+' must be opaque RGB'
                assert (bundle/filename).read_bytes()==data
                assert archive.read(prefix+filename)==data
        else:
            filename=plist['CFBundleIconFile']
            data=(ROOT/'source/gui/macOS/Resources'/filename).read_bytes()
            assert (bundle/resources/filename).read_bytes()==data
            assert archive.read(prefix+resources+'/'+filename)==data
            assert data[:4]==b'icns' and struct.unpack('>I',data[4:8])[0]==len(data)
            offset=8; elements=set()
            while offset<len(data):
                kind,length=struct.unpack('>4sI',data[offset:offset+8])
                assert 8<length<=300_000,(kind,length,'ICNS slice exceeds 300 KB')
                assert offset+length<=len(data)
                assert kind not in elements
                elements.add(kind); offset+=length
            assert offset==len(data)
            assert {b'is32',b's8mk',b'il32',b'l8mk',b'ih32',b'h8mk',b'it32',b't8mk',
                    b'ic08',b'ic09',b'ic10',b'ic11',b'ic12',b'ic13',b'ic14'} <= elements
    print('PASS:',platform,'architectures, resources, package freshness, and application metadata')
