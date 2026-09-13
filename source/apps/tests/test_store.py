"""Offline behavior tests against the real portable application store."""
import ctypes as C
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / 'build/apps/tests'
BUILD.mkdir(parents=True, exist_ok=True)
subprocess.run(['cc', '-std=c99', '-Wall', '-Wextra', '-Werror', '-shared', '-fPIC',
                str(ROOT/'source/apps/shared/rdapp_store.c'), '-lsqlite3',
                '-o', str(BUILD/'store.so')], check=True)
lib = C.CDLL(str(BUILD/'store.so'))
P = C.c_void_p
S = C.c_char_p
I = C.c_int64
class Entry(C.Structure):
    _fields_ = [('video_id', S), ('title', S), ('position', C.c_int)]
CB = C.CFUNCTYPE(C.c_int, P, C.c_int, C.POINTER(S), C.POINTER(S))
for name, args in {
    'open':[S,C.POINTER(P)], 'close':[P], 'error':[P],
    'snapshot':[P,S,S,C.POINTER(Entry),C.c_size_t,C.POINTER(I)],
    'discovered_playlist':[P,S,S], 'playlist':[P,S,S,C.POINTER(I)], 'enqueue':[P,I,S,S],
    'claim':[P,CB,P], 'finish':[P,I,S,S,S], 'retry':[P,I],
    'cancel':[P,I], 'forget_file':[P,I], 'remove_playlist':[P,I,S],
    'reconcile':[P,S], 'remove_file':[P,I,S],
    'export':[P,I,S], 'list':[P,C.c_int,I,CB,P],
}.items():
    fn=getattr(lib, 'rdapp_store_'+name)
    fn.argtypes=args
    fn.restype=S if name=='error' else (None if name=='close' else C.c_int)

class StoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.path=Path(self.tmp.name)
        self.db=P()
        self.assertEqual(lib.rdapp_store_open(os.fsencode(self.path/'db.sqlite'),C.byref(self.db)),1)
        self.key=I()
        self.snapshot()
    def tearDown(self):
        lib.rdapp_store_close(self.db)
        self.tmp.cleanup()
    def check(self, result):
        self.assertEqual(result,1,lib.rdapp_store_error(self.db))
    def snapshot(self, entries=None):
        if entries is None:
            entries=[(b'abcdefghijk',b'First / title\n',0),(b'lmnopqrstuv',b'Second',1),(b'abcdefghijk',b'Duplicate',2)]
        array=(Entry*len(entries))(*(Entry(*e) for e in entries))
        return lib.rdapp_store_snapshot(self.db,b'PLtest',b'My / playlist',array,len(entries),C.byref(self.key))
    def rows(self, kind):
        rows=[]
        @CB
        def callback(ctx,n,names,values):
            rows.append({names[i].decode():values[i].decode() if values[i] else '' for i in range(n)})
            return 1
        self.check(lib.rdapp_store_list(self.db,kind,self.key,callback,None))
        return rows
    def claim(self):
        rows=[]
        @CB
        def callback(ctx,n,names,values):
            rows.append({names[i].decode():values[i].decode() if values[i] else '' for i in range(n)})
            return 1
        self.check(lib.rdapp_store_claim(self.db,callback,None))
        return rows[0] if rows else None
    def test_snapshot_preserves_order_and_duplicates(self):
        rows=self.rows(1)
        self.assertEqual([r['video_id'] for r in rows],['abcdefghijk','lmnopqrstuv','abcdefghijk'])
        self.assertEqual(len(self.rows(0)),1)
    def test_failed_snapshot_rolls_back(self):
        self.assertEqual(self.snapshot([(b'lmnopqrstuv',b'Changed',0),(b'bad',b'Broken',1)]),0)
        self.assertEqual(self.rows(1)[0]['title'],'First / title\n')
        self.assertEqual(len(self.rows(1)),3)
    def test_queue_is_idempotent_and_quality_specific(self):
        for _ in range(2): self.check(lib.rdapp_store_enqueue(self.db,self.key,None,b'18'))
        self.assertEqual(len(self.rows(2)),2)
        self.check(lib.rdapp_store_enqueue(self.db,self.key,b'abcdefghijk',b'136+140'))
        self.assertEqual(len(self.rows(2)),3)
        job=self.claim()
        self.assertEqual(job['state'],'running')
        self.assertNotIn('\n',job['path'])
        self.assertTrue(job['path'].startswith('Playlists/My _ playlist [PLtest]/'))
    def test_crash_recovery_retry_cancel(self):
        self.check(lib.rdapp_store_enqueue(self.db,self.key,None,b'18'))
        job=self.claim()
        lib.rdapp_store_close(self.db)
        self.check(lib.rdapp_store_open(os.fsencode(self.path/'db.sqlite'),C.byref(self.db)))
        self.assertEqual(next(r for r in self.rows(2) if r['id']==job['id'])['state'],'interrupted')
        self.check(lib.rdapp_store_retry(self.db,int(job['id'])))
        self.assertEqual(self.claim()['id'],job['id'])
        self.check(lib.rdapp_store_finish(self.db,int(job['id']),b'failed',b'',b'403'))
        other=self.claim()
        self.check(lib.rdapp_store_finish(self.db,int(other['id']),b'cancelled',b'',b'Cancelled'))
        self.check(lib.rdapp_store_retry(self.db,int(other['id'])))
        self.check(lib.rdapp_store_cancel(self.db,int(other['id'])))
        self.assertIsNone(self.claim())
    def test_export_complete_existing_files_in_playlist_order(self):
        self.check(lib.rdapp_store_enqueue(self.db,self.key,None,b'18'))
        job=self.claim()
        path=self.path/job['path']; path.parent.mkdir(parents=True); path.write_bytes(b'video fixture')
        self.check(lib.rdapp_store_finish(self.db,int(job['id']),b'complete',b'18',b''))
        self.check(lib.rdapp_store_export(self.db,self.key,os.fsencode(self.path)))
        export=path.parent/'Playlist.m3u8'
        self.assertEqual(export.read_text().splitlines(),['#EXTM3U','./'+path.name,'./'+path.name])
        path.unlink()
        self.check(lib.rdapp_store_export(self.db,self.key,os.fsencode(self.path)))
        self.assertEqual(export.read_text(),'#EXTM3U\n')
    def test_resync_keeps_downloads_but_changes_export_membership(self):
        self.check(lib.rdapp_store_enqueue(self.db,self.key,b'abcdefghijk',b'18'))
        job=self.claim(); path=self.path/job['path']; path.parent.mkdir(parents=True); path.write_bytes(b'video')
        self.check(lib.rdapp_store_finish(self.db,int(job['id']),b'complete',b'18',b''))
        self.check(self.snapshot([(b'lmnopqrstuv',b'Second',0)]))
        self.assertEqual(len(self.rows(3)),1)
        self.check(lib.rdapp_store_export(self.db,self.key,os.fsencode(self.path)))
        self.assertEqual((path.parent/'Playlist.m3u8').read_text(),'#EXTM3U\n')
        self.assertTrue(path.exists())
    def test_playlist_removal_requires_explicit_download_cleanup(self):
        self.check(lib.rdapp_store_enqueue(self.db,self.key,b'abcdefghijk',b'18'))
        self.assertEqual(lib.rdapp_store_remove_playlist(self.db,self.key,os.fsencode(self.path)),0)
        job=self.claim()
        self.check(lib.rdapp_store_finish(self.db,int(job['id']),b'complete',b'18',b''))
        self.assertEqual(lib.rdapp_store_remove_playlist(self.db,self.key,os.fsencode(self.path)),0)
        self.check(lib.rdapp_store_forget_file(self.db,int(job['id'])))
        self.check(lib.rdapp_store_remove_playlist(self.db,self.key,os.fsencode(self.path)))
        self.assertEqual(self.rows(0),[])
    def test_published_file_recovered_after_crash_and_missing_file_retried(self):
        self.check(lib.rdapp_store_enqueue(self.db,self.key,b'abcdefghijk',b'18'))
        job=self.claim(); path=self.path/job['path']; path.parent.mkdir(parents=True); path.write_bytes(b'completed media')
        self.check(lib.rdapp_store_finish(self.db,int(job['id']),b'running',b'18',b''))
        lib.rdapp_store_close(self.db)
        self.check(lib.rdapp_store_open(os.fsencode(self.path/'db.sqlite'),C.byref(self.db)))
        self.check(lib.rdapp_store_reconcile(self.db,os.fsencode(self.path)))
        self.assertEqual(self.rows(2)[0]['state'],'complete')
        path.unlink()
        self.check(lib.rdapp_store_reconcile(self.db,os.fsencode(self.path)))
        self.assertEqual(self.rows(2)[0]['state'],'removed')
        self.check(lib.rdapp_store_retry(self.db,int(job['id'])))
        self.assertEqual(self.claim()['id'],job['id'])
    def test_removal_cleans_failed_mux_tracks_and_preserves_unrelated_files(self):
        self.check(lib.rdapp_store_enqueue(self.db,self.key,b'abcdefghijk',b'18'))
        job=self.claim(); staging=self.path/'.staging'/job['id']; staging.mkdir(parents=True)
        track=staging/'video.mp4.audio.m4a'; track.write_bytes(b'audio')
        unrelated=self.path/'keep.mp4'; unrelated.write_bytes(b'keep')
        self.assertEqual(lib.rdapp_store_remove_file(self.db,int(job['id']),os.fsencode(self.path)),0)
        self.assertTrue(track.exists())
        self.check(lib.rdapp_store_finish(self.db,int(job['id']),b'failed',b'18',b'mux failed'))
        self.check(lib.rdapp_store_remove_file(self.db,int(job['id']),os.fsencode(self.path)))
        self.assertFalse(staging.exists())
        self.assertEqual(unrelated.read_bytes(),b'keep')
        self.assertEqual(self.rows(2)[0]['state'],'removed')
    def test_playlist_removal_cleans_cancelled_staging(self):
        self.check(lib.rdapp_store_enqueue(self.db,self.key,b'abcdefghijk',b'18'))
        job=self.claim(); staging=self.path/'.staging'/job['id']; staging.mkdir(parents=True)
        (staging/'video.mp4.video.mp4').write_bytes(b'retained track')
        self.check(lib.rdapp_store_finish(self.db,int(job['id']),b'cancelled',b'',b'Cancelled'))
        self.check(lib.rdapp_store_remove_playlist(self.db,self.key,os.fsencode(self.path)))
        self.assertFalse(staging.exists())
        self.assertEqual(self.rows(0),[])
    def test_discovery_promotes_without_duplicate_or_data_loss(self):
        self.check(lib.rdapp_store_enqueue(self.db,self.key,b'abcdefghijk',b'18'))
        original=self.rows(0)[0]
        self.assertEqual(original['source'],'added')
        self.check(lib.rdapp_store_discovered_playlist(self.db,b'PLtest',b'Account playlist'))
        self.check(lib.rdapp_store_discovered_playlist(self.db,b'PLtest',b'Account playlist'))
        self.assertEqual(len(self.rows(0)),1)
        current=self.rows(0)[0]
        self.assertEqual(current['source'],'account')
        self.assertEqual(current['id'],original['id'])
        self.assertEqual(current['directory'],original['directory'])
        self.assertEqual(len(self.rows(1)),3)
        self.assertEqual(len(self.rows(2)),1)
        self.check(self.snapshot())
        self.assertEqual(self.rows(0)[0]['source'],'account')
        lib.rdapp_store_close(self.db)
        self.check(lib.rdapp_store_open(os.fsencode(self.path/'db.sqlite'),C.byref(self.db)))
        self.assertEqual(self.rows(0)[0]['source'],'account')

    def test_version_one_migration_preserves_playlist(self):
        path=self.path/'legacy.sqlite'
        with sqlite3.connect(path) as db:
            db.executescript("CREATE TABLE playlists (id INTEGER PRIMARY KEY, service_id TEXT NOT NULL UNIQUE, title TEXT NOT NULL, directory TEXT NOT NULL, synced_at INTEGER); INSERT INTO playlists VALUES(7,'PLold','Old','Playlists/Old',42); PRAGMA user_version=1;")
        other=P()
        self.check(lib.rdapp_store_open(os.fsencode(path),C.byref(other)))
        lib.rdapp_store_close(other)
        with sqlite3.connect(path) as db:
            self.assertEqual(db.execute('SELECT id,service_id,directory,synced_at,source FROM playlists').fetchone(),(7,'PLold','Playlists/Old',42,'added'))
            self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0],2)

    def test_rejects_path_injection_and_future_schema(self):
        self.assertEqual(lib.rdapp_store_playlist(self.db,b'../../escape',b'Bad',None),0)
        future=self.path/'future.sqlite'
        with sqlite3.connect(future) as db: db.execute('PRAGMA user_version=99')
        other=P()
        self.assertEqual(lib.rdapp_store_open(os.fsencode(future),C.byref(other)),0)
        self.assertFalse(other.value)

if __name__=='__main__': unittest.main()
