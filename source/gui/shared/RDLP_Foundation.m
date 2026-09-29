#import "RDLP_Foundation.h"
#import <TargetConditionals.h>
#include "rdlp_thread.h"

static void *RDLPThreadMain(void *context) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  NSInvocation *invocation=(NSInvocation *)context;
  [invocation invoke];
  [invocation release];
  [pool drain];
  [NSThread exit];
  return NULL;
}

@implementation NSThread (RDLP_Foundation)
+ (BOOL)RLDP_isMainThread {
  if([self respondsToSelector:@selector(isMainThread)]) return [self isMainThread];
  /* Tiger predates NSThread's main-thread queries. */
  return rdlp_thread_is_main()!=0;
}
+ (void)RDLP_prepareMultithreading:(id)object { (void)object; }
+ (int)RDLP_detachNewThreadSelector:(SEL)selector toTarget:(id)target
                       withObject:(id)object stackSize:(NSUInteger)stackSize {
  /* Tiger needs an NSThread launch to enable Cocoa's internal locks before
     using Cocoa on POSIX threads. The bootstrap does no application work. */
  if(![self isMultiThreaded])
    [self detachNewThreadSelector:@selector(RDLP_prepareMultithreading:)
      toTarget:self withObject:nil];
  NSInvocation *invocation=[[NSInvocation invocationWithMethodSignature:
    [target methodSignatureForSelector:selector]] retain];
  [invocation setTarget:target];
  [invocation setSelector:selector];
  [invocation setArgument:&object atIndex:2];
  [invocation retainArguments];
  int error=rdlp_thread_start(RDLPThreadMain,invocation,(size_t)stackSize);
  if(error) [invocation release];
  return error;
}
@end

@implementation NSFileManager (RDLP_Foundation)
- (BOOL)RDLP_createDirectoryAtPath:(NSString *)path error:(NSError **)error {
  NSDictionary *attributes=[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:0700]
    forKey:NSFilePosixPermissions];
  if(error) *error=nil;
  if([self respondsToSelector:@selector(createDirectoryAtPath:withIntermediateDirectories:attributes:error:)])
    return [self createDirectoryAtPath:path withIntermediateDirectories:YES attributes:attributes error:error];
#if !TARGET_OS_IPHONE
  /* Tiger has only the older API. Stop at the nearest existing directory. */
  BOOL directory=NO;
  if([self fileExistsAtPath:path isDirectory:&directory] && directory) return YES;
  NSString *parent=[path stringByDeletingLastPathComponent];
  if([path isAbsolutePath] && ![parent isEqualToString:path] &&
     [self RDLP_createDirectoryAtPath:parent error:error] &&
     [self createDirectoryAtPath:path attributes:attributes]) return YES;
  if(error && !*error) *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
    userInfo:[NSDictionary dictionaryWithObject:path forKey:NSFilePathErrorKey]];
#endif
  return NO;
}
@end

NSString * const RDLPDateBoundariesDidChange=@"RDLPDateBoundariesDidChange";

/* Keep deprecated calendar-unit spellings inside the compatibility layer. */
#if (defined(__MAC_OS_X_VERSION_MAX_ALLOWED) && __MAC_OS_X_VERSION_MAX_ALLOWED >= 101000) || (defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000)
#define RDLPDay NSCalendarUnitDay
#define RDLPWeek NSCalendarUnitWeekOfYear
#define RDLPMonth NSCalendarUnitMonth
#define RDLPYear NSCalendarUnitYear
#define RDLPEra NSCalendarUnitEra
#define RDLPWeekday NSCalendarUnitWeekday
#else
#define RDLPDay NSDayCalendarUnit
#define RDLPWeek NSWeekCalendarUnit
#define RDLPMonth NSMonthCalendarUnit
#define RDLPYear NSYearCalendarUnit
#define RDLPEra NSEraCalendarUnit
#define RDLPWeekday NSWeekdayCalendarUnit
#endif

@interface RDLPDateMonitor : NSObject {
  NSTimer *timer_;
}
- (void)refresh:(id)sender;
- (void)dateChanged:(NSNotification *)notification;
@end

