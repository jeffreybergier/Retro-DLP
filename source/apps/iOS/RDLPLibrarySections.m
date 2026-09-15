#import "RDLPLibrarySections.h"

/* Formatting belongs to row access, never to section/count construction. */
@interface RDLPLibrarySections (Rows)
- (NSDictionary *)displayRow:(NSDictionary *)item screen:(RDLPScreen)screen index:(NSUInteger)index playlist:(NSString *)playlist;
@end
@interface RDLPSectionRows : NSArray {
  NSArray *source_;
  RDLPLibrarySections *model_;
  RDLPScreen screen_;
  NSString *playlist_;
  NSMutableDictionary *cache_;
}
- (id)initWithRows:(NSArray *)rows model:(RDLPLibrarySections *)model screen:(RDLPScreen)screen playlist:(NSString *)playlist;
- (NSUInteger)indexForIdentity:(NSString *)identity;
- (id)cachedObjectAtIndex:(NSUInteger)index;
@end
@implementation RDLPSectionRows
- (id)initWithRows:(NSArray *)rows model:(RDLPLibrarySections *)model screen:(RDLPScreen)screen playlist:(NSString *)playlist;
{ self=[super init]; if(self) { cache_=[[NSMutableDictionary alloc] init]; source_=[rows retain]; model_=[model retain]; screen_=screen; playlist_=[playlist copy]; } return self; }
- (void)dealloc; { [cache_ release]; [source_ release]; [model_ release]; [playlist_ release]; [super dealloc]; }
- (NSUInteger)count; { return [source_ count]; }
- (id)copyWithZone:(NSZone *)zone; { (void)zone; return [self retain]; }
- (id)objectAtIndex:(NSUInteger)index;
{
  NSNumber *key=[NSNumber numberWithUnsignedLong:index];
  NSDictionary *row=[cache_ objectForKey:key];
  if(!row) {
    row=[model_ displayRow:[source_ objectAtIndex:index] screen:screen_ index:index playlist:playlist_];
    if([cache_ count]>=128) [cache_ removeAllObjects];
    [cache_ setObject:row forKey:key];
  }
  return [[row retain] autorelease];
}
- (id)cachedObjectAtIndex:(NSUInteger)index;
{ return [cache_ objectForKey:[NSNumber numberWithUnsignedLong:index]]; }
- (NSUInteger)indexForIdentity:(NSString *)identity;
{ return [(RDLPLibraryRows *)source_ indexForIdentity:identity]; }
@end

