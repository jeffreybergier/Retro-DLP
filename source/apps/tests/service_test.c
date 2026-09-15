#if !defined(__APPLE__)
#define _POSIX_C_SOURCE 200809L
#endif
#include "rdapp_service.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <sqlite3.h>

typedef struct {
  const char *base; const char *media; int fail, cancel, cancel_on_progress, depth;
  char player[4096]; int format_seen, target_seen, requests;
} fixture;
static const char playlist_json[] =
  "{\"metadata\":{\"playlistMetadataRenderer\":{\"title\":\"Offline playlist\"}},"
  "\"contents\":[{\"playlistVideoRenderer\":{\"videoId\":\"YE7VzlLtp-4\",\"title\":{\"simpleText\":\"One video\"},"
  "\"lengthSeconds\":\"3723\",\"shortBylineText\":{\"runs\":[{\"text\":\"Example Channel\",\"navigationEndpoint\":{\"browseEndpoint\":{\"browseId\":\"UC_fixture\"}}}]},"
  "\"viewCountText\":{\"simpleText\":\"1,234 views\"},\"publishedTimeText\":{\"simpleText\":\"2 days ago\"},\"descriptionSnippet\":{\"simpleText\":\"Available snippet\"},"
  "\"thumbnail\":{\"thumbnails\":[{\"url\":\"https://img.example/first.jpg\"},{\"url\":\"https://img.example/second.jpg\"}]}}}]}";
