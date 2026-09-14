"""Build the offline PowerPC AppKit regression app after `make app-macOS`.

The test requires a fresh prepare_native_fixture.py library at
/tmp/retrodlp-toolbar-fixture on the test Mac. It writes its result to
/tmp/retrodlp-toolbar-test.txt. The bundle deliberately has no CA resource.
"""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess

root = Path(__file__).resolve().parents[3]
app = root / 'build/apps/tests/RetroDLPToolbarTest.app'
if app.exists():
    shutil.rmtree(app)
shutil.copytree(root / 'build/apps/macOS/RetroDLP.app', app)
(app / 'Contents/Resources/cacert.pem').unlink()
(app / 'Contents/MacOS/RetroDLP').unlink()
plist = app / 'Contents/Info.plist'
info = plistlib.loads(plist.read_bytes())
info.update(CFBundleExecutable='RetroDLPToolbarTest',
            CFBundleName='RetroDLPToolbarTest',
            CFBundleIdentifier='test.retrodlp.toolbar')
plist.write_bytes(plistlib.dumps(info))
objects = root / 'build/apps/macOS/Intermediates/ppc'
cmd = ['/osxcross/legacy/target/bin/oppc32-gcc', '-arch', 'ppc',
       '-isysroot', '/osxcross/legacy/target/SDK/MacOSX10.5.sdk',
       '-Wall', '-Wextra', '-Werror', '-D_NONSTD_SOURCE',
       '-I/altivec/libs/cocoa/build-mac/include',
       '-I' + str(root / 'source/apps/shared'),
       str(root / 'source/apps/tests/mac_toolbar_test.m')]
cmd += [str(objects / (name + '.o')) for name in
        ['RDLPLibraryWindowController', 'RDLPAppKit', 'RDLPToolbarButton', 'RDLPQueueOutlineView', 'RDLPLibraryViews', 'RDLPDownloadPolicy', 'RDLPLibraryMenus', 'RDLPLibrary',
         'rdapp_store', 'rdapp_service']]
cmd += [str(root / 'build/macOS/libretrodlp-download.a'),
        str(root / 'build/macOS/libretrodlp.a'),
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
