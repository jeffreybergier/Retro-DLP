#if !defined(__APPLE__)
#define _POSIX_C_SOURCE 200809L
#endif
#include "rdapp_service.h"
#include <retrodlp/assets.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <unistd.h>
#include <errno.h>

static void lock_store(const rdapp_service_config *c) { if(c->lock) c->lock(c->lock_context); }
static void unlock_store(const rdapp_service_config *c) { if(c->unlock) c->unlock(c->lock_context); }
static void copy_error(char *message,size_t cap,const rdlp_error *error,rdlp_error_code code) {
  snprintf(message,cap,"%s",error->message[0]?error->message:rdlp_error_name(code));
}
static int cancelled(const rdapp_service_config *c) {
  return c->resolver.cancel_callback && c->resolver.cancel_callback(c->resolver.callback_context);
}
static rdlp_error_code sync_playlist(rdapp_store *s,const rdapp_service_config *c,
    rdlp_context *context,const char *input,char *message,size_t cap,rdlp_error *error) {
  rdlp_playlist_options options; rdlp_playlist *p=NULL;
  rdlp_error_code code; rdapp_entry *entries; const char **thumbnails=NULL;
  size_t i,j,n,total=0,offset=0; int64_t key=0; int ok;
  memset(&options,0,sizeof(options)); options.struct_size=sizeof(options); options.cookie_file=c->cookie_file;
  code=rdlp_list_playlist(context,input,&options,&p,error);
  if(code!=RDLP_OK) return code;
  n=rdlp_playlist_entry_count(p);
  if(n>INT_MAX || n>SIZE_MAX/sizeof(*entries)) { rdlp_playlist_destroy(p); return RDLP_ERROR_RESPONSE_TOO_LARGE; }
  entries=calloc(n?n:1,sizeof(*entries));
  if(!entries) { rdlp_playlist_destroy(p); return RDLP_ERROR_OUT_OF_MEMORY; }
  for(i=0;i<n;++i) {
    entries[i].video_id=rdlp_playlist_entry_video_id(p,i);
    entries[i].title=rdlp_playlist_entry_title(p,i); entries[i].position=(int)i;
    entries[i].channel=rdlp_playlist_entry_channel(p,i);
    entries[i].channel_id=rdlp_playlist_entry_channel_id(p,i);
    entries[i].view_count_text=rdlp_playlist_entry_view_count_text(p,i);
    entries[i].published_text=rdlp_playlist_entry_published_text(p,i);
    entries[i].description_snippet=rdlp_playlist_entry_description_snippet(p,i);
    entries[i].has_duration=rdlp_playlist_entry_duration(p,i,&entries[i].duration);
    entries[i].has_view_count=rdlp_playlist_entry_view_count(p,i,&entries[i].view_count);
    entries[i].thumbnail_count=rdlp_playlist_entry_thumbnail_count(p,i);
    if(entries[i].thumbnail_count>INT_MAX || entries[i].thumbnail_count>SIZE_MAX/sizeof(*thumbnails)-total) {
      code=RDLP_ERROR_RESPONSE_TOO_LARGE; goto end;
    }
    total+=entries[i].thumbnail_count;
  }
  if(total) {
    thumbnails=calloc(total,sizeof(*thumbnails));
    if(!thumbnails) { code=RDLP_ERROR_OUT_OF_MEMORY; goto end; }
    for(i=0;i<n;++i) {
      if(entries[i].thumbnail_count) entries[i].thumbnail_urls=thumbnails+offset;
      for(j=0;j<entries[i].thumbnail_count;++j) thumbnails[offset++]=rdlp_playlist_entry_thumbnail_url(p,i,j);
    }
  }
  if(cancelled(c)) { code=RDLP_ERROR_CANCELLED; goto end; }
  lock_store(c);
  ok=rdapp_store_snapshot(s,rdlp_playlist_id(p),rdlp_playlist_title(p),entries,n,&key);
  if(ok) ok=rdapp_store_export(s,key,c->download_root);
  if(ok) snprintf(message,cap,"Synced %s (%lu entries)",rdlp_playlist_title(p),(unsigned long)n);
  else { snprintf(error->message,sizeof(error->message),"%s",rdapp_store_error(s)); code=RDLP_ERROR_STORAGE_IO; }
  unlock_store(c);
end:
  free(thumbnails); free(entries); rdlp_playlist_destroy(p); return code;
}
static rdlp_error_code discover(rdapp_store *s,const rdapp_service_config *c,
    rdlp_context *context,char *message,size_t cap,rdlp_error *error) {
  rdlp_playlist_options options; rdlp_playlist_collection *p=NULL; size_t i,n; int ok=1;
  rdlp_error_code code;
  memset(&options,0,sizeof(options)); options.struct_size=sizeof(options); options.cookie_file=c->cookie_file;
  code=rdlp_list_playlist_collection(context,"https://www.youtube.com/feed/playlists",&options,&p,error);
  if(code!=RDLP_OK) return code;
  n=rdlp_playlist_collection_count(p);
  lock_store(c);
  for(i=0;i<n && ok;++i) ok=rdapp_store_discovered_playlist(s,rdlp_playlist_collection_id(p,i),rdlp_playlist_collection_title(p,i));
  if(ok) snprintf(message,cap,"Found %lu playlists. Select a playlist and Sync, or Sync All.",(unsigned long)n);
  else { snprintf(error->message,sizeof(error->message),"%s",rdapp_store_error(s)); code=RDLP_ERROR_STORAGE_IO; }
  unlock_store(c); rdlp_playlist_collection_destroy(p); return code;
}
static rdlp_error_code provision(const rdapp_service_config *c,rdlp_error *error) {
  rdlp_ejs_asset_info info; rdlp_ejs_asset_options options;
  if(!c->resolver.ejs_asset_directory) return RDLP_OK;
  memset(&info,0,sizeof(info)); info.struct_size=sizeof(info);
  if(rdlp_ejs_assets_inspect(c->resolver.ejs_asset_directory,&info,error)==RDLP_OK) return RDLP_OK;
  memset(&options,0,sizeof(options)); options.struct_size=sizeof(options);
  options.ca_bundle_path=c->resolver.ca_bundle_path;
  options.cancel_callback=c->resolver.cancel_callback;
  options.callback_context=c->resolver.callback_context;
  options.transport=c->resolver.transport;
  return rdlp_ejs_assets_install(c->resolver.ejs_asset_directory,&options,error);
}
static rdlp_error_code download_job(rdapp_store *s,const rdapp_service_config *c,
    rdlp_context *context,const rdapp_job *job,char *message,size_t cap,rdlp_error *error) {
  char destination[PATH_MAX],directory[PATH_MAX],staging[PATH_MAX],temporary[PATH_MAX],cleanup[PATH_MAX];
  char *slash; const char *suffixes[]={"",".part",".video.mp4",".video.mp4.part",".audio.m4a",".audio.m4a.part"};
  rdlp_selection *selection=NULL; rdlp_resolve_options options; rdlp_download_result result;
  rdlp_error_code code; size_t i; int ok;
  if(!job || !job->relative_path || strncmp(job->relative_path,"Playlists/",10) || strstr(job->relative_path,"/../") || strstr(job->relative_path,"/./")) return RDLP_ERROR_INVALID_PATH;
  if(snprintf(destination,sizeof(destination),"%s/%s",c->download_root,job->relative_path)>=(int)sizeof(destination) ||
     snprintf(staging,sizeof(staging),"%s/.staging/%lld",c->download_root,(long long)job->id)>=(int)sizeof(staging) ||
     snprintf(temporary,sizeof(temporary),"%s/video.mp4",staging)>=(int)sizeof(temporary)) return RDLP_ERROR_INVALID_PATH;
  strcpy(directory,destination); slash=strrchr(directory,'/'); if(!slash) return RDLP_ERROR_INVALID_PATH; *slash=0;
  code=provision(c,error); if(code!=RDLP_OK) return code;
  memset(&options,0,sizeof(options)); options.struct_size=sizeof(options);
  options.cookie_file=c->cookie_file; options.format_expression=job->format;
  code=rdlp_resolve_video(context,job->video_id,&options,&selection,error);
  if(code!=RDLP_OK) return code;
  if(c->status_callback) {
    char status[1024];
    snprintf(status,sizeof(status),"Format: %s · %dx%d",rdlp_selection_format_id(selection),
      rdlp_selection_media_width(selection,0),rdlp_selection_media_height(selection,0));
    c->status_callback(status,c->status_context);
    snprintf(status,sizeof(status),"File: %s",strrchr(destination,'/')+1);
    c->status_callback(status,c->status_context);
  }
  /* Persist actual format before file publication for crash reconciliation. */
  lock_store(c); ok=rdapp_store_finish(s,job->id,"running",rdlp_selection_format_id(selection),""); unlock_store(c);
  if(!ok) { code=RDLP_ERROR_STORAGE_IO; goto end; }
  if(!rdapp_make_directory(staging) || !rdapp_make_directory(directory)) { code=RDLP_ERROR_STORAGE_IO; goto end; }
  for(i=0;i<sizeof(suffixes)/sizeof(suffixes[0]);++i) {
    if(snprintf(cleanup,sizeof(cleanup),"%s%s",temporary,suffixes[i])>=(int)sizeof(cleanup)) { code=RDLP_ERROR_INVALID_PATH; goto end; }
    if(unlink(cleanup) && errno!=ENOENT) { code=RDLP_ERROR_STORAGE_IO; goto end; }
  }
  memset(&result,0,sizeof(result)); result.struct_size=sizeof(result);
  code=rdlp_download_selection(selection,temporary,&c->download,&result,error);
  if(code!=RDLP_OK) goto end;
  if(cancelled(c)) { code=RDLP_ERROR_CANCELLED; goto end; }
  /* Same-volume exclusive publication never overwrites another file. */
  if(link(temporary,destination)) {
    code=errno==EEXIST?RDLP_ERROR_DESTINATION_EXISTS:RDLP_ERROR_STORAGE_IO;
    snprintf(error->message,sizeof(error->message),"Cannot publish downloaded file: %s",strerror(errno)); goto end;
  }
  unlink(temporary); rmdir(staging);
  if(c->result) c->result->downloaded_bytes=result.bytes_written>0?(uint64_t)result.bytes_written:0;
  lock_store(c);
  ok=rdapp_store_finish(s,job->id,"complete",rdlp_selection_format_id(selection),"");
  if(!ok) {
    if(c->result) c->result->warning=1;
    snprintf(message,cap,"File downloaded, but its database update failed. Reopen the library to recover it.");
  } else if(!rdapp_store_export(s,job->playlist_id,c->download_root)) {
    if(c->result) c->result->warning=1;
    snprintf(message,cap,"Downloaded. VLC playlist export failed: %s. Sync the playlist to retry export.",rdapp_store_error(s));
  } else snprintf(message,cap,"Download complete (%s)",rdlp_selection_format_id(selection));
  unlock_store(c);
end:
  rdlp_selection_destroy(selection); return code;
}
rdlp_error_code rdapp_service_run(rdapp_store *s,const rdapp_service_config *c,
    rdapp_operation operation,const char *input,const rdapp_job *job,char *message,size_t cap) {
  rdlp_context *context=NULL; rdlp_error error; rdlp_error_code code;
  memset(&error,0,sizeof(error)); error.struct_size=sizeof(error);
  if(!s || !c || !message || !cap || !c->download_root) return RDLP_ERROR_INVALID_ARGUMENT;
  message[0]=0;
  if(c->result) memset(c->result,0,sizeof(*c->result));
  code=rdlp_context_create(&c->resolver,&context,&error);
  if(code==RDLP_OK) {
    switch(operation) {
      case RDAPP_SYNC: code=sync_playlist(s,c,context,input,message,cap,&error); break;
      case RDAPP_DISCOVER: code=discover(s,c,context,message,cap,&error); break;
      case RDAPP_DOWNLOAD: code=download_job(s,c,context,job,message,cap,&error); break;
      default: code=RDLP_ERROR_INVALID_ARGUMENT;
    }
  }
  if(code!=RDLP_OK) {
    copy_error(message,cap,&error,code);
    if(operation==RDAPP_DOWNLOAD && job) {
      lock_store(c); rdapp_store_finish(s,job->id,code==RDLP_ERROR_CANCELLED?"cancelled":"failed","",message); unlock_store(c);
    }
  }
  rdlp_context_destroy(context); return code;
}
