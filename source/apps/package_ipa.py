"""Package an already pseudo-signed application without changing its permissions."""
from pathlib import Path
import os
import sys
import zipfile

bundle = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
if bundle.suffix != '.app' or not (bundle/'Info.plist').is_file():
    raise SystemExit('Expected a built .app bundle')
output.parent.mkdir(parents=True, exist_ok=True)
temporary = output.with_suffix('.ipa.tmp')
with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(bundle.rglob('*')):
        archive.write(path, Path('Payload')/bundle.name/path.relative_to(bundle))
os.replace(temporary, output)
