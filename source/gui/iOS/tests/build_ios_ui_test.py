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
import zipfile

root = Path(__file__).resolve().parents[4]
build = Path(os.environ.get('BUILD_ROOT', root / 'build')).resolve()
app = build / 'tests/iOS/RetroDLPIOSOfflineTest.app'
if app.exists():
    shutil.rmtree(app)
shutil.copytree(build / 'iOS/release/RetroDLP/RetroDLP.app', app)
(app / 'cacert.pem').unlink()
(app / 'RetroDLP').unlink()
fixture = build / 'tests/iOS/ios-fixture.mp4'
if not fixture.exists():
    subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-f', 'lavfi',
                    '-i', 'testsrc2=size=320x180:rate=15', '-t', '3',
                    '-c:v', 'libx264', '-profile:v', 'baseline', '-level', '3.0',
                    '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(fixture)], check=True)
shutil.copyfile(fixture, app / 'fixture.mp4')
playback_fixture = build / 'tests/iOS/ios-playback-audio-fixture.mp4'
if not playback_fixture.exists():
    subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-stream_loop', '19',
                    '-i', str(fixture), '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=mono',
                    '-c:v', 'copy', '-c:a', 'aac', '-t', '60', str(playback_fixture)], check=True)
shutil.copyfile(playback_fixture, app / 'playback-fixture.mp4')
long_fixture = build / 'tests/iOS/ios-playback-long-audio-fixture.mp4'
if not long_fixture.exists():
    subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-stream_loop', '199',
                    '-i', str(fixture), '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=mono',
                    '-c:v', 'copy', '-c:a', 'aac', '-t', '600',
                    str(long_fixture)], check=True)
shutil.copyfile(long_fixture, app / 'playback-long-fixture.mp4')
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
if os.environ.get('RDLP_TEST_PLAYBACK_ONLY') == '1':
    info['RDLPTestPlaybackOnly'] = True
if os.environ.get('RDLP_TEST_NOW_PLAYING_HOLD') == '1':
    info['RDLPTestNowPlayingHold'] = True
if os.environ.get('RDLP_TEST_INTERACTION_ONLY') == '1':
    info['RDLPTestInteractionOnly'] = True
if os.environ.get('RDLP_TEST_UI_ONLY') == '1':
    info['RDLPTestUIOnly'] = True
plist.write_bytes(plistlib.dumps(info))
slices = []
for arch, minimum in [('armv7', '5.0'), ('arm64', '7.0')]:
    objects = build / 'iOS/release/RetroDLP/Intermediates' / arch
    output = app.parent / ('RetroDLPIOSOfflineTest-' + arch)
    cmd = ['/usr/bin/clang', '-target', arch + '-apple-ios' + minimum,
           '-isysroot', '/osxcross/modern/SDK/iPhoneOS8.4.sdk',
           '-B/osxcross/modern/bin', '-g', '-Wall', '-Wextra', '-Werror',
           '-fblocks', '-Wno-semicolon-before-method-body',
           '-isystem', str(root / 'source/deps/QuickJS'),
           '-I/altivec/libs/cocoa/build-phone/include',
           '-I' + str(root / 'source/gui/shared'),
           '-I' + str(root / 'source/library/shared/include'),
           str(root / 'source/gui/iOS/tests/ios_ui_test.m')]
    cmd += [str(path) for path in sorted(objects.rglob('*.o'))
            if path.name != 'main.m.o']
    cmd += [str(build / 'iOS/release/libretrodlp-download/libretrodlp-download.a'),
            str(build / 'iOS/release/libretrodlp/libretrodlp.a'),
            '/altivec/libs/core/build-phone/lib/libAltivecCore.a',
            '/altivec/libs/cocoa/build-phone/lib/libAltivecCocoa.a',
            '/altivec/libs/core/build-phone/lib/libcrypto.a']
    for framework in ['UIKit', 'Foundation', 'CoreGraphics', 'CoreText',
                      'CoreFoundation', 'SystemConfiguration', 'Security',
                      'MediaPlayer', 'AVFoundation', 'CoreMedia', 'QuartzCore']:
        cmd += ['-framework', framework]
    cmd += ['-lobjc', '-lpthread', '-o', str(output)]
    subprocess.run(cmd, check=True)
    slices.append(str(output))
subprocess.run(['/osxcross/modern/bin/lipo', '-create', *slices,
                '-output', str(app / 'RetroDLPIOSOfflineTest')], check=True)
entitlements = app.parent / 'ios-test-entitlements.plist'
entitlements.write_bytes(plistlib.dumps({
    'application-identifier': info['CFBundleIdentifier'],
    'com.apple.private.security.container-required': info['CFBundleIdentifier'],
}))
subprocess.run(['ldid', '-S' + str(entitlements),
                str(app / 'RetroDLPIOSOfflineTest')], check=True)
with zipfile.ZipFile(app.with_suffix('.ipa'), 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob('*')):
        archive.write(path, Path('Payload') / app.name / path.relative_to(app))
print(app.with_suffix('.ipa'))
