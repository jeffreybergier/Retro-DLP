#import "../RDLPDownloadSections.h"
#import "../RDLP_Foundation.h"

/* A snapshot double detects accidental eager loading during section creation. */
@interface RDLPSectionFixture : NSArray {
@public
  NSArray *dates;
  NSUInteger reads;
}
- (NSUInteger)rowsSinceDate:(NSDate *)date;
- (NSUInteger)indexForIdentity:(NSString *)identity;
- (id)cachedObjectAtIndex:(NSUInteger)index;
@end
@implementation RDLPSectionFixture
- (void)dealloc; { [dates release]; [super dealloc]; }
- (NSUInteger)count; { return [dates count]; }
- (NSUInteger)rowsSinceDate:(NSDate *)date;
{
  NSUInteger i, count=0;
  for(i=0;i<[dates count];++i) if([(NSDate *)[dates objectAtIndex:i] compare:date]!=NSOrderedAscending) ++count;
  return count;
}
- (id)objectAtIndex:(NSUInteger)index;
{
  ++reads;
  return [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"%lu",(unsigned long)index] forKey:@"id"];
}
- (NSUInteger)indexForIdentity:(NSString *)identity;
{ NSUInteger index=(NSUInteger)[identity intValue]; return index<[dates count]?index:NSNotFound; }
- (id)cachedObjectAtIndex:(NSUInteger)index; { (void)index; return nil; }
@end

static NSDate *sectionDate(NSCalendar *calendar,NSInteger year,NSInteger month,NSInteger day,NSInteger hour) {
  NSDateComponents *c=[[[NSDateComponents alloc] init] autorelease];
  [c setYear:year]; [c setMonth:month]; [c setDay:day]; [c setHour:hour];
  return [calendar dateFromComponents:c];
}
static void testDownloadSections(void) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  NSCalendar *calendar=[[[NSCalendar alloc] initWithCalendarIdentifier:@"gregorian"] autorelease];
  [calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]]; [calendar setFirstWeekday:2];
  RDLPSectionFixture *source=[[[RDLPSectionFixture alloc] init] autorelease];
  source->dates=[[NSArray alloc] initWithObjects:sectionDate(calendar,2026,9,29,1),sectionDate(calendar,2026,9,28,1),
    sectionDate(calendar,2026,9,15,1),sectionDate(calendar,2026,1,2,1),sectionDate(calendar,2025,1,2,1),[NSDate dateWithTimeIntervalSince1970:0],nil];
  RDLPDownloadSections *groups=[[[RDLPDownloadSections alloc] initWithRows:(RDLPLibraryRows *)source date:sectionDate(calendar,2026,9,29,12) calendar:calendar] autorelease];
  NSArray *sections=[groups sectionsWithRows:source], *table=[groups tableRows:source];
  metadataRequire(source->reads==0 && [sections count]==5 && [table count]==11,@"Section counts never fetch jobs");
  metadataRequire([[[sections objectAtIndex:0] objectForKey:@"title"] isEqual:@"Today"] && [[[sections objectAtIndex:4] objectForKey:@"rows"] count]==2,@"Calendar buckets include unknown dates in Older");
  metadataRequire([[table downloadHeaderIndexes] count]==5 && [table isSectionAtIndex:8] && source->reads==0,@"Header checks never fetch jobs");
  metadataRequire([(RDLPLibraryRows *)table indexForIdentity:@"5"]==10,@"Selection maps stable identity past every header");
  metadataRequire([[[table objectAtIndex:10] objectForKey:@"id"] isEqual:@"5"] && source->reads==1,@"Only requested row loads");
  NSArray *older=[[sections objectAtIndex:4] objectForKey:@"rows"];
  metadataRequire([(RDLPLibraryRows *)older indexForIdentity:@"5"]==1 && [(RDLPLibraryRows *)older indexForIdentity:@"0"]==NSNotFound,@"Slice selection uses local coordinates");
  metadataRequire([(RDLPLibraryRows *)older cachedObjectAtIndex:0]==nil && source->reads==1,@"Offscreen editability never loads rows");
  groups=[[[RDLPDownloadSections alloc] initWithRows:(RDLPLibraryRows *)source date:sectionDate(calendar,2026,10,1,12) calendar:calendar] autorelease];
  sections=[groups sections];
  metadataRequire([sections count]==3 && [[[sections objectAtIndex:0] objectForKey:@"title"] isEqual:@"This Week"] && [[[sections objectAtIndex:0] objectForKey:@"count"] intValue]==2,@"Week spanning months wins over month; empty buckets omitted");
  [source->dates release]; source->dates=[[NSArray alloc] init];
  groups=[[[RDLPDownloadSections alloc] initWithRows:(RDLPLibraryRows *)source date:[NSDate date] calendar:calendar] autorelease];
  metadataRequire([[groups sections] count]==0 && [[groups tableRows:source] count]==0,@"Empty library has no headers");
  [calendar setTimeZone:[NSTimeZone timeZoneWithName:@"America/Los_Angeles"]];
  NSDate *before=[[calendar RDLP_downloadSectionStartsForDate:sectionDate(calendar,2026,3,8,12)] objectAtIndex:0];
  NSDate *after=[[calendar RDLP_downloadSectionStartsForDate:sectionDate(calendar,2026,3,9,12)] objectAtIndex:0];
  metadataRequire([after timeIntervalSinceDate:before]==23*3600,@"Day boundaries use calendar arithmetic across DST");
  [pool drain];
}
