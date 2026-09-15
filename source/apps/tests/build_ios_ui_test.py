"""Build an isolated iOS UI regression app with an offline-only scheduler.

Run after make app-iOS. Install the resulting IPA on a jailbroken test device
and open test.retrodlp.ios. Reports/screenshots are written in its Documents.
The production app and its library are never opened or modified by the test.
"""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess

root = Path(__file__).resolve().parents[3]
app = root / 'build/apps/tests/RetroDLPIOSOfflineTest.app'
if app.exists():
    shutil.rmtree(app)
shutil.copytree(root / 'build/apps/iOS/RetroDLP.app', app)
(app / 'cacert.pem').unlink()
(app / 'RetroDLP').unlink()
fixture = root / 'build/apps/tests/ios-fixture.mp4'
if not fixture.exists():
    subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-f', 'lavfi',
                    '-i', 'testsrc2=size=320x180:rate=15', '-t', '3',
                    '-c:v', 'libx264', '-profile:v', 'baseline', '-level', '3.0',
                    '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(fixture)], check=True)
shutil.copyfile(fixture, app / 'fixture.mp4')
plist = app / 'Info.plist'
info = plistlib.loads(plist.read_bytes())
info.update(CFBundleExecutable='RetroDLPIOSOfflineTest',
            CFBundleName='RetroDLPIOSOfflineTest',
            CFBundleDisplayName='RDLP Offline Test',
            CFBundleIdentifier='test.retrodlp.ios',
            CFBundleURLTypes=[dict(CFBundleURLName='Offline Test',
                                  CFBundleURLSchemes=['retrodlp-offline-test'])])
if os.environ.get('RDLP_TEST_ICONS_ONLY') == '1':
    info['RDLPTestIconsOnly'] = True
plist.write_bytes(plistlib.dumps(info))
objects = root / 'build/apps/iOS/Intermediates'
cmd = ['/usr/bin/clang', '-target', 'armv7-apple-ios5.0', '-arch', 'armv7',
       '-isysroot', '/osxcross/modern/SDK/iPhoneOS8.4.sdk',
       '-B/osxcross/modern/bin', '-g', '-Wall', '-Wextra', '-Werror',
       '-Wno-semicolon-before-method-body',
       '-I/altivec/libs/cocoa/build-phone/include',
       '-I' + str(root / 'source/apps/shared'),
       '-I' + str(root / 'include'),
       str(root / 'source/apps/tests/ios_ui_test.m')]
cmd += [str(objects / (name + '.o')) for name in
        ['RDLPAppDelegate', 'RDLPLibraryViewController', 'RDLPLibraryActions',
         'RDLPLibrarySections', 'RDLPUIKit', 'RDLPDownloadPolicy', 'RDLPStatusBarView', 'RDLPSettingsViewController', 'RDLPPlaylistsViewController', 'RDLPPlaylistViewController', 'RDLPVideoListViewController', 'RDLPDownloadsViewController', 'RDLPQueueViewController',
         'RDLPLibrary', 'RDLPVideoRows', 'rdapp_store', 'rdapp_service']]
cmd += [str(root / 'build/iOS/libretrodlp-download.a'),
        str(root / 'build/iOS/libretrodlp.a'),
        '/altivec/libs/core/build-phone/lib/libAltivecCore.a',
        '/altivec/libs/cocoa/build-phone/lib/libAltivecCocoa.a',
        '/altivec/libs/core/build-phone/lib/libcrypto.a']
for framework in ['UIKit', 'Foundation', 'CoreGraphics', 'CoreText',
                  'CoreFoundation', 'SystemConfiguration', 'Security',
                  'MediaPlayer', 'AVFoundation']:
    cmd += ['-framework', framework]
cmd += ['-weak_framework', 'AVKit', '-lobjc', '-lpthread', '-o',
        str(app / 'RetroDLPIOSOfflineTest')]
subprocess.run(cmd, env=dict(os.environ, PATH='/osxcross/modern/bin:' + os.environ['PATH']), check=True)
subprocess.run(['ldid', '-S', str(app / 'RetroDLPIOSOfflineTest')], check=True)
subprocess.run(['python3', str(root / 'source/apps/package_ipa.py'), str(app),
                str(app.with_suffix('.ipa'))], check=True)
print(app.with_suffix('.ipa'))
