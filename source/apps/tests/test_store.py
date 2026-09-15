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
                str(ROOT/'source/apps/tests/store_probe.c'), '-lsqlite3',
                '-o', str(BUILD/'store.so')], check=True)
lib = C.CDLL(str(BUILD/'store.so'))
P = C.c_void_p
S = C.c_char_p
I = C.c_int64
class Entry(C.Structure):
    _fields_ = [('video_id', S), ('title', S), ('position', C.c_int),
                ('thumbnail_urls', C.POINTER(S)), ('thumbnail_count', C.c_size_t),
                ('channel', S), ('channel_id', S), ('view_count_text', S),
                ('published_text', S), ('description_snippet', S),
                ('duration', C.c_uint64), ('view_count', C.c_uint64),
                ('has_duration', C.c_int), ('has_view_count', C.c_int)]
METADATA_FIELDS = ('channel', 'channel_id', 'view_count_text', 'published_text',
                   'description_snippet', 'duration', 'view_count')
ENTRY_FIELDS = {'playlist_id', 'position', 'video_id', 'title', *METADATA_FIELDS}
CB = C.CFUNCTYPE(C.c_int, P, C.c_int, C.POINTER(S), C.POINTER(S))
for name, args in {
    'open':[S,C.POINTER(P)], 'open_reader':[S,C.POINTER(P)], 'close':[P], 'error':[P],
    'count':[P,C.c_int,I,S,S,C.POINTER(I)],
    'page':[P,C.c_int,I,S,S,I,I,CB,P],
    'after':[P,C.c_int,I,S,S,I,CB,P],
    'index':[P,C.c_int,I,I,C.POINTER(I)],
    'snapshot':[P,S,S,C.POINTER(Entry),C.c_size_t,C.POINTER(I)],
    'discovered_playlist':[P,S,S], 'playlist':[P,S,S,C.POINTER(I)], 'enqueue':[P,I,S,S],
    'claim':[P,CB,P], 'finish':[P,I,S,S,S], 'retry':[P,I],
    'cancel':[P,I], 'forget_file':[P,I], 'reconcile_job':[P,I,S], 'remove_playlist':[P,I,S],
    'reconcile':[P,S], 'remove_file':[P,I,S],
    'export':[P,I,S], 'list':[P,C.c_int,I,CB,P],
}.items():
    fn=getattr(lib, 'rdapp_store_'+name)
    fn.argtypes=args
    fn.restype=S if name=='error' else (None if name=='close' else C.c_int)

