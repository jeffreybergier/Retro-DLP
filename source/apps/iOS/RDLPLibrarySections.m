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
- (NSString *)queueGroupForJob:(NSDictionary *)job;
{
  NSString *state=[job objectForKey:@"state"];
  return [policy_ playable:job]?@"Done":([state isEqualToString:@"running"]?@"Downloading":([state isEqualToString:@"queued"]?@"Queued":@"Needs Attention"));
}
- (NSArray *)queueSections:(NSArray *)jobs collapsed:(NSSet *)collapsed;
{
  NSArray *names=[NSArray arrayWithObjects:@"Done",@"Downloading",@"Queued",@"Needs Attention",nil];
  NSMutableArray *sections=[NSMutableArray array];
  for(NSString *name in names) {
    NSMutableArray *group=[NSMutableArray array];
    for(NSDictionary *job in jobs) {
      NSString *target=[self queueGroupForJob:job];
      if([name isEqualToString:target]) [group addObject:job];
    }
    NSMutableArray *rows=[NSMutableArray array]; NSMutableSet *playlists=[NSMutableSet set];
    for(NSDictionary *job in group) {
      NSString *pid=[job objectForKey:@"playlist_id"];
      if([playlists containsObject:pid]) continue; [playlists addObject:pid];
      NSString *pk=[NSString stringWithFormat:@"%@/playlist:%@",name,pid];
      NSMutableDictionary *parent=[self row:[job objectForKey:@"playlist_title"] detail:@"" action:@"collapse"];
      [parent setObject:pk forKey:@"key"]; [rows addObject:parent];
      if([collapsed containsObject:pk]) continue;
      NSMutableSet *videos=[NSMutableSet set];
      for(NSDictionary *videoJob in group) {
        NSString *vid=[videoJob objectForKey:@"video_id"];
        if(![[videoJob objectForKey:@"playlist_id"] isEqualToString:pid] || [videos containsObject:vid]) continue;
        [videos addObject:vid]; NSString *vk=[pk stringByAppendingFormat:@"/video:%@",vid];
        NSMutableDictionary *video=[self row:[videoJob objectForKey:@"title"] detail:@"" action:@"collapse"];
        [video setObject:vk forKey:@"key"]; [video setObject:[NSNumber numberWithInt:1] forKey:@"depth"]; [rows addObject:video];
        if([collapsed containsObject:vk]) continue;
        for(NSDictionary *quality in group) {
          if(![[quality objectForKey:@"playlist_id"] isEqualToString:pid] || ![[quality objectForKey:@"video_id"] isEqualToString:vid]) continue;
          NSMutableDictionary *row=[NSMutableDictionary dictionaryWithDictionary:[self jobRow:quality]];
          [row setObject:[self qualityLabel:[quality objectForKey:@"format"]] forKey:@"title"];
          NSString *detail=[policy_ statusForJob:quality], *actual=[quality objectForKey:@"actual_format"];
          if([actual length] && ![actual isEqualToString:[quality objectForKey:@"format"]]) detail=[detail stringByAppendingFormat:@" · Saved as %@",actual];
          if([[quality objectForKey:@"error"] length]) detail=[detail stringByAppendingFormat:@"\n%@",[quality objectForKey:@"error"]];
          [row setObject:detail forKey:@"detail"];
          [row setObject:[NSNumber numberWithInt:2] forKey:@"depth"]; [rows addObject:row];
        }
      }
    }
    [sections addObject:[self section:name rows:rows]];
  }
  return sections;
}
- (NSArray *)sectionsForScreen:(RDLPScreen)screen playlist:(NSDictionary *)playlist video:(NSDictionary *)video collapsed:(NSSet *)collapsed;
{
  NSMutableArray *sections=[NSMutableArray array], *rows=[NSMutableArray array];
  NSString *pid=[playlist objectForKey:@"id"];
  if(screen==RDLPScreenLibrary) {
    [rows addObject:[self row:@"All Downloads" detail:@"" action:@"downloads"]];
    [rows addObject:[self row:@"Download Queue" detail:@"" action:@"queue"]];
    [rows addObject:[self row:@"Settings" detail:@"" action:@"settings"]];
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
    [cookies addObject:[self row:@"Import Documents/cookies.txt" detail:[library_ cookieStatus] action:@"import"]];
    [cookies addObject:[self row:@"Remove Cookies…" detail:@"" action:@"clearCookies"]];
    [cookies addObject:[self row:@"Cookie Export Guide" detail:@"" action:@"guide"]];
    [sections addObject:[self section:@"Cookies" rows:cookies]];
  } else {
    NSArray *jobs=[library_ jobsForPlaylist:screen==RDLPScreenVideo || screen==RDLPScreenPlaylist?pid:nil completedOnly:screen==RDLPScreenDownloads];
    if(screen==RDLPScreenQueue) return [self queueSections:jobs collapsed:collapsed];
    if(screen==RDLPScreenPlaylist) {
      for(NSDictionary *entry in [library_ entriesForPlaylist:pid]) {
        NSDictionary *job=[policy_ representativeJobForEntry:entry playlist:pid jobs:jobs];
        NSMutableDictionary *row=[self row:[entry objectForKey:@"title"] detail:[policy_ statusForJob:job] action:@"video"];
        [row setObject:entry forKey:@"video"]; [row setObject:[policy_ statusForJob:job] forKey:@"status"]; [rows addObject:row];
      }
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
        if(screen==RDLPScreenDownloads) [row setObject:[NSString stringWithFormat:@"%@ · %@",[row objectForKey:@"detail"],[job objectForKey:@"playlist_title"]] forKey:@"detail"];
        [rows addObject:row];
      }
    }
    [sections addObject:[self section:screen==RDLPScreenPlaylist?@"Videos":@"Downloads" rows:rows]];
  }
  return sections;
}
@end
