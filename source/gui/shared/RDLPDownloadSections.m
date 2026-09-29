#import "RDLPDownloadSections.h"
#import "RDLP_Foundation.h"

@interface RDLPDownloadRangeRows : NSArray {
  NSArray *source_, *sections_;
  NSUInteger offset_, count_;
}
- (id)initWithRows:(NSArray *)rows offset:(NSUInteger)offset count:(NSUInteger)count sections:(NSArray *)sections;
- (NSUInteger)indexForIdentity:(NSString *)identity;
- (id)cachedObjectAtIndex:(NSUInteger)index;
@end
@implementation RDLPDownloadRangeRows
- (id)initWithRows:(NSArray *)rows offset:(NSUInteger)offset count:(NSUInteger)count sections:(NSArray *)sections;
{ self=[super init]; if(self) { source_=[rows retain]; offset_=offset; count_=count; sections_=[sections retain]; } return self; }
- (void)dealloc; { [source_ release]; [sections_ release]; [super dealloc]; }
- (NSUInteger)count; { return count_; }
- (id)copyWithZone:(NSZone *)zone; { (void)zone; return [self retain]; }
- (NSUInteger)sourceIndex:(NSUInteger)index;
{
  if(index>=count_) [NSException raise:NSRangeException format:@"Download row outside section"];
  if(!sections_) return offset_+index;
  NSUInteger i;
  for(i=0;i<[sections_ count];++i) {
    NSDictionary *section=[sections_ objectAtIndex:i];
    NSUInteger header=[[section objectForKey:@"offset"] unsignedLongValue]+i;
    if(index==header) return NSNotFound;
    if(index<header+1+[[section objectForKey:@"count"] unsignedLongValue]) return index-i-1;
  }
  return NSNotFound;
}
- (NSIndexSet *)downloadHeaderIndexes;
{
  NSMutableIndexSet *indexes=[NSMutableIndexSet indexSet]; NSUInteger i;
  for(i=0;i<[sections_ count];++i) [indexes addIndex:[[[sections_ objectAtIndex:i] objectForKey:@"offset"] unsignedLongValue]+i];
  return indexes;
}
- (BOOL)isSectionAtIndex:(NSUInteger)index;
{ return [self sourceIndex:index]==NSNotFound; }
- (id)objectAtIndex:(NSUInteger)index;
{
  NSUInteger source=[self sourceIndex:index];
  if(source!=NSNotFound) return [source_ objectAtIndex:source];
  NSUInteger i;
  for(i=0;i<[sections_ count];++i) {
    NSDictionary *section=[sections_ objectAtIndex:i];
    if(index==[[section objectForKey:@"offset"] unsignedLongValue]+i)
      return [NSDictionary dictionaryWithObjectsAndKeys:[section objectForKey:@"title"],@"title",@"section",@"action",nil];
  }
  @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Download section mapping is inconsistent" userInfo:nil];
}
- (id)cachedObjectAtIndex:(NSUInteger)index;
{
  NSUInteger source=[self sourceIndex:index];
  return source==NSNotFound?nil:[(RDLPLibraryRows *)source_ cachedObjectAtIndex:source];
}
- (NSUInteger)indexForIdentity:(NSString *)identity;
{
  NSUInteger source=[(RDLPLibraryRows *)source_ indexForIdentity:identity];
  if(source==NSNotFound) return NSNotFound;
  if(!sections_) return source>=offset_ && source<offset_+count_?source-offset_:NSNotFound;
  NSUInteger i;
  for(i=0;i<[sections_ count];++i) {
    NSDictionary *section=[sections_ objectAtIndex:i];
    if(source<[[section objectForKey:@"offset"] unsignedLongValue]+[[section objectForKey:@"count"] unsignedLongValue]) return source+i+1;
  }
  return NSNotFound;
}
@end

@implementation RDLPDownloadSections
- (id)initWithRows:(RDLPLibraryRows *)rows date:(NSDate *)date calendar:(NSCalendar *)calendar;
{
  self=[super init]; if(!self) return nil;
  NSArray *titles=[NSArray arrayWithObjects:@"Today",@"This Week",@"This Month",@"This Year",@"Older",nil];
  NSArray *starts=[calendar RDLP_downloadSectionStartsForDate:date];
  NSMutableArray *sections=[NSMutableArray array];
  NSUInteger i, offset=0;
  NSDate *earliest=nil;
  for(i=0;i<5;++i) {
    NSUInteger end=[rows count];
    if(i<4) {
      NSDate *start=[starts objectAtIndex:i];
      /* A week can start in the preceding month/year. Earlier buckets win. */
      if(!earliest || [start compare:earliest]==NSOrderedAscending) earliest=start;
      end=[rows downloadsSince:earliest];
    }
    if(end>offset) [sections addObject:[NSDictionary dictionaryWithObjectsAndKeys:
      [titles objectAtIndex:i],@"title",[NSNumber numberWithUnsignedLong:offset],@"offset",
      [NSNumber numberWithUnsignedLong:end-offset],@"count",nil]];
    offset=end;
  }
  sections_=[sections copy]; return self;
}
- (void)dealloc; { [sections_ release]; [super dealloc]; }
- (NSArray *)sections; { return sections_; }
- (NSArray *)sectionsWithRows:(NSArray *)rows;
{
  NSMutableArray *result=[NSMutableArray array];
  NSEnumerator *enumerator=[sections_ objectEnumerator]; NSDictionary *section;
  while((section=[enumerator nextObject])) {
    NSArray *slice=[[[RDLPDownloadRangeRows alloc] initWithRows:rows
      offset:[[section objectForKey:@"offset"] unsignedLongValue]
      count:[[section objectForKey:@"count"] unsignedLongValue] sections:nil] autorelease];
    [result addObject:[NSDictionary dictionaryWithObjectsAndKeys:[section objectForKey:@"title"],@"title",slice,@"rows",nil]];
  }
  return result;
}
- (NSArray *)tableRows:(NSArray *)rows;
{ return [[[RDLPDownloadRangeRows alloc] initWithRows:rows offset:0 count:[rows count]+[sections_ count] sections:sections_] autorelease]; }
@end
