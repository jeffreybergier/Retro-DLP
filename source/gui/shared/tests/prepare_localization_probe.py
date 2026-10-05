"""Copy a built native regression app into an isolated synthetic translation probe.

Usage: python3 source/gui/shared/tests/prepare_localization_probe.py macOS|iOS
Run the normal native test builder first. Production resources are never edited.
"""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[4]
platform = sys.argv[1]
assert platform in ('macOS', 'iOS')
output = root/'build/apps/tests'
source = output/('RetroDLPToolbarTest.app' if platform == 'macOS' else 'RetroDLPIOSOfflineTest.app')
app = output/('RetroDLPLocalization'+platform+'.app')
if app.exists():
    shutil.rmtree(app)
shutil.copytree(source, app)
resources = app/'Contents/Resources' if platform == 'macOS' else app
plist = app/'Contents/Info.plist' if platform == 'macOS' else app/'Info.plist'
info = plistlib.loads(plist.read_bytes())
info.update(CFBundleIdentifier='test.retrodlp.localization',
            CFBundleName='RDLP Localization Test', CFBundleDisplayName='RDLP Strings Test',
            RDLPTestLocalizationOnly=True)
if platform == 'iOS':
    info['CFBundleURLTypes'] = [dict(CFBundleURLName='Localization Test',
                                  CFBundleURLSchemes=['retrodlp-localization-test'])]
plist.write_bytes(plistlib.dumps(info))
encoding = 'utf-16' if platform == 'macOS' else 'utf-8'
path = resources/'en.lproj/Localizable.strings'
text = path.read_text(encoding=encoding)
for key, old, new in [('Cannot open library database', 'Cannot open library database', '翻訳済みデータベース'),
                      ('Added Videos', 'Added Videos', '追加した動画'),
                      ('Resolving video…', 'Resolving…', '準備中…'),
                      ('Configuring client…', 'Configuring…', '設定中…')]:
    entry = f'"{key}" = "{old}";'
    assert entry in text
    text = text.replace(entry, f'"{key}" = "{new}";')
path.write_text(text, encoding=encoding)
if platform == 'iOS':
    subprocess.run(['python3', str(root/'source/gui/iOS/package_ipa.py'),
                    str(app), str(app.with_suffix('.ipa'))], check=True)
print(app)
