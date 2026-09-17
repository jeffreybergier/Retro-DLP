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
/* Jobs retain the first matching occurrence's text metadata after membership
   disappears. Matching rows are refreshed atomically with a playlist sync. */
#define RDAPP_METADATA_COLUMNS "channel,channel_id,view_count_text,published_text,description_snippet,duration,view_count"
#define RDAPP_COPY_FIELD(field) #field "=(SELECT e." #field " FROM entries e WHERE e.playlist_id=jobs.playlist_id AND e.video_id=jobs.video_id ORDER BY e.position LIMIT 1)"
static int refresh_job_metadata(rdapp_store *s,int64_t key) {
  char query[2048]; sqlite3_stmt *p;
  snprintf(query,sizeof(query),"UPDATE jobs SET "
    RDAPP_COPY_FIELD(channel) "," RDAPP_COPY_FIELD(channel_id) ","
    RDAPP_COPY_FIELD(view_count_text) "," RDAPP_COPY_FIELD(published_text) ","
    RDAPP_COPY_FIELD(description_snippet) "," RDAPP_COPY_FIELD(duration) "," RDAPP_COPY_FIELD(view_count)
    " WHERE %sEXISTS(SELECT 1 FROM entries e WHERE e.playlist_id=jobs.playlist_id AND e.video_id=jobs.video_id)",key?"playlist_id=?1 AND ":"");
  p=prepare(s,query); if(!p) return 0;
  if(key) sqlite3_bind_int64(p,1,key);
  return done(s,p);
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
  if (!p || sqlite3_step(p) != SQLITE_ROW || sqlite3_column_int(p,0) > 5) {
    sqlite3_finalize(p); rdapp_store_close(s); return 0;
  }
  version=sqlite3_column_int(p,0);
  sqlite3_finalize(p);
  if (!sql(s, "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; BEGIN IMMEDIATE;"
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
      (version<4 && !sql(s,"ALTER TABLE entries ADD COLUMN channel TEXT;"
        "ALTER TABLE entries ADD COLUMN channel_id TEXT;"
        "ALTER TABLE entries ADD COLUMN view_count_text TEXT;"
        "ALTER TABLE entries ADD COLUMN published_text TEXT;"
        "ALTER TABLE entries ADD COLUMN description_snippet TEXT;"
        "ALTER TABLE entries ADD COLUMN duration INTEGER;"
        "ALTER TABLE entries ADD COLUMN view_count INTEGER;")) ||
      (version<5 && !sql(s,"ALTER TABLE jobs ADD COLUMN channel TEXT;"
        "ALTER TABLE jobs ADD COLUMN channel_id TEXT;"
        "ALTER TABLE jobs ADD COLUMN view_count_text TEXT;"
        "ALTER TABLE jobs ADD COLUMN published_text TEXT;"
        "ALTER TABLE jobs ADD COLUMN description_snippet TEXT;"
        "ALTER TABLE jobs ADD COLUMN duration INTEGER;"
        "ALTER TABLE jobs ADD COLUMN view_count INTEGER;")) ||
      !sql(s,"CREATE TABLE IF NOT EXISTS entry_thumbnails (playlist_id INTEGER NOT NULL,"
        " position INTEGER NOT NULL, thumbnail_index INTEGER NOT NULL, url TEXT NOT NULL,"
        " PRIMARY KEY(playlist_id,position,thumbnail_index),"
        " FOREIGN KEY(playlist_id,position) REFERENCES entries(playlist_id,position) ON DELETE CASCADE);"
        "CREATE INDEX IF NOT EXISTS playlists_title ON playlists(title COLLATE NOCASE,id);"
        "CREATE INDEX IF NOT EXISTS playlists_source_title ON playlists(source,title COLLATE NOCASE,id);"
        "CREATE INDEX IF NOT EXISTS jobs_playlist_id ON jobs(playlist_id,id);"
        "CREATE INDEX IF NOT EXISTS jobs_queue_visible ON jobs(id) WHERE state<>'removed' OR error<>'';"
        "CREATE INDEX IF NOT EXISTS jobs_video_id ON jobs(playlist_id,video_id,id);"
        "CREATE INDEX IF NOT EXISTS jobs_playlist_state ON jobs(playlist_id,state,id);"
        "CREATE INDEX IF NOT EXISTS entries_video_position ON entries(playlist_id,video_id,position);")) { rdapp_store_close(s); return 0; }
  if((version<5 && !refresh_job_metadata(s,0)) || !sql(s,"PRAGMA user_version=5; COMMIT;")) {
    rdapp_store_close(s); return 0;
  }
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
  int rc, n, i; const char *values[32], *names[32];
  if (!p) return 0;
  n=sqlite3_column_count(p);
  if (n>32) { sqlite3_finalize(p); return failure(s,"Too many result columns"); }
  while ((rc=sqlite3_step(p)) == SQLITE_ROW) {
    for(i=0;i<n;++i) { names[i]=sqlite3_column_name(p,i); values[i]=(const char *)sqlite3_column_text(p,i); }
    if (cb && !cb(ctx,n,names,values)) { sqlite3_finalize(p); return failure(s,"Result processing failed"); }
  }
  if(rc!=SQLITE_DONE) failure(s,sqlite3_errmsg(s->db));
  sqlite3_finalize(p); return rc==SQLITE_DONE;
}
int rdapp_store_open_reader(const char *path, rdapp_store **out) {
  rdapp_store *s=calloc(1,sizeof(*s)); *out=NULL;
  if(!s) return 0;
  if(sqlite3_open_v2(path,&s->db,SQLITE_OPEN_READONLY,NULL)!=SQLITE_OK ||
     !sql(s,"BEGIN")) { rdapp_store_close(s); return 0; }
  *out=s; return 1;
}
/* Keep counting free of row projection, sorting and correlated metadata queries. */
static int query_parts(rdapp_query kind,int64_t key,const char *format,
                       const char **fields,const char **from,const char **order) {
  *fields="j.*, p.title AS playlist_title";
  *order="j.id DESC";
  switch(kind) {
    case RDAPP_ADDED_IDS: case RDAPP_ACCOUNT_IDS:
      *fields="p.id";
      *from=kind==RDAPP_ADDED_IDS?"playlists p WHERE p.source='added'":"playlists p WHERE p.source='account'";
      *order="p.title COLLATE NOCASE,p.id"; break;
    case RDAPP_PLAYLISTS: case RDAPP_ADDED_PLAYLISTS: case RDAPP_ACCOUNT_PLAYLISTS: case RDAPP_PLAYLIST: case RDAPP_PLAYLIST_INPUT:
      *fields="p.*, (SELECT count(*) FROM entries e WHERE e.playlist_id=p.id) AS count";
      *from=kind==RDAPP_ADDED_PLAYLISTS?"playlists p WHERE p.source='added'":
        (kind==RDAPP_ACCOUNT_PLAYLISTS?"playlists p WHERE p.source='account'":
        (kind==RDAPP_PLAYLIST?"playlists p WHERE p.id=?1":(kind==RDAPP_PLAYLIST_INPUT?"playlists p WHERE p.service_id=?2":"playlists p WHERE 1")));
      *order="p.title COLLATE NOCASE,p.id"; break;
    case RDAPP_MISSING: case RDAPP_DOWNLOAD_CANDIDATES:
      *fields="e.*,j.id AS job_id,j.state,j.path";
      *from=kind==RDAPP_MISSING?
        "entries e LEFT JOIN jobs j ON j.playlist_id=e.playlist_id AND j.video_id=e.video_id AND j.format=?3 WHERE e.playlist_id=?1 AND (j.id IS NULL OR j.state='removed') AND e.position=(SELECT min(e2.position) FROM entries e2 WHERE e2.playlist_id=e.playlist_id AND e2.video_id=e.video_id)":
        "entries e LEFT JOIN jobs j ON j.playlist_id=e.playlist_id AND j.video_id=e.video_id AND j.format=?3 WHERE e.playlist_id=?1 AND (j.id IS NULL OR j.state IN ('removed','complete')) AND e.position=(SELECT min(e2.position) FROM entries e2 WHERE e2.playlist_id=e.playlist_id AND e2.video_id=e.video_id)";
      *order="e.position"; break;
    case RDAPP_VIDEO_ENTRIES:
      *fields="e.*"; *from="entries e WHERE e.playlist_id=?1 AND e.video_id=?2"; *order="e.position"; break;
    case RDAPP_ENTRIES:
      *fields="e.*"; *from="entries e WHERE e.playlist_id=?1"; *order="e.position"; break;
    case RDAPP_DOWNLOADS:
      *from=key?"jobs j JOIN playlists p ON p.id=j.playlist_id WHERE j.state='complete' AND j.playlist_id=?1":
        "jobs j JOIN playlists p ON p.id=j.playlist_id WHERE j.state='complete'"; break;
    case RDAPP_QUEUE:
      *from="jobs j JOIN playlists p ON p.id=j.playlist_id WHERE (j.state<>'removed' OR j.error<>'')";
      *order="j.id DESC"; break;
    case RDAPP_PENDING:
      *from="jobs j JOIN playlists p ON p.id=j.playlist_id WHERE j.state='queued'"; break;
    case RDAPP_BLOCKING_JOBS:
      *from="jobs j JOIN playlists p ON p.id=j.playlist_id WHERE j.playlist_id=?1 AND j.state IN ('queued','running','complete')"; break;
    case RDAPP_VIDEO_JOBS:
      *from=format?"jobs j JOIN playlists p ON p.id=j.playlist_id WHERE j.playlist_id=?1 AND j.video_id=?2 AND j.format=?3":
        "jobs j JOIN playlists p ON p.id=j.playlist_id WHERE j.playlist_id=?1 AND j.video_id=?2"; break;
    case RDAPP_JOB:
      *from="jobs j JOIN playlists p ON p.id=j.playlist_id WHERE j.id=?1"; break;
    case RDAPP_JOBS:
      *from=key?"jobs j JOIN playlists p ON p.id=j.playlist_id WHERE j.playlist_id=?1":
        "jobs j JOIN playlists p ON p.id=j.playlist_id WHERE 1"; break;
    default: return 0;
  }
  return 1;
}
static sqlite3_stmt *list_statement(rdapp_store *s,rdapp_query kind,int64_t key,
                                   const char *video,const char *format,int count) {
  const char *fields,*from,*order; char query[2048]; sqlite3_stmt *p;
  if(!query_parts(kind,key,format,&fields,&from,&order)) { failure(s,"Invalid list query"); return NULL; }
  if(count && !strncmp(from,"jobs j JOIN playlists p ON p.id=j.playlist_id WHERE ",strlen("jobs j JOIN playlists p ON p.id=j.playlist_id WHERE ")))
    snprintf(query,sizeof(query),"SELECT count(*) FROM jobs j WHERE %s",from+strlen("jobs j JOIN playlists p ON p.id=j.playlist_id WHERE "));
  else if(count) snprintf(query,sizeof(query),"SELECT count(*) FROM %s",from);
  else snprintf(query,sizeof(query),"SELECT %s FROM %s ORDER BY %s LIMIT ?4 OFFSET ?5",fields,from,order);
  p=prepare(s,query);
  if(p) { sqlite3_bind_int64(p,1,key); bind_text(p,2,video); bind_text(p,3,format); }
  return p;
}
int rdapp_store_count(rdapp_store *s,rdapp_query kind,int64_t key,const char *video,const char *format,int64_t *count) {
  sqlite3_stmt *p=list_statement(s,kind,key,video,format,1); int ok;
  *count=0; if(!p) return 0;
  ok=sqlite3_step(p)==SQLITE_ROW;
  if(ok) *count=sqlite3_column_int64(p,0); else failure(s,sqlite3_errmsg(s->db));
  sqlite3_finalize(p); return ok;
}
int rdapp_store_page(rdapp_store *s,rdapp_query kind,int64_t key,const char *video,const char *format,
                     int64_t offset,int64_t limit,rdapp_row_callback cb,void *ctx) {
  sqlite3_stmt *p;
  if(offset<0 || limit< -1) return failure(s,"Invalid page range");
  p=list_statement(s,kind,key,video,format,0); if(!p) return 0;
  sqlite3_bind_int64(p,4,limit); sqlite3_bind_int64(p,5,offset); return each(s,p,cb,ctx);
}
int rdapp_store_after(rdapp_store *s,rdapp_query kind,int64_t key,const char *video,const char *format,
                      int64_t identity,rdapp_row_callback cb,void *ctx) {
  const char *fields,*from,*order; char query[2048]; sqlite3_stmt *p;
  if(!query_parts(kind,key,format,&fields,&from,&order) || kind==RDAPP_PLAYLISTS ||
     kind==RDAPP_ADDED_PLAYLISTS || kind==RDAPP_ACCOUNT_PLAYLISTS || kind==RDAPP_PLAYLIST || kind==RDAPP_PLAYLIST_INPUT ||
     kind==RDAPP_ADDED_IDS || kind==RDAPP_ACCOUNT_IDS)
    return failure(s,"Invalid seek query");
  snprintf(query,sizeof(query),"SELECT %s FROM %s AND %s%s?4 ORDER BY %s LIMIT 1",fields,from,
    (kind==RDAPP_ENTRIES || kind==RDAPP_VIDEO_ENTRIES || kind==RDAPP_MISSING || kind==RDAPP_DOWNLOAD_CANDIDATES)?"e.position":"j.id",
    (kind==RDAPP_ENTRIES || kind==RDAPP_VIDEO_ENTRIES || kind==RDAPP_MISSING || kind==RDAPP_DOWNLOAD_CANDIDATES)?">":"<",order);
  p=prepare(s,query); if(!p) return 0;
  sqlite3_bind_int64(p,1,key); bind_text(p,2,video); bind_text(p,3,format); sqlite3_bind_int64(p,4,identity);
  return each(s,p,cb,ctx);
}
int rdapp_store_list(rdapp_store *s,rdapp_query kind,int64_t key,rdapp_row_callback cb,void *ctx) {
  if(kind==RDAPP_ENTRIES) {
    sqlite3_stmt *p=prepare(s,"SELECT e.*, coalesce((SELECT j.state FROM jobs j WHERE j.playlist_id=e.playlist_id AND j.video_id=e.video_id ORDER BY (j.state='complete') DESC,j.id DESC LIMIT 1),'not downloaded') AS state, coalesce((SELECT j.actual_format FROM jobs j WHERE j.playlist_id=e.playlist_id AND j.video_id=e.video_id AND j.state='complete' ORDER BY j.id DESC LIMIT 1),'') AS quality FROM entries e WHERE e.playlist_id=? ORDER BY position");
    if(!p) return 0;
    sqlite3_bind_int64(p,1,key); return each(s,p,cb,ctx);
  }
  return rdapp_store_page(s,kind,key,NULL,NULL,0,-1,cb,ctx);
}
int rdapp_store_index(rdapp_store *s,rdapp_query kind,int64_t key,int64_t identity,int64_t *index) {
  const char *fields,*from,*order,*column,*comparison; char query[2048]; sqlite3_stmt *p; int ok;
  *index=-1;
  if(kind!=RDAPP_ENTRIES && kind!=RDAPP_DOWNLOADS && kind!=RDAPP_QUEUE) return failure(s,"Invalid indexed list");
  if(!query_parts(kind,key,NULL,&fields,&from,&order)) return failure(s,"Invalid indexed list");
  column=kind==RDAPP_ENTRIES?"e.position":"j.id"; comparison=kind==RDAPP_ENTRIES?"<":">";
  snprintf(query,sizeof(query),"SELECT count(*) FROM %s AND %s=?2",from,column);
  p=prepare(s,query); if(!p) return 0;
  sqlite3_bind_int64(p,1,key); sqlite3_bind_int64(p,2,identity);
  ok=sqlite3_step(p)==SQLITE_ROW;
  if(!ok || !sqlite3_column_int64(p,0)) { sqlite3_finalize(p); return ok; }
  sqlite3_finalize(p);
  snprintf(query,sizeof(query),"SELECT count(*) FROM %s AND %s%s?2",from,column,comparison);
  p=prepare(s,query); if(!p) return 0;
  sqlite3_bind_int64(p,1,key); sqlite3_bind_int64(p,2,identity);
  ok=sqlite3_step(p)==SQLITE_ROW;
  if(ok) *index=sqlite3_column_int64(p,0); else failure(s,sqlite3_errmsg(s->db));
  sqlite3_finalize(p); return ok;
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
  int64_t k; size_t i,j; sqlite3_stmt *p;
  if(!sql(s,"BEGIN IMMEDIATE")) return 0;
  if(!rdapp_store_playlist(s,id,title,&k)) goto rollback;
  p=prepare(s,"DELETE FROM entries WHERE playlist_id=?"); if(!p) goto rollback;
  sqlite3_bind_int64(p,1,k); if(!done(s,p)) goto rollback;
  for(i=0;i<count;++i) {
    if(!entries[i].video_id || strlen(entries[i].video_id)!=11 || strspn(entries[i].video_id,"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")!=11) { failure(s,"Invalid video ID in playlist"); goto rollback; }
    p=prepare(s,"INSERT OR REPLACE INTO videos(id,title) VALUES(?,?)"); if(!p) goto rollback;
    bind_text(p,1,entries[i].video_id); bind_text(p,2,entries[i].title); if(!done(s,p)) goto rollback;
    if((entries[i].has_duration && entries[i].duration>UINT64_C(9007199254740991)) ||
       (entries[i].has_view_count && entries[i].view_count>UINT64_C(9007199254740991))) {
      failure(s,"Invalid numeric metadata in playlist"); goto rollback;
    }
    p=prepare(s,"INSERT INTO entries(playlist_id,position,video_id,title,channel,channel_id,view_count_text,published_text,description_snippet,duration,view_count) VALUES(?,?,?,?,?,?,?,?,?,?,?)"); if(!p) goto rollback;
    sqlite3_bind_int64(p,1,k); sqlite3_bind_int(p,2,entries[i].position);
    bind_text(p,3,entries[i].video_id); bind_text(p,4,entries[i].title);
    /* NULL text and unbound numeric parameters remain SQL NULL, distinct from zero. */
    sqlite3_bind_text(p,5,entries[i].channel,-1,SQLITE_TRANSIENT);
    sqlite3_bind_text(p,6,entries[i].channel_id,-1,SQLITE_TRANSIENT);
    sqlite3_bind_text(p,7,entries[i].view_count_text,-1,SQLITE_TRANSIENT);
    sqlite3_bind_text(p,8,entries[i].published_text,-1,SQLITE_TRANSIENT);
    sqlite3_bind_text(p,9,entries[i].description_snippet,-1,SQLITE_TRANSIENT);
    if(entries[i].has_duration) sqlite3_bind_int64(p,10,(sqlite3_int64)entries[i].duration);
    if(entries[i].has_view_count) sqlite3_bind_int64(p,11,(sqlite3_int64)entries[i].view_count);
    if(!done(s,p)) goto rollback;
    if(entries[i].thumbnail_count>INT_MAX || (entries[i].thumbnail_count && !entries[i].thumbnail_urls)) {
      failure(s,"Invalid thumbnail list in playlist"); goto rollback;
    }
    for(j=0;j<entries[i].thumbnail_count;++j) {
      if(!entries[i].thumbnail_urls[j] || !entries[i].thumbnail_urls[j][0]) {
        failure(s,"Invalid thumbnail URL in playlist"); goto rollback;
      }
      p=prepare(s,"INSERT INTO entry_thumbnails(playlist_id,position,thumbnail_index,url) VALUES(?,?,?,?)"); if(!p) goto rollback;
      sqlite3_bind_int64(p,1,k); sqlite3_bind_int(p,2,entries[i].position); sqlite3_bind_int(p,3,(int)j);
      bind_text(p,4,entries[i].thumbnail_urls[j]); if(!done(s,p)) goto rollback;
    }
  }
  if(!refresh_job_metadata(s,k)) goto rollback;
  p=prepare(s,"UPDATE playlists SET synced_at=strftime('%s','now') WHERE id=?"); if(!p) goto rollback;
  sqlite3_bind_int64(p,1,k); if(!done(s,p)) goto rollback;
  if(!sql(s,"COMMIT")) goto rollback;
  if(key) *key=k;
  return 1;
rollback:
  sqlite3_exec(s->db,"ROLLBACK",NULL,NULL,NULL); return 0;
}
static int add_adhoc(rdapp_store *s,const char *video_id,const char *title,const char *format,int64_t *key) {
  sqlite3_stmt *p; int64_t k,position=0; int exists;
  if(!video_id || strlen(video_id)!=11 || strspn(video_id,"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")!=11 || (title && !*title))
    return failure(s,"Invalid video");
  if(!sql(s,"BEGIN IMMEDIATE")) return 0;
  if(!rdapp_store_playlist(s,RDAPP_ADHOC_PLAYLIST_ID,"Ad-Hoc",&k)) goto rollback;
  p=prepare(s,"UPDATE playlists SET source='system', synced_at=strftime('%s','now') WHERE id=?"); if(!p) goto rollback;
  sqlite3_bind_int64(p,1,k); if(!done(s,p)) goto rollback;
  p=prepare(s,title?"INSERT OR REPLACE INTO videos(id,title) VALUES(?,?)":"INSERT OR IGNORE INTO videos(id,title) VALUES(?,?)"); if(!p) goto rollback;
  bind_text(p,1,video_id); bind_text(p,2,title?title:video_id); if(!done(s,p)) goto rollback;
  p=prepare(s,"SELECT position FROM entries WHERE playlist_id=? AND video_id=? ORDER BY position LIMIT 1"); if(!p) goto rollback;
  sqlite3_bind_int64(p,1,k); bind_text(p,2,video_id); exists=sqlite3_step(p)==SQLITE_ROW;
  if(exists) position=sqlite3_column_int64(p,0);
  sqlite3_finalize(p);
  if(exists) {
    p=prepare(s,"UPDATE entries SET title=coalesce(?,title) WHERE playlist_id=? AND position=?"); if(!p) goto rollback;
    sqlite3_bind_text(p,1,title,-1,SQLITE_TRANSIENT); sqlite3_bind_int64(p,2,k); sqlite3_bind_int64(p,3,position); if(!done(s,p)) goto rollback;
  } else {
    p=prepare(s,"SELECT coalesce(max(position)+1,0) FROM entries WHERE playlist_id=?"); if(!p) goto rollback;
    sqlite3_bind_int64(p,1,k); if(sqlite3_step(p)!=SQLITE_ROW) { sqlite3_finalize(p); goto rollback; }
    position=sqlite3_column_int64(p,0); sqlite3_finalize(p);
    p=prepare(s,"INSERT INTO entries(playlist_id,position,video_id,title) VALUES(?,?,?,coalesce(?4,(SELECT title FROM videos WHERE id=?3)))"); if(!p) goto rollback;
    sqlite3_bind_int64(p,1,k); sqlite3_bind_int64(p,2,position); bind_text(p,3,video_id); sqlite3_bind_text(p,4,title,-1,SQLITE_TRANSIENT); if(!done(s,p)) goto rollback;
  }
  if(format) {
    if(!rdapp_store_enqueue(s,k,video_id,format)) goto rollback;
    p=prepare(s,"UPDATE jobs SET state='queued',error='' WHERE playlist_id=? AND video_id=? AND format=? AND state IN ('failed','cancelled','interrupted','removed')"); if(!p) goto rollback;
    sqlite3_bind_int64(p,1,k); bind_text(p,2,video_id); bind_text(p,3,format); if(!done(s,p)) goto rollback;
  }
  if(!refresh_job_metadata(s,k) || !sql(s,"COMMIT")) goto rollback;
  if(key) *key=k;
  return 1;
rollback:
  sqlite3_exec(s->db,"ROLLBACK",NULL,NULL,NULL); return 0;
}
int rdapp_store_add_adhoc(rdapp_store *s,const char *video_id,const char *title,int64_t *key) {
  return add_adhoc(s,video_id,title,NULL,key);
}
int rdapp_store_add_adhoc_download(rdapp_store *s,const char *video_id,const char *title,const char *format,int64_t *key) {
  if(!format || !*format) return failure(s,"Missing download format");
  return add_adhoc(s,video_id,title,format,key);
}
int rdapp_store_enqueue(rdapp_store *s,int64_t key,const char *video,const char *format) {
  sqlite3_stmt *p=prepare(s,"INSERT OR IGNORE INTO jobs(playlist_id,video_id,title,format," RDAPP_METADATA_COLUMNS ") SELECT playlist_id,video_id,title,?," RDAPP_METADATA_COLUMNS " FROM entries WHERE playlist_id=? AND (?='' OR video_id=?) ORDER BY position");
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
int rdapp_store_resolve_job(rdapp_store *s,int64_t key,const char *title,char *path,size_t capacity) {
  sqlite3_stmt *p; char resolved[PATH_MAX],safe[128]; int adhoc,n;
  if(!title || !*title || !path || !capacity) return failure(s,"Invalid resolved job");
  if(!sql(s,"BEGIN IMMEDIATE")) return 0;
  p=prepare(s,"SELECT j.path,p.service_id,p.directory FROM jobs j JOIN playlists p ON p.id=j.playlist_id WHERE j.id=? AND j.state='running'");
  if(!p) goto rollback;
  sqlite3_bind_int64(p,1,key);
  if(sqlite3_step(p)!=SQLITE_ROW) { sqlite3_finalize(p); failure(s,"Download is no longer running"); goto rollback; }
  adhoc=!strcmp((const char *)sqlite3_column_text(p,1),RDAPP_ADHOC_PLAYLIST_ID);
  if(adhoc) {
    rdapp_filename(title,safe,sizeof(safe));
    n=snprintf(resolved,sizeof(resolved),"%s/%s [%lld].mp4",sqlite3_column_text(p,2),safe,(long long)key);
  } else n=snprintf(resolved,sizeof(resolved),"%s",sqlite3_column_text(p,0));
  sqlite3_finalize(p);
  if(n<0 || n>=(int)sizeof(resolved) || (size_t)n>=capacity) { failure(s,"Resolved path is too long"); goto rollback; }
  if(adhoc) {
    const char *updates[]={
      "UPDATE videos SET title=?1 WHERE id=(SELECT video_id FROM jobs WHERE id=?2)",
      "UPDATE entries SET title=?1 WHERE playlist_id=(SELECT playlist_id FROM jobs WHERE id=?2) AND video_id=(SELECT video_id FROM jobs WHERE id=?2)",
      "UPDATE jobs SET title=?1 WHERE playlist_id=(SELECT playlist_id FROM jobs WHERE id=?2) AND video_id=(SELECT video_id FROM jobs WHERE id=?2)"
    };
    size_t i;
    for(i=0;i<sizeof(updates)/sizeof(updates[0]);++i) {
      p=prepare(s,updates[i]); if(!p) goto rollback;
      bind_text(p,1,title); sqlite3_bind_int64(p,2,key); if(!done(s,p)) goto rollback;
    }
    p=prepare(s,"UPDATE jobs SET path=? WHERE id=?"); if(!p) goto rollback;
    bind_text(p,1,resolved); sqlite3_bind_int64(p,2,key); if(!done(s,p)) goto rollback;
  }
  if(!sql(s,"COMMIT")) goto rollback;
  memcpy(path,resolved,(size_t)n+1); return 1;
rollback:
  sqlite3_exec(s->db,"ROLLBACK",NULL,NULL,NULL); return 0;
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

int rdapp_store_reconcile_job(rdapp_store *s,int64_t key,const char *root) {
  sqlite3_stmt *p=prepare(s,"SELECT path,state,actual_format FROM jobs WHERE id=?");
  int rc,ok=1; struct stat st; char path[PATH_MAX];
  if(!p) return 0;
  sqlite3_bind_int64(p,1,key); rc=sqlite3_step(p);
  if(rc==SQLITE_ROW) {
    const char *state=(const char *)sqlite3_column_text(p,1);
    const char *format=(const char *)sqlite3_column_text(p,2);
    int exists=snprintf(path,sizeof(path),"%s/%s",root,sqlite3_column_text(p,0))<(int)sizeof(path) &&
      lstat(path,&st)==0 && S_ISREG(st.st_mode) && st.st_size>0;
    if(!strcmp(state,"complete") && !exists)
      ok=rdapp_store_finish(s,key,"removed",format,"File is missing. Retry to download it again.");
    else if(!strcmp(state,"interrupted") && exists && format[0])
      ok=rdapp_store_finish(s,key,"complete",format,"Recovered completed download after interruption.");
  } else if(rc!=SQLITE_DONE) ok=failure(s,sqlite3_errmsg(s->db));
  sqlite3_finalize(p); return ok;
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
