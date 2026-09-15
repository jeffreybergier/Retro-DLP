#import "RDLPLibrary.h"
#import <CoreFoundation/CoreFoundation.h>
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
NSString * const RDLPLibraryStatusDidChange = @"RetroDLPLibraryStatusDidChange";
NSString * const RDLPLibraryErrorDidOccur = @"RetroDLPLibraryErrorDidOccur";
static NSString *string(const char *s) { NSString *v=s?[NSString stringWithUTF8String:s]:nil; return v?v:@""; }
static long long identifier(NSString *value) { return value?strtoll([value UTF8String],NULL,10):0; }
static int collect(void *context,int count,const char *const *names,const char *const *values) {
  NSMutableDictionary *row=[NSMutableDictionary dictionary]; int i;
  for(i=0;i<count;++i) [row setObject:string(values[i]) forKey:string(names[i])];
  [(NSMutableArray *)context addObject:row]; return 1;
}
@interface RDLPLibrary (ReadErrors)
- (void)reportError:(NSString *)title detail:(NSString *)detail;
@end
@interface RDLPLibraryRows (Private)
- (id)initWithLibrary:(RDLPLibrary *)library path:(NSString *)path query:(rdapp_query)query key:(NSString *)key video:(NSString *)video format:(NSString *)format;
@end
@implementation RDLPLibraryRows
- (id)initWithLibrary:(RDLPLibrary *)library path:(NSString *)path query:(rdapp_query)query key:(NSString *)key video:(NSString *)video format:(NSString *)format;
{
  self=[super init]; if(!self) return nil;
  owner_=[library retain]; query_=(int)query; key_=identifier(key); video_=[video copy]; format_=[format copy];
  cache_=[[NSMutableDictionary alloc] init]; int64_t count=0;
  if(!rdapp_store_open_reader([path fileSystemRepresentation],(rdapp_store **)&reader_) ||
     !rdapp_store_count(reader_,query,key_,[video UTF8String],[format UTF8String],&count)) { [self release]; return nil; }
  count_=(NSUInteger)count; lastIndex_=NSNotFound; return self;
}
- (void)dealloc;
{ rdapp_store_close(reader_); [owner_ release]; [video_ release]; [format_ release]; [cache_ release]; [super dealloc]; }
- (NSUInteger)count; { return count_; }
- (id)copyWithZone:(NSZone *)zone; { (void)zone; return [self retain]; }
- (id)objectAtIndex:(NSUInteger)index;
{
  if(index>=count_) [NSException raise:NSRangeException format:@"Library row %lu outside %lu rows",(unsigned long)index,(unsigned long)count_];
  NSNumber *key=[NSNumber numberWithUnsignedLong:index];
  NSDictionary *row=[cache_ objectForKey:key];
  if(!row) {
    NSMutableArray *rows=[NSMutableArray array];
    BOOL seek=lastIndex_!=NSNotFound && index==lastIndex_+1 &&
      query_!=RDAPP_PLAYLISTS && query_!=RDAPP_ADDED_PLAYLISTS && query_!=RDAPP_ACCOUNT_PLAYLISTS && query_!=RDAPP_PLAYLIST && query_!=RDAPP_PLAYLIST_INPUT && query_!=RDAPP_ADDED_IDS && query_!=RDAPP_ACCOUNT_IDS;
    int ok=seek?rdapp_store_after(reader_,(rdapp_query)query_,key_,[video_ UTF8String],[format_ UTF8String],lastIdentity_,collect,rows):
      rdapp_store_page(reader_,(rdapp_query)query_,key_,[video_ UTF8String],[format_ UTF8String],(int64_t)index,1,collect,rows);
    if(!ok && !readFailed_) {
      readFailed_=YES;
      [owner_ reportError:@"Couldn’t read library" detail:string(rdapp_store_error(reader_))];
    }
    row=[rows count]?[rows objectAtIndex:0]:[NSDictionary dictionary];
    /* Retain only a small working set, even after scrolling through a huge list. */
    if([cache_ count]>=128) [cache_ removeAllObjects];
    [cache_ setObject:row forKey:key];
  }
  lastIndex_=index; lastIdentity_=identifier([row objectForKey:(query_==RDAPP_ENTRIES || query_==RDAPP_VIDEO_ENTRIES || query_==RDAPP_MISSING || query_==RDAPP_DOWNLOAD_CANDIDATES)?@"position":@"id"]);
  return [[row retain] autorelease];
}
- (id)cachedObjectAtIndex:(NSUInteger)index;
{ return [cache_ objectForKey:[NSNumber numberWithUnsignedLong:index]]; }
- (NSDictionary *)playlistForID:(NSString *)key;
{
  if(!key) return nil;
  NSMutableArray *rows=[NSMutableArray array];
  if(!rdapp_store_page(reader_,RDAPP_PLAYLIST,identifier(key),NULL,NULL,0,1,collect,rows)) return nil;
  return [rows count]?[rows objectAtIndex:0]:nil;
}
- (NSUInteger)indexForIdentity:(NSString *)identity;
{
  int64_t index=-1;
  if(!identity) return NSNotFound;
  if(!rdapp_store_index(reader_,(rdapp_query)query_,key_,identifier(identity),&index)) return NSNotFound;
  return index<0?NSNotFound:(NSUInteger)index;
}
@end
@interface RDLPLibrary (Private)
- (void)startNext;
- (void)work:(NSDictionary *)command;
- (void)finished:(NSDictionary *)result;
- (void)changed;
- (void)showStatus:(NSString *)message;
- (BOOL)cancelled;
- (void)reportError:(NSString *)title detail:(NSString *)detail;
- (void)clearStatus;
- (void)displayProgress:(NSDictionary *)progress;
- (void)resolverEvent:(rdlp_event_type)type;
- (void)queuePlaylistInput:(NSString *)input adding:(BOOL)adding;
- (void)progress:(NSString *)phase completed:(uint64_t)completed expected:(uint64_t)expected;
@end
static void store_lock(void *context) { [(NSLock *)context lock]; }
static void store_unlock(void *context) { [(NSLock *)context unlock]; }
static int cancel_callback(void *context) { return [(RDLPLibrary *)context cancelled]?1:0; }
static void event_callback(const rdlp_event *event,void *context) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  if(event) [(RDLPLibrary *)context resolverEvent:event->type];
  [pool drain];
}
static void service_status(const char *message,void *context) {
  [(RDLPLibrary *)context progress:string(message) completed:0 expected:0];
}
static void download_callback(const rdlp_download_event *event,void *context) {
  NSString *phase;
  if(!event) return;
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  switch(event->type) {
    case RDLP_DOWNLOAD_EVENT_DOWNLOADING_AUDIO: phase=@"Downloading audio"; break;
    case RDLP_DOWNLOAD_EVENT_DOWNLOADING_VIDEO: phase=@"Downloading video"; break;
    case RDLP_DOWNLOAD_EVENT_DOWNLOADING_MEDIA: phase=@"Downloading"; break;
    case RDLP_DOWNLOAD_EVENT_MUXING: phase=@"Combining audio and video…"; break;
    case RDLP_DOWNLOAD_EVENT_CLEANING_UP: phase=@"Finishing download…"; break;
    default: phase=@"Downloading"; break;
  }
  [(RDLPLibrary *)context progress:phase completed:event->completed_bytes expected:event->expected_bytes];
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
  support_=[support copy]; root_=[root copy]; lock_=[[NSLock alloc] init]; cancelLock_=[[NSLock alloc] init]; commands_=[[NSMutableArray alloc] init];
  cookies_=[[support stringByAppendingPathComponent:@"cookies.txt"] copy];
  ca_=[[[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"] copy];
  assets_=[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"ejs"];
  if(![[NSFileManager defaultManager] fileExistsAtPath:[assets_ stringByAppendingPathComponent:@"core.min.js"]])
    assets_=[support stringByAppendingPathComponent:@"ejs"];
  assets_=[assets_ copy]; status_=[@"" copy]; errors_=[[NSMutableArray alloc] init];
  if(!rdapp_make_directory([support fileSystemRepresentation]) || !rdapp_make_directory([root fileSystemRepresentation]) ||
     !rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],(rdapp_store **)&store_)) {
    [self release]; return nil;
  }
  chmod([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],0600);
  paused_=YES;
  [commands_ addObject:[NSDictionary dictionaryWithObject:@"reconcile" forKey:@"type"]];
  [self performSelector:@selector(startNext) withObject:nil afterDelay:0];
  return self;
}
- (void)dealloc;
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [lastPhase_ release]; [lastReadError_ release]; [errors_ release];
  rdapp_store_close(store_); [lock_ release]; [cancelLock_ release]; [commands_ release]; [activeCommand_ release]; [support_ release]; [root_ release];
  [ca_ release]; [assets_ release]; [cookies_ release]; [status_ release]; [super dealloc];
}
- (void)changed; { [[NSNotificationCenter defaultCenter] postNotificationName:RDLPLibraryDidChange object:self]; }
- (void)showStatus:(NSString *)message;
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(clearStatus) object:nil];
  NSString *next=[(message?message:@"") copy]; [status_ release]; status_=next;
  if([status_ length] && !stopping_)
    [self performSelector:@selector(clearStatus) withObject:nil afterDelay:10
                 inModes:[NSArray arrayWithObject:(NSString *)kCFRunLoopCommonModes]];
  [[NSNotificationCenter defaultCenter] postNotificationName:RDLPLibraryStatusDidChange object:self];
}
- (void)clearStatus;
{ transferCompleted_=0; transferExpected_=0; [self showStatus:@""]; }
- (NSString *)status; { return status_; }
- (NSDictionary *)activityProgress;
{
  return [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithBool:busy_ && [status_ length]>0],@"active",
    [NSNumber numberWithUnsignedLongLong:transferCompleted_],@"completed",
    [NSNumber numberWithUnsignedLongLong:transferExpected_],@"expected",nil];
}
- (void)reportError:(NSString *)title detail:(NSString *)detail;
{
  NSDictionary *error=[NSDictionary dictionaryWithObjectsAndKeys:title,@"title",detail?detail:@"",@"detail",nil];
  if(![errors_ containsObject:error]) [errors_ addObject:error];
  [[NSNotificationCenter defaultCenter] postNotificationName:RDLPLibraryErrorDidOccur object:self];
}
- (NSDictionary *)takeError;
{
  if(![errors_ count]) return nil;
  NSDictionary *error=[[[errors_ objectAtIndex:0] retain] autorelease];
  [errors_ removeObjectAtIndex:0]; return error;
}
- (BOOL)hasErrors; { return [errors_ count]>0; }
- (BOOL)isBusy; { return busy_; }
- (NSDictionary *)queueProgress;
{
  NSUInteger pending=[self queuedCount], running=0;
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
{ paused_=NO; [self startNext]; }
- (BOOL)isPaused; { return paused_; }
- (RDLPLibraryRows *)rows:(rdapp_query)query playlist:(NSString *)key video:(NSString *)video format:(NSString *)format;
{
  RDLPLibraryRows *rows=[[[RDLPLibraryRows alloc] initWithLibrary:self path:[support_ stringByAppendingPathComponent:@"retrodlp.sqlite"] query:query key:key video:video format:format] autorelease];
  if(!rows && !lastReadError_) {
    lastReadError_=[@"Could not open a library read snapshot." copy];
    [self reportError:@"Couldn’t read library" detail:lastReadError_];
  } else if(rows) { [lastReadError_ release]; lastReadError_=nil; }
  return rows;
}
- (NSArray *)rows:(rdapp_query)query playlist:(NSString *)key;
{ return [self rows:query playlist:key video:nil format:nil]; }
- (NSArray *)playlists; { return [self rows:RDAPP_PLAYLISTS playlist:nil]; }
- (NSArray *)playlistsFromAccount:(BOOL)account;
{ return [self rows:account?RDAPP_ACCOUNT_PLAYLISTS:RDAPP_ADDED_PLAYLISTS playlist:nil]; }
- (NSDictionary *)playlistForID:(NSString *)key;
{ NSArray *rows=key?[self rows:RDAPP_PLAYLIST playlist:key]:nil; return [rows count]?[rows objectAtIndex:0]:nil; }
- (NSArray *)playlistIDsFromAccount:(BOOL)account;
{ return [self rows:account?RDAPP_ACCOUNT_IDS:RDAPP_ADDED_IDS playlist:nil]; }
- (NSDictionary *)jobForID:(NSString *)key;
{ NSArray *rows=key?[self rows:RDAPP_JOB playlist:key]:nil; return [rows count]?[rows objectAtIndex:0]:nil; }
- (NSArray *)jobsForPlaylist:(NSString *)key video:(NSString *)video;
{ return key && video?[self rows:RDAPP_VIDEO_JOBS playlist:key video:video format:nil]:[NSArray array]; }
- (NSDictionary *)jobForPlaylist:(NSString *)key video:(NSString *)video format:(NSString *)format;
{
  NSArray *rows=key && video && format?[self rows:RDAPP_VIDEO_JOBS playlist:key video:video format:format]:nil;
  return [rows count]?[rows objectAtIndex:0]:nil;
}
- (BOOL)playlist:(NSString *)key containsVideo:(NSString *)video;
{ return [[self rows:RDAPP_VIDEO_ENTRIES playlist:key video:video format:nil] count]>0; }
- (NSArray *)entriesForPlaylist:(NSString *)key; { return [self rows:RDAPP_ENTRIES playlist:key]; }
- (NSArray *)jobsForPlaylist:(NSString *)key completedOnly:(BOOL)completed;
{ return [self rows:completed?RDAPP_DOWNLOADS:RDAPP_JOBS playlist:key]; }
- (RDLPLibraryRows *)queueRows;
{ return [self rows:RDAPP_QUEUE playlist:nil video:nil format:nil]; }
- (NSUInteger)queuedCount; { return [[self rows:RDAPP_PENDING playlist:nil] count]; }
- (BOOL)hasBlockingJobsForPlaylist:(NSString *)key;
{ return [[self rows:RDAPP_BLOCKING_JOBS playlist:key] count]>0; }
- (BOOL)hasPlaylistsToSync;
{
  NSUInteger total=[[self playlists] count];
  if(!total) return NO;
  NSMutableSet *pending=[NSMutableSet set];
  if([[activeCommand_ objectForKey:@"type"] isEqualToString:@"sync"])
    [pending addObject:[activeCommand_ objectForKey:@"input"]];
  NSEnumerator *e=[commands_ objectEnumerator]; NSDictionary *command;
  while((command=[e nextObject])) if([[command objectForKey:@"type"] isEqualToString:@"sync"])
    [pending addObject:[command objectForKey:@"input"]];
  if(total>[pending count]) return YES;
  NSUInteger matched=0; e=[pending objectEnumerator]; NSString *input;
  while((input=[e nextObject]))
    matched+=[[self rows:RDAPP_PLAYLIST_INPUT playlist:nil video:input format:nil] count];
  return total>matched;
}
- (BOOL)hasMissingEntriesForPlaylist:(NSString *)key format:(NSString *)format;
{ return [[self rows:RDAPP_MISSING playlist:key video:nil format:format] count]>0; }
- (NSArray *)missingPlanForPlaylist:(NSString *)key format:(NSString *)format;
{
  NSMutableArray *plan=[NSMutableArray array];
  NSArray *candidates=[self rows:RDAPP_DOWNLOAD_CANDIDATES playlist:key video:nil format:format];
  NSEnumerator *e=[candidates objectEnumerator];
  for(;;) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    NSDictionary *entry=[e nextObject];
    if(!entry) { [pool drain]; break; }
    NSString *path=[self fileForJob:entry];
    BOOL exists=[[entry objectForKey:@"state"] isEqualToString:@"complete"] && path &&
      [[NSFileManager defaultManager] fileExistsAtPath:path];
    if(!exists) {
      NSMutableDictionary *item=[NSMutableDictionary dictionaryWithObjectsAndKeys:key,@"playlist",[entry objectForKey:@"video_id"],@"video",format,@"format",nil];
      if([[entry objectForKey:@"job_id"] length]) [item setObject:[entry objectForKey:@"job_id"] forKey:@"job"];
      [plan addObject:item];
    }
    [pool drain];
  }
  return plan;
}
- (void)setPaused:(BOOL)paused;
{
  paused_=paused;
  [cancelLock_ lock]; if(paused && activeJob_) cancel_=YES; [cancelLock_ unlock];
  [self changed];
  [self startNext];
}
- (void)shutdown;
{ stopping_=YES; [NSObject cancelPreviousPerformRequestsWithTarget:self]; [commands_ removeAllObjects]; [cancelLock_ lock]; cancel_=YES; [cancelLock_ unlock]; }
- (BOOL)cancelled;
{ BOOL value; [cancelLock_ lock]; value=cancel_; [cancelLock_ unlock]; return value; }
- (void)resolverEvent:(rdlp_event_type)type;
{
  NSString *command=[activeCommand_ objectForKey:@"type"], *phase=nil;
  if(![command isEqualToString:@"download"]) {
    phase=[command isEqualToString:@"discover"]?@"Loading playlists…":
      ([[activeCommand_ objectForKey:@"adding"] boolValue]?@"Adding playlist…":@"Syncing playlist…");
  } else switch(type) {
    case RDLP_EVENT_AUTHENTICATING: phase=@"Reading cookies…"; break;
    case RDLP_EVENT_LOADING_CONFIGURATION: phase=@"Configuring client…"; break;
    case RDLP_EVENT_FETCHING_BOOTSTRAP: phase=@"Loading mobile player…"; break;
    case RDLP_EVENT_REQUESTING_METADATA: phase=@"Requesting metadata…"; break;
    case RDLP_EVENT_REFRESHING_METADATA: phase=@"Refreshing visitor data…"; break;
    case RDLP_EVENT_SELECTING_FORMATS: phase=@"Selecting format…"; break;
    case RDLP_EVENT_LOADING_PLAYER_JAVASCRIPT: phase=@"Downloading player script…"; break;
    case RDLP_EVENT_SOLVING_CHALLENGES: phase=@"Solving challenges…"; break;
    case RDLP_EVENT_ENUMERATING_PLAYLIST: phase=@"Reading playlist…"; break;
    case RDLP_EVENT_OTHER: return;
  }
  if(phase) [self progress:phase completed:0 expected:0];
}
- (void)progress:(NSString *)phase completed:(uint64_t)completed expected:(uint64_t)expected;
{
  struct timeval t; gettimeofday(&t,NULL);
  double now=(double)t.tv_sec+(double)t.tv_usec/1000000.0;
  BOOL changed=![phase isEqualToString:lastPhase_];
  if(changed) { [lastPhase_ release]; lastPhase_=[phase copy]; transferStarted_=now; }
  /* Only repeated byte ticks are throttled. Every new CLI phase is delivered. */
  if(!changed && completed && now-lastProgress_<0.25 && (!expected || completed<expected)) return;
  lastProgress_=now;
  NSString *message=phase;
  if(completed || expected) {
    double elapsed=now-transferStarted_;
    NSString *speed=elapsed>0?[NSString stringWithFormat:@" · %.1f Mbps",(double)completed*8.0/elapsed/1000000.0]:@"";
    message=expected?[NSString stringWithFormat:@"%@ · %.0f%%%@",phase,MIN(100.0,100.0*(double)completed/(double)expected),speed]:
      [NSString stringWithFormat:@"%@%@",phase,speed];
  }
  NSDictionary *update=[NSDictionary dictionaryWithObjectsAndKeys:message,@"message",
    [NSNumber numberWithUnsignedLongLong:completed],@"completed",
    [NSNumber numberWithUnsignedLongLong:expected],@"expected",nil];
  [self performSelectorOnMainThread:@selector(displayProgress:) withObject:update waitUntilDone:NO];
}
- (void)displayProgress:(NSDictionary *)progress;
{
  if(stopping_) return;
  transferCompleted_=[[progress objectForKey:@"completed"] unsignedLongLongValue];
  transferExpected_=[[progress objectForKey:@"expected"] unsignedLongLongValue];
  [self showStatus:[progress objectForKey:@"message"]];
}
- (void)addPlaylistInput:(NSString *)input;
{ [self queuePlaylistInput:input adding:YES]; }
- (void)syncPlaylistInput:(NSString *)input;
{ [self queuePlaylistInput:input adding:NO]; }
- (void)queuePlaylistInput:(NSString *)input adding:(BOOL)adding;
{
  input=[input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if(![input length]) { [self reportError:@"Enter a playlist" detail:@"Enter a playlist URL or ID."]; return; }
  if([self isSyncPendingForInput:input]) return;
  [commands_ addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"sync",@"type",input,@"input",
    [NSNumber numberWithBool:adding],@"adding",nil]]; [self startNext];
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
  if(![key length]) { [self reportError:@"Select a playlist" detail:@"Select a synced playlist first."]; return; }
  if(!rdlp_format_expression_valid([format UTF8String])) { [self reportError:@"Invalid format" detail:@"Enter a format ID, such as 18 or 136+140."]; return; }
  [lock_ lock]; ok=rdapp_store_enqueue(store_,identifier(key),[video UTF8String],[format UTF8String]);
  NSString *error=ok?nil:[string(rdapp_store_error(store_)) copy];
  [lock_ unlock];
  if(error) [self reportError:@"Couldn’t queue download" detail:error];
  [error release]; [self changed];
  [self startNext];
}
- (void)retryJob:(NSString *)key;
{
  [lock_ lock];
  int ok=rdapp_store_reconcile_job(store_,identifier(key),[root_ fileSystemRepresentation]) && rdapp_store_retry(store_,identifier(key));
  NSString *error=ok?nil:[string(rdapp_store_error(store_)) copy]; [lock_ unlock];
  if(ok) { [self changed]; [self startNext]; }
  else [self reportError:@"Couldn’t retry download" detail:error];
  [error release];
}
- (void)cancelJob:(NSString *)key;
{
  NSString *error=nil;
  if(activeJob_==identifier(key)) {
    [cancelLock_ lock]; cancel_=YES; [cancelLock_ unlock];
  } else {
    [lock_ lock];
    if(!rdapp_store_cancel(store_,identifier(key))) error=[string(rdapp_store_error(store_)) copy];
    [lock_ unlock];
  }
  if(error) [self reportError:@"Couldn’t stop download" detail:error];
  [error release]; [self changed];
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
  if(busy_) { [self reportError:@"Couldn’t delete download" detail:@"Wait for the current operation to finish."]; return; }
  [lock_ lock];
  int ok=rdapp_store_remove_file(store_,identifier(key),[root_ fileSystemRepresentation]);
  NSString *error=ok?nil:[string(rdapp_store_error(store_)) copy];
  [lock_ unlock]; if(error) [self reportError:@"Couldn’t delete download" detail:error]; [error release]; [self changed];
}
- (void)removePlaylist:(NSDictionary *)playlist;
{
  if(busy_) { [self reportError:@"Couldn’t remove playlist" detail:@"Wait for the current operation to finish."]; return; }
  [lock_ lock]; int ok=rdapp_store_remove_playlist(store_,identifier([playlist objectForKey:@"id"]),[root_ fileSystemRepresentation]);
  NSString *error=ok?nil:[string(rdapp_store_error(store_)) copy]; [lock_ unlock];
  if(ok) { unlink([[self playlistFile:playlist] fileSystemRepresentation]); rmdir([[root_ stringByAppendingPathComponent:[playlist objectForKey:@"directory"]] fileSystemRepresentation]); }
  if(error) [self reportError:@"Couldn’t remove playlist" detail:error]; [error release]; [self changed];
}
- (BOOL)importCookies:(NSString *)path;
{
  if(busy_) { [self reportError:@"Couldn’t import cookies" detail:@"Wait for the current operation to finish."]; return NO; }
  NSData *data=[NSData dataWithContentsOfFile:path];
  if(!data || ![data length] || [data length]>4*1024*1024) { [self reportError:@"Couldn’t import cookies" detail:@"Choose a readable, nonempty Netscape cookies.txt file of 4 MiB or less."]; return NO; }
  if(![data writeToFile:cookies_ atomically:YES] || chmod([cookies_ fileSystemRepresentation],0600)) { [self reportError:@"Couldn’t save cookies" detail:@"Check available storage and try again."]; return NO; }
  [self changed]; return YES;
}
- (void)clearCookies;
{
  if(busy_) { [self reportError:@"Couldn’t remove cookies" detail:@"Wait for the current operation to finish."]; return; }
  if(unlink([cookies_ fileSystemRepresentation]) && errno!=ENOENT) [self reportError:@"Couldn’t remove cookies" detail:string(strerror(errno))];
  else [self changed];
}
- (void)startNext;
{
  if(busy_ || stopping_) return;
  NSDictionary *command=nil;
  if([commands_ count]) { command=[[[commands_ objectAtIndex:0] retain] autorelease]; [commands_ removeObjectAtIndex:0]; }
  else if(!paused_) {
    NSMutableArray *rows=[NSMutableArray array];
    [lock_ lock]; int ok=rdapp_store_claim(store_,collect,rows); [lock_ unlock];
    if(!ok) { [self reportError:@"Couldn’t start download" detail:string(rdapp_store_error(store_))]; return; }
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
  busy_=YES; [cancelLock_ lock]; cancel_=NO; [cancelLock_ unlock];
  activeJob_=identifier([[command objectForKey:@"job"] objectForKey:@"id"]);
  transferCompleted_=0; transferExpected_=0; lastProgress_=0;
  [lastPhase_ release]; lastPhase_=nil;
  NSString *type=[command objectForKey:@"type"];
  if(![type isEqualToString:@"reconcile"]) [self showStatus:[type isEqualToString:@"download"]?@"Resolving video…":
    ([type isEqualToString:@"discover"]?@"Loading playlists…":([[command objectForKey:@"adding"] boolValue]?@"Adding playlist…":@"Syncing playlist…"))];
  [self changed];
  [NSThread detachNewThreadSelector:@selector(work:) toTarget:self withObject:command];
}
- (void)finished:(NSDictionary *)result;
{
  if([[activeCommand_ objectForKey:@"type"] isEqualToString:@"reconcile"]) {
    [activeCommand_ release]; activeCommand_=nil; busy_=NO;
    if([[result objectForKey:@"code"] intValue]!=RDLP_OK)
      [self reportError:@"Couldn’t read library" detail:[result objectForKey:@"message"]];
    if(!stopping_) { [self changed]; [self performSelector:@selector(startNext) withObject:nil afterDelay:0]; }
    return;
  }
  if([[activeCommand_ objectForKey:@"type"] isEqualToString:@"download"]) {
    ++queueProcessed_;
    NSString *key=[[activeCommand_ objectForKey:@"job"] objectForKey:@"id"];
    NSDictionary *job=[self jobForID:key];
    if([[job objectForKey:@"state"] isEqualToString:@"failed"]) ++queueFailed_;
    if([[job objectForKey:@"state"] isEqualToString:@"cancelled"] ||
       [[job objectForKey:@"state"] isEqualToString:@"interrupted"]) ++queueCancelled_;
  }
  NSString *type=[activeCommand_ objectForKey:@"type"];
  BOOL download=[type isEqualToString:@"download"], discover=[type isEqualToString:@"discover"];
  BOOL adding=[[activeCommand_ objectForKey:@"adding"] boolValue];
  rdlp_error_code code=(rdlp_error_code)[[result objectForKey:@"code"] intValue];
  NSString *status=download?@"Download complete":(discover?@"Playlists loaded":(adding?@"Playlist added":@"Playlist synced"));
  if(download && code==RDLP_OK) status=[NSString stringWithFormat:@"Downloaded · %.1f MiB",[[result objectForKey:@"bytes"] doubleValue]/1048576.0];
  if(code==RDLP_ERROR_CANCELLED) status=download?@"Download stopped":@"Playlist operation stopped";
  else if(code!=RDLP_OK) status=download?@"Download failed":(discover?@"Error loading playlists":(adding?@"Error adding playlist":@"Error syncing playlist"));
  BOOL warning=[[result objectForKey:@"warning"] boolValue];
  if(warning) status=@"Download needs attention";
  if((code!=RDLP_OK && code!=RDLP_ERROR_CANCELLED) || warning) {
    NSString *title=download?[[activeCommand_ objectForKey:@"job"] objectForKey:@"title"]:[activeCommand_ objectForKey:@"input"];
    NSString *detail=[result objectForKey:@"message"];
    if([title length]) detail=[NSString stringWithFormat:@"%@\n\n%@",title,detail];
    [self reportError:status detail:detail];
  }
  [activeCommand_ release]; activeCommand_=nil;
  busy_=NO; transferCompleted_=0; transferExpected_=0;
  activeJob_=0;
  if(!stopping_) { [self showStatus:status]; [self changed];
    [self performSelector:@selector(startNext) withObject:nil afterDelay:0.1]; }

}
- (void)work:(NSDictionary *)command;
{
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  if([[command objectForKey:@"type"] isEqualToString:@"reconcile"]) {
    [lock_ lock]; BOOL ok=rdapp_store_reconcile(store_,[root_ fileSystemRepresentation])!=0;
    NSString *message=ok?@"":[NSString stringWithUTF8String:rdapp_store_error(store_)];
    NSDictionary *result=[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:ok?RDLP_OK:RDLP_ERROR_STORAGE_IO],@"code",message,@"message",nil];
    [lock_ unlock];
    [self performSelectorOnMainThread:@selector(finished:) withObject:result waitUntilDone:NO];
    [pool drain]; return;
  }
  rdapp_service_config config; rdapp_service_result outcome; rdapp_job job; char message[1024];
  rdlp_error_code code=RDLP_OK; memset(&outcome,0,sizeof(outcome));
  memset(&config,0,sizeof(config)); memset(&job,0,sizeof(job));
  config.download_root=[root_ fileSystemRepresentation];
  config.result=&outcome; config.status_callback=service_status; config.status_context=self;
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
    code=RDLP_ERROR_CERTIFICATE_BUNDLE;
    snprintf(message,sizeof(message),"The application is missing its CA certificate bundle.");
    if(row) { [lock_ lock]; rdapp_store_finish(store_,job.id,"failed","",message); [lock_ unlock]; }
  } else code=rdapp_service_run(store_,&config,operation,[[command objectForKey:@"input"] UTF8String],&job,message,sizeof(message));
  NSDictionary *result=[NSDictionary dictionaryWithObjectsAndKeys:string(message),@"message",
    [NSNumber numberWithInt:code],@"code",[NSNumber numberWithBool:outcome.warning!=0],@"warning",
    [NSNumber numberWithUnsignedLongLong:outcome.downloaded_bytes],@"bytes",nil];
  [self performSelectorOnMainThread:@selector(finished:) withObject:result waitUntilDone:NO];
  [pool drain];
}
@end
