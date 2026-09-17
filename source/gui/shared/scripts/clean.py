"""Remove only generated application build outputs in this checkout."""
from pathlib import Path
import shutil

root=Path(__file__).resolve().parents[4]
output=root/'build/apps'
if output.is_symlink():
    raise SystemExit('Refusing to follow a symlink at build/apps')
if output.is_dir():
    shutil.rmtree(output)
