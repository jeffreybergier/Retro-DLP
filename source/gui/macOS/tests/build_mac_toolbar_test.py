"""Build the offline PowerPC AppKit regression app after `make app-macOS`.

The test requires a fresh prepare_native_fixture.py library at
/tmp/retrodlp-toolbar-fixture on the test Mac. It writes its result to
/tmp/retrodlp-toolbar-test.txt. The bundle deliberately has no CA resource.
"""
from pathlib import Path
import os
import json
import re
import plistlib
import shutil
import subprocess

root = Path(__file__).resolve().parents[4]
build = Path(os.environ.get('BUILD_ROOT', root / 'build')).resolve()
app = build / 'tests/macOS/RetroDLPToolbarTest.app'
if app.exists():
    shutil.rmtree(app)
shutil.copytree(build / 'macOS/release/RetroDLP/RetroDLP.app', app)
(app / 'Contents/Resources/cacert.pem').unlink()
(app / 'Contents/MacOS/RetroDLP').unlink()
plist = app / 'Contents/Info.plist'
info = plistlib.loads(plist.read_bytes())
info.update(CFBundleExecutable='RetroDLPToolbarTest',
            CFBundleName='RetroDLPToolbarTest',
            CFBundleIdentifier='test.retrodlp.toolbar')
plist.write_bytes(plistlib.dumps(info))
test_source = root / 'source/gui/macOS/tests/mac_toolbar_test.m'
# Keep remote fixture/results inside a caller-owned Desktop directory.
if os.environ.get('RDLP_TEST_ROOT'):
    remote = os.environ['RDLP_TEST_ROOT'].rstrip('/')
    if not remote.startswith('/'):
        raise SystemExit('RDLP_TEST_ROOT must be an absolute remote directory')
    generated = build / 'tests/macOS/mac_toolbar_test.m'
    generated.write_text(re.sub(r'"/tmp/(retrodlp-[^"]*)"',
        lambda match: json.dumps(remote + '/' + match[1]), test_source.read_text()))
    test_source = generated
objects = build / 'macOS/release/RetroDLP/Intermediates/ppc'
cmd = ['/osxcross/legacy/target/bin/oppc32-gcc', '-arch', 'ppc',
       '-isysroot', '/osxcross/legacy/target/SDK/MacOSX10.5.sdk',
       '-Wall', '-Wextra', '-Werror', '-D_NONSTD_SOURCE',
       '-isystem', str(root / 'source/deps/QuickJS'),
       '-I/altivec/libs/cocoa/build-mac/include',
       '-I' + str(root / 'source/gui/shared'),
       '-I' + str(root / 'source/library/shared/include'),
       '-I' + str(root / 'source/gui/macOS/tests'), str(test_source)]
cmd += [str(path) for path in sorted(objects.rglob('*.o'))
        if path.name != 'main.m.o']
cmd += [str(build / 'macOS/release/libretrodlp-download/libretrodlp-download.a'),
        str(build / 'macOS/release/libretrodlp/libretrodlp.a'),
        '/altivec/libs/cocoa-sqlite/build-mac/lib/libAltivecCocoaSQLite.a',
        '/altivec/libs/core/build-mac/lib/libAltivecCore.a',
        '/altivec/libs/cocoa/build-mac/lib/libAltivecCocoa.a',
        '/altivec/libs/core/build-mac/lib/libcrypto.a']
for framework in ['AppKit', 'Foundation', 'CoreFoundation', 'SystemConfiguration',
                  'WebKit', 'CoreServices', 'ApplicationServices']:
    cmd += ['-framework', framework]
cmd += ['-lobjc', '-lpthread', '-lgcc_s.10.4', '-o',
        str(app / 'Contents/MacOS/RetroDLPToolbarTest')]
subprocess.run(cmd, env=dict(os.environ, MACOSX_DEPLOYMENT_TARGET='10.4'), check=True)
print(app)
