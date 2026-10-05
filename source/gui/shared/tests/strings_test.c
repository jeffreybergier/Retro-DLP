#include "rdapp_strings.h"
#include "rdapp_store.h"
#include "rdapp_service.h"
#include <assert.h>
#include <pthread.h>
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int fail_after=-1;
void *__real_malloc(size_t size);
void *__wrap_malloc(size_t size) {
  if(fail_after==0) return NULL;
  if(fail_after>0) --fail_after;
  return __real_malloc(size);
}
static char scratch[512];
static const char *lookup(const char *key,void *context) {
  (void)context;
  if(!strcmp(key,"This playlist type cannot be synced by RetroDLP.")) return "100% unsupported";
  if(!strcmp(key,"Invalid video")) return NULL;
  if(!strcmp(key,"Invalid playlist ID")) return "";
  if(!strcmp(key,"Synced %s (%lu entries)"))
    return "%2$lu éléments : %1$s";
  snprintf(scratch,sizeof(scratch),"日本語: %s",key);
  return scratch;
}
static void *read_strings(void *context) {
  int i;
  (void)context;
  for(i=0;i<10000;++i)
    assert(!strcmp(rdapp_string(RDAPP_STRING_ADDED_VIDEOS),"日本語: Added Videos"));
  return NULL;
}
static int job_row(void *context,int count,const char *const *names,const char *const *values) {
  int i; int64_t *id=context;
  for(i=0;i<count;++i) {
    if(!strcmp(names[i],"id")) *id=strtoll(values[i],NULL,10);
    if(!strcmp(names[i],"playlist_title")) assert(!strcmp(values[i],"日本語: Added Videos"));
    if(!strcmp(names[i],"error")) assert(!strcmp(values[i],"日本語: Interrupted. Retry restarts the download."));
    if(!strcmp(names[i],"state")) assert(!strcmp(values[i],"interrupted"));
  }
  return 1;
}
static int playlist_row(void *context,int count,const char *const *names,const char *const *values) {
  const char *title=NULL,*service=NULL; int i;
  (void)context;
  for(i=0;i<count;++i) {
    if(!strcmp(names[i],"title")) title=values[i];
    if(!strcmp(names[i],"service_id")) service=values[i];
    if(!strcmp(names[i],"directory")) assert(!strstr(values[i],"日本語"));
  }
  assert(title && service);
  assert(!strcmp(title,!strcmp(service,"adhoc")?"日本語: Added Videos":"Added Videos"));
  return 1;
}
int main(int argc,char **argv) {
  rdapp_store *store=NULL,*reader=NULL;
  rdapp_service_config config;
  sqlite3 *raw=NULL; sqlite3_stmt *statement=NULL;
  int64_t playlist=0,other=0,job=0; char formatted[256];
  pthread_t threads[4]; int i;
  assert(argc==2);
  assert(!strcmp(rdapp_string(RDAPP_STRING_ADDED_VIDEOS),"Added Videos"));
  fail_after=3;
  assert(!rdapp_strings_initialize(lookup,NULL));
  fail_after=-1;
  assert(!strcmp(rdapp_string(RDAPP_STRING_ADDED_VIDEOS),"Added Videos"));
  assert(rdapp_store_open(argv[1],&store));
  assert(rdapp_store_add_adhoc_download(store,"abcdefghijk","Video","18",&playlist));
  assert(rdapp_store_playlist(store,"PLordinary","Added Videos",&other));
  assert(rdapp_store_claim(store,NULL,NULL));
  rdapp_store_close(store);
  /* Reopening recovers a running job using a stable English record. */
  assert(rdapp_strings_initialize(lookup,NULL));
  memset(scratch,'x',sizeof(scratch));
  assert(!strcmp(rdapp_string(RDAPP_STRING_ADDED_VIDEOS),"日本語: Added Videos"));
  assert(!strcmp(rdapp_string(RDAPP_STRING_INVALID_VIDEO),"Invalid video"));
  assert(!strcmp(rdapp_string(RDAPP_STRING_INVALID_PLAYLIST_ID),"Invalid playlist ID"));
  assert(rdapp_strings_initialize(NULL,NULL)); /* Cannot invalidate readers. */
  for(i=0;i<4;++i) assert(!pthread_create(&threads[i],NULL,read_strings,NULL));
  for(i=0;i<4;++i) assert(!pthread_join(threads[i],NULL));
  snprintf(formatted,sizeof(formatted),rdapp_string(RDAPP_STRING_SYNCED_S_LU_ENTRIES),"Test",3UL);
  assert(!strcmp(formatted,"3 éléments : Test"));
  assert(!strcmp(rdapp_localize_key("Unknown SQLite diagnostic"),"Unknown SQLite diagnostic"));
  assert(rdapp_store_open(argv[1],&store));
  assert(!rdapp_store_playlist(store,"", "", &other));
  assert(!strcmp(rdapp_store_error(store),"Invalid playlist ID"));
  assert(!rdapp_store_add_adhoc_download(store,"abcdefghijk","Video",NULL,&other));
  assert(!strcmp(rdapp_store_error(store),"日本語: Missing download format"));
  memset(&config,0,sizeof(config)); config.download_root=argv[1];
  assert(rdapp_service_run(store,&config,RDAPP_SYNC,"WL",NULL,formatted,sizeof(formatted))==RDLP_ERROR_INVALID_PLAYLIST);
  assert(!strcmp(formatted,"100% unsupported"));
  assert(rdapp_store_open_reader(argv[1],&reader));
  assert(rdapp_store_list(reader,RDAPP_PLAYLISTS,0,playlist_row,NULL));
  assert(rdapp_store_list(reader,RDAPP_JOBS,playlist,job_row,&job));
  assert(job>0);
  rdapp_store_close(reader);
  assert(sqlite3_open(argv[1],&raw)==SQLITE_OK);
  assert(sqlite3_prepare_v2(raw,"SELECT p.title,j.error,j.state FROM playlists p JOIN jobs j ON j.playlist_id=p.id WHERE p.service_id='adhoc'",-1,&statement,NULL)==SQLITE_OK);
  assert(sqlite3_step(statement)==SQLITE_ROW);
  assert(!strcmp((const char *)sqlite3_column_text(statement,0),"Added Videos"));
  assert(!strcmp((const char *)sqlite3_column_text(statement,1),"Interrupted. Retry restarts the download."));
  assert(!strcmp((const char *)sqlite3_column_text(statement,2),"interrupted"));
  sqlite3_finalize(statement); sqlite3_close(raw); rdapp_store_close(store);
  puts("PASS: C translation ownership, fallback, failure recovery, worker reads, formatting, and stable database records");
  return 0;
}