static rdlp_error_code send_fixture(void *ctx,const rdlp_transport_request *request,rdlp_transport_response *response,rdlp_error *error) {
  fixture *f=ctx; static char page[8192]; const char *data=NULL; (void)error;
  assert(f->depth==0);
  ++f->requests;
  assert(!strstr(request->url,"img.example"));
  if(f->fail) return RDLP_ERROR_TRANSPORT_REQUEST_FAILED;
  if(strstr(request->url,"/feed/playlists")) {
    data="<script>ytcfg.set({\"LOGGED_IN\":true,\"INNERTUBE_API_KEY\":\"test\",\"INNERTUBE_CONTEXT_CLIENT_VERSION\":\"1.20260828\"});var ytInitialData={\"contents\":[{\"playlistRenderer\":{\"playlistId\":\"PLcollection\",\"title\":{\"simpleText\":\"Account playlist\"}}}]};</script>";
  } else if(strstr(request->url,"/playlist?")) {
    snprintf(page,sizeof(page),"<script>ytcfg.set({\"INNERTUBE_API_KEY\":\"test\",\"INNERTUBE_CONTEXT_CLIENT_VERSION\":\"1.20260828\"});var ytInitialData=%s;</script>",playlist_json); data=page;
  } else if(strstr(request->url,"/youtubei/v1/browse")) data=playlist_json;
  else if(strstr(request->url,"/watch")) data="{\"INNERTUBE_CONTEXT_CLIENT_VERSION\":\"2.20260708\",\"STS\":12345,\"jsUrl\":\"/s/player/test/base.js\"}";
  else if(strstr(request->url,"/youtubei/v1/player")) {
    snprintf(f->player,sizeof(f->player),"{\"playabilityStatus\":{\"status\":\"OK\"},\"videoDetails\":{\"videoId\":\"YE7VzlLtp-4\",\"title\":\"One video\"},\"streamingData\":{\"formats\":[{\"itag\":18,\"url\":\"%s/%s\",\"mimeType\":\"video/mp4; codecs=\\\"avc1.42001E, mp4a.40.2\\\"\",\"width\":640,\"height\":360}]}}",f->base,f->media); data=f->player;
  }
  if(!data) return RDLP_ERROR_TRANSPORT_REQUEST_FAILED;
  response->http_status=200; response->data=data; response->data_length=strlen(data); return RDLP_OK;
}
static void lock(void *ctx) { fixture *f=ctx; assert(f->depth==0); ++f->depth; }
static void unlock(void *ctx) { fixture *f=ctx; assert(f->depth==1); --f->depth; }
static int cancelled(void *ctx) { return ((fixture *)ctx)->cancel; }
static void progress(const rdlp_download_event *event,void *ctx) {
  fixture *f=ctx; assert(!f->depth); if(f->cancel_on_progress && event->completed_bytes) f->cancel=1;
}
static void status_message(const char *message,void *ctx) {
  fixture *f=ctx; assert(!f->depth);
  if(!strncmp(message,"Format: ",8)) { assert(strstr(message,"640x360")); ++f->format_seen; }
  else if(!strncmp(message,"File: ",6)) { assert(f->format_seen>f->target_seen); ++f->target_seen; }
  else assert(0);
}
typedef struct { rdapp_job job; char video[64],format[64],path[1024],state[64]; int count, account_count; } claimed;
static int collect(void *ctx,int count,const char *const *names,const char *const *values) {
  claimed *c=ctx; int i; ++c->count;
  for(i=0;i<count;++i) {
    const char *v=values[i]?values[i]:"";
    if(!strcmp(names[i],"source") && !strcmp(v,"account")) ++c->account_count;
    if(!strcmp(names[i],"id")) c->job.id=atoll(v);
    if(!strcmp(names[i],"playlist_id")) c->job.playlist_id=atoll(v);
    if(!strcmp(names[i],"video_id")) snprintf(c->video,sizeof(c->video),"%s",v);
    if(!strcmp(names[i],"format")) snprintf(c->format,sizeof(c->format),"%s",v);
    if(!strcmp(names[i],"path")) snprintf(c->path,sizeof(c->path),"%s",v);
    if(!strcmp(names[i],"state")) snprintf(c->state,sizeof(c->state),"%s",v);
  }
  c->job.video_id=c->video; c->job.format=c->format; c->job.relative_path=c->path; return 1;
}
static void claim(rdapp_store *s,claimed *c) { memset(c,0,sizeof(*c)); assert(rdapp_store_claim(s,collect,c)); assert(c->count==1); }
static void require(rdlp_error_code code,const char *message) { if(code!=RDLP_OK) { fprintf(stderr,"service failed: %d %s\n",code,message); abort(); } }
static void check_thumbnails(const char *path,int64_t playlist) {
  sqlite3 *db=NULL; sqlite3_stmt *query=NULL; int i;
  const char *urls[]={"https://img.example/first.jpg","https://img.example/second.jpg"};
  assert(sqlite3_open(path,&db)==SQLITE_OK);
  assert(sqlite3_prepare_v2(db,"SELECT position,thumbnail_index,url FROM entry_thumbnails WHERE playlist_id=? ORDER BY position,thumbnail_index",-1,&query,NULL)==SQLITE_OK);
  assert(sqlite3_bind_int64(query,1,playlist)==SQLITE_OK);
  for(i=0;i<2;++i) {
    assert(sqlite3_step(query)==SQLITE_ROW);
    assert(sqlite3_column_int(query,0)==0 && sqlite3_column_int(query,1)==i);
    assert(!strcmp((const char *)sqlite3_column_text(query,2),urls[i]));
  }
  assert(sqlite3_step(query)==SQLITE_DONE);
  sqlite3_finalize(query);
  assert(sqlite3_prepare_v2(db,"SELECT channel,channel_id,view_count_text,published_text,description_snippet,duration,view_count FROM entries WHERE playlist_id=? AND position=0",-1,&query,NULL)==SQLITE_OK);
  assert(sqlite3_bind_int64(query,1,playlist)==SQLITE_OK && sqlite3_step(query)==SQLITE_ROW);
  {
    const char *expected[]={"Example Channel","UC_fixture","1,234 views","2 days ago","Available snippet","3723","1234"};
    for(i=0;i<7;++i) assert(!strcmp((const char *)sqlite3_column_text(query,i),expected[i]));
  }
  sqlite3_finalize(query); sqlite3_close(db);
}
int main(int argc,char **argv) {
  rdapp_store *s=NULL; rdapp_service_config config; rdapp_service_result outcome; rdlp_transport transport; fixture f;
  char db[2048],cookies[2048],message[1024],file[2048],export[2048]; FILE *output;
  int64_t key=0; claimed c; rdlp_error_code code; struct stat st;
  assert(argc==4); memset(&config,0,sizeof(config)); memset(&transport,0,sizeof(transport)); memset(&f,0,sizeof(f));
  f.base=argv[2]; f.media="media";
  config.download_root=argv[1]; config.resolver.struct_size=sizeof(config.resolver);
  config.resolver.ca_bundle_path=argv[3]; config.resolver.cancel_callback=cancelled; config.resolver.callback_context=&f;
  transport.struct_size=sizeof(transport); transport.send=send_fixture; transport.context=&f; config.resolver.transport=&transport;
  config.download.struct_size=sizeof(config.download); config.download.ca_bundle_path=argv[3];
  config.download.cancel_callback=cancelled; config.download.event_callback=progress; config.download.callback_context=&f;
  config.result=&outcome; config.status_callback=status_message; config.status_context=&f;
  config.lock=lock; config.unlock=unlock; config.lock_context=&f;
  snprintf(db,sizeof(db),"%s/library.sqlite",argv[1]); assert(rdapp_store_open(db,&s));
  require(rdapp_service_run(s,&config,RDAPP_SYNC,"PLfixture",NULL,message,sizeof(message)),message);
  assert(f.requests==2); /* Existing playlist page + browse; no image/video requests. */
  memset(&c,0,sizeof(c)); assert(rdapp_store_list(s,RDAPP_PLAYLISTS,0,collect,&c)); assert(c.count==1); key=c.job.id;
  {
    rdapp_job added; int before=f.requests;
    memset(&added,0,sizeof(added)); added.format="137+140"; /* Unavailable download preference must not block adding metadata. */
    require(rdapp_service_run(s,&config,RDAPP_ADD_VIDEO,"https://youtu.be/YE7VzlLtp-4",&added,message,sizeof(message)),message);
    assert(f.requests==before+2 && strstr(message,"Ad-Hoc")); /* Local fixture watch/player only. */
    claim(s,&c); assert(!strcmp(c.format,"137+140") && !strcmp(c.video,"YE7VzlLtp-4") && c.job.playlist_id!=key);
    assert(rdapp_service_run(s,&config,RDAPP_DOWNLOAD,NULL,&c.job,message,sizeof(message))==RDLP_ERROR_FORMAT_UNAVAILABLE);
    /* A supported quality must download through the normal queue after Add,
       without an explicit enqueue call. */
    added.format="18";
    require(rdapp_service_run(s,&config,RDAPP_ADD_VIDEO,"YE7VzlLtp-4",&added,message,sizeof(message)),message);
    claim(s,&c); assert(!strcmp(c.format,"18") && c.job.playlist_id!=key);
    require(rdapp_service_run(s,&config,RDAPP_DOWNLOAD,NULL,&c.job,message,sizeof(message)),message);
    snprintf(file,sizeof(file),"%s/%s",argv[1],c.path); assert(stat(file,&st)==0 && st.st_size>0);
    require(rdapp_service_run(s,&config,RDAPP_ADD_VIDEO,"YE7VzlLtp-4",&added,message,sizeof(message)),message);
    memset(&c,0,sizeof(c)); assert(rdapp_store_list(s,RDAPP_PENDING,0,collect,&c)); assert(c.count==0);
    assert(rdapp_service_run(s,&config,RDAPP_ADD_VIDEO,"bad/id",&added,message,sizeof(message))!=RDLP_OK);
    memset(&c,0,sizeof(c)); assert(rdapp_store_list(s,RDAPP_JOBS,0,collect,&c)); assert(c.count==2);
    f.format_seen=0; f.target_seen=0;
  }
  memset(&c,0,sizeof(c)); assert(rdapp_store_list(s,RDAPP_PLAYLISTS,0,collect,&c)); assert(c.count==2);
  check_thumbnails(db,key); /* Playlist object and its borrowed strings are already destroyed. */
  memset(&c,0,sizeof(c)); assert(rdapp_store_list(s,RDAPP_ENTRIES,key,collect,&c)); assert(c.count==1);
  f.fail=1;
  assert(rdapp_service_run(s,&config,RDAPP_SYNC,"PLfixture",NULL,message,sizeof(message))!=RDLP_OK);
  memset(&c,0,sizeof(c)); assert(rdapp_store_list(s,RDAPP_ENTRIES,key,collect,&c)); assert(c.count==1); f.fail=0;
  check_thumbnails(db,key);
  /* Account collection import uses synthetic cookie data, never real credentials. */
  snprintf(cookies,sizeof(cookies),"%s/cookies.txt",argv[1]); output=fopen(cookies,"w"); assert(output);
  fputs("# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t4102444800\tLOGIN_INFO\tfixture\n.youtube.com\tTRUE\t/\tTRUE\t4102444800\tSAPISID\tfixture\n",output); fclose(output); config.cookie_file=cookies;
  require(rdapp_service_run(s,&config,RDAPP_DISCOVER,NULL,NULL,message,sizeof(message)),message);
  memset(&c,0,sizeof(c)); assert(rdapp_store_list(s,RDAPP_PLAYLISTS,0,collect,&c)); assert(c.count==3 && c.account_count==1); config.cookie_file=NULL;
  assert(rdapp_store_enqueue(s,key,NULL,"18")); claim(s,&c);
  require(rdapp_service_run(s,&config,RDAPP_DOWNLOAD,NULL,&c.job,message,sizeof(message)),message);
  snprintf(file,sizeof(file),"%s/%s",argv[1],c.path); assert(stat(file,&st)==0 && st.st_size>0);
  assert(outcome.downloaded_bytes==(uint64_t)st.st_size && !outcome.warning && f.format_seen==1 && f.target_seen==1);
  snprintf(export,sizeof(export),"%s/Playlists/Offline playlist [PLfixture]/Playlist.m3u8",argv[1]); output=fopen(export,"r"); assert(output); assert(fgets(message,sizeof(message),output)); assert(!strcmp(message,"#EXTM3U\n")); assert(fgets(message,sizeof(message),output)); assert(strstr(message,"One video")); fclose(output);
  /* A second explicit quality expression exercises HTTP failure and fresh retry. */
  assert(rdapp_store_enqueue(s,key,NULL,"18/18")); claim(s,&c); f.media="status";
  code=rdapp_service_run(s,&config,RDAPP_DOWNLOAD,NULL,&c.job,message,sizeof(message)); assert(code==RDLP_ERROR_HTTP_STATUS);
  assert(rdapp_store_retry(s,c.job.id)); claim(s,&c); f.media="media";
  require(rdapp_service_run(s,&config,RDAPP_DOWNLOAD,NULL,&c.job,message,sizeof(message)),message);
  /* Cancellation must persist, and the subsequent retry must not hit stale parts. */
  assert(rdapp_store_enqueue(s,key,NULL,"18/18/18")); claim(s,&c); f.media="slow"; f.cancel_on_progress=1;
  assert(rdapp_service_run(s,&config,RDAPP_DOWNLOAD,NULL,&c.job,message,sizeof(message))==RDLP_ERROR_CANCELLED);
  f.cancel=0; f.cancel_on_progress=0; f.media="media"; assert(rdapp_store_retry(s,c.job.id)); claim(s,&c);
  require(rdapp_service_run(s,&config,RDAPP_DOWNLOAD,NULL,&c.job,message,sizeof(message)),message);
  assert(rdapp_store_remove_file(s,c.job.id,argv[1]));
  /* Successful media with an export problem must produce an alertable warning. */
  assert(rdapp_store_enqueue(s,key,NULL,"18/18/18/18")); claim(s,&c);
  assert(unlink(export)==0 && mkdir(export,0700)==0);
  require(rdapp_service_run(s,&config,RDAPP_DOWNLOAD,NULL,&c.job,message,sizeof(message)),message);
  assert(outcome.warning && outcome.downloaded_bytes>0 && strstr(message,"export failed"));
  assert(rmdir(export)==0);
  assert(!f.depth); rdapp_store_close(s);
  puts("PASS: application sync, account discovery, download, export, HTTP retry, cancellation, and removal"); return 0;
}
