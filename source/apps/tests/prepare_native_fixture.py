"""Create an isolated, offline UI library with a playable synthetic MP4."""
import ctypes as C
from pathlib import Path
import subprocess
import sys
from test_store import lib, P, I, Entry, CB

root=Path(sys.argv[1]).resolve()
support=root/'Support'; support.mkdir(parents=True,exist_ok=True)
downloads=root/'Downloads'; downloads.mkdir(parents=True,exist_ok=True)
store=P(); key=I()
assert lib.rdapp_store_open(str(support/'retrodlp.sqlite').encode(),C.byref(store))
entries=(Entry*2)(Entry(b'YE7VzlLtp-4',b'Portable video playback fixture',0),Entry(b'AAAAAAAAAAA',b'Undownloaded video',1))
assert lib.rdapp_store_snapshot(store,b'PLfixture',b'Offline test playlist',entries,2,C.byref(key))
assert lib.rdapp_store_enqueue(store,key,b'YE7VzlLtp-4',b'18')
rows=[]
@CB
def collect(ctx,n,names,values):
    rows.append({names[i].decode():values[i].decode() if values[i] else '' for i in range(n)})
    return 1
assert lib.rdapp_store_claim(store,collect,None)
job=rows[0]; video=downloads/job['path']; video.parent.mkdir(parents=True,exist_ok=True)
subprocess.run(['ffmpeg','-nostdin','-v','error','-f','lavfi','-i','testsrc2=size=320x180:rate=15',
    '-f','lavfi','-i','anullsrc=r=44100:cl=stereo','-t','30','-c:v','libx264','-profile:v','baseline',
    '-level','3.0','-pix_fmt','yuv420p','-c:a','aac','-b:a','64k','-movflags','+faststart',str(video)],check=True)
assert lib.rdapp_store_finish(store,int(job['id']),b'complete',b'18',b'')
assert lib.rdapp_store_export(store,key,str(downloads).encode())
lib.rdapp_store_close(store)
