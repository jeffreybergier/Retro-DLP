#import "../RDLPListLoader.h"
#import "../RDLPVideoRows.h"

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
  }
  return [NSDictionary dictionaryWithObjectsAndKeys:[input objectForKey:@"value"],@"value",
    [NSNumber numberWithBool:[NSThread RLDP_isMainThread]],@"main",nil];
}
- (void)didLoadList:(NSDictionary *)result;
{ ++deliveries; [last release]; last=[result copy]; }
- (void)dealloc; { [last release]; [super dealloc]; }
@end
@interface RDLPAsyncFixture : NSArray { @public NSUInteger reads; BOOL mainRead; }
@end
@implementation RDLPAsyncFixture
- (NSUInteger)count; { return 100000; }
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
  metadataRequire([gate lockWhenCondition:1 beforeDate:[NSDate dateWithTimeIntervalSinceNow:10]],@"Async snapshot worker starts without blocking main thread");
  [gate unlock];
  [loader request:[NSDictionary dictionaryWithObject:@"middle" forKey:@"value"]];
  [loader request:[NSDictionary dictionaryWithObject:@"latest" forKey:@"value"]];
  metadataRequire([loader isCancelled],@"New generation cancels obsolete count work");
  [gate lock]; [gate unlockWithCondition:2];
  NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
  while(!probe->deliveries && [deadline timeIntervalSinceNow]>0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
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
    NSDictionary *placeholder=[rows RDLP_requestRow:indexes[i]];
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
  [rows RDLP_invalidateRows]; [pool drain];
}
