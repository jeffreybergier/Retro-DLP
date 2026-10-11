"""Compile, link, and analyze the player; package its isolated device tests.

Run after make app-iOS; the harness links production UI support objects.
This does not install or launch the Retro-DLP app. Run the test
app on a device to execute UIKit/AVFoundation tests; compilation alone is not a
runtime test. Override CLANG, IOS_SDK, IOS_BIN, and LDID for another toolchain.
"""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess

player = Path(__file__).resolve().parents[1]
root = player.parents[3]
build = Path(os.environ.get('BUILD_ROOT', root / 'build')).resolve()
output = build / 'tests/iOS/player'
output.mkdir(parents=True, exist_ok=True)
content_test = output / 'content-tests'
subprocess.run([os.environ.get('CC', 'cc'), '-std=c99', '-Wall', '-Wextra', '-Werror',
                str(player / 'tests/content_tests.c'), '-lm', '-o', str(content_test)], check=True)
subprocess.run([str(content_test)], check=True)
clang = os.environ.get('CLANG', '/usr/bin/clang')
sdk = os.environ.get('IOS_SDK', '/osxcross/modern/SDK/iPhoneOS8.4.sdk')
bin_dir = os.environ.get('IOS_BIN', '/osxcross/modern/bin')
env = dict(os.environ, PATH=bin_dir + os.pathsep + os.environ['PATH'])
sources = [player / 'RDLPPlayerControls.m', player / 'RDLPPlayerViewController.m',
           player / 'RDLPPlayerQueue.m', player / 'RDLPPlayerNavigationController.m']
flags = ['-isysroot', sdk, '-B' + bin_dir, '-fno-objc-arc', '-fblocks',
         '-Wall', '-Wextra', '-Werror', '-Wunguarded-availability',
         '-Wno-deprecated-declarations', '-I' + str(player),
         '-I/altivec/libs/cocoa/build-phone/include']
fixture = output / 'fixture.mp4'
if not fixture.exists():
    subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-f', 'lavfi',
                    '-i', 'testsrc2=size=320x180:rate=15', '-f', 'lavfi',
                    '-i', 'sine=frequency=440:sample_rate=44100', '-t', '8',
                    '-c:v', 'libx264', '-profile:v', 'baseline', '-level', '3.0',
                    '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-ac', '1',
                    '-movflags', '+faststart', str(fixture)], check=True)

for arch, minimum in [('armv7', '5.0'), ('arm64', '7.0')]:
    target = ['-target', f'{arch}-apple-ios{minimum}']
    app = output / arch / 'RDLPPlayerTests.app'
    app.mkdir(parents=True, exist_ok=True)
    command = [clang] + target + flags + [str(p) for p in sources]
    command += [str(player / 'tests/main.m'), str(player / 'tests/queue_tests.m'), '-lobjc']
    objects = build / 'iOS/release/RetroDLP/Intermediates' / arch
    compiled = {p.name + '.o' for p in sources} | {'main.m.o'}
    command += [str(p) for p in sorted(objects.rglob('*.o')) if p.name not in compiled]
    command += [str(build / 'iOS/release/libretrodlp-download/libretrodlp-download.a'),
                str(build / 'iOS/release/libretrodlp/libretrodlp.a'),
                '/altivec/libs/cocoa/build-phone/lib/libAltivecCocoa.a',
                '/altivec/libs/core/build-phone/lib/libAltivecCore.a',
                '/altivec/libs/core/build-phone/lib/libcrypto.a']
    for framework in ['UIKit', 'Foundation', 'AVFoundation', 'CoreMedia',
                      'CoreGraphics', 'QuartzCore', 'MediaPlayer', 'CoreFoundation',
                      'SystemConfiguration', 'Security', 'CoreText']:
        command += ['-framework', framework]
    command += ['-o', str(app / 'RDLPPlayerTests')]
    subprocess.run(command, env=env, check=True)
    for source in sources:
        subprocess.run([clang, '--analyze', '-Xanalyzer', '-analyzer-output=text']
                       + target + flags + [str(source)], env=env, check=True)
    shutil.rmtree(app / 'RDLPPlayer.bundle', ignore_errors=True)
    shutil.copytree(player / 'RDLPPlayer.bundle', app / 'RDLPPlayer.bundle')
    shutil.copyfile(fixture, app / 'fixture.mp4')
    shutil.copytree(build / 'iOS/release/RetroDLP/RetroDLP.app/Fonts', app / 'Fonts',
                    dirs_exist_ok=True)
    info = dict(CFBundleExecutable='RDLPPlayerTests', CFBundleName='RDLPPlayerTests',
                CFBundleDisplayName='Player Tests', CFBundleIdentifier='test.retrodlp.player',
                CFBundlePackageType='APPL', CFBundleVersion='1',
                CFBundleShortVersionString='1.0', MinimumOSVersion=minimum,
                LSRequiresIPhoneOS=True, UIDeviceFamily=[1, 2], UIFileSharingEnabled=True,
                CFBundleURLTypes=[dict(CFBundleURLName='Player Tests',
                                       CFBundleURLSchemes=['retrodlp-player-tests'])])
    (app / 'Info.plist').write_bytes(plistlib.dumps(info))
    entitlements = output / 'player-entitlements.plist'
    entitlements.write_bytes(plistlib.dumps({
        'application-identifier': info['CFBundleIdentifier'],
        'com.apple.private.security.container-required': info['CFBundleIdentifier'],
    }))
    subprocess.run([os.environ.get('LDID', 'ldid'), '-S' + str(entitlements),
                    str(app / 'RDLPPlayerTests')], check=True)
    print(f'PASS: {arch}/iOS {minimum} compiled, linked, and analyzed; device test app: {app}')