@implementation RDLPLibrarySections
- (id)initWithLibrary:(RDLPLibrary *)library;
{ self=[super init]; if(self) { library_=[library retain]; policy_=[[RDLPDownloadPolicy alloc] initWithLibrary:library]; } return self; }
- (void)dealloc; { [library_ release]; [policy_ release]; [super dealloc]; }
- (NSDictionary *)section:(NSString *)title rows:(NSArray *)rows;
{ return [NSDictionary dictionaryWithObjectsAndKeys:title,@"title",rows,@"rows",nil]; }
- (NSMutableDictionary *)row:(NSString *)title detail:(NSString *)detail action:(NSString *)action;
{ return [NSMutableDictionary dictionaryWithObjectsAndKeys:title?title:@"Untitled",@"title",detail?detail:@"",@"detail",action,@"action",nil]; }
- (NSDictionary *)currentJob:(NSString *)key;
{ return [library_ jobForID:key]; }
- (NSDictionary *)jobForPlaylist:(NSString *)playlist video:(NSString *)video format:(NSString *)format;
{ return [library_ jobForPlaylist:playlist video:video format:format]; }
- (NSArray *)missingPlanForPlaylist:(NSString *)playlist format:(NSString *)format;
{ return [library_ missingPlanForPlaylist:playlist format:format];
}
- (BOOL)canRemovePlaylist:(NSDictionary *)playlist;
{
  if(!playlist || [library_ isBusy]) return NO;
  return ![library_ hasBlockingJobsForPlaylist:[playlist objectForKey:@"id"]];
}
- (NSArray *)actionsForJob:(NSDictionary *)job;
{
  NSMutableArray *actions=[NSMutableArray array];
  if([policy_ playable:job]) [actions addObject:@"Play"];
  if([policy_ canRetry:job] || [policy_ canDownloadAgain:job]) [actions addObject:@"Download Video"];
  if([policy_ canCancel:job]) [actions addObject:@"Stop Download…"];
  if([policy_ canRemove:job] && ![policy_ canCancel:job]) [actions addObject:@"Delete Download…"];
  [actions addObject:@"Show in Queue"];
  return actions;
}
- (NSDictionary *)jobRow:(NSDictionary *)job;
{
  NSString *detail=[NSString stringWithFormat:@"%@ · %@\n%@",[policy_ statusForJob:job],[RDLPLibrary qualityLabelForFormat:[job objectForKey:@"format"]],([job objectForKey:@"error"]?[job objectForKey:@"error"]:@"")];
  NSMutableDictionary *row=[self row:[job objectForKey:@"title"] detail:detail action:@"job"];
  [row setObject:job forKey:@"job"]; [row setObject:[policy_ statusForJob:job] forKey:@"status"]; return row;
}
/* Both video lists share cells; Playlist shows quality only for a playable copy. */
- (NSDictionary *)videoRow:(NSDictionary *)entry job:(NSDictionary *)job playlist:(NSString *)playlist showQuality:(BOOL)showQuality;
{
  NSString *detail=showQuality?[RDLPLibrary qualityLabelForFormat:[job objectForKey:@"format"]]:@"";
  NSMutableDictionary *row=[self row:[entry objectForKey:@"title"] detail:detail action:@"video"];
  [row setObject:entry forKey:@"video"]; [row setObject:playlist forKey:@"playlist_id"];
  if(job) [row setObject:job forKey:@"job"];
  [row setObject:[policy_ statusForJob:job] forKey:@"status"];
  return row;
}
- (NSArray *)displayRows:(NSArray *)rows screen:(RDLPScreen)screen playlist:(NSString *)playlist;
{ return [[[RDLPSectionRows alloc] initWithRows:rows model:self screen:screen playlist:playlist] autorelease]; }
- (NSDictionary *)displayRow:(NSDictionary *)item screen:(RDLPScreen)screen index:(NSUInteger)index playlist:(NSString *)playlist;
{
  if(screen==RDLPScreenLibrary) {
    NSMutableDictionary *row=[self row:[item objectForKey:@"title"] detail:[[item objectForKey:@"synced_at"] length]?[NSString stringWithFormat:@"%@ videos",[item objectForKey:@"count"]]:@"Not synced" action:@"playlist"];
    [row setObject:item forKey:@"playlist"]; return row;
  }
  if(screen==RDLPScreenQueue) {
    NSString *title=[NSString stringWithFormat:@"%lu) %@",(unsigned long)index+1,[item objectForKey:@"title"]];
    NSString *detail=[NSString stringWithFormat:@"%@ · %@",[RDLPLibrary qualityLabelForFormat:[item objectForKey:@"format"]],[item objectForKey:@"playlist_title"]];
    NSMutableDictionary *row=[self row:title detail:detail action:@"job"];
    NSString *status=[policy_ statusForJob:item];
    [row setObject:[status isEqualToString:@"Cancelled"]?@"Stopped":status forKey:@"status"];
    [row setObject:item forKey:@"job"]; return row;
  }
  if(screen==RDLPScreenPlaylist) {
    NSArray *jobs=[library_ jobsForPlaylist:playlist video:[item objectForKey:@"video_id"]];
    NSDictionary *job=[policy_ representativeJobForEntry:item playlist:playlist jobs:jobs];
    return [self videoRow:item job:job playlist:playlist showQuality:[policy_ playable:job]];
  }
  if(screen==RDLPScreenDownloads)
    return [self videoRow:item job:item playlist:[item objectForKey:@"playlist_id"] showQuality:YES];
  return [self jobRow:item];
}
- (NSArray *)sectionsForScreen:(RDLPScreen)screen playlist:(NSDictionary *)playlist video:(NSDictionary *)video collapsed:(NSSet *)collapsed;
{
  (void)collapsed;
  NSMutableArray *sections=[NSMutableArray array], *rows=[NSMutableArray array];
  NSString *pid=[playlist objectForKey:@"id"];
  if(screen==RDLPScreenLibrary) {
    [rows addObject:[self row:@"All Downloads" detail:@"" action:@"downloads"]];
    [sections addObject:[self section:@"System" rows:rows]];
    [sections addObject:[self section:@"Added Playlists" rows:[self displayRows:[library_ playlistsFromAccount:NO] screen:screen playlist:nil]]];
    [sections addObject:[self section:@"My Playlists" rows:[self displayRows:[library_ playlistsFromAccount:YES] screen:screen playlist:nil]]];
  } else if(screen==RDLPScreenSettings) {
    NSArray *titles=[RDLPLibrary qualityTitles], *formats=[RDLPLibrary qualityFormats]; NSString *format=[RDLPLibrary preferredFormat];
    for(NSUInteger i=0;i<[titles count];++i) {
      NSMutableDictionary *row=[self row:[titles objectAtIndex:i] detail:i==3?format:@"" action:i==3?@"custom":@"quality"];
      if(i<3) [row setObject:[formats objectAtIndex:i] forKey:@"format"];
      [row setObject:[NSNumber numberWithBool:i<3?[format isEqualToString:[formats objectAtIndex:i]]:![formats containsObject:format]] forKey:@"checked"]; [rows addObject:row];
    }
    [sections addObject:[self section:@"Download Quality" rows:rows]];
    NSMutableArray *cookies=[NSMutableArray array];
    [cookies addObject:[self row:@"Import Cookies..." detail:@"" action:@"import"]];
    [cookies addObject:[self row:@"Remove Cookies…" detail:@"" action:@"clearCookies"]];
    [cookies addObject:[self row:@"Cookie Export Guide" detail:@"" action:@"guide"]];
    [sections addObject:[self section:@"Cookies" rows:cookies]];
  } else {
    if(screen==RDLPScreenQueue)
      return [NSArray arrayWithObject:[self section:@"" rows:[self displayRows:[library_ queueRows] screen:screen playlist:nil]]];
    if(screen==RDLPScreenPlaylist || screen==RDLPScreenDownloads) {
      NSArray *source=screen==RDLPScreenPlaylist?[library_ entriesForPlaylist:pid]:[library_ jobsForPlaylist:nil completedOnly:YES];
      return [NSArray arrayWithObject:[self section:screen==RDLPScreenPlaylist?@"Videos":@"Downloads" rows:[self displayRows:source screen:screen playlist:pid]]];
    } else {
      NSArray *jobs=[library_ jobsForPlaylist:pid video:[video objectForKey:@"video_id"]];
      if(screen==RDLPScreenVideo) {
        NSMutableArray *commands=[NSMutableArray array];
        NSDictionary *representative=[policy_ representativeJobForEntry:video playlist:pid jobs:jobs];
        if([policy_ playable:representative]) {
          NSMutableDictionary *play=[self row:@"Play" detail:[RDLPLibrary qualityLabelForFormat:[representative objectForKey:@"format"]] action:@"play"];
          [play setObject:representative forKey:@"job"]; [commands addObject:play];
        }
        NSDictionary *exact=[self jobForPlaylist:pid video:[video objectForKey:@"video_id"] format:[RDLPLibrary preferredFormat]];
        NSString *action=[policy_ playable:exact]?@"delete":([policy_ canCancel:exact]?@"showQueue":@"download");
        NSMutableDictionary *command=[self row:[action isEqualToString:@"delete"]?@"Delete Download…":([action isEqualToString:@"showQueue"]?@"Show in Queue":@"Download Video") detail:[RDLPLibrary qualityLabelForFormat:[RDLPLibrary preferredFormat]] action:action];
        if(exact) [command setObject:exact forKey:@"job"]; [commands addObject:command];
        [commands addObject:[self row:@"Download Quality" detail:@"" action:@"settings"]];
        [sections addObject:[self section:([video objectForKey:@"title"]?[video objectForKey:@"title"]:@"Video") rows:commands]];
      }
      [sections addObject:[self section:@"Downloads" rows:[self displayRows:jobs screen:screen playlist:pid]]];
      return sections;
    }
  }
  return sections;
}
@end
