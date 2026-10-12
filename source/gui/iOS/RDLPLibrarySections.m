#import <AICollectionSnapshot.h>
#import "RDLPLibrarySections.h"
#import "RDLPVideoRows.h"
#import "RDLPDownloadSections.h"
#import "RDLPListLoader.h"

/* Formatting belongs to row access, never to section/count construction. */
@interface RDLPLibrarySections (Rows)
- (NSDictionary *)displayRow:(NSDictionary *)item screen:(RDLPScreen)screen playlist:(NSString *)playlist;
@end
@interface RDLPSectionRows : AIPagedRows {
  NSArray *source_;
  RDLPLibrarySections *model_;
  RDLPScreen screen_;
  NSString *playlist_;
}
- (id)initWithRows:(NSArray *)rows model:(RDLPLibrarySections *)model screen:(RDLPScreen)screen playlist:(NSString *)playlist;
- (NSUInteger)indexForIdentity:(NSString *)identity;
@end
@implementation RDLPSectionRows
- (id)initWithRows:(NSArray *)rows model:(RDLPLibrarySections *)model screen:(RDLPScreen)screen playlist:(NSString *)playlist;
{ self=[super init]; if(self) { source_=[rows retain]; model_=[model retain]; screen_=screen; playlist_=[playlist copy]; } return self; }
- (void)dealloc; { [source_ release]; [model_ release]; [playlist_ release]; [super dealloc]; }
- (NSUInteger)count; { return [source_ count]; }
- (NSArray *)RDLP_collectionIdentifiers; { return [source_ RDLP_collectionIdentifiers]; }
- (id)copyWithZone:(NSZone *)zone; { (void)zone; return [self retain]; }
- (NSArray *)pageAtOffset:(NSUInteger)offset error:(NSError **)error;
{
  NSMutableArray *page=[NSMutableArray array];
  NSUInteger i, end=MIN(offset+32,[self count]);
  for(i=offset;i<end;++i) {
    NSDictionary *row=[source_ objectAtIndex:i];
    if([source_ respondsToSelector:@selector(readError)] && [(AIPagedRows *)source_ readError]) break;
    [page addObject:[model_ displayRow:row screen:screen_ playlist:playlist_]];
  }
  if([source_ respondsToSelector:@selector(readError)] && [(AIPagedRows *)source_ readError]) {
    if(error) *error=[(AIPagedRows *)source_ readError]; return nil;
  }
  return page;
}
- (void)RDLP_invalidateRows;
{ [self invalidatePages]; [source_ RDLP_invalidateRows]; }
- (NSUInteger)indexForIdentity:(NSString *)identity;
{ return [(RDLPLibraryRows *)source_ indexForIdentity:identity]; }
@end

