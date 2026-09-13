#if !defined(__APPLE__)
#define _POSIX_C_SOURCE 200809L
#endif
#include "rdapp_store.h"
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>
#include <limits.h>

struct rdapp_store { sqlite3 *db; char error[512]; };
static int failure(rdapp_store *s, const char *message) {
  snprintf(s->error, sizeof(s->error), "%s", message); return 0;
}
static int sql(rdapp_store *s, const char *q) {
  if (sqlite3_exec(s->db, q, NULL, NULL, NULL) != SQLITE_OK)
    return failure(s, sqlite3_errmsg(s->db));
  return 1;
}
static sqlite3_stmt *prepare(rdapp_store *s, const char *q) {
  sqlite3_stmt *p = NULL;
  if (sqlite3_prepare_v2(s->db, q, -1, &p, NULL) != SQLITE_OK)
    failure(s, sqlite3_errmsg(s->db));
  return p;
}
static int done(rdapp_store *s, sqlite3_stmt *p) {
  int ok = p && sqlite3_step(p) == SQLITE_DONE;
  if (!ok) failure(s, sqlite3_errmsg(s->db));
  sqlite3_finalize(p); return ok;
}
static void bind_text(sqlite3_stmt *p, int n, const char *v) {
  sqlite3_bind_text(p, n, v ? v : "", -1, SQLITE_TRANSIENT);
}
const char *rdapp_store_error(rdapp_store *s) { return s ? s->error : "Cannot open library database"; }
void rdapp_store_close(rdapp_store *s) { if (s) { sqlite3_close(s->db); free(s); } }
int rdapp_store_open(const char *path, rdapp_store **out) {
  rdapp_store *s = calloc(1, sizeof(*s));
  sqlite3_stmt *p; int version;
  *out = NULL;
  if (!s) return 0;
  if (sqlite3_open(path, &s->db) != SQLITE_OK) { rdapp_store_close(s); return 0; }
  sqlite3_busy_timeout(s->db, 5000);
  p = prepare(s, "PRAGMA user_version");
  if (!p || sqlite3_step(p) != SQLITE_ROW || sqlite3_column_int(p,0) > 2) {
    sqlite3_finalize(p); rdapp_store_close(s); return 0;
  }
  version=sqlite3_column_int(p,0);
  sqlite3_finalize(p);
  if (!sql(s, "PRAGMA foreign_keys=ON; BEGIN IMMEDIATE;"
    "CREATE TABLE IF NOT EXISTS playlists (id INTEGER PRIMARY KEY, service_id TEXT NOT NULL UNIQUE,"
    " title TEXT NOT NULL, directory TEXT NOT NULL, synced_at INTEGER);"
    "CREATE TABLE IF NOT EXISTS videos (id TEXT PRIMARY KEY, title TEXT NOT NULL);"
    "CREATE TABLE IF NOT EXISTS entries (playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,"
    " position INTEGER NOT NULL, video_id TEXT NOT NULL REFERENCES videos(id), title TEXT NOT NULL,"
    " PRIMARY KEY(playlist_id,position));"
    "CREATE TABLE IF NOT EXISTS jobs (id INTEGER PRIMARY KEY AUTOINCREMENT,"
    " playlist_id INTEGER NOT NULL REFERENCES playlists(id), video_id TEXT NOT NULL REFERENCES videos(id),"
    " title TEXT NOT NULL, format TEXT NOT NULL, actual_format TEXT NOT NULL DEFAULT '',"
    " path TEXT NOT NULL DEFAULT '', state TEXT NOT NULL DEFAULT 'queued', error TEXT NOT NULL DEFAULT '',"
    " UNIQUE(playlist_id,video_id,format));"
    "CREATE INDEX IF NOT EXISTS jobs_state ON jobs(state,id);"
    "UPDATE jobs SET state='interrupted', error='Interrupted. Retry restarts the download.' WHERE state='running';")) {
    rdapp_store_close(s); return 0;
  }
  if ((version<2 && !sql(s,"ALTER TABLE playlists ADD COLUMN source TEXT NOT NULL DEFAULT 'added';")) ||
      !sql(s,"PRAGMA user_version=2; COMMIT;")) { rdapp_store_close(s); return 0; }
  *out = s; return 1;
}
void rdapp_filename(const char *text, char *out, size_t cap) {
  size_t n = 0, i = 0;
  if (!cap) return;
  /* Preserve whole UTF-8 codepoints; filenames cannot inject paths or M3U lines. */
  while (text && text[i] && n + 1 < cap && n < 100) {
    unsigned char c = (unsigned char)text[i];
    size_t len = c < 128 ? 1 : (c < 224 ? 2 : (c < 240 ? 3 : 4));
    size_t j;
    if (n + len >= cap || n + len > 100) break;
    for (j=1; j<len && text[i+j]; ++j) {}
    if (j != len) break;
    if (c < 32 || c == 127 || strchr("/\\:*?\"<>|", c)) { out[n++] = '_'; ++i; }
    else { memcpy(out+n,text+i,len); n+=len; i+=len; }
  }
  while (n && (out[n-1] == ' ' || out[n-1] == '.')) --n;
  if (!n && cap > 1) out[n++] = '_';
  out[n] = 0;
}
int rdapp_make_directory(const char *path) {
  char buffer[PATH_MAX]; size_t i; struct stat st;
  if (!path || path[0]!='/' || strlen(path)>=sizeof(buffer)) return 0;
  strcpy(buffer,path);
  for (i=1;;++i) {
    if (buffer[i]=='/' || buffer[i]==0) {
      char saved=buffer[i]; buffer[i]=0;
      if (mkdir(buffer,0700) && errno != EEXIST) return 0;
      if (stat(buffer,&st) || !S_ISDIR(st.st_mode)) return 0;
      buffer[i]=saved; if (!saved) break;
    }
  }
  return 1;
}
static int each(rdapp_store *s, sqlite3_stmt *p, rdapp_row_callback cb, void *ctx) {
  int rc, n, i; const char *values[16], *names[16];
  if (!p) return 0;
  n=sqlite3_column_count(p);
  if (n>16) { sqlite3_finalize(p); return failure(s,"Too many result columns"); }
  while ((rc=sqlite3_step(p)) == SQLITE_ROW) {
    for(i=0;i<n;++i) { names[i]=sqlite3_column_name(p,i); values[i]=(const char *)sqlite3_column_text(p,i); }
    if (cb && !cb(ctx,n,names,values)) { sqlite3_finalize(p); return failure(s,"Result processing failed"); }
  }
  if(rc!=SQLITE_DONE) failure(s,sqlite3_errmsg(s->db));
  sqlite3_finalize(p); return rc==SQLITE_DONE;
}
int rdapp_store_list(rdapp_store *s, rdapp_query kind, int64_t key, rdapp_row_callback cb, void *ctx) {
  const char *q;
  sqlite3_stmt *p;
  switch(kind) {
    case RDAPP_PLAYLISTS: q="SELECT p.*, (SELECT count(*) FROM entries e WHERE e.playlist_id=p.id) AS count FROM playlists p ORDER BY title COLLATE NOCASE"; break;
    case RDAPP_ENTRIES: q="SELECT e.*, coalesce((SELECT j.state FROM jobs j WHERE j.playlist_id=e.playlist_id AND j.video_id=e.video_id ORDER BY (j.state='complete') DESC,j.id DESC LIMIT 1),'not downloaded') AS state, coalesce((SELECT j.actual_format FROM jobs j WHERE j.playlist_id=e.playlist_id AND j.video_id=e.video_id AND j.state='complete' ORDER BY j.id DESC LIMIT 1),'') AS quality FROM entries e WHERE e.playlist_id=? ORDER BY position"; break;
    case RDAPP_DOWNLOADS: q="SELECT j.*, p.title AS playlist_title FROM jobs j JOIN playlists p ON p.id=j.playlist_id WHERE j.state='complete' AND (?=0 OR j.playlist_id=?) ORDER BY j.id DESC"; break;
    default: q="SELECT j.*, p.title AS playlist_title FROM jobs j JOIN playlists p ON p.id=j.playlist_id WHERE (?=0 OR j.playlist_id=?) ORDER BY j.id DESC"; break;
  }
  p=prepare(s,q); if(!p) return 0;
  sqlite3_bind_int64(p,1,key); sqlite3_bind_int64(p,2,key);
  return each(s,p,cb,ctx);
}
int rdapp_store_playlist(rdapp_store *s,const char *id,const char *title,int64_t *key) {
  char safe[128], directory[256]; sqlite3_stmt *p; int ok;
  /* Service IDs become path components; reject every non-identifier byte. */
  if(!id || !*id || strspn(id,"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")!=strlen(id) || strlen(id)>100)
    return failure(s,"Invalid playlist ID");
  rdapp_filename(title,safe,sizeof(safe));
  snprintf(directory,sizeof(directory),"Playlists/%s [%s]",safe,id);
  p=prepare(s,"INSERT OR IGNORE INTO playlists(service_id,title,directory) VALUES(?,?,?)");
  if(!p) return 0;
  bind_text(p,1,id); bind_text(p,2,title); bind_text(p,3,directory); if(!done(s,p)) return 0;
  p=prepare(s,"UPDATE playlists SET title=? WHERE service_id=?"); if(!p) return 0;
  bind_text(p,1,title); bind_text(p,2,id); if(!done(s,p)) return 0;
  p=prepare(s,"SELECT id FROM playlists WHERE service_id=?"); if(!p) return 0;
  bind_text(p,1,id); ok=sqlite3_step(p)==SQLITE_ROW;
  if(ok && key) *key=sqlite3_column_int64(p,0);
  sqlite3_finalize(p); return ok;
}
/* Discovery promotes an existing manual entry without changing its key,
   directory, membership, or downloads. Ordinary sync never demotes it. */
