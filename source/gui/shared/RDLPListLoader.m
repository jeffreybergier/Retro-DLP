#import "RDLPListLoader.h"
#import "RDLPLibrary.h"
#import "RDLPDownloadSections.h"
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
/* A presentation snapshot owns all row text. Its query source remains paged,
 * and supplies identity/section metadata without changing the displayed rows. */
@interface RDLPPreparedRows : NSArray {
  NSArray *source_, *rows_;
}
- (id)initWithRows:(NSArray *)source;
@end
@implementation RDLPPreparedRows
- (id)initWithRows:(NSArray *)source;
{
  self=[super init]; if(!self) return nil;
  source_=[source retain];
  NSMutableArray *rows=[[NSMutableArray alloc] initWithCapacity:[source count]];
  @try {
    NSUInteger index;
    for(index=0;index<[source count];++index) {
      NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
      @try {
        if([[AICollectionController currentController] isCancelled])
          [NSException raise:@"RDLPListCancelled" format:@"List preparation cancelled"];
        id row=[source objectAtIndex:index];
        NSError *error=[source respondsToSelector:@selector(readError)]?[(AIPagedRows *)source readError]:nil;
        if(error) [NSException raise:@"RDLPListReadFailed" format:@"%@",[error localizedDescription]];
        [rows addObject:row];
      } @finally { [pool drain]; }
    }
    rows_=[rows copy];
  } @catch(id exception) { [self release]; @throw; }
  @finally { [rows release]; }
  return self;
}
- (void)dealloc; { [source_ release]; [rows_ release]; [super dealloc]; }
- (NSUInteger)count; { return [rows_ count]; }
- (id)objectAtIndex:(NSUInteger)index; { return [rows_ objectAtIndex:index]; }
- (id)cachedObjectAtIndex:(NSUInteger)index; { return index<[rows_ count]?[rows_ objectAtIndex:index]:nil; }
- (id)copyWithZone:(NSZone *)zone; { (void)zone; return [self retain]; }
- (NSArray *)RDLP_preparedRows; { return self; }
- (NSArray *)RDLP_collectionIdentifiers; { return [source_ RDLP_collectionIdentifiers]; }
- (NSUInteger)indexForIdentity:(NSString *)identity;
{ return [source_ respondsToSelector:_cmd]?[(RDLPLibraryRows *)source_ indexForIdentity:identity]:NSNotFound; }
- (NSArray *)jobsForPlaylist:(NSString *)playlist video:(NSString *)video;
{ return [(RDLPLibraryRows *)source_ jobsForPlaylist:playlist video:video]; }
- (BOOL)isSectionAtIndex:(NSUInteger)index;
{ return [source_ respondsToSelector:_cmd] && [(id)source_ isSectionAtIndex:index]; }
- (NSIndexSet *)downloadHeaderIndexes;
{ return [source_ respondsToSelector:_cmd]?[(id)source_ downloadHeaderIndexes]:[NSIndexSet indexSet]; }
@end

@implementation NSArray (RDLPAsyncRows)
- (NSArray *)RDLP_preparedRows;
{ return [[[RDLPPreparedRows alloc] initWithRows:self] autorelease]; }
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
  return [self objectAtIndex:index];
}
- (void)RDLP_invalidateRows;
{ if([self respondsToSelector:@selector(invalidatePages)]) [(AIPagedRows *)self invalidatePages]; }
- (BOOL)RDLP_containsRows:(id)rows; { return self==rows; }
@end
