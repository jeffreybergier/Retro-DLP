#import "RDLPListLoader.h"
@implementation RDLPListLoader
- (id)initWithTarget:(id)target builder:(Class)builder;
{ return [super initWithTarget:target selector:@selector(didLoadList:) builder:builder]; }
- (id)buildResultForRequest:(NSDictionary *)input;
{
  NSMutableDictionary *thread=[[NSThread currentThread] threadDictionary];
  [thread setObject:self forKey:@"RDLPListLoader"];
  id output=nil;
  @try {
    output=[super buildResultForRequest:input];
    NSString *error=[thread objectForKey:@"RDLPListError"];
    if(error) output=[NSDictionary dictionaryWithObject:error forKey:@"error"];
  } @catch (NSException *exception) {
    output=[NSDictionary dictionaryWithObject:([exception reason] ?: @"List read failed") forKey:@"error"];
  } @finally {
    [thread removeObjectForKey:@"RDLPListLoader"];
    [thread removeObjectForKey:@"RDLPListError"];
  }
  return output;
}
@end
@implementation NSArray (RDLPAsyncRows)
- (NSArray *)RDLP_collectionIdentifiers;
{
  /* Ordinary command rows are already resident. Paged subclasses opt in with
   * a narrow metadata query; never enumerate their display payloads here. */
  if([self isKindOfClass:[AIPagedRows class]]) return nil;
  NSMutableArray *ids=[NSMutableArray array];
  NSEnumerator *e=[self objectEnumerator]; NSDictionary *row;
  while((row=[e nextObject])) {
    id key=[row objectForKey:@"format"] ?: [row objectForKey:@"action"];
    if(!key) return nil;
    [ids addObject:key];
  }
  return ids;
}

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