lib.rdapp_test_measure.argtypes=[P]
lib.rdapp_test_measure.restype=None
lib.rdapp_test_steps.argtypes=[]
lib.rdapp_test_steps.restype=I

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
        array=(Entry*len(entries))(*(e if isinstance(e,Entry) else Entry(*e) for e in entries))
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
    def count(self, kind, key=None, video=None, format=None, store=None):
        result=I()
        self.check(lib.rdapp_store_count(store or self.db,kind,self.key if key is None else key,video,format,C.byref(result)))
        return result.value
    def page(self, kind, offset=0, limit=1, key=None, video=None, format=None, store=None, after=None):
        rows=[]
        @CB
        def callback(ctx,n,names,values):
            rows.append({names[i].decode():values[i].decode() if values[i] else '' for i in range(n)})
            return 1
        args=[store or self.db,kind,self.key if key is None else key,video,format]
        if after is None:
            self.check(lib.rdapp_store_page(*args,offset,limit,callback,None))
        else:
            self.check(lib.rdapp_store_after(*args,after,callback,None))
        return rows
    def index(self, kind, identity, key=None, store=None):
        result=I()
        self.check(lib.rdapp_store_index(store or self.db,kind,self.key if key is None else key,identity,C.byref(result)))
        return result.value

    def test_count_page_seek_and_identity_preserve_membership(self):
        self.check(self.snapshot([(b'abcdefghijk',b'First',3),(b'lmnopqrstuv',b'Second',8),(b'abcdefghijk',b'Duplicate',15)]))
        self.assertEqual(self.count(1),3)
        self.assertEqual([self.page(1,i)[0]['position'] for i in range(3)],['3','8','15'])
        self.assertEqual(self.page(1,limit=0),[])
        self.assertEqual(self.page(1,offset=3),[])
        self.assertEqual(self.page(1,after=8)[0]['title'],'Duplicate')
        self.assertEqual(self.index(1,15),2)
        self.assertEqual(self.index(1,9),-1)
        self.assertEqual(self.page(1)[0].keys(),ENTRY_FIELDS)

    def test_filtered_lists_and_exact_job_lookups(self):
        self.check(lib.rdapp_store_discovered_playlist(self.db,b'PLaccount',b'Account'))
        self.assertEqual(self.count(4),1)
        self.assertEqual(self.count(5),1)
        self.assertEqual(self.page(4)[0]['service_id'],'PLtest')
        self.assertEqual(self.page(5)[0]['service_id'],'PLaccount')
        self.assertEqual(self.count(14,video=b'PLtest'),1)
        self.assertEqual(self.count(14,video=b'absent'),0)
        self.check(lib.rdapp_store_enqueue(self.db,self.key,None,b'18'))
        self.check(lib.rdapp_store_enqueue(self.db,self.key,b'abcdefghijk',b'136+140'))
        jobs=self.rows(2)
        self.check(lib.rdapp_store_finish(self.db,int(jobs[0]['id']),b'removed',b'',b''))
        self.check(lib.rdapp_store_finish(self.db,int(jobs[1]['id']),b'removed',b'',b'Missing file'))
        self.check(lib.rdapp_store_finish(self.db,int(jobs[2]['id']),b'complete',b'18',b''))
        self.assertEqual(self.count(6),2) # Deliberate deletion hidden; missing retained.
        self.assertEqual([r['id'] for r in self.page(6,limit=10)],[jobs[2]['id'],jobs[1]['id']])
        self.assertEqual(self.page(6,after=int(jobs[2]['id']))[0]['id'],jobs[1]['id'])
        self.assertEqual(self.index(6,int(jobs[1]['id'])),1)
        self.assertEqual(self.index(6,int(jobs[0]['id'])),-1)
        self.assertEqual(self.count(3),1)
        self.assertEqual(self.index(3,int(jobs[2]['id'])),0)
        self.assertEqual(self.count(7),0)
        self.assertEqual(self.count(8),1)
        self.assertEqual(self.page(9,video=b'abcdefghijk',format=b'18')[0]['id'],jobs[2]['id'])
        self.assertEqual(self.page(10,key=int(jobs[1]['id']))[0]['error'],'Missing file')
        self.assertEqual(self.page(11)[0]['service_id'],'PLtest')

    def test_missing_plan_deduplicates_and_excludes_retry_only_states(self):
        self.check(lib.rdapp_store_enqueue(self.db,self.key,b'abcdefghijk',b'18'))
        job=self.rows(2)[0]
        self.check(lib.rdapp_store_finish(self.db,int(job['id']),b'failed',b'',b'Failure'))
        self.assertEqual(self.count(12,format=b'18'),1)
        self.assertEqual(self.page(13,format=b'18',limit=10)[0]['video_id'],'lmnopqrstuv')
        self.check(lib.rdapp_store_finish(self.db,int(job['id']),b'complete',b'18',b''))
        self.assertEqual(self.count(12,format=b'18'),1)
        self.assertEqual(self.count(13,format=b'18'),2)
        self.assertEqual(self.page(13,format=b'18',after=0)[0]['video_id'],'lmnopqrstuv')
        self.check(lib.rdapp_store_finish(self.db,int(job['id']),b'removed',b'',b''))
        self.assertEqual(self.count(12,format=b'18'),2)

    def test_retry_reconciliation_touches_only_the_selected_job(self):
        self.check(lib.rdapp_store_enqueue(self.db,self.key,None,b'18'))
        jobs=self.rows(2)
        for job in jobs:
            self.check(lib.rdapp_store_finish(self.db,int(job['id']),b'complete',b'18',b''))
        self.check(lib.rdapp_store_reconcile_job(self.db,int(jobs[0]['id']),os.fsencode(self.path)))
        self.assertEqual(self.page(10,key=int(jobs[0]['id']))[0]['state'],'removed')
        self.assertEqual(self.page(10,key=int(jobs[1]['id']))[0]['state'],'complete')
        self.check(lib.rdapp_store_retry(self.db,int(jobs[0]['id'])))
        self.assertEqual(self.page(10,key=int(jobs[0]['id']))[0]['state'],'queued')

    def test_reader_snapshot_is_stable_without_blocking_writes(self):
        reader=P()
        self.check(lib.rdapp_store_open_reader(os.fsencode(self.path/'db.sqlite'),C.byref(reader)))
        try:
            self.assertEqual(self.count(1,store=reader),3) # Establish snapshot, no payloads.
            self.check(self.snapshot([(b'lmnopqrstuv',b'Changed',0)]))
            self.assertEqual(self.count(1),1)
            self.assertEqual(self.count(1,store=reader),3)
            self.assertEqual(self.page(1,2,store=reader)[0]['title'],'Duplicate')
            self.assertEqual(self.index(1,2,store=reader),2)
            self.assertEqual(self.page(1)[0]['title'],'Changed')
            # A reader must not run startup recovery on running jobs.
            self.check(lib.rdapp_store_enqueue(self.db,self.key,None,b'18'))
            job=self.claim()
            self.assertEqual(self.page(10,key=int(job['id']))[0]['state'],'running')
            # Uncommitted background writes still permit UI counts and payload reads.
            with sqlite3.connect(self.path/'db.sqlite') as writer:
                writer.execute("UPDATE entries SET title='Uncommitted'")
                self.assertEqual(self.page(1)[0]['title'],'Changed')
        finally:
            lib.rdapp_store_close(reader)

    def test_large_list_reads_only_requested_payloads(self):
        size=50000
        with sqlite3.connect(self.path/'db.sqlite') as db:
            db.execute('DELETE FROM entries')
            db.executemany('INSERT INTO entries(playlist_id,position,video_id,title) VALUES(?,?,?,?)',
                ((self.key.value,i*2,'abcdefghijk','Large payload '+('x'*1024)) for i in range(size)))
        self.assertEqual(self.count(1),size)
        self.assertEqual(len(self.page(1,offset=size-3,limit=2)),2)
        lib.rdapp_test_measure(self.db)
        self.assertEqual(self.page(1,after=(size-2)*2)[0]['position'],str((size-1)*2))
        self.assertLess(lib.rdapp_test_steps(),1000,'Sequential scrolling must seek, not scan preceding entries')
        self.assertEqual(self.index(1,(size-1)*2),size-1)
        self.assertEqual(self.page(1,after=(size-1)*2),[])

    def test_snapshot_preserves_order_and_duplicates(self):
        rows=self.rows(1)
        self.assertEqual([r['video_id'] for r in rows],['abcdefghijk','lmnopqrstuv','abcdefghijk'])
        self.assertEqual(len(self.rows(0)),1)

    def thumbnails(self):
        with sqlite3.connect(self.path/'db.sqlite') as db:
            return db.execute('SELECT position,thumbnail_index,url FROM entry_thumbnails WHERE playlist_id=? ORDER BY position,thumbnail_index', (self.key.value,)).fetchall()

    def test_thumbnail_urls_preserve_occurrences_and_replace_on_sync(self):
        urls=(S*2)(b'https://img.example/first.jpg?x=1&y=2',b'https://img.example/second.jpg')
        duplicate=(S*1)(b'https://img.example/duplicate.jpg')
        self.check(self.snapshot([(b'abcdefghijk',b'First',3,urls,2),
                                  (b'abcdefghijk',b'Duplicate',8,duplicate,1),
                                  (b'lmnopqrstuv',b'Absent',9)]))
        expected=[(3,0,urls[0].decode()),(3,1,urls[1].decode()),(8,0,duplicate[0].decode())]
        self.assertEqual(self.thumbnails(),expected)
        # Storage owns the strings; normal list payloads still exclude thumbnails.
        urls[0]=b'changed'
        self.assertEqual(self.thumbnails(),expected)
        self.assertEqual(self.page(1)[0].keys(),ENTRY_FIELDS)
        self.check(lib.rdapp_store_enqueue(self.db,self.key,None,b'18'))
        jobs=self.rows(2)
        self.check(self.snapshot([(b'abcdefghijk',b'Now absent',3),
                                  (b'abcdefghijk',b'New position',4,duplicate,1)]))
        self.assertEqual(self.thumbnails(),[(4,0,duplicate[0].decode())])
        self.assertEqual(self.rows(2),jobs)
        self.check(self.snapshot([]))
        self.assertEqual(self.thumbnails(),[])

    def test_thumbnail_snapshot_rollback_and_playlist_cleanup(self):
        urls=(S*1)(b'https://img.example/old.jpg')
        self.check(self.snapshot([(b'abcdefghijk',b'Original',0,urls,1)]))
        original=self.thumbnails()
        for invalid in [(None,1),((S*1)(None),1),((S*1)(b''),1)]:
            self.assertEqual(self.snapshot([(b'abcdefghijk',b'Changed',0),
                                            (b'lmnopqrstuv',b'Invalid',1,*invalid)]),0)
            self.assertEqual(self.thumbnails(),original)
            self.assertEqual(self.rows(1)[0]['title'],'Original')
        self.assertEqual(self.snapshot([(b'lmnopqrstuv',b'Changed',1,urls,1),
                                        (b'bad',b'Invalid video',2)]),0)
        self.assertEqual(self.thumbnails(),original)
        self.check(lib.rdapp_store_remove_playlist(self.db,self.key,os.fsencode(self.path)))
        self.assertEqual(self.thumbnails(),[])
    def test_failed_snapshot_rolls_back(self):
        self.assertEqual(self.snapshot([(b'lmnopqrstuv',b'Changed',0),(b'bad',b'Broken',1)]),0)
        self.assertEqual(self.rows(1)[0]['title'],'First / title\n')
        self.assertEqual(len(self.rows(1)),3)

    def test_optional_metadata_roundtrip_zero_duplicates_and_replacement(self):
        rich=Entry(b'abcdefghijk',b'Rich',0,channel='Café Channel'.encode(),channel_id=b'UC_fixture',
                   view_count_text=b'1,234 views',published_text=b'2 days ago',description_snippet='A snippet…'.encode(),
                   duration=3723,view_count=1234,has_duration=1,has_view_count=1)
        zero=Entry(b'lmnopqrstuv',b'Zero',2,duration=0,view_count=0,has_duration=1,has_view_count=1)
        rounded=Entry(b'lmnopqrstuv',b'Rounded',3,view_count_text=b'1.2M views')
        self.check(self.snapshot([rich,(b'abcdefghijk',b'Duplicate without metadata',1),zero,rounded]))
        rows=self.rows(1)
        self.assertEqual([rows[0][f] for f in METADATA_FIELDS],['Café Channel','UC_fixture','1,234 views','2 days ago','A snippet…','3723','1234'])
        self.assertTrue(all(rows[1][f]=='' for f in METADATA_FIELDS))
        self.assertEqual((rows[2]['duration'],rows[2]['view_count']),('0','0'))
        self.assertEqual((rows[3]['view_count'],rows[3]['view_count_text']),('','1.2M views'))
        with sqlite3.connect(self.path/'db.sqlite') as db:
            self.assertEqual(db.execute('SELECT duration,view_count FROM entries ORDER BY position').fetchall(),[(3723,1234),(None,None),(0,0),(None,None)])
        self.check(lib.rdapp_store_enqueue(self.db,self.key,None,b'18'))
        jobs=self.rows(2)
        self.assertEqual(self.snapshot([rich,(b'bad',b'Invalid',1)]),0)
        self.assertEqual([{f:r[f] for f in ENTRY_FIELDS} for r in self.rows(1)],
                         [{f:r[f] for f in ENTRY_FIELDS} for r in rows])
        self.assertEqual(self.rows(2),jobs)  # Failed sync must preserve job metadata too.
        self.check(self.snapshot())
        self.assertTrue(all(row[f]=='' for row in self.rows(1) for f in METADATA_FIELDS))
        self.assertTrue(all(row[f]=='' for row in self.rows(2) for f in METADATA_FIELDS))
        self.assertEqual([{k:v for k,v in r.items() if k not in METADATA_FIELDS} for r in self.rows(2)],
                         [{k:v for k,v in r.items() if k not in METADATA_FIELDS} for r in jobs])

    def test_download_metadata_tracks_first_occurrence_and_survives_removal(self):
        first=Entry(b'abcdefghijk',b'First occurrence',5,channel=b'First channel',duration=0,has_duration=1)
        second=Entry(b'abcdefghijk',b'Second occurrence',9,channel=b'Second channel',duration=99,has_duration=1)
        self.check(self.snapshot([second,first]))
        for quality in (b'18',b'137+140'):
            self.check(lib.rdapp_store_enqueue(self.db,self.key,None,quality))
        self.assertEqual(len(self.rows(2)),2)
        self.assertTrue(all(r['channel']=='First channel' and r['duration']=='0' for r in self.rows(2)))
        self.check(lib.rdapp_store_finish(self.db,int(self.rows(2)[0]['id']),b'complete',b'18',b''))
        first.channel=b'Updated channel'
        self.check(self.snapshot([first,second]))
        self.assertTrue(all(r['channel']=='Updated channel' for r in self.rows(2)))
        jobs=self.rows(2)
        self.check(self.snapshot([]))
        self.assertEqual(self.rows(2),jobs)
        self.assertEqual(len(self.rows(3)),1)  # Still one row per completed quality.

    def test_version_four_backfills_downloads_without_duplicating_jobs(self):
        self.check(self.snapshot([Entry(b'abcdefghijk',b'First',0,channel=b'Original',duration=0,has_duration=1),
                                  Entry(b'abcdefghijk',b'Duplicate',1,channel=b'Other',duration=88,has_duration=1)]))
        self.check(lib.rdapp_store_enqueue(self.db,self.key,None,b'18'))
        jobs=self.rows(2)
        lib.rdapp_store_close(self.db); self.db=P()
        with sqlite3.connect(self.path/'db.sqlite') as db:
            for field in METADATA_FIELDS: db.execute('ALTER TABLE jobs DROP COLUMN '+field)
            db.execute('PRAGMA user_version=4')
        self.check(lib.rdapp_store_open(os.fsencode(self.path/'db.sqlite'),C.byref(self.db)))
        self.assertEqual(self.rows(2),jobs)

    def test_metadata_numeric_limits_and_rollback(self):
        entry=Entry(b'abcdefghijk',b'Large',0,duration=9007199254740991,view_count=9007199254740991,has_duration=1,has_view_count=1)
        self.check(self.snapshot([entry]))
        original=self.rows(1)
        self.assertEqual(original[0]['duration'],'9007199254740991')
        for field in ('duration','view_count'):
            setattr(entry,field,9007199254740992)
            self.assertEqual(self.snapshot([entry]),0)
            self.assertEqual(self.rows(1),original)
            setattr(entry,field,9007199254740991)
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
            self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0],5)
            self.assertEqual(db.execute('SELECT count(*) FROM entry_thumbnails').fetchone()[0],0)

    def test_version_two_migration_preserves_entries_and_jobs(self):
        self.check(lib.rdapp_store_enqueue(self.db,self.key,None,b'18'))
        entries,jobs=self.rows(1),self.rows(2)
        lib.rdapp_store_close(self.db)
        self.db=P()
        with sqlite3.connect(self.path/'db.sqlite') as db:
            db.executescript('DROP TABLE entry_thumbnails; PRAGMA user_version=2;')
            for field in METADATA_FIELDS:
                db.execute('ALTER TABLE entries DROP COLUMN '+field)
                db.execute('ALTER TABLE jobs DROP COLUMN '+field)
        self.check(lib.rdapp_store_open(os.fsencode(self.path/'db.sqlite'),C.byref(self.db)))
        self.assertEqual(self.rows(1),entries)
        self.assertEqual(self.rows(2),jobs)
        self.assertEqual(self.thumbnails(),[])
        urls=(S*1)(b'https://img.example/new.jpg')
        self.check(self.snapshot([(b'abcdefghijk',b'First',0,urls,1)]))
        lib.rdapp_store_close(self.db)
        self.db=P()
        self.check(lib.rdapp_store_open(os.fsencode(self.path/'db.sqlite'),C.byref(self.db)))
        self.assertEqual(self.thumbnails(),[(0,0,urls[0].decode())])
        self.assertEqual(self.rows(2),jobs)

    def test_rejects_path_injection_and_future_schema(self):
        self.assertEqual(lib.rdapp_store_playlist(self.db,b'../../escape',b'Bad',None),0)
        future=self.path/'future.sqlite'
        with sqlite3.connect(future) as db: db.execute('PRAGMA user_version=99')
        other=P()
        self.assertEqual(lib.rdapp_store_open(os.fsencode(future),C.byref(other)),0)
        self.assertFalse(other.value)

    def test_version_three_migration_preserves_thumbnail_urls(self):
        urls=(S*1)(b'https://img.example/existing.jpg')
        self.check(self.snapshot([(b'abcdefghijk',b'Existing',0,urls,1)]))
        self.check(lib.rdapp_store_enqueue(self.db,self.key,None,b'18'))
        jobs=self.rows(2)
        lib.rdapp_store_close(self.db); self.db=P()
        with sqlite3.connect(self.path/'db.sqlite') as db:
            for field in METADATA_FIELDS:
                db.execute('ALTER TABLE entries DROP COLUMN '+field)
                db.execute('ALTER TABLE jobs DROP COLUMN '+field)
            db.execute('PRAGMA user_version=3')
        self.check(lib.rdapp_store_open(os.fsencode(self.path/'db.sqlite'),C.byref(self.db)))
        self.assertEqual(self.thumbnails(),[(0,0,urls[0].decode())])
        self.assertTrue(all(self.rows(1)[0][f]=='' for f in METADATA_FIELDS))
        self.assertEqual(self.rows(2),jobs)

if __name__=='__main__': unittest.main()
