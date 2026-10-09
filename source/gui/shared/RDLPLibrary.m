#import "RDLPLibrary.h"
#import "RDLPLibrary+Platform.h"
#import "RDLP_Foundation.h"
#import <CoreFoundation/CoreFoundation.h>
#import <TargetConditionals.h>
#include "rdapp_store.h"
#include "rdapp_service.h"
#include "rdapp_strings.h"
#include <retrodlp/retrodlp.h>
#include <retrodlp/download.h>
#include <retrodlp/assets.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>

NSString * const RDLPLibraryDidChange = @"RetroDLPLibraryDidChange";
NSString * const RDLPLibraryStatusDidChange = @"RetroDLPLibraryStatusDidChange";
NSString * const RDLPLibraryErrorDidOccur = @"RetroDLPLibraryErrorDidOccur";
NSString * const RDLPLibraryActivityDidChange = @"RetroDLPLibraryActivityDidChange";
NSString * const RDLPLibraryDownloadDidComplete = @"RetroDLPLibraryDownloadDidComplete";
static NSString *string(const char *s) { NSString *v=s?[NSString stringWithUTF8String:s]:nil; return v?v:@""; }
static const char *localized_c_string(const char *key,void *context) {
  (void)context;
  return [NSLocalizedString(string(key), nil) UTF8String];
}
static long long identifier(NSString *value) { return value?strtoll([value UTF8String],NULL,10):0; }
static const char *remove_download_file(void *context,const char *path) {
  return [[(RDLPLibrary *)context removeDownloadFileAtPath:string(path)] UTF8String];
}
static BOOL entry_number(NSDictionary *entry,NSString *key,unsigned long long *value) {
  NSString *text=[entry objectForKey:key];
  if(![text length]) return NO;
  const char *start=[text UTF8String]; char *end=NULL;
  if(!start || start[0]<'0' || start[0]>'9') return NO;
  unsigned long long number=strtoull(start,&end,10);
  if(*end || number>9007199254740991ULL) return NO;
  *value=number; return YES;
}
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
      query_!=RDAPP_PLAYLISTS && query_!=RDAPP_ADDED_PLAYLISTS && query_!=RDAPP_ACCOUNT_PLAYLISTS && query_!=RDAPP_PLAYLIST && query_!=RDAPP_PLAYLIST_INPUT && query_!=RDAPP_ADDED_IDS && query_!=RDAPP_ACCOUNT_IDS && query_!=RDAPP_UNSUPPORTED_IDS && query_!=RDAPP_UNSUPPORTED_PLAYLISTS;
    int ok=seek?rdapp_store_after(reader_,(rdapp_query)query_,key_,[video_ UTF8String],[format_ UTF8String],lastIdentity_,collect,rows):
      rdapp_store_page(reader_,(rdapp_query)query_,key_,[video_ UTF8String],[format_ UTF8String],(int64_t)index,1,collect,rows);
    if(!ok && !readFailed_) {
      readFailed_=YES;
      [owner_ reportError:NSLocalizedString(@"Couldn’t read library", nil) detail:string(rdapp_store_error(reader_))];
    }
    row=[rows count]?[rows objectAtIndex:0]:[NSDictionary dictionary];
    /* Retain only a small working set, even after scrolling through a huge list. */
    if([cache_ count]>=128) [cache_ removeAllObjects];
    [cache_ setObject:row forKey:key];
  }
  lastIndex_=index; lastIdentity_=identifier([row objectForKey:(query_==RDAPP_ENTRIES || query_==RDAPP_ADDED_VIDEOS || query_==RDAPP_VIDEO_ENTRIES || query_==RDAPP_MISSING || query_==RDAPP_DOWNLOAD_CANDIDATES)?@"position":@"id"]);
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
- (NSUInteger)rowsSinceDate:(NSDate *)date;
{
  int64_t count=0;
  int64_t timestamp=(int64_t)[date timeIntervalSince1970];
  int ok=query_==RDAPP_ADDED_VIDEOS?rdapp_store_added_videos_since(reader_,key_,timestamp,&count):
    (query_==RDAPP_ALL_DOWNLOADS && rdapp_store_downloads_since(reader_,timestamp,&count));
  if(!ok) [owner_ reportError:NSLocalizedString(@"Couldn’t read date sections", nil) detail:string(rdapp_store_error(reader_))];
  return (NSUInteger)count;
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
- (void)beginOperation;
- (void)endOperation;
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
- (void)queueVideoInput:(NSString *)input;
- (void)progress:(NSString *)phase completed:(uint64_t)completed expected:(uint64_t)expected;
- (void)progress:(NSString *)phase completed:(uint64_t)completed expected:(uint64_t)expected
  step:(NSUInteger)step total:(NSUInteger)total;
@end
static void store_lock(void *context) { [(NSLock *)context lock]; }
static void store_unlock(void *context) { [(NSLock *)context unlock]; }
static int cancel_callback(void *context) { return [(RDLPLibrary *)context cancelled]?1:0; }
static void event_callback(const rdlp_event *event,void *context) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  if(event) [(RDLPLibrary *)context resolverEvent:event->type];
  [pool drain];
}
static void service_changed(void *context) {
  [(RDLPLibrary *)context performSelectorOnMainThread:@selector(changed) withObject:nil waitUntilDone:NO];
}
static void download_callback(const rdlp_download_event *event,void *context) {
  NSString *phase;
  NSUInteger step=0;
  if(!event) return;
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  switch(event->type) {
    case RDLP_DOWNLOAD_EVENT_DOWNLOADING_AUDIO: phase=NSLocalizedString(@"Downloading audio", nil); break;
    case RDLP_DOWNLOAD_EVENT_DOWNLOADING_VIDEO: phase=NSLocalizedString(@"Downloading video", nil); break;
    case RDLP_DOWNLOAD_EVENT_DOWNLOADING_MEDIA: phase=NSLocalizedString(@"Downloading", nil); break;
    case RDLP_DOWNLOAD_EVENT_MUXING: step=9; phase=NSLocalizedString(@"Combining audio and video…", nil); break;
    case RDLP_DOWNLOAD_EVENT_CLEANING_UP: step=10; phase=NSLocalizedString(@"Finishing download…", nil); break;
    default: phase=NSLocalizedString(@"Downloading", nil); break;
  }
  [(RDLPLibrary *)context progress:phase completed:event->completed_bytes expected:event->expected_bytes step:step total:10];
  [pool drain];
}
@implementation RDLPLibrary
+ (void)initialize;
{
  if(self==[RDLPLibrary class]) {
    /* Objective-C serializes +initialize before any library instance or worker.
       C copies the UTF-8 bytes and retains them for the process lifetime. */
    if(!rdapp_strings_initialize(localized_c_string,NULL))
      NSLog(@"Could not initialize C UI strings; using English defaults.");
  }
}
+ (NSArray *)qualityTitles;
{
  NSMutableArray *titles=[NSMutableArray array];
  NSEnumerator *formats=[[self qualityFormats] objectEnumerator]; NSString *format;
  while((format=[formats nextObject])) [titles addObject:[self qualityLabelForFormat:format]];
  [titles addObject:NSLocalizedString(@"Custom Format…", nil)];
  return titles;
}
+ (NSArray *)qualityFormats;
{
  if(RDLP_isIOSApp())
    return [NSArray arrayWithObjects:@"18",@"136+140/135+140/18",@"137+140/136+140/135+140/18",nil];
  /* Keep the Mac presets within older PowerPC playback capabilities. */
  return [NSArray arrayWithObjects:@"18",@"135+140/18",@"136+140/135+140/18",nil];
}
+ (NSString *)qualityLabelForFormat:(NSString *)format;
{
  if(![format length]) return @"";
  NSUInteger index=[[self qualityFormats] indexOfObject:format];
  /* Preserve labels for existing jobs and saved exact-format preferences. */
  if(index==NSNotFound && [format isEqualToString:@"136+140"]) index=1;
  if(index==NSNotFound && [format isEqualToString:@"137+140"]) index=2;
  NSArray *names=[NSArray arrayWithObjects:NSLocalizedString(@"Low", nil),NSLocalizedString(@"Med", nil),NSLocalizedString(@"High", nil),nil];
  return index==NSNotFound?NSLocalizedString(@"Custom", nil):[names objectAtIndex:index];
}
+ (NSString *)qualityDetailForFormat:(NSString *)format;
{
  if(![format length]) return @"";
  return [NSString stringWithFormat:NSLocalizedString(@"%@ (%@)", nil),[self qualityLabelForFormat:format],format];
}
+ (NSString *)durationLabelForEntry:(NSDictionary *)entry;
{
  unsigned long long seconds;
  if(!entry_number(entry,@"duration",&seconds)) return @"";
  return seconds>=3600?[NSString stringWithFormat:NSLocalizedString(@"%llu:%02llu:%02llu", nil),seconds/3600,(seconds/60)%60,seconds%60]:
    [NSString stringWithFormat:NSLocalizedString(@"%llu:%02llu", nil),seconds/60,seconds%60];
}
+ (NSString *)spokenDurationForEntry:(NSDictionary *)entry;
{
  unsigned long long seconds;
  if(!entry_number(entry,@"duration",&seconds)) return @"";
  NSMutableArray *parts=[NSMutableArray array];
  unsigned long long hours=seconds/3600, minutes=(seconds/60)%60, remainder=seconds%60;
  if(hours) [parts addObject:[NSString stringWithFormat:NSLocalizedString(@"%llu %@", nil),hours,hours==1?NSLocalizedString(@"hour", nil):NSLocalizedString(@"hours", nil)]];
  if(minutes) [parts addObject:[NSString stringWithFormat:NSLocalizedString(@"%llu %@", nil),minutes,minutes==1?NSLocalizedString(@"minute", nil):NSLocalizedString(@"minutes", nil)]];
  if(remainder || !seconds) [parts addObject:[NSString stringWithFormat:NSLocalizedString(@"%llu %@", nil),remainder,remainder==1?NSLocalizedString(@"second", nil):NSLocalizedString(@"seconds", nil)]];
  return [parts componentsJoinedByString:@", "];
}
+ (NSString *)metadataSummaryForEntry:(NSDictionary *)entry;
{
  NSMutableArray *parts=[NSMutableArray array];
  NSString *duration=[self durationLabelForEntry:entry], *channel=[entry objectForKey:@"channel"];
  if([duration length]) [parts addObject:duration];
  if([channel length]) [parts addObject:channel];
  return [parts componentsJoinedByString:@"·"];
}
+ (NSString *)metadataTooltipForEntry:(NSDictionary *)entry;
{
  NSMutableArray *lines=[NSMutableArray array], *snapshot=[NSMutableArray array];
  NSString *title=[entry objectForKey:@"title"], *summary=[self metadataSummaryForEntry:entry];
  NSString *views=[entry objectForKey:@"view_count_text"], *published=[entry objectForKey:@"published_text"];
  NSString *snippet=[entry objectForKey:@"description_snippet"]; unsigned long long count;
  if([title length]) [lines addObject:title];
  if([summary length]) [lines addObject:summary];
  if(![views length] && entry_number(entry,@"view_count",&count)) views=[NSString stringWithFormat:NSLocalizedString(@"%llu views", nil),count];
  if([views length]) [snapshot addObject:views];
  if([published length]) [snapshot addObject:[NSLocalizedString(@"Published ", nil) stringByAppendingString:published]];
  if([snapshot count]) [lines addObject:[NSLocalizedString(@"At last sync: ", nil) stringByAppendingString:[snapshot componentsJoinedByString:@"·"]]];
  if([snippet length]) [lines addObject:snippet];
  return [lines componentsJoinedByString:@"\n"];
}
+ (NSString *)fileSizeLabelForBytes:(unsigned long long)bytes;
{
  if(bytes<1000000) return [NSString stringWithFormat:NSLocalizedString(@"%llu KB", nil),(bytes+999)/1000];
  return [NSString stringWithFormat:NSLocalizedString(@"%.1f MB", nil),(double)bytes/1000000.0];
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
  NSError *directoryError=nil;
  NSFileManager *files=[NSFileManager defaultManager];
  if(![files RDLP_createDirectoryAtPath:support error:&directoryError] ||
     ![files RDLP_createDirectoryAtPath:root error:&directoryError]) {
    NSLog(@"Cannot prepare RetroDLP library directories: %@",directoryError);
    [self release]; return nil;
  }
  if(!rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],(rdapp_store **)&store_)) {
    NSLog(@"Cannot open RetroDLP library database in %@",support);
    [self release]; return nil;
  }
  chmod([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],0600);
  [self configurePlatformStorage];
  paused_=YES;
  [commands_ addObject:[NSDictionary dictionaryWithObject:@"reconcile" forKey:@"type"]];
  [self performSelector:@selector(startNext) withObject:nil afterDelay:0];
  return self;
}
- (void)dealloc;
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [lastPhase_ release]; [lastReadError_ release]; [errors_ release];
  [platformStorage_ release];
  rdapp_store_close(store_); [lock_ release]; [cancelLock_ release]; [commands_ release]; [activeCommand_ release]; [support_ release]; [root_ release];
  [ca_ release]; [assets_ release]; [cookies_ release]; [status_ release]; [super dealloc];
}
- (void)changed; { [[NSNotificationCenter defaultCenter] postNotificationName:RDLPLibraryDidChange object:self]; }
- (void)showStatus:(NSString *)message;
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(clearStatus) object:nil];
  NSString *next=[(message?message:@"") copy]; [status_ release]; status_=next;
  if([status_ length] && !busy_ && !stopping_)
    [self performSelector:@selector(clearStatus) withObject:nil afterDelay:10
                 inModes:[NSArray arrayWithObject:(NSString *)kCFRunLoopCommonModes]];
  [[NSNotificationCenter defaultCenter] postNotificationName:RDLPLibraryStatusDidChange object:self];
}
- (void)clearStatus;
{ if(busy_) return; transferCompleted_=0; transferExpected_=0; [self showStatus:@""]; }
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
- (NSUInteger)operationCount; { return operationCount_; }
- (void)beginOperation;
{
  NSAssert([NSThread RLDP_isMainThread],@"Operation references belong to the main thread");
  ++operationCount_;
  [[NSNotificationCenter defaultCenter] postNotificationName:RDLPLibraryActivityDidChange object:self];
}
- (void)endOperation;
{
  NSAssert([NSThread RLDP_isMainThread] && operationCount_>0,@"Unbalanced operation reference");
  --operationCount_;
  [[NSNotificationCenter defaultCenter] postNotificationName:RDLPLibraryActivityDidChange object:self];
}
- (void)suspendOperations;
{
  operationsSuspended_=YES;
  [cancelLock_ lock]; cancel_=YES; [cancelLock_ unlock];
  [self changed];
}
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
  if(stat([cookies_ fileSystemRepresentation],&info)) return errno==ENOENT?NSLocalizedString(@"Not Imported", nil):NSLocalizedString(@"Unavailable", nil);
  if(!S_ISREG(info.st_mode) || info.st_size<=0 || info.st_size>4*1024*1024 || access([cookies_ fileSystemRepresentation],R_OK)) return NSLocalizedString(@"Unavailable", nil);
  return NSLocalizedString(@"Imported", nil);
}
- (void)startDownloads;
{ operationsSuspended_=NO; paused_=NO; [self startNext]; }
- (BOOL)isPaused; { return paused_; }
- (RDLPLibraryRows *)rows:(rdapp_query)query playlist:(NSString *)key video:(NSString *)video format:(NSString *)format;
{
  RDLPLibraryRows *rows=[[[RDLPLibraryRows alloc] initWithLibrary:self path:[support_ stringByAppendingPathComponent:@"retrodlp.sqlite"] query:query key:key video:video format:format] autorelease];
  if(!rows && !lastReadError_) {
    lastReadError_=[NSLocalizedString(@"Could not open a library read snapshot.", nil) copy];
    [self reportError:NSLocalizedString(@"Couldn’t read library", nil) detail:lastReadError_];
  } else if(rows) { [lastReadError_ release]; lastReadError_=nil; }
  return rows;
}
- (NSArray *)rows:(rdapp_query)query playlist:(NSString *)key;
{ return [self rows:query playlist:key video:nil format:nil]; }
+ (BOOL)canSyncPlaylist:(NSDictionary *)playlist;
{ return rdapp_playlist_can_sync([[playlist objectForKey:@"service_id"] UTF8String])!=0; }
- (NSArray *)unsupportedPlaylists;
{ return [self rows:RDAPP_UNSUPPORTED_PLAYLISTS playlist:nil]; }
- (NSArray *)unsupportedPlaylistIDs;
{ return [self rows:RDAPP_UNSUPPORTED_IDS playlist:nil]; }
- (NSArray *)playlists; { return [self rows:RDAPP_PLAYLISTS playlist:nil]; }
- (NSArray *)playlistsFromAccount:(BOOL)account;
{ return [self rows:account?RDAPP_ACCOUNT_PLAYLISTS:RDAPP_ADDED_PLAYLISTS playlist:nil]; }
- (NSDictionary *)playlistForID:(NSString *)key;
{ NSArray *rows=key?[self rows:RDAPP_PLAYLIST playlist:key]:nil; return [rows count]?[rows objectAtIndex:0]:nil; }
- (NSDictionary *)adhocPlaylist;
{ NSArray *rows=[self rows:RDAPP_PLAYLIST_INPUT playlist:nil video:@RDAPP_ADHOC_PLAYLIST_ID format:nil]; return [rows count]?[rows objectAtIndex:0]:nil; }
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
- (RDLPLibraryRows *)addedVideos;
{ return [self rows:RDAPP_ADDED_VIDEOS playlist:[[self adhocPlaylist] objectForKey:@"id"] video:nil format:nil]; }
- (RDLPLibraryRows *)allDownloads;
{ return [self rows:RDAPP_ALL_DOWNLOADS playlist:nil video:nil format:nil]; }
- (RDLPLibraryRows *)queueRows;
{ return [self rows:RDAPP_QUEUE playlist:nil video:nil format:nil]; }
- (NSUInteger)queuedCount; { return [[self rows:RDAPP_PENDING playlist:nil] count]; }
- (BOOL)hasBlockingJobsForPlaylist:(NSString *)key;
{ return [[self rows:RDAPP_BLOCKING_JOBS playlist:key] count]>0; }
- (BOOL)hasPlaylistsToSync;
{
  NSUInteger total=[[self playlistIDsFromAccount:NO] count];
  if(!total) return NO;
  NSMutableSet *pending=[NSMutableSet set];
  if([[activeCommand_ objectForKey:@"type"] isEqualToString:@"sync"])
    [pending addObject:[activeCommand_ objectForKey:@"input"]];
  NSEnumerator *e=[commands_ objectEnumerator]; NSDictionary *command;
  while((command=[e nextObject])) if([[command objectForKey:@"type"] isEqualToString:@"sync"])
    [pending addObject:[command objectForKey:@"input"]];
  if(total>[pending count]) return YES;
  NSUInteger matched=0; e=[pending objectEnumerator]; NSString *input;
  while((input=[e nextObject])) if(rdapp_playlist_can_sync([input UTF8String])) {
    NSArray *rows=[self rows:RDAPP_PLAYLIST_INPUT playlist:nil video:input format:nil];
    if([rows count] && [[[rows objectAtIndex:0] objectForKey:@"source"] isEqualToString:@"added"]) ++matched;
  }
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
  NSUInteger step=0, total=10;
  /* Fixed phase positions let cached/optional work skip ahead. A repeated
     bootstrap or metadata request must not move processing progress backward. */
  switch(type) {
    case RDLP_EVENT_AUTHENTICATING: step=1; break;
    case RDLP_EVENT_LOADING_CONFIGURATION: step=2; break;
    case RDLP_EVENT_FETCHING_BOOTSTRAP: step=3; break;
    case RDLP_EVENT_REQUESTING_METADATA: step=4; break;
    case RDLP_EVENT_REFRESHING_METADATA: step=5; break;
    case RDLP_EVENT_SELECTING_FORMATS: step=6; break;
    case RDLP_EVENT_LOADING_PLAYER_JAVASCRIPT: step=7; break;
    case RDLP_EVENT_SOLVING_CHALLENGES: step=8; break;
    case RDLP_EVENT_ENUMERATING_PLAYLIST: step=5; break;
    case RDLP_EVENT_OTHER: return;
  }
  if(![command isEqualToString:@"download"] && ![command isEqualToString:@"addVideo"]) {
    total=5; step=MIN(step,total);
    phase=[command isEqualToString:@"discover"]?NSLocalizedString(@"Syncing My Playlists…", nil):
      ([[activeCommand_ objectForKey:@"adding"] boolValue]?NSLocalizedString(@"Adding playlist…", nil):NSLocalizedString(@"Syncing playlist…", nil));
  } else switch(type) {
    case RDLP_EVENT_AUTHENTICATING: phase=NSLocalizedString(@"Reading cookies…", nil); break;
    case RDLP_EVENT_LOADING_CONFIGURATION: phase=NSLocalizedString(@"Configuring client…", nil); break;
    case RDLP_EVENT_FETCHING_BOOTSTRAP: phase=NSLocalizedString(@"Loading mobile player…", nil); break;
    case RDLP_EVENT_REQUESTING_METADATA: phase=NSLocalizedString(@"Requesting metadata…", nil); break;
    case RDLP_EVENT_REFRESHING_METADATA: phase=NSLocalizedString(@"Refreshing visitor data…", nil); break;
    case RDLP_EVENT_SELECTING_FORMATS: phase=NSLocalizedString(@"Selecting format…", nil); break;
    case RDLP_EVENT_LOADING_PLAYER_JAVASCRIPT: phase=NSLocalizedString(@"Downloading player script…", nil); break;
    case RDLP_EVENT_SOLVING_CHALLENGES: phase=NSLocalizedString(@"Solving challenges…", nil); break;
    case RDLP_EVENT_ENUMERATING_PLAYLIST: phase=NSLocalizedString(@"Reading playlist…", nil); break;
    case RDLP_EVENT_OTHER: return;
  }
  if(phase) [self progress:phase completed:0 expected:0 step:step total:total];
}
- (void)progress:(NSString *)phase completed:(uint64_t)completed expected:(uint64_t)expected;
{ [self progress:phase completed:completed expected:expected step:0 total:1]; }
- (void)progress:(NSString *)phase completed:(uint64_t)completed expected:(uint64_t)expected
  step:(NSUInteger)step total:(NSUInteger)total;
{
  if(step) operationStep_=MAX(operationStep_,step);
  struct timeval t; gettimeofday(&t,NULL);
  double now=(double)t.tv_sec+(double)t.tv_usec/1000000.0;
  BOOL changed=![phase isEqualToString:lastPhase_];
  if(changed) { [lastPhase_ release]; lastPhase_=[phase copy]; transferStarted_=now; }
  /* Only repeated byte ticks are throttled. Every new CLI phase is delivered. */
  if(!changed && completed && now-lastProgress_<0.25 && (!expected || completed<expected)) return;
  lastProgress_=now;
  NSString *message=step?phase:[NSString stringWithFormat:NSLocalizedString(@"%@…", nil),phase];
  if(completed) {
    double elapsed=now-transferStarted_;
    if(elapsed>0) message=[NSString stringWithFormat:NSLocalizedString(@"%@ (%.1f Mbps)", nil),
      phase,(double)completed*8.0/elapsed/1000000.0];
  }
  /* Media transfers each use their own byte range. Unknown lengths show an
     empty determinate track until a total arrives; status still reports speed.
     Other phases resume the operation's fixed step range. */
  uint64_t barCompleted=step?MIN(operationStep_,total):(expected?completed:0);
  uint64_t barExpected=step?total:(expected?expected:1);
  NSDictionary *update=[NSDictionary dictionaryWithObjectsAndKeys:message,@"message",
    [NSNumber numberWithUnsignedLongLong:barCompleted],@"completed",
    [NSNumber numberWithUnsignedLongLong:barExpected],@"expected",nil];
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
- (void)addVideoInput:(NSString *)input;
{ [self queueVideoInput:input]; }
- (void)syncPlaylistInput:(NSString *)input;
{ [self queuePlaylistInput:input adding:NO]; }
- (void)queuePlaylistInput:(NSString *)input adding:(BOOL)adding;
{
  input=[input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if(![input length]) { [self reportError:NSLocalizedString(@"Enter a playlist", nil) detail:NSLocalizedString(@"Enter a playlist URL or ID.", nil)]; return; }
  if(!rdapp_playlist_can_sync([input UTF8String])) {
    if(adding) [self reportError:NSLocalizedString(@"Unsupported playlist", nil) detail:NSLocalizedString(@"This playlist type cannot be synced by RetroDLP.", nil)];
    return;
  }
  if([self isSyncPendingForInput:input]) return;
  [commands_ addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"sync",@"type",input,@"input",
    [NSNumber numberWithBool:adding],@"adding",nil]]; [self startNext];
}
- (void)queueVideoInput:(NSString *)input;
{
  input=[input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if(![input length]) { [self reportError:NSLocalizedString(@"Enter a video", nil) detail:NSLocalizedString(@"Enter a YouTube video URL or ID.", nil)]; return; }
  /* Admission is local: show the row immediately, even during another transfer.
     The normal worker resolves metadata and media URLs once, when claimed. */
  rdapp_service_config config; rdapp_job job; char message[1024];
  memset(&config,0,sizeof(config)); memset(&job,0,sizeof(job));
  config.download_root=[root_ fileSystemRepresentation];
  config.lock=store_lock; config.unlock=store_unlock; config.lock_context=lock_;
  job.format=[[RDLPLibrary preferredFormat] UTF8String];
  rdlp_error_code code=rdapp_service_run(store_,&config,RDAPP_ADD_VIDEO,[input UTF8String],&job,message,sizeof(message));
  if(code!=RDLP_OK) { [self reportError:NSLocalizedString(@"Couldn’t add video", nil) detail:string(message)]; return; }
  if(!busy_) [self showStatus:NSLocalizedString(@"Video added", nil)];
  [self changed]; [self startNext];
}
- (void)syncAll;
{
  NSArray *rows=[self playlistsFromAccount:NO]; unsigned int i;
  for(i=0;i<[rows count];++i) if([RDLPLibrary canSyncPlaylist:[rows objectAtIndex:i]] && ![self isSyncPendingForInput:[[rows objectAtIndex:i] objectForKey:@"service_id"]]) [commands_ addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"sync",@"type",[[rows objectAtIndex:i] objectForKey:@"service_id"],@"input",nil]];
  [self startNext];
}
- (void)discoverPlaylists;
{ if([self isDiscoveryPending]) return; [commands_ addObject:[NSDictionary dictionaryWithObject:@"discover" forKey:@"type"]]; [self startNext]; }
- (void)enqueuePlaylist:(NSString *)key video:(NSString *)video format:(NSString *)format;
{
  int ok;
  if(![key length]) { [self reportError:NSLocalizedString(@"Select a playlist", nil) detail:NSLocalizedString(@"Select a synced playlist first.", nil)]; return; }
  if(!rdlp_format_expression_valid([format UTF8String])) { [self reportError:NSLocalizedString(@"Invalid format", nil) detail:NSLocalizedString(@"Enter a format ID, such as 18 or 136+140.", nil)]; return; }
  [lock_ lock]; ok=rdapp_store_enqueue(store_,identifier(key),[video UTF8String],[format UTF8String]);
  NSString *error=ok?nil:[string(rdapp_store_error(store_)) copy];
  [lock_ unlock];
  if(error) [self reportError:NSLocalizedString(@"Couldn’t queue download", nil) detail:error];
  [error release]; [self changed];
  [self startNext];
}
- (void)retryJob:(NSString *)key;
{
  [lock_ lock];
  int ok=rdapp_store_reconcile_job(store_,identifier(key),[root_ fileSystemRepresentation]) && rdapp_store_retry(store_,identifier(key));
  NSString *error=ok?nil:[string(rdapp_store_error(store_)) copy]; [lock_ unlock];
  if(ok) { [self changed]; [self startNext]; }
  else [self reportError:NSLocalizedString(@"Couldn’t retry download", nil) detail:error];
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
  if(error) [self reportError:NSLocalizedString(@"Couldn’t stop download", nil) detail:error];
  [error release]; [self changed];
}
- (double)storedPlaybackSecondsForVideo:(NSString *)video;
{
  double seconds=0;
  [lock_ lock];
  int ok=rdapp_store_playback_seconds(store_,[video UTF8String],&seconds);
  if(!ok) NSLog(@"Could not read playback position: %s",rdapp_store_error(store_));
  [lock_ unlock]; return seconds;
}
- (void)storePlaybackSeconds:(double)seconds forVideo:(NSString *)video;
{
  [lock_ lock];
  if(!rdapp_store_save_playback_seconds(store_,[video UTF8String],seconds))
    NSLog(@"Could not save playback position: %s",rdapp_store_error(store_));
  [lock_ unlock];
}
- (NSString *)fileForJob:(NSDictionary *)job;
{
  NSString *relative=[job objectForKey:@"path"];
  if(![relative length] || [relative isAbsolutePath] || [[relative pathComponents] containsObject:@".."]) return nil;
  return [root_ stringByAppendingPathComponent:relative];
}
- (NSString *)playlistFile:(NSDictionary *)playlist;
{ return [[root_ stringByAppendingPathComponent:[playlist objectForKey:@"directory"]] stringByAppendingPathComponent:@"Playlist.xspf"]; }
- (void)removeDownload:(NSDictionary *)job;
{
  NSString *key=[job objectForKey:@"id"];
  if(busy_) { [self reportError:NSLocalizedString(@"Couldn’t delete download", nil) detail:NSLocalizedString(@"Wait for the current operation to finish.", nil)]; return; }
  [lock_ lock];
  int ok=rdapp_store_remove_file_with_callback(store_,identifier(key),[root_ fileSystemRepresentation],remove_download_file,self);
  NSString *error=ok?nil:[string(rdapp_store_error(store_)) copy];
  [lock_ unlock]; if(error) [self reportError:NSLocalizedString(@"Couldn’t delete download", nil) detail:error]; [error release]; [self changed];
}
- (BOOL)canRemovePlaylist:(NSDictionary *)playlist;
{
  if(!playlist || [[playlist objectForKey:@"service_id"] isEqualToString:@RDAPP_ADHOC_PLAYLIST_ID]) return NO;
  /* Downloads only need the retained parent. Serialize removal against sync
     commands, which could otherwise restore membership after removal. */
  if(busy_ && ![[activeCommand_ objectForKey:@"type"] isEqualToString:@"download"]) return NO;
  NSEnumerator *e=[commands_ objectEnumerator]; NSDictionary *command;
  while((command=[e nextObject])) if([[command objectForKey:@"type"] isEqualToString:@"sync"]) return NO;
  return YES;
}
- (void)removePlaylist:(NSDictionary *)playlist;
{
  if(![self canRemovePlaylist:playlist]) { [self reportError:NSLocalizedString(@"Couldn’t remove playlist", nil) detail:NSLocalizedString(@"Wait for playlist operations to finish. Added Videos cannot be removed.", nil)]; return; }
  [lock_ lock]; int ok=rdapp_store_remove_playlist(store_,identifier([playlist objectForKey:@"id"]),[root_ fileSystemRepresentation]);
  NSString *error=ok?nil:[string(rdapp_store_error(store_)) copy]; [lock_ unlock];
  if(ok) {
    NSString *directory=[root_ stringByAppendingPathComponent:[playlist objectForKey:@"directory"]];
    unlink([[directory stringByAppendingPathComponent:@"Playlist.xspf"] fileSystemRepresentation]);
    unlink([[directory stringByAppendingPathComponent:@"Playlist.m3u8"] fileSystemRepresentation]);
    /* An active transfer may already have prepared this destination folder. */
  }
  if(error) [self reportError:NSLocalizedString(@"Couldn’t remove playlist", nil) detail:error]; [error release]; [self changed];
}
- (BOOL)importCookies:(NSString *)path;
{
  if(busy_) { [self reportError:NSLocalizedString(@"Couldn’t import cookies", nil) detail:NSLocalizedString(@"Wait for the current operation to finish.", nil)]; return NO; }
  NSData *data=[NSData dataWithContentsOfFile:path];
  if(!data || ![data length] || [data length]>4*1024*1024) { [self reportError:NSLocalizedString(@"Couldn’t import cookies", nil) detail:NSLocalizedString(@"Choose a readable, nonempty Netscape cookies.txt file of 4 MiB or less.", nil)]; return NO; }
  if(![data writeToFile:cookies_ atomically:YES] || chmod([cookies_ fileSystemRepresentation],0600)) { [self reportError:NSLocalizedString(@"Couldn’t save cookies", nil) detail:NSLocalizedString(@"Check available storage and try again.", nil)]; return NO; }
  [self changed]; return YES;
}
- (void)clearCookies;
{
  if(busy_) { [self reportError:NSLocalizedString(@"Couldn’t remove cookies", nil) detail:NSLocalizedString(@"Wait for the current operation to finish.", nil)]; return; }
  if(unlink([cookies_ fileSystemRepresentation]) && errno!=ENOENT) [self reportError:NSLocalizedString(@"Couldn’t remove cookies", nil) detail:string(strerror(errno))];
  else [self changed];
}
- (void)startNext;
{
  if(busy_ || stopping_ || operationsSuspended_) return;
  NSDictionary *command=nil;
  if([commands_ count]) { command=[[[commands_ objectAtIndex:0] retain] autorelease]; [commands_ removeObjectAtIndex:0]; }
  else if(!paused_) {
    NSMutableArray *rows=[NSMutableArray array];
    [lock_ lock]; int ok=rdapp_store_claim(store_,collect,rows); [lock_ unlock];
    if(!ok) { [self reportError:NSLocalizedString(@"Couldn’t start download", nil) detail:string(rdapp_store_error(store_))]; return; }
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
  [self beginOperation];
  transferCompleted_=0; transferExpected_=
    ([[command objectForKey:@"type"] isEqualToString:@"download"] ||
     [[command objectForKey:@"type"] isEqualToString:@"addVideo"])?10:5;
  operationStep_=0; lastProgress_=0;
  [lastPhase_ release]; lastPhase_=nil;
  NSString *type=[command objectForKey:@"type"];
  if(![type isEqualToString:@"reconcile"]) [self showStatus:[type isEqualToString:@"download"]?NSLocalizedString(@"Resolving video…", nil):
    ([type isEqualToString:@"discover"]?NSLocalizedString(@"Syncing My Playlists…", nil):([type isEqualToString:@"addVideo"]?NSLocalizedString(@"Adding video…", nil):([[command objectForKey:@"adding"] boolValue]?NSLocalizedString(@"Adding playlist…", nil):NSLocalizedString(@"Syncing playlist…", nil))))];
  [self changed];
  /* QuickJS permits 1 MiB of stack; the default 512 KiB worker stack can
     hit its guard page before QuickJS detects overflow. Leave native headroom. */
  int error=[NSThread RDLP_detachNewThreadSelector:@selector(work:) toTarget:self
    withObject:command stackSize:2U*1024U*1024U];
  if(error) {
    NSString *message=[NSString stringWithFormat:NSLocalizedString(@"Couldn’t start worker: %s", nil),strerror(error)];
    paused_=YES; operationsSuspended_=YES;
    if(activeJob_) {
      [lock_ lock];
      rdapp_store_finish(store_,activeJob_,"failed","",[message UTF8String]);
      [lock_ unlock];
    }
    [self finished:[NSDictionary dictionaryWithObjectsAndKeys:
      [NSNumber numberWithInt:RDLP_ERROR_INTERNAL],@"code",message,@"message",nil]];
  }
}
- (void)finished:(NSDictionary *)result;
{
  if([[activeCommand_ objectForKey:@"type"] isEqualToString:@"reconcile"]) {
    [activeCommand_ release]; activeCommand_=nil; busy_=NO;
    if([[result objectForKey:@"code"] intValue]!=RDLP_OK)
      [self reportError:NSLocalizedString(@"Couldn’t read library", nil) detail:[result objectForKey:@"message"]];
    if(!stopping_) { [self changed]; [self startNext]; }
    [self endOperation];
    return;
  }
  if([[activeCommand_ objectForKey:@"type"] isEqualToString:@"download"]) {
    ++queueProcessed_;
    NSString *key=[[activeCommand_ objectForKey:@"job"] objectForKey:@"id"];
    NSDictionary *job=[self jobForID:key];
    if([[result objectForKey:@"code"] intValue]==RDLP_OK &&
       [[job objectForKey:@"state"] isEqualToString:@"complete"])
      [[NSNotificationCenter defaultCenter] postNotificationName:RDLPLibraryDownloadDidComplete object:self userInfo:job];
    if([[job objectForKey:@"state"] isEqualToString:@"failed"]) ++queueFailed_;
    if([[job objectForKey:@"state"] isEqualToString:@"cancelled"] ||
       [[job objectForKey:@"state"] isEqualToString:@"interrupted"]) ++queueCancelled_;
  }
  NSString *type=[activeCommand_ objectForKey:@"type"];
  BOOL download=[type isEqualToString:@"download"], discover=[type isEqualToString:@"discover"], addVideo=[type isEqualToString:@"addVideo"];
  BOOL adding=[[activeCommand_ objectForKey:@"adding"] boolValue];
  rdlp_error_code code=(rdlp_error_code)[[result objectForKey:@"code"] intValue];
  NSString *status=download?NSLocalizedString(@"Download complete", nil):(discover?NSLocalizedString(@"My Playlists synced", nil):(addVideo?NSLocalizedString(@"Video added", nil):(adding?NSLocalizedString(@"Playlist added", nil):NSLocalizedString(@"Playlist synced", nil))));
  if(download && code==RDLP_OK) status=[NSString stringWithFormat:NSLocalizedString(@"Downloaded·%.1f MiB", nil),[[result objectForKey:@"bytes"] doubleValue]/1048576.0];
  if(code==RDLP_ERROR_CANCELLED) status=download?NSLocalizedString(@"Download stopped", nil):NSLocalizedString(@"Playlist operation stopped", nil);
  else if(code!=RDLP_OK) status=download?NSLocalizedString(@"Download failed", nil):(discover?NSLocalizedString(@"Error syncing My Playlists", nil):(addVideo?NSLocalizedString(@"Error adding video", nil):(adding?NSLocalizedString(@"Error adding playlist", nil):NSLocalizedString(@"Error syncing playlist", nil))));
  BOOL warning=[[result objectForKey:@"warning"] boolValue];
  if(warning) status=NSLocalizedString(@"Download needs attention", nil);
  if((code!=RDLP_OK && code!=RDLP_ERROR_CANCELLED) || warning) {
    NSString *title=download?[[activeCommand_ objectForKey:@"job"] objectForKey:@"title"]:[activeCommand_ objectForKey:@"input"];
    NSString *detail=[result objectForKey:@"message"];
    if([title length]) detail=[NSString stringWithFormat:NSLocalizedString(@"%@\n\n%@", nil),title,detail];
    [self reportError:status detail:detail];
  }
  [activeCommand_ release]; activeCommand_=nil;
  busy_=NO; transferCompleted_=0; transferExpected_=0;
  activeJob_=0;
  if(!stopping_) { [self showStatus:status]; [self changed];
    /* Acquire the next worker's reference before releasing this one so iOS
       cannot suspend the queue in a gap between consecutive operations. */
    [self startNext]; }
  [self endOperation];

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
  /* Typed resolver/download events drive the status bar; omit raw format/file notices. */
  config.result=&outcome; config.status_context=self;
  config.change_callback=service_changed;
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
  rdapp_operation operation=[type isEqualToString:@"sync"]?RDAPP_SYNC:([type isEqualToString:@"discover"]?RDAPP_DISCOVER:([type isEqualToString:@"addVideo"]?RDAPP_ADD_VIDEO:RDAPP_DOWNLOAD));
  if(operation==RDAPP_ADD_VIDEO) job.format=[[command objectForKey:@"format"] UTF8String];
  if(!ca_) {
    code=RDLP_ERROR_CERTIFICATE_BUNDLE;
    snprintf(message,sizeof(message),"%s",rdapp_string(RDAPP_STRING_CA_BUNDLE_MISSING));
    if(row) { [lock_ lock]; rdapp_store_finish(store_,job.id,"failed","",message); [lock_ unlock]; }
  } else code=rdapp_service_run(store_,&config,operation,[[command objectForKey:@"input"] UTF8String],&job,message,sizeof(message));
  NSDictionary *result=[NSDictionary dictionaryWithObjectsAndKeys:string(message),@"message",
    [NSNumber numberWithInt:code],@"code",[NSNumber numberWithBool:outcome.warning!=0],@"warning",
    [NSNumber numberWithUnsignedLongLong:outcome.downloaded_bytes],@"bytes",nil];
  [self performSelectorOnMainThread:@selector(finished:) withObject:result waitUntilDone:NO];
  [pool drain];
}
@end
