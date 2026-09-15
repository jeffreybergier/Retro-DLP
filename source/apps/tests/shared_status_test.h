/* Run the same bridge regressions inside both offline native test apps. */
#include <retrodlp/retrodlp.h>
@interface RDLPLibrary (StatusTesting)
- (void)showStatus:(NSString *)message;
- (void)resolverEvent:(rdlp_event_type)type;
- (void)progress:(NSString *)phase completed:(uint64_t)completed expected:(uint64_t)expected;
- (void)finished:(NSDictionary *)result;
@end
@interface RDLPStatusTestLibrary : RDLPLibrary
@end
@implementation RDLPStatusTestLibrary
- (void)startNext { /* Tests inject events; never start networking. */ }
@end
static void statusRequire(BOOL condition,NSString *message) {
  if(!condition) [NSException raise:@"StatusRegression" format:@"%@",message];
}
static void statusWait(NSTimeInterval interval) {
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:interval]];
}
static void testSharedStatus(NSString *base) {
  RDLPStatusTestLibrary *library=[[RDLPStatusTestLibrary alloc]
    initWithSupportDirectory:[base stringByAppendingPathComponent:@"Support"]
    downloadDirectory:[base stringByAppendingPathComponent:@"Downloads"]];
  statusRequire(library!=nil,@"Open isolated status fixture");
  statusRequire(![[library status] length],@"No startup/Ready message");
  [library showStatus:@"Download complete"];
  NSString *cookie=[base stringByAppendingPathComponent:@"cookies.txt"];
  [@"# Netscape HTTP Cookie File\n" writeToFile:cookie atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  statusRequire([library importCookies:cookie],@"Import synthetic cookies");
  statusRequire([[library status] isEqualToString:@"Download complete"],@"Cookie import leaves download status untouched");
  [library clearCookies];
  statusRequire([[library status] isEqualToString:@"Download complete"],@"Cookie removal leaves download status untouched");
  statusRequire(![library importCookies:[base stringByAppendingPathComponent:@"absent"]],@"Missing cookie file fails");
  NSDictionary *error=[library takeError];
  statusRequire([[error objectForKey:@"title"] isEqualToString:@"Couldn’t import cookies"] && [[error objectForKey:@"detail"] length]>0,@"Action failure is a separate alert");
  statusRequire([[library status] isEqualToString:@"Download complete"] && ![library takeError],@"Error does not replace status or repeat after consumption");

  [library setValue:[NSDictionary dictionaryWithObject:@"download" forKey:@"type"] forKey:@"activeCommand_"];
  [library setValue:[NSNumber numberWithBool:YES] forKey:@"busy_"];
  rdlp_event_type events[]={RDLP_EVENT_AUTHENTICATING,RDLP_EVENT_LOADING_CONFIGURATION,
    RDLP_EVENT_FETCHING_BOOTSTRAP,RDLP_EVENT_REQUESTING_METADATA,RDLP_EVENT_REFRESHING_METADATA,
    RDLP_EVENT_SELECTING_FORMATS,RDLP_EVENT_LOADING_PLAYER_JAVASCRIPT,RDLP_EVENT_SOLVING_CHALLENGES};
  NSArray *labels=[NSArray arrayWithObjects:@"Reading cookies…",@"Configuring client…",@"Loading mobile player…",
    @"Requesting metadata…",@"Refreshing visitor data…",@"Selecting format…",@"Downloading player script…",@"Solving challenges…",nil];
  unsigned int i;
  for(i=0;i<sizeof(events)/sizeof(events[0]);++i) {
    [library resolverEvent:events[i]]; statusWait(0.01);
    statusRequire([[library status] isEqualToString:[labels objectAtIndex:i]],@"Every CLI step survives rapid phase changes");
  }
  [library progress:@"Downloading" completed:25 expected:100]; statusWait(0.01);
  statusRequire([[library status] rangeOfString:@"25%"].location!=NSNotFound,@"Transfer text has current byte percentage");
  statusRequire([[[library activityProgress] objectForKey:@"completed"] intValue]==25 &&
    [[[library activityProgress] objectForKey:@"expected"] intValue]==100,@"Bar uses transfer bytes, not queue counts");
  [library progress:@"Combining audio and video…" completed:0 expected:0]; statusWait(0.01);
  statusRequire([[[library activityProgress] objectForKey:@"expected"] intValue]==0,@"Unknown phase has no fabricated percentage");

  [library setValue:[NSDictionary dictionaryWithObjectsAndKeys:@"sync",@"type",[NSNumber numberWithBool:YES],@"adding",nil] forKey:@"activeCommand_"];
  [library resolverEvent:RDLP_EVENT_FETCHING_BOOTSTRAP]; statusWait(0.01);
  statusRequire([[library status] isEqualToString:@"Adding playlist…"],@"Adding keeps a simple playlist message");
  [library finished:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:RDLP_OK],@"code",@"Internal service text",@"message",nil]];
  statusRequire([[library status] isEqualToString:@"Playlist added"],@"Adding has its own final message");
  [library setValue:[NSDictionary dictionaryWithObject:@"sync" forKey:@"type"] forKey:@"activeCommand_"];
  [library finished:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:RDLP_ERROR_STORAGE_IO],@"code",@"Synthetic database failure",@"message",nil]];
  statusRequire([[library status] isEqualToString:@"Error syncing playlist"] &&
    [[[[library takeError] objectForKey:@"detail"] description] isEqualToString:@"Synthetic database failure"],@"Playlist failure has short status and detailed alert");

  /* Identical new messages reset the shared deadline; reads/refreshes do not. */
  [library setValue:nil forKey:@"activeCommand_"];
  [library setValue:[NSNumber numberWithBool:YES] forKey:@"busy_"];
  [library showStatus:@"Downloading"];
  statusWait(6);
  [library showStatus:@"Downloading"];
  statusWait(5);
  statusRequire([[library status] isEqualToString:@"Downloading"],@"Identical new message resets ten-second deadline");
  NSDate *expiry=[NSDate dateWithTimeIntervalSinceNow:5.2];
  while([expiry timeIntervalSinceNow]>0) { [library status]; [library activityProgress]; statusWait(0.1); }
  statusRequire(![[library status] length] && ![[[library activityProgress] objectForKey:@"active"] boolValue],@"Ten seconds without messages clears text and progress even while busy");
  [library showStatus:@"Downloading"];
  statusRequire([[library status] isEqualToString:@"Downloading"],@"Same text can reappear after expiry as a new event");
  [library shutdown]; [library release];
}
