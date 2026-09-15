#import "RDLPLibrary.h"
#include "rdapp_store.h"
#include "rdapp_service.h"
#include <retrodlp/retrodlp.h>
#include <retrodlp/download.h>
#include <retrodlp/assets.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>
#include <errno.h>

NSString * const RDLPLibraryDidChange = @"RetroDLPLibraryDidChange";
static NSString *string(const char *s) { NSString *v=s?[NSString stringWithUTF8String:s]:nil; return v?v:@""; }
static long long identifier(NSString *value) { return value?strtoll([value UTF8String],NULL,10):0; }
static int collect(void *context,int count,const char *const *names,const char *const *values) {
  NSMutableDictionary *row=[NSMutableDictionary dictionary]; int i;
  for(i=0;i<count;++i) [row setObject:string(values[i]) forKey:string(names[i])];
  [(NSMutableArray *)context addObject:row]; return 1;
}
@interface RDLPLibrary (Private)
- (void)startNext;
- (void)work:(NSDictionary *)command;
- (void)finished:(NSString *)message;
- (void)changed;
- (void)showStatus:(NSString *)message;
- (BOOL)cancelled;
- (void)progress:(NSString *)phase completed:(uint64_t)completed expected:(uint64_t)expected;
@end
static void store_lock(void *context) { [(NSLock *)context lock]; }
static void store_unlock(void *context) { [(NSLock *)context unlock]; }
static int cancel_callback(void *context) { return [(RDLPLibrary *)context cancelled]?1:0; }
static void event_callback(const rdlp_event *event,void *context) {
  (void)event;
  [(RDLPLibrary *)context progress:@"Loading YouTube metadata" completed:0 expected:0];
}
static void download_callback(const rdlp_download_event *event,void *context) {
  const char *phases[]={"Downloading audio","Downloading video","Downloading video","Muxing MP4","Cleaning up"};
  unsigned int index=(unsigned int)event->type;
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  [(RDLPLibrary *)context progress:string(index<5?phases[index]:"Downloading") completed:event->completed_bytes expected:event->expected_bytes];
  [pool drain];
}
@implementation RDLPLibrary
+ (NSArray *)qualityTitles;
{ return [NSArray arrayWithObjects:[self qualityLabelForFormat:@"18"],[self qualityLabelForFormat:@"136+140"],[self qualityLabelForFormat:@"137+140"],@"Custom Format…",nil]; }
+ (NSArray *)qualityFormats;
{ return [NSArray arrayWithObjects:@"18",@"136+140",@"137+140",nil]; }
+ (NSString *)qualityLabelForFormat:(NSString *)format;
{
  if(![format length]) return @"";
  NSUInteger index=[[self qualityFormats] indexOfObject:format];
  NSArray *names=[NSArray arrayWithObjects:@"Low",@"Med",@"High",nil];
  NSString *name=index==NSNotFound?@"Custom":[names objectAtIndex:index];
  return [NSString stringWithFormat:@"%@ (%@)",name,format];
}
+ (NSString *)preferredFormat;
{
  NSString *format=[[NSUserDefaults standardUserDefaults] stringForKey:@"downloadFormat"];
  return format && rdlp_format_expression_valid([format UTF8String])?format:@"18";
}
+ (BOOL)validFormat:(NSString *)format;
{ return format && rdlp_format_expression_valid([format UTF8String]); }
+ (BOOL)savePreferredFormat:(NSString *)format;
{
  if(!rdlp_format_expression_valid([format UTF8String])) return NO;
  [[NSUserDefaults standardUserDefaults] setObject:format forKey:@"downloadFormat"]; return YES;
}
- (id)initWithSupportDirectory:(NSString *)support downloadDirectory:(NSString *)root;
{
  self=[super init]; if(!self) return nil;
  support_=[support copy]; root_=[root copy]; lock_=[[NSLock alloc] init]; commands_=[[NSMutableArray alloc] init];
  cookies_=[[support stringByAppendingPathComponent:@"cookies.txt"] copy];
  ca_=[[[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"] copy];
  assets_=[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"ejs"];
  if(![[NSFileManager defaultManager] fileExistsAtPath:[assets_ stringByAppendingPathComponent:@"core.min.js"]])
    assets_=[support stringByAppendingPathComponent:@"ejs"];
  assets_=[assets_ copy]; status_=[@"Ready" copy];
  if(!rdapp_make_directory([support fileSystemRepresentation]) || !rdapp_make_directory([root fileSystemRepresentation]) ||
     !rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],(rdapp_store **)&store_)) {
    [self release]; return nil;
  }
  chmod([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],0600);
  /* Relaunch preserves pending jobs. Explicit Resume avoids surprise transfers. */
  paused_=YES;
  if(rdapp_store_reconcile(store_,[root_ fileSystemRepresentation]))
    [self showStatus:@"Ready. Resume Queue to start pending downloads."];
  else [self showStatus:string(rdapp_store_error(store_))];
  return self;
}
- (void)dealloc;
{
  rdapp_store_close(store_); [lock_ release]; [commands_ release]; [activeCommand_ release]; [support_ release]; [root_ release];
  [ca_ release]; [assets_ release]; [cookies_ release]; [status_ release]; [super dealloc];
}
- (void)changed; { [[NSNotificationCenter defaultCenter] postNotificationName:RDLPLibraryDidChange object:self]; }
- (void)showStatus:(NSString *)message;
{ [status_ release]; status_=[message copy]; [self changed]; }
- (NSString *)status; { return status_; }
- (BOOL)isBusy; { return busy_; }
- (NSDictionary *)queueProgress;
{
  NSUInteger pending=0, running=0;
  NSEnumerator *e=[[self jobsForPlaylist:nil completedOnly:NO] objectEnumerator]; NSDictionary *job;
  while((job=[e nextObject])) {
    NSString *state=[job objectForKey:@"state"];
    if([state isEqualToString:@"queued"]) ++pending;
  }
  /* The worker can finish its store update before finished: reaches the UI. */
  if([[activeCommand_ objectForKey:@"type"] isEqualToString:@"download"]) running=1;
  return [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithBool:queueRun_],@"active",
    [NSNumber numberWithUnsignedLong:queueProcessed_],@"processed",
    [NSNumber numberWithUnsignedLong:queueFailed_],@"failed",
    [NSNumber numberWithUnsignedLong:queueCancelled_],@"cancelled",
    [NSNumber numberWithUnsignedLong:pending],@"pending",
    [NSNumber numberWithUnsignedLong:running],@"running",
    [NSNumber numberWithUnsignedLong:queueProcessed_+pending+running],@"total",nil];
}
- (NSString *)downloadsDirectory; { return root_; }
- (BOOL)isSyncPendingForInput:(NSString *)input;
{
  if([[activeCommand_ objectForKey:@"type"] isEqualToString:@"sync"] && [[activeCommand_ objectForKey:@"input"] isEqualToString:input]) return YES;
  NSEnumerator *e=[commands_ objectEnumerator]; NSDictionary *command;
  while((command=[e nextObject])) if([[command objectForKey:@"type"] isEqualToString:@"sync"] && [[command objectForKey:@"input"] isEqualToString:input]) return YES;
  return NO;
}
- (BOOL)isDiscoveryPending;
{
  if([[activeCommand_ objectForKey:@"type"] isEqualToString:@"discover"]) return YES;
  NSEnumerator *e=[commands_ objectEnumerator]; NSDictionary *command;
  while((command=[e nextObject])) if([[command objectForKey:@"type"] isEqualToString:@"discover"]) return YES;
  return NO;
}
- (NSString *)cookieStatus;
{
  struct stat info;
  if(stat([cookies_ fileSystemRepresentation],&info)) return errno==ENOENT?@"Not Imported":@"Unavailable";
  if(!S_ISREG(info.st_mode) || info.st_size<=0 || info.st_size>4*1024*1024 || access([cookies_ fileSystemRepresentation],R_OK)) return @"Unavailable";
  return @"Imported";
}
- (void)startDownloads;
{ paused_=NO; [self showStatus:@"Ready"]; [self startNext]; }
- (BOOL)isPaused; { return paused_; }
- (NSArray *)rows:(rdapp_query)query playlist:(NSString *)key;
{
  NSMutableArray *rows=[NSMutableArray array];
  [lock_ lock];
  if(!rdapp_store_list(store_,query,identifier(key),collect,rows)) { [status_ release]; status_=[string(rdapp_store_error(store_)) copy]; }
  [lock_ unlock]; return rows;
}
- (NSArray *)playlists; { return [self rows:RDAPP_PLAYLISTS playlist:nil]; }
- (NSArray *)entriesForPlaylist:(NSString *)key; { return [self rows:RDAPP_ENTRIES playlist:key]; }
- (NSArray *)jobsForPlaylist:(NSString *)key completedOnly:(BOOL)completed;
{ return [self rows:completed?RDAPP_DOWNLOADS:RDAPP_JOBS playlist:key]; }
- (void)setPaused:(BOOL)paused;
{
  paused_=paused;
  [lock_ lock]; if(paused && activeJob_) cancel_=YES; [lock_ unlock];
  [self showStatus:paused?@"Queue paused. Active transfers stop and can be retried.":@"Queue resumed"];
  [self startNext];
}
- (void)shutdown;
{ stopping_=YES; [commands_ removeAllObjects]; [lock_ lock]; cancel_=YES; [lock_ unlock]; }
- (BOOL)cancelled;
{ BOOL value; [lock_ lock]; value=cancel_; [lock_ unlock]; return value; }
- (void)progress:(NSString *)phase completed:(uint64_t)completed expected:(uint64_t)expected;
{
  struct timeval t; double now; NSString *message=phase;
  gettimeofday(&t,NULL); now=(double)t.tv_sec+(double)t.tv_usec/1000000.0;
  if(now-lastProgress_<0.25) return;
  lastProgress_=now;
  if(expected) message=[NSString stringWithFormat:@"%@: %.0f%% (%.1f MB)",phase,100.0*(double)completed/(double)expected,(double)completed/1048576.0];
  else if(completed) message=[NSString stringWithFormat:@"%@: %.1f MB",phase,(double)completed/1048576.0];
  [self performSelectorOnMainThread:@selector(showStatus:) withObject:message waitUntilDone:NO];
}
- (void)syncPlaylistInput:(NSString *)input;
{
  input=[input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if(![input length]) { [self showStatus:@"Enter a playlist URL or ID."]; return; }
  if([self isSyncPendingForInput:input]) return;
  [commands_ addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"sync",@"type",input,@"input",nil]]; [self startNext];
}
- (void)syncAll;
{
  NSArray *rows=[self playlists]; unsigned int i;
  for(i=0;i<[rows count];++i) if(![self isSyncPendingForInput:[[rows objectAtIndex:i] objectForKey:@"service_id"]]) [commands_ addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"sync",@"type",[[rows objectAtIndex:i] objectForKey:@"service_id"],@"input",nil]];
  [self startNext];
}
- (void)discoverPlaylists;
{ if([self isDiscoveryPending]) return; [commands_ addObject:[NSDictionary dictionaryWithObject:@"discover" forKey:@"type"]]; [self startNext]; }
- (void)enqueuePlaylist:(NSString *)key video:(NSString *)video format:(NSString *)format;
{
  int ok;
  if(![key length]) { [self showStatus:@"Select a synced playlist first."]; return; }
  if(!rdlp_format_expression_valid([format UTF8String])) { [self showStatus:@"Enter an exact format such as 18 or 136+140."]; return; }
  [lock_ lock]; ok=rdapp_store_enqueue(store_,identifier(key),[video UTF8String],[format UTF8String]);
  NSString *message=ok?@"Added missing downloads. Existing jobs can be retried in Queue.":string(rdapp_store_error(store_));
  [message retain]; [lock_ unlock]; [self showStatus:message]; [message release];
  [self startNext];
}
- (void)retryJob:(NSString *)key;
{
  [lock_ lock]; rdapp_store_reconcile(store_,[root_ fileSystemRepresentation]);
  int ok=rdapp_store_retry(store_,identifier(key)); [lock_ unlock];
  if(ok) { [self changed]; [self startNext]; }
}
- (void)cancelJob:(NSString *)key;
{
  [lock_ lock]; if(activeJob_==identifier(key)) cancel_=YES; else rdapp_store_cancel(store_,identifier(key)); [lock_ unlock]; [self changed];
}
- (NSString *)fileForJob:(NSDictionary *)job;
{
  NSString *relative=[job objectForKey:@"path"];
  if(![relative length] || [relative isAbsolutePath] || [[relative pathComponents] containsObject:@".."]) return nil;
  return [root_ stringByAppendingPathComponent:relative];
}
- (NSString *)playlistFile:(NSDictionary *)playlist;
{ return [[root_ stringByAppendingPathComponent:[playlist objectForKey:@"directory"]] stringByAppendingPathComponent:@"Playlist.m3u8"]; }
- (void)removeDownload:(NSDictionary *)job;
{
  NSString *key=[job objectForKey:@"id"];
  if(busy_) { [self showStatus:@"Pause the queue and wait for the current operation before removing files."]; return; }
  [lock_ lock];
  int ok=rdapp_store_remove_file(store_,identifier(key),[root_ fileSystemRepresentation]);
  NSString *message=[(ok?@"Download removed; playlist membership retained.":string(rdapp_store_error(store_))) retain];
  [lock_ unlock]; [self showStatus:message]; [message release];
}
- (void)removePlaylist:(NSDictionary *)playlist;
{
  if(busy_) { [self showStatus:@"Wait for the current operation before removing a playlist."]; return; }
  [lock_ lock]; int ok=rdapp_store_remove_playlist(store_,identifier([playlist objectForKey:@"id"]),[root_ fileSystemRepresentation]);
  NSString *message=[(ok?@"Playlist removed.":string(rdapp_store_error(store_))) retain]; [lock_ unlock];
  if(ok) { unlink([[self playlistFile:playlist] fileSystemRepresentation]); rmdir([[root_ stringByAppendingPathComponent:[playlist objectForKey:@"directory"]] fileSystemRepresentation]); }
  [self showStatus:message]; [message release];
}
- (BOOL)importCookies:(NSString *)path;
{
  if(busy_) { [self showStatus:@"Wait for the current operation before replacing cookies."]; return NO; }
  NSData *data=[NSData dataWithContentsOfFile:path];
  if(!data || ![data length] || [data length]>4*1024*1024) { [self showStatus:@"Choose a Netscape cookies.txt file smaller than 4 MB."]; return NO; }
  if(![data writeToFile:cookies_ atomically:YES] || chmod([cookies_ fileSystemRepresentation],0600)) { [self showStatus:@"Could not save cookies."]; return NO; }
  [self showStatus:@"Cookies imported. Load My Playlists to discover your account library."]; return YES;
}
- (void)clearCookies;
{
  if(busy_) { [self showStatus:@"Wait for the current operation before removing cookies."]; return; }
  if(unlink([cookies_ fileSystemRepresentation]) && errno!=ENOENT) [self showStatus:@"Could not remove cookies."];
  else [self showStatus:@"Cookies removed."];
}
- (void)startNext;
{
  if(busy_ || stopping_) return;
  NSDictionary *command=nil;
  if([commands_ count]) { command=[[[commands_ objectAtIndex:0] retain] autorelease]; [commands_ removeObjectAtIndex:0]; }
  else if(!paused_) {
    NSMutableArray *rows=[NSMutableArray array];
    [lock_ lock]; int ok=rdapp_store_claim(store_,collect,rows); [lock_ unlock];
    if(!ok) { [self showStatus:@"Could not claim a download job."]; return; }
    if([rows count]) command=[NSDictionary dictionaryWithObjectsAndKeys:@"download",@"type",[rows objectAtIndex:0],@"job",nil];
  }
  if(!command) {
    if(!paused_) queueRun_=NO;
    [self changed]; return;
  }
  if([[command objectForKey:@"type"] isEqualToString:@"download"] && !queueRun_) {
    queueRun_=YES; queueProcessed_=0; queueFailed_=0; queueCancelled_=0;
  }
  [activeCommand_ release]; activeCommand_=[command retain];
  busy_=YES; [lock_ lock]; cancel_=NO; activeJob_=identifier([[command objectForKey:@"job"] objectForKey:@"id"]); [lock_ unlock];
  [self showStatus:@"Starting…"];
  [NSThread detachNewThreadSelector:@selector(work:) toTarget:self withObject:command];
}
- (void)finished:(NSString *)message;
{
  if([[activeCommand_ objectForKey:@"type"] isEqualToString:@"download"]) {
    ++queueProcessed_;
    NSString *key=[[activeCommand_ objectForKey:@"job"] objectForKey:@"id"];
    NSEnumerator *e=[[self jobsForPlaylist:nil completedOnly:NO] objectEnumerator]; NSDictionary *job;
    while((job=[e nextObject])) if([[job objectForKey:@"id"] isEqualToString:key]) {
      if([[job objectForKey:@"state"] isEqualToString:@"failed"]) ++queueFailed_;
      if([[job objectForKey:@"state"] isEqualToString:@"cancelled"] ||
         [[job objectForKey:@"state"] isEqualToString:@"interrupted"]) ++queueCancelled_;
      break;
    }
  }
  [activeCommand_ release]; activeCommand_=nil;
  busy_=NO; [lock_ lock]; activeJob_=0; [lock_ unlock];
  [self showStatus:message];
  [self performSelector:@selector(startNext) withObject:nil afterDelay:0.1];
}
- (void)work:(NSDictionary *)command;
{
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  rdapp_service_config config; rdapp_job job; char message[1024];
  memset(&config,0,sizeof(config)); memset(&job,0,sizeof(job));
  config.download_root=[root_ fileSystemRepresentation];
  config.resolver.struct_size=sizeof(config.resolver);
  config.resolver.ca_bundle_path=[ca_ fileSystemRepresentation];
  config.resolver.ejs_asset_directory=[assets_ fileSystemRepresentation];
  NSString *cache=[support_ stringByAppendingPathComponent:@"cache"];
  config.resolver.cache_directory=[cache fileSystemRepresentation];
  config.resolver.event_callback=event_callback; config.resolver.cancel_callback=cancel_callback;
  config.resolver.callback_context=self;
  config.download.struct_size=sizeof(config.download);
  config.download.ca_bundle_path=[ca_ fileSystemRepresentation];
  config.download.event_callback=download_callback; config.download.cancel_callback=cancel_callback;
  config.download.callback_context=self;
  config.lock=store_lock; config.unlock=store_unlock; config.lock_context=lock_;
  if([[NSFileManager defaultManager] fileExistsAtPath:cookies_]) config.cookie_file=[cookies_ fileSystemRepresentation];
  NSDictionary *row=[command objectForKey:@"job"];
  job.id=identifier([row objectForKey:@"id"]); job.playlist_id=identifier([row objectForKey:@"playlist_id"]);
  job.video_id=[[row objectForKey:@"video_id"] UTF8String]; job.format=[[row objectForKey:@"format"] UTF8String];
  job.relative_path=[[row objectForKey:@"path"] UTF8String];
  NSString *type=[command objectForKey:@"type"];
  rdapp_operation operation=[type isEqualToString:@"sync"]?RDAPP_SYNC:([type isEqualToString:@"discover"]?RDAPP_DISCOVER:RDAPP_DOWNLOAD);
  if(!ca_) {
    snprintf(message,sizeof(message),"The application is missing its CA certificate bundle.");
    if(row) { [lock_ lock]; rdapp_store_finish(store_,job.id,"failed","",message); [lock_ unlock]; }
  } else rdapp_service_run(store_,&config,operation,[[command objectForKey:@"input"] UTF8String],&job,message,sizeof(message));
  [self performSelectorOnMainThread:@selector(finished:) withObject:string(message) waitUntilDone:NO];
  [pool drain];
}
@end
