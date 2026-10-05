"""Exercise initialized C translations and presentation against the real store."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
BUILD = ROOT/'build/apps/tests'
BUILD.mkdir(parents=True, exist_ok=True)
shared = ROOT/'source/gui/shared'
flags = ['-fsanitize=address,undefined', '-fno-omit-frame-pointer'] if os.environ.get('RDAPP_SANITIZE') else []
subprocess.run(['cc', '-std=c99', '-Wall', '-Wextra', '-Werror'] + flags + [
    '-I'+str(shared), '-I'+str(ROOT/'source/library/shared/include'),
    str(shared/'tests/strings_test.c'), str(shared/'rdapp_strings.c'),
    str(shared/'rdapp_store.c'), str(shared/'rdapp_service.c'),
    str(ROOT/'build/linux/libretrodlp-download.a'), str(ROOT/'build/linux/libretrodlp.a'),
    '-Wl,--wrap=malloc', '-lsqlite3', '-lcurl', '-lcrypto', '-lm', '-ldl', '-lpthread',
    '-o', str(BUILD/'strings-test')], check=True)
with tempfile.TemporaryDirectory(prefix='rdapp-strings-') as directory:
    subprocess.run([str(BUILD/'strings-test'), str(Path(directory)/'library.sqlite')], check=True)