@implementation RDLPLibrarySections
+ (NSDictionary *)buildList:(NSDictionary *)input;
{
  RDLPLibrary *library=[input objectForKey:@"library"];
  RDLPLibrarySections *model=[[[self alloc] initWithLibrary:library] autorelease];
  NSDictionary *playlist=[input objectForKey:@"playlist"];
  NSDictionary *current=[library playlistForID:[playlist objectForKey:@"id"]];
  if(current) playlist=current;
  NSArray *sections=[model sectionsForScreen:(RDLPScreen)[[input objectForKey:@"mode"] intValue] playlist:playlist video:[input objectForKey:@"video"] collapsed:nil];
  NSMutableDictionary *result=[NSMutableDictionary dictionaryWithDictionary:input];
  [result setObject:sections forKey:@"sections"];
  NSMutableArray *metadata=[NSMutableArray array];
  NSEnumerator *sectionEnumerator=[sections objectEnumerator]; NSDictionary *item;
  NSUInteger remaining=AICollectionIdentityLimit;
  while((item=[sectionEnumerator nextObject])) {
    NSMutableDictionary *entry=[[item mutableCopy] autorelease];
    [entry setObject:[item objectForKey:@"title"] forKey:@"id"];
    NSArray *rows=[item objectForKey:@"rows"];
    if([rows count]<=remaining) {
      NSArray *ids=[rows RDLP_collectionIdentifiers];
      if(ids) [entry setObject:ids forKey:@"identifiers"];
      remaining-=[rows count];
    } else remaining=0;
    [metadata addObject:entry];
  }
  [result setObject:[[[AICollectionSnapshot alloc] initWithSections:metadata] autorelease] forKey:@"collection"];
  if(playlist) [result setObject:playlist forKey:@"playlist"];
  NSArray *keys=[NSArray arrayWithObjects:@"anchor",@"selection",nil];
  NSEnumerator *e=[keys objectEnumerator]; NSString *key;
  while((key=[e nextObject])) {
    NSString *identity=[input objectForKey:key]; NSUInteger section;
    NSArray *oldRows=[input objectForKey:@"anchorRows"];
    NSUInteger oldIndex=[[input objectForKey:@"anchorRow"] unsignedLongValue];
    if(!identity && [key isEqualToString:@"anchor"] && oldIndex<[oldRows count]) {
      NSDictionary *old=[oldRows objectAtIndex:oldIndex];
      BOOL playlistMode=[[input objectForKey:@"mode"] intValue]==RDLPScreenPlaylist;
      identity=playlistMode?[[old objectForKey:@"video"] objectForKey:@"position"]:
        ([[old objectForKey:@"job"] objectForKey:@"id"]?:[[old objectForKey:@"playlist"] objectForKey:@"id"]);
    }
    if(![identity length]) continue;
    for(section=0;section<[sections count];++section) {
      NSArray *rows=[[sections objectAtIndex:section] objectForKey:@"rows"];
      if(![rows respondsToSelector:@selector(indexForIdentity:)]) continue;
      NSUInteger row=[(RDLPLibraryRows *)rows indexForIdentity:identity];
      if(row!=NSNotFound) {
        [result setObject:[NSArray arrayWithObjects:[NSNumber numberWithUnsignedLong:section],[NSNumber numberWithUnsignedLong:row],nil] forKey:[key stringByAppendingString:@"Index"]]; break;
      }
    }
  }
  [result removeObjectForKey:@"anchorRows"];
  return result;
}
- (id)initWithLibrary:(RDLPLibrary *)library;
{ self=[super init]; if(self) { library_=[library retain]; policy_=[[RDLPDownloadPolicy alloc] initWithLibrary:library]; } return self; }
- (void)dealloc; { [library_ release]; [policy_ release]; [super dealloc]; }
- (NSDictionary *)section:(NSString *)title rows:(NSArray *)rows;
{ return [NSDictionary dictionaryWithObjectsAndKeys:title,@"title",rows,@"rows",nil]; }
- (NSMutableDictionary *)row:(NSString *)title detail:(NSString *)detail action:(NSString *)action;
{ return [NSMutableDictionary dictionaryWithObjectsAndKeys:title?title:NSLocalizedString(@"Untitled", nil),@"title",detail?detail:@"",@"detail",action,@"action",nil]; }
- (NSDictionary *)currentJob:(NSString *)key;
{ return [library_ jobForID:key]; }
- (NSDictionary *)jobForPlaylist:(NSString *)playlist video:(NSString *)video format:(NSString *)format;
{ return [library_ jobForPlaylist:playlist video:video format:format]; }
- (NSArray *)missingPlanForPlaylist:(NSString *)playlist format:(NSString *)format;
{ return [library_ missingPlanForPlaylist:playlist format:format];
}
- (BOOL)canRemovePlaylist:(NSDictionary *)playlist;
{
  return [library_ canRemovePlaylist:playlist];
}
- (NSArray *)actionsForJob:(NSDictionary *)job;
{
  NSMutableArray *actions=[NSMutableArray array];
  if([policy_ playable:job]) [actions addObject:NSLocalizedString(@"Play", nil)];
  if([policy_ canRetry:job] || [policy_ canDownloadAgain:job]) [actions addObject:NSLocalizedString(@"Download Video", nil)];
  if([policy_ canCancel:job]) [actions addObject:NSLocalizedString(@"Stop…", nil)];
  if([policy_ canRemove:job] && ![policy_ canCancel:job]) [actions addObject:NSLocalizedString(@"Delete…", nil)];
  [actions addObject:NSLocalizedString(@"Show in Queue", nil)];
  return actions;
}
- (NSDictionary *)jobRow:(NSDictionary *)job;
{
  NSString *status=[policy_ statusForJob:job];
  NSString *detail=[NSString stringWithFormat:NSLocalizedString(@"%@·%@\n%@", nil),status,[RDLPLibrary qualityLabelForFormat:[job objectForKey:@"format"]],([job objectForKey:@"error"]?[job objectForKey:@"error"]:@"")];
  NSMutableDictionary *row=[self row:[job objectForKey:@"title"] detail:detail action:@"job"];
  [row setObject:job forKey:@"job"]; [row setObject:status forKey:@"status"]; return row;
}
- (NSArray *)displayRows:(NSArray *)rows screen:(RDLPScreen)screen playlist:(NSString *)playlist;
{ return [[[RDLPSectionRows alloc] initWithRows:rows model:self screen:screen playlist:playlist] autorelease]; }
- (NSString *)subtitleForJob:(NSDictionary *)job dateKey:(NSString *)key;
{
  NSMutableArray *parts=[NSMutableArray array];
  if([[job objectForKey:@"playlist_title"] length]) [parts addObject:[job objectForKey:@"playlist_title"]];
  if([[job objectForKey:@"format"] length]) [parts addObject:[RDLPLibrary qualityLabelForFormat:[job objectForKey:@"format"]]];
  NSString *detail=[parts componentsJoinedByString:@"·"];
  NSTimeInterval seconds=[[job objectForKey:key] doubleValue];
  if(seconds>0) detail=[NSString stringWithFormat:NSLocalizedString(@"%@·%@", nil),
    [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:seconds]
      dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterNoStyle],detail];
  return detail;
}
- (NSDictionary *)displayRow:(NSDictionary *)item screen:(RDLPScreen)screen playlist:(NSString *)playlist;
{
  if(screen==RDLPScreenDownloads || screen==RDLPScreenPlaylist) {
    NSMutableDictionary *row=[[item mutableCopy] autorelease];
    NSDictionary *job=[item objectForKey:@"job"];
    if(screen==RDLPScreenPlaylist) {
      /* Added Videos has one row per occurrence, not per downloaded quality.
         Its date is the latest enqueue across qualities, independent of which
         playable job supplies the row's actions and quality label. */
      NSMutableDictionary *subtitle=[NSMutableDictionary dictionaryWithDictionary:job?job:[NSDictionary dictionary]];
      NSDictionary *entry=[item objectForKey:@"video"];
      [subtitle setObject:[entry objectForKey:@"enqueueDate"] forKey:@"enqueueDate"];
      [subtitle setObject:[entry objectForKey:@"playlist_title"] forKey:@"playlist_title"];
      job=subtitle;
    }
    NSString *detail=[self subtitleForJob:job dateKey:screen==RDLPScreenDownloads?@"latestDownloadDate":@"enqueueDate"];
    NSString *spoken=[[job objectForKey:@"format"] length]?[detail stringByAppendingFormat:NSLocalizedString(@", %@", nil),[job objectForKey:@"format"]]:detail;
    [row setObject:detail forKey:@"detail"]; [row setObject:spoken forKey:@"spoken_detail"];
    [row setObject:[NSString stringWithFormat:NSLocalizedString(@"%@, %@, %@", nil),[row objectForKey:@"title"],spoken,[row objectForKey:@"status"]] forKey:@"accessibility_label"];
    return row;
  }
  if(screen==RDLPScreenLibrary) {
    NSMutableDictionary *row=[self row:[item objectForKey:@"title"] detail:[[item objectForKey:@"synced_at"] length]?[NSString stringWithFormat:NSLocalizedString(@"%@ videos", nil),[item objectForKey:@"count"]]:NSLocalizedString(@"Not synced", nil) action:@"playlist"];
    if(![[item objectForKey:@"service_id"] isEqualToString:@RDAPP_ADHOC_PLAYLIST_ID] && ![RDLPLibrary canSyncPlaylist:item]) [row setObject:NSLocalizedString(@"This playlist type cannot be synced", nil) forKey:@"detail"];
    [row setObject:item forKey:@"playlist"]; return row;
  }
  if(screen==RDLPScreenQueue) {
    NSString *title=[item objectForKey:@"title"];
    NSString *detail=[self subtitleForJob:item dateKey:@"enqueueDate"];
    NSMutableDictionary *row=[self row:title detail:detail action:@"job"];
    [row setObject:[[item objectForKey:@"format"] length]?[detail stringByAppendingFormat:NSLocalizedString(@", %@", nil),[item objectForKey:@"format"]]:detail forKey:@"spoken_detail"];
    NSString *status=[policy_ statusForJob:item];
    [row setObject:[status isEqualToString:NSLocalizedString(@"Cancelled", nil)]?NSLocalizedString(@"Stopped", nil):status forKey:@"status"];
    [row setObject:item forKey:@"job"]; return row;
  }
  return [self jobRow:item];
}
- (NSArray *)sectionsForScreen:(RDLPScreen)screen playlist:(NSDictionary *)playlist video:(NSDictionary *)video collapsed:(NSSet *)collapsed;
{
  (void)collapsed;
  NSMutableArray *sections=[NSMutableArray array], *rows=[NSMutableArray array];
  NSString *pid=[playlist objectForKey:@"id"];
  if(screen==RDLPScreenLibrary) {
    [rows addObject:[self row:NSLocalizedString(@"All Downloads", nil) detail:@"" action:@"downloads"]];
    NSDictionary *adhoc=[library_ adhocPlaylist];
    if(adhoc) {
      NSMutableDictionary *row=[self row:NSLocalizedString(@"Added Videos", nil) detail:[NSString stringWithFormat:NSLocalizedString(@"%@ videos", nil),[adhoc objectForKey:@"count"]] action:@"playlist"];
      [row setObject:adhoc forKey:@"playlist"]; [rows addObject:row];
    }
    [sections addObject:[self section:NSLocalizedString(@"System", nil) rows:rows]];
    [sections addObject:[self section:NSLocalizedString(@"Added Playlists", nil) rows:[self displayRows:[library_ playlistsFromAccount:NO] screen:screen playlist:nil]]];
    [sections addObject:[self section:NSLocalizedString(@"My Playlists", nil) rows:[self displayRows:[library_ playlistsFromAccount:YES] screen:screen playlist:nil]]];
    [sections addObject:[self section:NSLocalizedString(@"Unsupported Playlists", nil) rows:[self displayRows:[library_ unsupportedPlaylists] screen:screen playlist:nil]]];
  } else if(screen==RDLPScreenSettings) {
    NSArray *titles=[RDLPLibrary qualityTitles], *formats=[RDLPLibrary qualityFormats]; NSString *format=[RDLPLibrary preferredFormat];
    for(NSUInteger i=0;i<[titles count];++i) {
      NSMutableDictionary *row=[self row:[titles objectAtIndex:i] detail:i==3?format:@"" action:i==3?@"custom":@"quality"];
      if(i<3) [row setObject:[formats objectAtIndex:i] forKey:@"format"];
      [row setObject:[NSNumber numberWithBool:i<3?[format isEqualToString:[formats objectAtIndex:i]]:![formats containsObject:format]] forKey:@"checked"]; [rows addObject:row];
    }
    [sections addObject:[self section:NSLocalizedString(@"Download Quality", nil) rows:rows]];
    NSMutableArray *cookies=[NSMutableArray array];
    [cookies addObject:[self row:NSLocalizedString(@"Import Cookies...", nil) detail:@"" action:@"import"]];
    [cookies addObject:[self row:NSLocalizedString(@"Remove Cookies…", nil) detail:@"" action:@"clearCookies"]];
    [cookies addObject:[self row:NSLocalizedString(@"Export Guide", nil) detail:@"" action:@"guide"]];
    [sections addObject:[self section:NSLocalizedString(@"Cookies", nil) rows:cookies]];
  } else {
    if(screen==RDLPScreenQueue)
      return [NSArray arrayWithObject:[self section:@"" rows:[self displayRows:[library_ queueRows] screen:screen playlist:nil]]];
    if(screen==RDLPScreenPlaylist || screen==RDLPScreenDownloads) {
      BOOL added=screen==RDLPScreenPlaylist && [[playlist objectForKey:@"service_id"] isEqualToString:@RDAPP_ADHOC_PLAYLIST_ID];
      NSArray *source=added?[library_ addedVideos]:(screen==RDLPScreenPlaylist?[library_ entriesForPlaylist:pid]:[library_ allDownloads]);
      if(screen==RDLPScreenDownloads || added) {
        RDLPDownloadSections *groups=[[[RDLPDownloadSections alloc] initWithRows:(RDLPLibraryRows *)source date:[NSDate date] calendar:[NSCalendar currentCalendar]] autorelease];
        NSArray *videos=[[[RDLPVideoRows alloc] initWithRows:source library:library_ playlist:added?pid:nil] autorelease];
        return [groups sectionsWithRows:[self displayRows:videos screen:screen playlist:added?pid:nil]];
      }
      return [NSArray arrayWithObject:[self section:screen==RDLPScreenPlaylist?NSLocalizedString(@"Videos", nil):NSLocalizedString(@"Downloads", nil) rows:[[[RDLPVideoRows alloc] initWithRows:source library:library_ playlist:screen==RDLPScreenPlaylist?pid:nil] autorelease]]];
    } else {
      NSArray *jobs=[library_ jobsForPlaylist:pid video:[video objectForKey:@"video_id"]];
      if(screen==RDLPScreenVideo) {
        NSMutableArray *commands=[NSMutableArray array];
        NSDictionary *representative=[policy_ representativeJobForEntry:video playlist:pid jobs:jobs];
        if([policy_ playable:representative]) {
          NSMutableDictionary *play=[self row:NSLocalizedString(@"Play", nil) detail:[RDLPLibrary qualityLabelForFormat:[representative objectForKey:@"format"]] action:@"play"];
          [play setObject:representative forKey:@"job"]; [commands addObject:play];
        }
        NSDictionary *exact=[self jobForPlaylist:pid video:[video objectForKey:@"video_id"] format:[RDLPLibrary preferredFormat]];
        NSString *action=[policy_ playable:exact]?@"delete":([policy_ canCancel:exact]?@"showQueue":@"download");
        NSMutableDictionary *command=[self row:[action isEqualToString:@"delete"]?NSLocalizedString(@"Delete…", nil):([action isEqualToString:@"showQueue"]?NSLocalizedString(@"Show in Queue", nil):NSLocalizedString(@"Download Video", nil)) detail:[RDLPLibrary qualityLabelForFormat:[RDLPLibrary preferredFormat]] action:action];
        if(exact) [command setObject:exact forKey:@"job"]; [commands addObject:command];
        [commands addObject:[self row:NSLocalizedString(@"Download Quality", nil) detail:@"" action:@"settings"]];
        [sections addObject:[self section:([video objectForKey:@"title"]?[video objectForKey:@"title"]:NSLocalizedString(@"Video", nil)) rows:commands]];
      }
      [sections addObject:[self section:NSLocalizedString(@"Downloads", nil) rows:[self displayRows:jobs screen:screen playlist:pid]]];
      return sections;
    }
  }
  return sections;
}
@end
