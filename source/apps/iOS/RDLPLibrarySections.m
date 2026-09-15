#import "RDLPLibrarySections.h"

@implementation RDLPLibrarySections
- (id)initWithLibrary:(RDLPLibrary *)library;
{ self=[super init]; if(self) { library_=[library retain]; policy_=[[RDLPDownloadPolicy alloc] initWithLibrary:library]; } return self; }
- (void)dealloc; { [library_ release]; [policy_ release]; [super dealloc]; }
- (NSDictionary *)section:(NSString *)title rows:(NSArray *)rows;
{ return [NSDictionary dictionaryWithObjectsAndKeys:title,@"title",rows,@"rows",nil]; }
- (NSMutableDictionary *)row:(NSString *)title detail:(NSString *)detail action:(NSString *)action;
{ return [NSMutableDictionary dictionaryWithObjectsAndKeys:title?title:@"Untitled",@"title",detail?detail:@"",@"detail",action,@"action",nil]; }
- (NSDictionary *)currentJob:(NSString *)key;
{
  for(NSDictionary *job in [library_ jobsForPlaylist:nil completedOnly:NO])
    if([[job objectForKey:@"id"] isEqualToString:key]) return job;
  return nil;
}
- (NSDictionary *)jobForPlaylist:(NSString *)playlist video:(NSString *)video format:(NSString *)format;
{
  for(NSDictionary *job in [library_ jobsForPlaylist:playlist completedOnly:NO])
    if([[job objectForKey:@"video_id"] isEqualToString:video] && [[job objectForKey:@"format"] isEqualToString:format]) return job;
  return nil;
}
- (NSArray *)missingPlanForPlaylist:(NSString *)playlist format:(NSString *)format;
{
  NSMutableArray *plan=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set];
  for(NSDictionary *entry in [library_ entriesForPlaylist:playlist]) {
    NSString *video=[entry objectForKey:@"video_id"]; if([seen containsObject:video]) continue; [seen addObject:video];
    NSDictionary *job=[self jobForPlaylist:playlist video:video format:format];
    if(!job || [policy_ canDownloadAgain:job]) [plan addObject:[NSDictionary dictionaryWithObjectsAndKeys:playlist,@"playlist",video,@"video",format,@"format",nil]];
  }
  return plan;
}
- (BOOL)canRemovePlaylist:(NSDictionary *)playlist;
{
  if(!playlist || [library_ isBusy]) return NO;
  for(NSDictionary *job in [library_ jobsForPlaylist:[playlist objectForKey:@"id"] completedOnly:NO])
    if([policy_ canCancel:job] || [RDLPDownloadPolicy job:job hasState:@"complete"]) return NO;
  return YES;
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
- (NSString *)qualityLabel:(NSString *)format;
{
  NSUInteger index=[[RDLPLibrary qualityFormats] indexOfObject:format];
  return index==NSNotFound?format:[NSString stringWithFormat:@"%@ (%@)",[[RDLPLibrary qualityTitles] objectAtIndex:index],format];
}
- (NSDictionary *)jobRow:(NSDictionary *)job;
{
  NSString *detail=[NSString stringWithFormat:@"%@ · %@\n%@",[policy_ statusForJob:job],[self qualityLabel:[job objectForKey:@"format"]],([job objectForKey:@"error"]?[job objectForKey:@"error"]:@"")];
  NSMutableDictionary *row=[self row:[job objectForKey:@"title"] detail:detail action:@"job"];
  [row setObject:job forKey:@"job"]; [row setObject:[policy_ statusForJob:job] forKey:@"status"]; return row;
}
/* Both video lists use the same title, quality subtitle, and status accessory. */
- (NSDictionary *)videoRow:(NSDictionary *)entry job:(NSDictionary *)job playlist:(NSString *)playlist;
{
  NSString *format=job?[job objectForKey:@"format"]:[RDLPLibrary preferredFormat];
  NSMutableDictionary *row=[self row:[entry objectForKey:@"title"] detail:[self qualityLabel:format] action:@"video"];
  [row setObject:entry forKey:@"video"]; [row setObject:playlist forKey:@"playlist_id"];
  if(job) [row setObject:job forKey:@"job"];
  [row setObject:[policy_ statusForJob:job] forKey:@"status"];
  return row;
}
- (NSArray *)queueSections:(NSArray *)jobs;
{
  NSMutableArray *rows=[NSMutableArray array];
  /* Store queries return newest first; the worker claims the lowest job ID.
   * Number visible rows consecutively, independently of permanent database IDs. */
  for(NSDictionary *job in [jobs reverseObjectEnumerator]) {
    if([RDLPDownloadPolicy job:job hasState:@"removed"] && ![[job objectForKey:@"error"] length]) continue;
    NSString *title=[NSString stringWithFormat:@"%lu) %@",(unsigned long)[rows count]+1,[job objectForKey:@"title"]];
    NSString *detail=[NSString stringWithFormat:@"%@ · %@",[self qualityLabel:[job objectForKey:@"format"]],[job objectForKey:@"playlist_title"]];
    NSMutableDictionary *row=[self row:title detail:detail action:@"job"];
    NSString *status=[policy_ statusForJob:job];
    [row setObject:[status isEqualToString:@"Cancelled"]?@"Stopped":status forKey:@"status"];
    [row setObject:job forKey:@"job"]; [rows addObject:row];
  }
  return [NSArray arrayWithObject:[self section:@"" rows:rows]];
}
- (NSArray *)sectionsForScreen:(RDLPScreen)screen playlist:(NSDictionary *)playlist video:(NSDictionary *)video collapsed:(NSSet *)collapsed;
{
  (void)collapsed;
  NSMutableArray *sections=[NSMutableArray array], *rows=[NSMutableArray array];
  NSString *pid=[playlist objectForKey:@"id"];
  if(screen==RDLPScreenLibrary) {
    [rows addObject:[self row:@"All Downloads" detail:@"" action:@"downloads"]];
    [sections addObject:[self section:@"System" rows:rows]];
    for(NSString *origin in [NSArray arrayWithObjects:@"manual",@"discovered",nil]) {
      NSMutableArray *playlists=[NSMutableArray array];
      for(NSDictionary *item in [library_ playlists]) {
        BOOL discovered=[[item objectForKey:@"source"] isEqualToString:@"account"];
        if(discovered!=[origin isEqualToString:@"discovered"]) continue;
        NSMutableDictionary *row=[self row:[item objectForKey:@"title"] detail:[[item objectForKey:@"synced_at"] length]?[NSString stringWithFormat:@"%@ videos",[item objectForKey:@"count"]]:@"Not synced" action:@"playlist"];
        [row setObject:item forKey:@"playlist"]; [playlists addObject:row];
      }
      [sections addObject:[self section:[origin isEqualToString:@"manual"]?@"Added Playlists":@"My Playlists" rows:playlists]];
    }
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
    NSArray *jobs=[library_ jobsForPlaylist:screen==RDLPScreenVideo || screen==RDLPScreenPlaylist?pid:nil completedOnly:screen==RDLPScreenDownloads];
    if(screen==RDLPScreenQueue) return [self queueSections:jobs];
    if(screen==RDLPScreenPlaylist) {
      for(NSDictionary *entry in [library_ entriesForPlaylist:pid]) {
        NSDictionary *job=[policy_ representativeJobForEntry:entry playlist:pid jobs:jobs];
        [rows addObject:[self videoRow:entry job:job playlist:pid]];
      }
    } else if(screen==RDLPScreenDownloads) {
      /* Completed jobs retain their individual quality and playlist identity. */
      for(NSDictionary *job in jobs)
        [rows addObject:[self videoRow:job job:job playlist:[job objectForKey:@"playlist_id"]]];
    } else {
      if(screen==RDLPScreenVideo) {
        NSMutableArray *commands=[NSMutableArray array];
        NSDictionary *representative=[policy_ representativeJobForEntry:video playlist:pid jobs:jobs];
        if([policy_ playable:representative]) {
          NSMutableDictionary *play=[self row:@"Play" detail:[self qualityLabel:[representative objectForKey:@"format"]] action:@"play"];
          [play setObject:representative forKey:@"job"]; [commands addObject:play];
        }
        NSDictionary *exact=[self jobForPlaylist:pid video:[video objectForKey:@"video_id"] format:[RDLPLibrary preferredFormat]];
        NSString *action=[policy_ playable:exact]?@"delete":([policy_ canCancel:exact]?@"showQueue":@"download");
        NSMutableDictionary *command=[self row:[action isEqualToString:@"delete"]?@"Delete Download…":([action isEqualToString:@"showQueue"]?@"Show in Queue":@"Download Video") detail:[self qualityLabel:[RDLPLibrary preferredFormat]] action:action];
        if(exact) [command setObject:exact forKey:@"job"]; [commands addObject:command];
        [commands addObject:[self row:@"Download Quality" detail:@"" action:@"settings"]];
        [sections addObject:[self section:([video objectForKey:@"title"]?[video objectForKey:@"title"]:@"Video") rows:commands]];
      }
      for(NSDictionary *job in jobs) {
        if(screen==RDLPScreenVideo && ![[job objectForKey:@"video_id"] isEqualToString:[video objectForKey:@"video_id"]]) continue;
        NSMutableDictionary *row=[NSMutableDictionary dictionaryWithDictionary:[self jobRow:job]];
        [rows addObject:row];
      }
    }
    [sections addObject:[self section:screen==RDLPScreenPlaylist?@"Videos":@"Downloads" rows:rows]];
  }
  return sections;
}
@end
