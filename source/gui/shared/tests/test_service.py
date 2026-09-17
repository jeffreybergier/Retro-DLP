"""Run real resolver/downloader application workflows using local HTTPS fixtures."""
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[4]
BUILD = ROOT/'build/apps/tests'
BUILD.mkdir(parents=True, exist_ok=True)
subprocess.run(['cc', '-std=c99', '-Wall', '-Wextra', '-Werror',
    '-I'+str(ROOT/'source/library/shared/include'), '-I'+str(ROOT/'source/gui/shared'),
    str(ROOT/'source/gui/shared/tests/service_test.c'),
    str(ROOT/'source/gui/shared/rdapp_store.c'), str(ROOT/'source/gui/shared/rdapp_service.c'),
    str(ROOT/'build/linux/libretrodlp-download.a'), str(ROOT/'build/linux/libretrodlp.a'),
    '-lsqlite3', '-lcurl', '-lcrypto', '-lm', '-ldl', '-lpthread',
    '-o',str(BUILD/'service-test')], check=True)
with tempfile.TemporaryDirectory(prefix='rdapp-service-') as directory:
    folder=Path(directory)
    certificate,key,port=(folder/n for n in ('cert.pem','key.pem','port'))
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1',
        '-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost',
        '-keyout',str(key),'-out',str(certificate)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    server=subprocess.Popen(['python3',str(ROOT/'source/library/linux/tests/download_server.py'),str(certificate),str(key),str(port)])
    try:
        for _ in range(100):
            if port.exists() and port.stat().st_size: break
            if server.poll() is not None: raise RuntimeError('HTTPS fixture server exited')
            time.sleep(.05)
        library=folder/'library'; library.mkdir()
        subprocess.run([str(BUILD/'service-test'),str(library),'https://localhost:'+port.read_text(),str(certificate)],check=True,timeout=60)
    finally:
        server.terminate(); server.wait(timeout=10)