int rdapp_store_discovered_playlist(rdapp_store *s,const char *id,const char *title) {
  sqlite3_stmt *p;
  if(!sql(s,"BEGIN IMMEDIATE")) return 0;
  if(!rdapp_store_playlist(s,id,title,NULL)) goto rollback;
  p=prepare(s,"UPDATE playlists SET source='account' WHERE service_id=?");
  if(!p) goto rollback;
  bind_text(p,1,id); if(!done(s,p)) goto rollback;
  if(sql(s,"COMMIT")) return 1;
rollback:
  sql(s,"ROLLBACK"); return 0;
}
int rdapp_store_snapshot(rdapp_store *s,const char *id,const char *title,const rdapp_entry *entries,size_t count,int64_t *key) {
  int64_t k; size_t i; sqlite3_stmt *p;
  if(!sql(s,"BEGIN IMMEDIATE")) return 0;
  if(!rdapp_store_playlist(s,id,title,&k)) goto rollback;
  p=prepare(s,"DELETE FROM entries WHERE playlist_id=?"); if(!p) goto rollback;
  sqlite3_bind_int64(p,1,k); if(!done(s,p)) goto rollback;
  for(i=0;i<count;++i) {
    if(!entries[i].video_id || strlen(entries[i].video_id)!=11 || strspn(entries[i].video_id,"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")!=11) { failure(s,"Invalid video ID in playlist"); goto rollback; }
    p=prepare(s,"INSERT OR REPLACE INTO videos(id,title) VALUES(?,?)"); if(!p) goto rollback;
    bind_text(p,1,entries[i].video_id); bind_text(p,2,entries[i].title); if(!done(s,p)) goto rollback;
    p=prepare(s,"INSERT INTO entries(playlist_id,position,video_id,title) VALUES(?,?,?,?)"); if(!p) goto rollback;
    sqlite3_bind_int64(p,1,k); sqlite3_bind_int(p,2,entries[i].position);
    bind_text(p,3,entries[i].video_id); bind_text(p,4,entries[i].title); if(!done(s,p)) goto rollback;
  }
  p=prepare(s,"UPDATE playlists SET synced_at=strftime('%s','now') WHERE id=?"); if(!p) goto rollback;
  sqlite3_bind_int64(p,1,k); if(!done(s,p)) goto rollback;
  if(!sql(s,"COMMIT")) goto rollback;
  if(key) *key=k;
  return 1;
rollback:
  sqlite3_exec(s->db,"ROLLBACK",NULL,NULL,NULL); return 0;
}
int rdapp_store_enqueue(rdapp_store *s,int64_t key,const char *video,const char *format) {
  sqlite3_stmt *p=prepare(s,"INSERT OR IGNORE INTO jobs(playlist_id,video_id,title,format) SELECT playlist_id,video_id,title,? FROM entries WHERE playlist_id=? AND (?='' OR video_id=?) ORDER BY position");
  if(!p) return 0;
  bind_text(p,1,format); sqlite3_bind_int64(p,2,key); bind_text(p,3,video); bind_text(p,4,video); return done(s,p);
}
int rdapp_store_claim(rdapp_store *s,rdapp_row_callback cb,void *ctx) {
  sqlite3_stmt *p; int64_t id; int rc; char safe[128], file[256];
  if(!sql(s,"BEGIN IMMEDIATE")) return 0;
  p=prepare(s,"SELECT id,title FROM jobs WHERE state='queued' ORDER BY id LIMIT 1");
  if(!p) goto fail;
  rc=sqlite3_step(p);
  if(rc==SQLITE_DONE) { sqlite3_finalize(p); return sql(s,"COMMIT"); }
  if(rc!=SQLITE_ROW) { failure(s,sqlite3_errmsg(s->db)); sqlite3_finalize(p); goto fail; }
  id=sqlite3_column_int64(p,0); rdapp_filename((const char *)sqlite3_column_text(p,1),safe,sizeof(safe));
  snprintf(file,sizeof(file),"%s [%lld].mp4",safe,(long long)id); sqlite3_finalize(p);
  p=prepare(s,"UPDATE jobs SET state='running', error='', path=(SELECT directory FROM playlists WHERE id=playlist_id)||'/'||? WHERE id=?");
  if(!p) goto fail;
  bind_text(p,1,file); sqlite3_bind_int64(p,2,id); if(!done(s,p)) goto fail;
  p=prepare(s,"SELECT * FROM jobs WHERE id=?"); if(!p) goto fail;
  sqlite3_bind_int64(p,1,id); if(!each(s,p,cb,ctx)) goto fail;
  if(sql(s,"COMMIT")) return 1;
fail: sqlite3_exec(s->db,"ROLLBACK",NULL,NULL,NULL); return 0;
}
int rdapp_store_finish(rdapp_store *s,int64_t key,const char *state,const char *format,const char *message) {
  sqlite3_stmt *p=prepare(s,"UPDATE jobs SET state=?,actual_format=?,error=? WHERE id=?");
  if(!p) return 0;
  bind_text(p,1,state); bind_text(p,2,format); bind_text(p,3,message); sqlite3_bind_int64(p,4,key); return done(s,p);
}
static int by_id(rdapp_store *s,const char *q,int64_t key) {
  sqlite3_stmt *p=prepare(s,q); if(!p) return 0; sqlite3_bind_int64(p,1,key); return done(s,p);
}
int rdapp_store_retry(rdapp_store *s,int64_t key) {
  return by_id(s,"UPDATE jobs SET state='queued',error='' WHERE id=? AND state IN ('failed','cancelled','interrupted','removed')",key);
}
int rdapp_store_cancel(rdapp_store *s,int64_t key) {
  return by_id(s,"UPDATE jobs SET state='cancelled',error='Cancelled' WHERE id=? AND state='queued'",key);
}
int rdapp_store_forget_file(rdapp_store *s,int64_t key) {
  return by_id(s,"UPDATE jobs SET state='removed',actual_format='',error='' WHERE id=? AND state<>'running'",key);
}
int rdapp_store_remove_playlist(rdapp_store *s,int64_t key,const char *root) {
  sqlite3_stmt *p=prepare(s,"SELECT count(*) FROM jobs WHERE playlist_id=? AND state IN ('running','queued','complete')"); int blocked;
  if(!p) return 0;
  sqlite3_bind_int64(p,1,key); blocked=sqlite3_step(p)!=SQLITE_ROW || sqlite3_column_int(p,0)!=0; sqlite3_finalize(p);
  if(blocked) return failure(s,"Cancel queued jobs and remove downloaded files before removing this playlist.");
  /* Failed/cancelled jobs can retain mux inputs. Remove those before deleting
     their ledger rows so no staging files become orphaned. */
  p=prepare(s,"SELECT id FROM jobs WHERE playlist_id=?");
  if(!p) return 0;
  sqlite3_bind_int64(p,1,key);
  {
    int rc;
    while((rc=sqlite3_step(p))==SQLITE_ROW) {
      if(!rdapp_store_remove_file(s,sqlite3_column_int64(p,0),root)) { sqlite3_finalize(p); return 0; }
    }
    sqlite3_finalize(p); if(rc!=SQLITE_DONE) return failure(s,sqlite3_errmsg(s->db));
  }
  if(!sql(s,"BEGIN IMMEDIATE")) return 0;
  if(by_id(s,"DELETE FROM jobs WHERE playlist_id=?",key) && by_id(s,"DELETE FROM playlists WHERE id=?",key) && sql(s,"COMMIT")) return 1;
  sqlite3_exec(s->db,"ROLLBACK",NULL,NULL,NULL); return 0;
}
int rdapp_store_export(rdapp_store *s,int64_t key,const char *root) {
  sqlite3_stmt *p; char dir[PATH_MAX],path[PATH_MAX],temp[PATH_MAX]; FILE *f; int fd,rc; struct stat st;
  p=prepare(s,"SELECT directory FROM playlists WHERE id=?"); if(!p) return 0;
  sqlite3_bind_int64(p,1,key);
  if(sqlite3_step(p)!=SQLITE_ROW) { sqlite3_finalize(p); return failure(s,"Playlist does not exist"); }
  rc=snprintf(dir,sizeof(dir),"%s/%s",root,sqlite3_column_text(p,0)); sqlite3_finalize(p);
  if(rc<0 || (size_t)rc>=sizeof(dir) || !rdapp_make_directory(dir)) return failure(s,"Cannot create playlist directory");
  if(snprintf(path,sizeof(path),"%s/Playlist.m3u8",dir)>=(int)sizeof(path) || snprintf(temp,sizeof(temp),"%s/.playlist-XXXXXX",dir)>=(int)sizeof(temp)) return failure(s,"Playlist path is too long");
  fd=mkstemp(temp); if(fd<0) return failure(s,strerror(errno));
  f=fdopen(fd,"w"); if(!f) { close(fd); unlink(temp); return failure(s,strerror(errno)); }
  fputs("#EXTM3U\n",f);
  p=prepare(s,"SELECT j.path FROM entries e JOIN jobs j ON j.id=(SELECT j2.id FROM jobs j2 WHERE j2.playlist_id=e.playlist_id AND j2.video_id=e.video_id AND j2.state='complete' ORDER BY j2.id DESC LIMIT 1) WHERE e.playlist_id=? ORDER BY e.position");
  if(!p) { fclose(f); unlink(temp); return 0; }
  sqlite3_bind_int64(p,1,key);
  while((rc=sqlite3_step(p))==SQLITE_ROW) {
    char full[PATH_MAX]; const char *relative=(const char *)sqlite3_column_text(p,0); const char *base=strrchr(relative,'/');
    if(snprintf(full,sizeof(full),"%s/%s",root,relative)<(int)sizeof(full) && lstat(full,&st)==0 && S_ISREG(st.st_mode))
      fprintf(f,"./%s\n",base?base+1:relative);
  }
  sqlite3_finalize(p);
  { int ok=rc==SQLITE_DONE && !ferror(f); if(fflush(f) || fsync(fd)) ok=0; if(fclose(f)) ok=0;
    if(!ok || rename(temp,path)) { unlink(temp); return failure(s,"Could not write VLC playlist"); }
  }
  return 1;
}

