/* Test-only instrumentation shared by the native AppKit/UIKit runners. */
#import "../RDLPLibrary.h"
#import "../RDLPVideoRows.h"
#include <sqlite3.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

static void perfRequire(BOOL ok, NSString *message) {
  if(!ok) [NSException raise:@"RDLPPerformance" format:@"%@",message];
}
static double perfNow(void) {
  mach_timebase_info_data_t info; mach_timebase_info(&info);
  return (double)mach_absolute_time()*info.numer/info.denom/1e9;
}
static void perfPump(void) {
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
}
static pthread_mutex_t perfSQLLock=PTHREAD_MUTEX_INITIALIZER;
static unsigned long long perfSQLCount=0;
static void perfTrace(void *context,const char *sql) {
  (void)context; (void)sql;
  pthread_mutex_lock(&perfSQLLock); ++perfSQLCount; pthread_mutex_unlock(&perfSQLLock);
}
static int perfExtension(sqlite3 *db,char **error,const sqlite3_api_routines *api) {
  (void)error; (void)api; sqlite3_trace(db,perfTrace,NULL); return SQLITE_OK;
}
static unsigned long long perfQueries(void) {
  unsigned long long count;
  pthread_mutex_lock(&perfSQLLock); count=perfSQLCount; pthread_mutex_unlock(&perfSQLLock); return count;
}
static unsigned long long perfResident(void) {
  mach_msg_type_number_t count;
  /* TASK_BASIC_INFO is available on Tiger, unlike MACH_TASK_BASIC_INFO. */
  struct task_basic_info legacy; count=TASK_BASIC_INFO_COUNT;
  perfRequire(task_info(mach_task_self(),TASK_BASIC_INFO,(task_info_t)&legacy,&count)==KERN_SUCCESS,@"Read resident memory");
  return legacy.resident_size;
}
static unsigned long long perfFileBytes(NSString *path) {
  struct stat info;
  return stat([path fileSystemRepresentation],&info)==0?(unsigned long long)info.st_size:0;
}
/* NSArray's valueForKey: maps over every element. Invoke NSObject's KVC
 * implementation directly to inspect test-only cache ivars without reading rows. */
