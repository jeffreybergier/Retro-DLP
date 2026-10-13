#import "../RDLPListLoader.h"
#import "../RDLPVideoRows.h"
#import "../RDLPDownloadSections.h"

static BOOL asyncProbeCancelled;
@interface RDLPAsyncProbe : NSObject {
@public
  NSUInteger deliveries;
  NSDictionary *last;
}
@end
@implementation RDLPAsyncProbe
+ (NSDictionary *)buildList:(NSDictionary *)input;
{
  NSConditionLock *gate=[input objectForKey:@"gate"];
  if(gate) {
    [gate lock]; [gate unlockWithCondition:1];
    [gate lockWhenCondition:2]; [gate unlock];
    asyncProbeCancelled=[[AICollectionController currentController] isCancelled];
  }
  return [NSDictionary dictionaryWithObjectsAndKeys:[input objectForKey:@"value"],@"value",
    [NSNumber numberWithBool:[NSThread RLDP_isMainThread]],@"main",nil];
}
- (void)didLoadList:(NSDictionary *)result;
{ ++deliveries; [last release]; last=[result copy]; }
- (void)dealloc; { [last release]; [super dealloc]; }
@end
@interface RDLPAsyncFixture : NSArray { @public NSUInteger reads, total; BOOL mainRead; }
@end
@implementation RDLPAsyncFixture
- (NSUInteger)count; { return total?total:100000; }
- (id)objectAtIndex:(NSUInteger)index;
{
  ++reads; if([NSThread RLDP_isMainThread]) mainRead=YES;
  return [NSDictionary dictionaryWithObjectsAndKeys:@"Fixture",@"title",@"queued",@"state",
    [NSString stringWithFormat:@"%lu",(unsigned long)index],@"id",nil];
}
@end
static void testSharedAsyncLists(void) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  RDLPAsyncProbe *probe=[[RDLPAsyncProbe alloc] init];
  RDLPListLoader *loader=[[RDLPListLoader alloc] initWithTarget:probe builder:[RDLPAsyncProbe class]];
  NSConditionLock *gate=[[[NSConditionLock alloc] initWithCondition:0] autorelease];
  [loader request:[NSDictionary dictionaryWithObjectsAndKeys:gate,@"gate",@"old",@"value",nil]];
  NSDate *startDeadline=[NSDate dateWithTimeIntervalSinceNow:10];
  BOOL started=NO;
  while([startDeadline timeIntervalSinceNow]>0) {
    if([gate tryLockWhenCondition:1]) { started=YES; [gate unlock]; break; }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
  metadataRequire(started,@"Coalesced snapshot worker starts while main run loop stays responsive");
  [loader request:[NSDictionary dictionaryWithObject:@"middle" forKey:@"value"]];
  [loader request:[NSDictionary dictionaryWithObject:@"latest" forKey:@"value"]];
  [gate lock]; [gate unlockWithCondition:2];
  NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
  while(!probe->deliveries && [deadline timeIntervalSinceNow]>0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  metadataRequire(asyncProbeCancelled,@"New generation cancels obsolete count work on the worker");
  metadataRequire(probe->deliveries==1 && [[probe->last objectForKey:@"value"] isEqual:@"latest"] && ![[probe->last objectForKey:@"main"] boolValue],@"Coalesced snapshots deliver only the latest generation from a worker");
  [loader request:[NSDictionary dictionaryWithObject:@"disposed" forKey:@"value"]];
  [loader invalidate]; [loader release];
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
  metadataRequire(probe->deliveries==1,@"Disposed view rejects queued snapshot callbacks");
  [probe release];
  RDLPAsyncFixture *source=[[[RDLPAsyncFixture alloc] init] autorelease];
  RDLPVideoRows *rows=[[[RDLPVideoRows alloc] initWithRows:source library:nil playlist:nil] autorelease];
  NSUInteger indexes[]={0,99999,40000,32,8192},i;
  NSTimeInterval maximum=0;
  for(i=0;i<5;++i) {
    NSTimeInterval start=[NSDate timeIntervalSinceReferenceDate];
    NSDictionary *placeholder=[rows requestObjectAtIndex:indexes[i] placeholder:[NSDictionary dictionaryWithObject:@"placeholder" forKey:@"action"]];
    maximum=MAX(maximum,[NSDate timeIntervalSinceReferenceDate]-start);
    metadataRequire([[placeholder objectForKey:@"action"] isEqual:@"placeholder"] && ![placeholder objectForKey:@"job"],@"Missing page returns a non-actionable placeholder");
    deadline=[NSDate dateWithTimeIntervalSinceNow:10];
    while(![rows cachedObjectAtIndex:indexes[i]] && [deadline timeIntervalSinceNow]>0)
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    metadataRequire([rows cachedObjectAtIndex:indexes[i]]!=nil,@"Random jump asynchronously fetches its bounded presentation page");
  }
  metadataRequire(!source->mainRead && source->reads<=160,@"100000 rows use bounded background presentation work");
  metadataRequire(![rows cachedObjectAtIndex:0],@"Old pages leave the bounded presentation cache");
  NSLog(@"Async 100000-row fixture: %lu source rows, max main request %.3f ms (budget 50 ms)",(unsigned long)source->reads,maximum*1000);
  metadataRequire(maximum<0.05,@"Placeholder callbacks meet the legacy-device 50 ms budget");
  [rows RDLP_invalidateRows];
  RDLPAsyncFixture *readySource=[[[RDLPAsyncFixture alloc] init] autorelease]; readySource->total=2048;
  RDLPVideoRows *lazy=[[[RDLPVideoRows alloc] initWithRows:readySource library:nil playlist:nil] autorelease];
  NSTimeInterval preparation=[NSDate timeIntervalSinceReferenceDate];
  NSArray *ready=[lazy RDLP_preparedRows];
  preparation=[NSDate timeIntervalSinceReferenceDate]-preparation;
  metadataRequire([ready count]==2048 && readySource->reads==2048,@"Initial presentation prepares every row before exposing it");
  metadataRequire([[ready downloadHeaderIndexes] firstIndex]==NSNotFound,@"Ungrouped prepared rows have an empty header index set");
  [lazy invalidatePages];
  NSUInteger reads=readySource->reads;
  NSUInteger jumps[]={0,2047,512,1024,32,1536,0};
  for(i=0;i<7;++i) {
    NSDictionary *row=[ready RDLP_requestRow:jumps[i]];
    metadataRequire([[row objectForKey:@"title"] isEqual:@"Fixture"] && [row objectForKey:@"detail"] &&
      [[[row objectForKey:@"job"] objectForKey:@"id"] intValue]==(int)jumps[i],
      @"Scrolling beyond the page cache and back always returns complete matching text");
  }
  metadataRequire(readySource->reads==reads,@"Prepared cell access performs no additional source reads");
  NSLog(@"Prepared 2048 presentation rows in %.3f seconds; scrolling reads: %lu",preparation,(unsigned long)(readySource->reads-reads));
  [pool drain];
}
