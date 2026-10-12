#import "RDLPListLoader.h"
@implementation RDLPListLoader
- (id)initWithTarget:(id)target builder:(Class)builder;
{ self=[super init]; if(self) { target_=target; builder_=builder; lock_=[[NSLock alloc] init]; } return self; }
- (void)dealloc;
{ [lock_ release]; [pending_ release]; [super dealloc]; }
- (void)request:(NSDictionary *)input;
{
  [lock_ lock]; ++generation_;
  [pending_ release]; pending_=[input copy];
  BOOL start=!working_ && !invalid_; if(start) working_=YES;
  [lock_ unlock];
  if(start) [NSThread detachNewThreadSelector:@selector(work:) toTarget:self withObject:nil];
}
- (void)invalidate;
{
  [lock_ lock]; invalid_=YES; target_=nil; ++generation_;
  [pending_ release]; pending_=nil; [lock_ unlock];
}
- (BOOL)isCancelled;
{
  [lock_ lock]; BOOL cancelled=invalid_ || pending_!=nil; [lock_ unlock];
  return cancelled;
}
- (BOOL)isLoading;
{ [lock_ lock]; BOOL loading=working_ || pending_!=nil; [lock_ unlock]; return loading; }
- (void)work:(id)ignored;
{
  (void)ignored;
  for(;;) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    [lock_ lock];
    NSDictionary *input=pending_; pending_=nil;
    unsigned long generation=generation_;
    if(!input || invalid_) { working_=NO; [lock_ unlock]; [input release]; [pool drain]; return; }
    [lock_ unlock];
    [[[NSThread currentThread] threadDictionary] setObject:self forKey:@"RDLPListLoader"];
    NSDictionary *output=[builder_ buildList:input];
    NSString *error=[[[NSThread currentThread] threadDictionary] objectForKey:@"RDLPListError"];
    if(error) output=[NSDictionary dictionaryWithObject:error forKey:@"error"];
    [[[NSThread currentThread] threadDictionary] removeObjectForKey:@"RDLPListLoader"];
    NSDictionary *result=[NSDictionary dictionaryWithObjectsAndKeys:output?output:[NSDictionary dictionary],@"output",
      [NSNumber numberWithUnsignedLong:generation],@"generation",nil];
    [self performSelectorOnMainThread:@selector(deliver:) withObject:result waitUntilDone:YES];
    [[[NSThread currentThread] threadDictionary] removeObjectForKey:@"RDLPListError"];
    [input release]; [pool drain];
  }
}
- (void)deliver:(NSDictionary *)result;
{
  [lock_ lock]; BOOL current=!invalid_ && generation_==[[result objectForKey:@"generation"] unsignedLongValue];
  id target=target_; [lock_ unlock];
  if(current) [target didLoadList:[result objectForKey:@"output"]];
}
@end
@implementation NSArray (RDLPAsyncRows)
- (id)RDLP_requestRow:(NSUInteger)index;
{
  if(index>=[self count]) return nil;
  if([self respondsToSelector:@selector(requestObjectAtIndex:placeholder:)]) {
    BOOL failed=[(AIPagedRows *)self readError]!=nil;
    NSDictionary *placeholder=[NSDictionary dictionaryWithObjectsAndKeys:
      failed?NSLocalizedString(@"Couldn’t read library",nil):NSLocalizedString(@"Loading…",nil),@"title",@"placeholder",@"action",nil];
    return [(AIPagedRows *)self requestObjectAtIndex:index placeholder:placeholder];
  }
  return [self objectAtIndex:index];
}
- (void)RDLP_invalidateRows;
{ if([self respondsToSelector:@selector(invalidatePages)]) [(AIPagedRows *)self invalidatePages]; }
- (BOOL)RDLP_containsRows:(id)rows; { return self==rows; }
@end