static id perfIvar(id object, NSString *key) {
  typedef id (*Getter)(id, SEL, NSString *);
  Getter getter=(Getter)[NSObject instanceMethodForSelector:@selector(valueForKey:)];
  return getter(object,@selector(valueForKey:),key);
}
static NSUInteger perfCachedRows(id rows) {
  perfRequire([rows isKindOfClass:[AIPagedRows class]],@"Expected paged rows for cache measurement");
  NSLock *lock=perfIvar(rows,@"pageCacheLock_"); [lock lock];
  NSDictionary *pages=perfIvar(rows,@"rowPages_");
  NSUInteger count=0; NSEnumerator *e=[pages objectEnumerator]; NSArray *page;
  while((page=[e nextObject])) count+=[page count];
  [lock unlock]; return count;
}
@interface RDLPPerfLibrary : RDLPLibrary
@end
@implementation RDLPPerfLibrary
- (void)startNext; { /* Never start the network/download scheduler. */ }
@end
@protocol RDLPPerfTable
- (void)openLibrary:(RDLPLibrary *)library playlist:(NSDictionary *)playlist;
- (void)scrollToRow:(NSUInteger)row;
- (void)refresh;
- (BOOL)loading;
- (NSArray *)displayRows;
- (void)close;
- (void)validateRun;
@end
@interface RDLPPerfPulse : NSObject { @public double last, maximum; NSUInteger stalls; }
- (void)tick:(NSTimer *)timer;
@end
@implementation RDLPPerfPulse
- (void)tick:(NSTimer *)timer;
{
  (void)timer; double now=perfNow(), gap=now-last;
  if(gap>maximum) maximum=gap;
  if(gap>0.05) ++stalls;
  last=now;
}
@end
@interface RDLPPerfWriter : NSObject {
@public
  NSConditionLock *done; NSLock *lock; BOOL stop, ok; NSUInteger writes;
  NSString *path;
}
- (void)run:(id)unused;
@end
@implementation RDLPPerfWriter
- (void)run:(id)unused;
{
  (void)unused; NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  sqlite3 *db=NULL; ok=sqlite3_open([path fileSystemRepresentation],&db)==SQLITE_OK;
  if(ok) sqlite3_busy_timeout(db,5000);
  for(;;) {
    [lock lock]; BOOL quit=stop; [lock unlock]; if(quit || !ok) break;
    ok=sqlite3_exec(db,"UPDATE entries SET title=CASE WHEN title='Updated performance row' THEN 'Performance row' ELSE 'Updated performance row' END WHERE position=0",NULL,NULL,NULL)==SQLITE_OK;
    if(ok) ++writes;
    usleep(25000);
  }
  if(db) sqlite3_close(db);
  [pool drain]; [done lock]; [done unlockWithCondition:1];
}
- (void)dealloc; { [done release]; [lock release]; [path release]; [super dealloc]; }
@end
static void perfWait(id<RDLPPerfTable> table) {
  double deadline=perfNow()+60;
  while([table loading] && perfNow()<deadline) perfPump();
  perfRequire(![table loading],@"Native refresh timed out after 60 seconds");
}
static NSDictionary *perfPhase(id<RDLPPerfTable> table,NSString *name,NSUInteger count,NSUInteger rows) {
  NSMutableArray *times=[NSMutableArray array]; NSUInteger i, maxDisplay=0,maxSource=0;
  unsigned long long before=perfQueries(), peak=perfResident();
  RDLPPerfPulse *pulse=[[RDLPPerfPulse alloc] init]; pulse->last=perfNow();
  NSTimer *timer=[NSTimer scheduledTimerWithTimeInterval:0.01 target:pulse selector:@selector(tick:) userInfo:nil repeats:YES];
  for(i=0;i<count;++i) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init]; double start=perfNow();
    if([name isEqualToString:@"refresh_during_writes"]) {
      NSArray *previous=[[table displayRows] retain];
      [table refresh]; perfWait(table);
      BOOL replaced=[table displayRows]!=previous;
      [previous release];
      perfRequire(replaced,@"Refresh must install a new row snapshot");
      [table scrollToRow:0];
    }
    else [table scrollToRow:[name isEqualToString:@"sequential"]?(i*8)%rows:(i*7919U+123U)%rows];
    perfPump(); [table validateRun];
    [times addObject:[NSNumber numberWithDouble:(perfNow()-start)*1000]];
    NSArray *display=[table displayRows];
    NSUInteger cached=perfCachedRows(display); if(cached>maxDisplay) maxDisplay=cached;
    if([display isKindOfClass:[RDLPVideoRows class]]) {
      cached=perfCachedRows(perfIvar(display,@"source_")); if(cached>maxSource) maxSource=cached;
    }
    unsigned long long memory=perfResident(); if(memory>peak) peak=memory;
    [pool drain];
  }
  [pulse tick:nil]; [timer invalidate];
  NSArray *sorted=[times sortedArrayUsingSelector:@selector(compare:)];
  NSDictionary *result=[NSDictionary dictionaryWithObjectsAndKeys:name,@"phase",times,@"samples_ms",
    [sorted objectAtIndex:count/2],@"p50_ms",[sorted objectAtIndex:(count-1)*95/100],@"p95_ms",[sorted lastObject],@"max_ms",
    [NSNumber numberWithDouble:pulse->maximum*1000],@"max_main_loop_gap_ms",
    [NSNumber numberWithUnsignedLong:pulse->stalls],@"gaps_over_50ms",
    [NSNumber numberWithUnsignedLongLong:perfQueries()-before],@"sql_statements",
    [NSNumber numberWithUnsignedLongLong:peak],@"peak_sampled_resident_bytes",
    [NSNumber numberWithUnsignedLong:maxDisplay],@"max_display_cached_rows",
    [NSNumber numberWithUnsignedLong:maxSource],@"max_source_cached_rows",nil];
  [pulse release];
  perfRequire(maxDisplay>0 && maxSource>0,@"Both row caches were exercised");
  perfRequire(maxDisplay<=128 && maxSource<=128,@"Native list exceeded its 128-row cache bound");
  return result;
}
static void runNativePerformance(id<RDLPPerfTable> table,NSString *base,NSString *reportPath) {
  /* A unique fixture per invocation prevents old rows or live app data reuse. */
  base=[base stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  NSString *support=[base stringByAppendingPathComponent:@"Support"], *downloads=[base stringByAppendingPathComponent:@"Downloads"];
  perfRequire(rdapp_make_directory([support fileSystemRepresentation]),@"Create isolated fixture");
  NSString *dbPath=[support stringByAppendingPathComponent:@"retrodlp.sqlite"];
  NSUInteger count=10000,i; rdapp_entry *entries=calloc(count,sizeof(*entries));
  perfRequire(entries!=NULL,@"Allocate fixture");
  for(i=0;i<count;++i) {
    char video[12]; snprintf(video,sizeof(video),"P%010lu",(unsigned long)i);
    entries[i].video_id=strdup(video); entries[i].title="Performance row";
    entries[i].position=(int)i; entries[i].channel="Offline performance channel";
    entries[i].duration=123; entries[i].has_duration=1;
  }
  rdapp_store *store=NULL; int64_t key=0;
  perfRequire(rdapp_store_open([dbPath fileSystemRepresentation],&store),@"Open fixture store");
  perfRequire(rdapp_store_snapshot(store,"PLperformance","Performance playlist",entries,count,&key),@"Seed 10,000 entries");
  for(i=0;i<count;++i) free((void *)entries[i].video_id); free(entries); rdapp_store_close(store);
  perfRequire(sqlite3_auto_extension((void (*)(void))perfExtension)==SQLITE_OK,@"Install test SQL counter");
  NSAutoreleasePool *workPool=[[NSAutoreleasePool alloc] init];
  NSAutoreleasePool *opening=[[NSAutoreleasePool alloc] init];
  RDLPPerfPulse *initialPulse=[[RDLPPerfPulse alloc] init]; initialPulse->last=perfNow();
  NSTimer *initialTimer=[NSTimer scheduledTimerWithTimeInterval:0.01 target:initialPulse selector:@selector(tick:) userInfo:nil repeats:YES];
  double start=perfNow(); unsigned long long queries=perfQueries();
  RDLPLibrary *library=[[RDLPPerfLibrary alloc] initWithSupportDirectory:support downloadDirectory:downloads];
  perfRequire(library!=nil,@"Open offline library");
  [table openLibrary:library playlist:[library playlistForID:[NSString stringWithFormat:@"%lld",(long long)key]]];
  perfWait(table); perfPump(); [table validateRun];
  perfRequire([[table displayRows] count]==count,@"Native table exposes all fixture rows");
  double initial=(perfNow()-start)*1000; queries=perfQueries()-queries;
  [initialPulse tick:nil]; [initialTimer invalidate];
  double initialGap=initialPulse->maximum*1000; [initialPulse release];
  perfRequire(queries>0,@"SQL tracing is active");
  [opening drain];
  NSMutableArray *phases=[NSMutableArray array];
  [phases addObject:perfPhase(table,@"sequential",120,count)];
  [phases addObject:perfPhase(table,@"random_jumps",80,count)];
  /* Keep an explicit old snapshot while a separate connection commits. */
  NSArray *held=[[library entriesForPlaylist:[NSString stringWithFormat:@"%lld",(long long)key]] retain];
  RDLPPerfWriter *writer=[[RDLPPerfWriter alloc] init]; writer->path=[dbPath copy];
  writer->done=[[NSConditionLock alloc] initWithCondition:0]; writer->lock=[[NSLock alloc] init];
  [NSThread detachNewThreadSelector:@selector(run:) toTarget:writer withObject:nil];
  @try {
    double deadline=perfNow()+0.3; while(perfNow()<deadline) perfPump();
    [phases addObject:perfPhase(table,@"scroll_during_writes",80,count)];
    [phases addObject:perfPhase(table,@"refresh_during_writes",20,count)];
  } @finally {
    [writer->lock lock]; writer->stop=YES; [writer->lock unlock];
    perfRequire([writer->done lockWhenCondition:1 beforeDate:[NSDate dateWithTimeIntervalSinceNow:10]],@"Join concurrent writer");
    [writer->done unlock];
  } perfRequire(writer->ok && writer->writes>0,@"Concurrent writes succeeded");
  unsigned long long wal=perfFileBytes([dbPath stringByAppendingString:@"-wal"]);
  NSUInteger commits=writer->writes;
  [phases retain]; [writer release];
  [held release]; [table close]; [library shutdown]; [library release];
  [workPool drain];
  sqlite3 *db=NULL; perfRequire(sqlite3_open([dbPath fileSystemRepresentation],&db)==SQLITE_OK,@"Open checkpoint connection");
  /* Open the schema before checkpointing: a fresh connection can otherwise
   * return SQLITE_OK with log=-1 without discovering the database's WAL. */
  perfRequire(sqlite3_exec(db,"PRAGMA journal_mode",NULL,NULL,NULL)==SQLITE_OK,@"Discover WAL before checkpoint");
  int log=-1, checkpointed=-1;
  int checkpoint=sqlite3_wal_checkpoint_v2(db,NULL,SQLITE_CHECKPOINT_TRUNCATE,&log,&checkpointed);
  unsigned long long after=perfFileBytes([dbPath stringByAppendingString:@"-wal"]); sqlite3_close(db);
  NSDictionary *report=[NSDictionary dictionaryWithObjectsAndKeys:@"native-collection-v1",@"scenario",
    [[NSProcessInfo processInfo] operatingSystemVersionString],@"os",base,@"fixture",
    [NSNumber numberWithUnsignedLong:count],@"rows",[NSNumber numberWithDouble:initial],@"initial_display_ms",
    [NSNumber numberWithUnsignedLongLong:queries],@"initial_sql_statements",phases,@"phases",
    [NSNumber numberWithDouble:initialGap],@"initial_max_main_loop_gap_ms",
    [NSNumber numberWithUnsignedLong:commits],@"concurrent_commits",
    [NSNumber numberWithUnsignedLongLong:wal],@"wal_with_old_snapshot_bytes",
    [NSNumber numberWithUnsignedLongLong:after],@"wal_after_release_bytes",
    [NSNumber numberWithInt:checkpoint],@"checkpoint_result",nil];
  perfRequire([report writeToFile:reportPath atomically:YES],@"Write performance report");
  [phases release];
  perfRequire(checkpoint==SQLITE_OK && after==0,@"Released snapshots permit WAL truncation");
}