@implementation NSCalendar (RDLP_Foundation)
- (NSDate *)RDLP_startOfUnit:(NSCalendarUnit)unit date:(NSDate *)date;
{
  SEL selector=@selector(rangeOfUnit:startDate:interval:forDate:);
  if([self respondsToSelector:selector]) {
    NSInvocation *invocation=[NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:selector]];
    NSDate *start=nil, **startPointer=&start; NSTimeInterval interval=0, *intervalPointer=&interval; BOOL success=NO;
    [invocation setTarget:self]; [invocation setSelector:selector];
    [invocation setArgument:&unit atIndex:2]; [invocation setArgument:&startPointer atIndex:3];
    [invocation setArgument:&intervalPointer atIndex:4]; [invocation setArgument:&date atIndex:5];
    [invocation invoke]; [invocation getReturnValue:&success]; if(success) return start;
  }
  NSUInteger units=RDLPEra|RDLPYear|RDLPMonth|RDLPDay;
  NSDateComponents *components=[self components:units fromDate:date];
  if(unit==RDLPYear) { [components setMonth:1]; [components setDay:1]; }
  else if(unit==RDLPMonth) [components setDay:1];
  NSDate *start=[self dateFromComponents:components];
  if(unit==RDLPWeek) {
    NSInteger weekday=[[self components:RDLPWeekday fromDate:date] weekday];
    NSDateComponents *offset=[[[NSDateComponents alloc] init] autorelease];
    [offset setDay:-((weekday-(NSInteger)[self firstWeekday]+7)%7)];
    start=[self dateByAddingComponents:offset toDate:start options:0];
    start=[self dateFromComponents:[self components:units fromDate:start]];
  }
  return start;
}
- (NSArray *)RDLP_downloadSectionStartsForDate:(NSDate *)date;
{
  return [NSArray arrayWithObjects:[self RDLP_startOfUnit:RDLPDay date:date],
    [self RDLP_startOfUnit:RDLPWeek date:date],[self RDLP_startOfUnit:RDLPMonth date:date],
    [self RDLP_startOfUnit:RDLPYear date:date],nil];
}
+ (void)RDLP_monitorDateBoundaries;
{
  static RDLPDateMonitor *monitor=nil;
  if(monitor) return;
  monitor=[[RDLPDateMonitor alloc] init];
  NSArray *names=[NSArray arrayWithObjects:@"NSCurrentLocaleDidChangeNotification",
#if TARGET_OS_IPHONE
    @"UIApplicationSignificantTimeChangeNotification",@"UIApplicationDidBecomeActiveNotification",
#else
    @"NSSystemTimeZoneDidChangeNotification",@"NSSystemClockDidChangeNotification",@"NSApplicationDidBecomeActiveNotification",
#endif
    nil];
  NSEnumerator *enumerator=[names objectEnumerator]; NSString *name;
  while((name=[enumerator nextObject])) [[NSNotificationCenter defaultCenter] addObserver:monitor selector:@selector(dateChanged:) name:name object:nil];
  [monitor refresh:nil];
}
@end

@implementation RDLPDateMonitor
- (void)dateChanged:(NSNotification *)notification;
{ [self performSelectorOnMainThread:@selector(refresh:) withObject:notification waitUntilDone:NO]; }
- (void)refresh:(id)sender;
{
#if !TARGET_OS_IPHONE
  [timer_ invalidate]; [timer_ release];
  NSCalendar *calendar=[NSCalendar currentCalendar]; NSDate *now=[NSDate date];
  NSDateComponents *offset=[[[NSDateComponents alloc] init] autorelease]; [offset setDay:1];
  NSDate *tomorrow=[calendar dateByAddingComponents:offset toDate:[calendar RDLP_startOfUnit:RDLPDay date:now] options:0];
  tomorrow=[calendar RDLP_startOfUnit:RDLPDay date:tomorrow];
  timer_=[[NSTimer timerWithTimeInterval:MAX(1.0,[tomorrow timeIntervalSinceDate:now]) target:self selector:@selector(refresh:) userInfo:nil repeats:NO] retain];
  /* NSRunLoopCommonModes requires Leopard. A midnight refresh may wait until
     menu tracking or dragging ends; the default mode also works on Tiger. */
  [[NSRunLoop currentRunLoop] addTimer:timer_ forMode:NSDefaultRunLoopMode];
#endif
  if(sender) [[NSNotificationCenter defaultCenter] postNotificationName:RDLPDateBoundariesDidChange object:nil];
}
@end