int rdapp_store_reconcile(rdapp_store *s,const char *root) {
  sqlite3_stmt *p=prepare(s,"SELECT id,path,state,actual_format FROM jobs WHERE state IN ('complete','interrupted')");
  int rc,ok=1; struct stat st;
  if(!p) return 0;
  while((rc=sqlite3_step(p))==SQLITE_ROW) {
    char path[PATH_MAX];
    int64_t key=sqlite3_column_int64(p,0);
    const char *relative=(const char *)sqlite3_column_text(p,1);
    const char *state=(const char *)sqlite3_column_text(p,2);
    const char *format=(const char *)sqlite3_column_text(p,3);
    int exists=snprintf(path,sizeof(path),"%s/%s",root,relative)<(int)sizeof(path) &&
      lstat(path,&st)==0 && S_ISREG(st.st_mode) && st.st_size>0;
    if(!strcmp(state,"complete") && !exists)
      ok=rdapp_store_finish(s,key,"removed",format,"File is missing. Retry to download it again.");
    else if(!strcmp(state,"interrupted") && exists && format[0])
      ok=rdapp_store_finish(s,key,"complete",format,"Recovered completed download after interruption.");
    if(!ok) break;
  }
  sqlite3_finalize(p);
  if(!ok || rc!=SQLITE_DONE) return 0;
  p=prepare(s,"SELECT id FROM playlists");
  if(!p) return 0;
  while((rc=sqlite3_step(p))==SQLITE_ROW) {
    if(!rdapp_store_export(s,sqlite3_column_int64(p,0),root)) { ok=0; break; }
  }
  sqlite3_finalize(p); return ok && rc==SQLITE_DONE;
}
int rdapp_store_remove_file(rdapp_store *s,int64_t key,const char *root) {
  sqlite3_stmt *p=prepare(s,"SELECT path,playlist_id,state FROM jobs WHERE id=?");
  char path[PATH_MAX],staging[PATH_MAX]; int64_t playlist; size_t i; int n;
  const char *files[]={"video.mp4","video.mp4.part","video.mp4.video.mp4","video.mp4.video.mp4.part","video.mp4.audio.m4a","video.mp4.audio.m4a.part"};
  if(!p) return 0;
  sqlite3_bind_int64(p,1,key);
  if(sqlite3_step(p)!=SQLITE_ROW) { sqlite3_finalize(p); return failure(s,"Job does not exist"); }
  if(!strcmp((const char *)sqlite3_column_text(p,2),"running")) { sqlite3_finalize(p); return failure(s,"Cancel the active download before removing it"); }
  playlist=sqlite3_column_int64(p,1);
  n=snprintf(path,sizeof(path),"%s/%s",root,sqlite3_column_text(p,0));
  if(!sqlite3_column_bytes(p,0)) path[0]=0;
  sqlite3_finalize(p);
  if(n<0 || (size_t)n>=sizeof(path)) return failure(s,"Download path is too long");
  if(path[0] && unlink(path) && errno!=ENOENT) return failure(s,strerror(errno));
  if(snprintf(staging,sizeof(staging),"%s/.staging/%lld",root,(long long)key)>=(int)sizeof(staging)) return failure(s,"Staging path is too long");
  for(i=0;i<sizeof(files)/sizeof(files[0]);++i) {
    if(snprintf(path,sizeof(path),"%s/%s",staging,files[i])>=(int)sizeof(path)) return failure(s,"Staging path is too long");
    if(unlink(path) && errno!=ENOENT) return failure(s,strerror(errno));
  }
  if(rmdir(staging) && errno!=ENOENT) return failure(s,strerror(errno));
  return rdapp_store_forget_file(s,key) && rdapp_store_export(s,playlist,root);
}
