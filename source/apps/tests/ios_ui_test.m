/* Native UIKit regressions. All data is synthetic and confined to this bundle.
   The scheduler override below never calls the production worker. */
#import "../iOS/RDLPLibraryViewController.h"
#import "../iOS/RDLPAppDelegate.h"
#import "../iOS/RDLPUIKit.h"
#import <AIFontAwesome.h>
#import "../shared/rdapp_store.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

static void require(BOOL condition,NSString *message) {
  if(!condition) [NSException raise:@"RDLPIOSOfflineTest" format:@"%@",message];
}
static int ignoreRow(void *context,int count,const char *const *names,const char *const *values) {
  (void)context; (void)count; (void)names; (void)values; return 1;
}
static void pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.35]]; }
@interface RDLPOfflineLibrary : RDLPLibrary {
  NSDictionary *testProgress_;
  BOOL testBusy_;
}
@property(nonatomic,retain) NSDictionary *testProgress;
@property(nonatomic,assign) BOOL testBusy;
@end
@implementation RDLPOfflineLibrary
@synthesize testProgress=testProgress_, testBusy=testBusy_;
- (NSDictionary *)queueProgress { return testProgress_?testProgress_:[super queueProgress]; }
- (BOOL)isBusy { return testBusy_ || [super isBusy]; }
- (void)dealloc { [testProgress_ release]; [super dealloc]; }
- (void)startNext { /* Deliberately never schedules network or media work. */ }
- (void)work:(NSDictionary *)command {
  (void)command; [NSException raise:@"OfflineViolation" format:@"Worker must never run in this test"];
}
@end
@interface RDLPLibraryViewController (Testing)
- (void)queueAction:(UIButton *)sender;
@end
static NSArray *sections(RDLPLibraryViewController *controller) { return [controller valueForKey:@"sections_"]; }
static NSDictionary *findRow(RDLPLibraryViewController *controller,NSString *action) {
  for(NSDictionary *section in sections(controller)) for(NSDictionary *row in [section objectForKey:@"rows"])
    if([[row objectForKey:@"action"] isEqualToString:action]) return row;
  return nil;
}
static void confirmAt(RDLPLibraryViewController *controller,BOOL accept,int line) {
  UIAlertView *alert=[controller valueForKey:@"alert_"];
  require(alert!=nil,[NSString stringWithFormat:@"Expected confirmation at test line %d",line]); [alert retain];
  [controller alertView:alert clickedButtonAtIndex:accept?1:0];
  [alert dismissWithClickedButtonIndex:accept?1:0 animated:NO]; [alert release]; pump();
}
#define confirm(controller,accept) confirmAt(controller,accept,__LINE__)
static void choose(RDLPLibraryViewController *controller,NSString *title) {
  UIAlertView *alert=[controller valueForKey:@"alert_"]; require(alert!=nil,@"Expected job actions"); [alert retain];
  NSInteger index=0; for(NSInteger i=1;i<alert.numberOfButtons;++i) if([[alert buttonTitleAtIndex:i] isEqualToString:title]) index=i;
  require(index>0,[NSString stringWithFormat:@"Missing action %@",title]);
  [controller alertView:alert clickedButtonAtIndex:index]; [alert dismissWithClickedButtonIndex:index animated:NO]; [alert release]; pump();
}
static void screenshot(UIWindow *window,NSString *path) {
  UIGraphicsBeginImageContextWithOptions(window.bounds.size,NO,0);
  [window.layer renderInContext:UIGraphicsGetCurrentContext()];
  [UIImagePNGRepresentation(UIGraphicsGetImageFromCurrentImageContext()) writeToFile:path atomically:YES]; UIGraphicsEndImageContext();
}
@interface RDLPIOSOfflineTest : UIResponder <UIApplicationDelegate> {
  UIWindow *window_;
  RDLPOfflineLibrary *library_;
  UINavigationController *navigation_;
  NSString *documents_;
}
@end
@implementation RDLPIOSOfflineTest
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options;
{
  (void)application; (void)options; [AIFontAwesome registerBundledFonts];
  documents_=[[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) objectAtIndex:0] copy];
  window_=[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  window_.rootViewController=[[[UIViewController alloc] init] autorelease]; [window_ makeKeyAndVisible];
  [self performSelector:@selector(run) withObject:nil afterDelay:0.5]; return YES;
}
- (RDLPLibraryViewController *)show:(RDLPScreen)mode playlist:(NSDictionary *)playlist video:(NSDictionary *)video;
{
  RDLPLibraryViewController *controller=[[[RDLPLibraryViewController alloc] initWithLibrary:library_ mode:mode playlist:playlist video:video] autorelease];
  [navigation_ setViewControllers:[NSArray arrayWithObject:controller] animated:NO]; [controller view]; [controller refresh:nil]; pump(); return controller;
}
- (void)run;
{
  NSString *report=@"PASS";
  @try {
    require([[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"]==nil,@"Isolated bundle must not contain a CA resource");
    require([RDLPUIKit statusIcon:@"Downloaded"]!=nil && [RDLPUIKit queueActionIcon:YES]!=nil && [RDLPUIKit queueActionIcon:NO]!=nil,@"Status and queue action glyphs render");
    NSString *base=[documents_ stringByAppendingPathComponent:@"Fixture"];
    [[NSFileManager defaultManager] removeItemAtPath:base error:NULL];
    NSString *support=[base stringByAppendingPathComponent:@"Support"], *downloads=[base stringByAppendingPathComponent:@"Downloads"];
    rdapp_make_directory([support fileSystemRepresentation]); rdapp_make_directory([downloads fileSystemRepresentation]);
    rdapp_store *store=NULL; long long pid=0, other=0;
    require(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Open fixture");
    rdapp_entry entries[]={{"AAAAAAAAAAA","A playable video",0},{"BBBBBBBBBBB","Failed and queued video",1},{"CCCCCCCCCCC","Missing video",2},{"CCCCCCCCCCC","Repeated video",3}};
    require(rdapp_store_snapshot(store,"PLfixture","Offline Test Playlist",entries,4,&pid),@"Create fixture playlist");
    require(rdapp_store_snapshot(store,"PLaccount","Account Playlist",NULL,0,&other),@"Create account playlist");
    require(rdapp_store_discovered_playlist(store,"PLaccount","Account Playlist"),@"Promote account fixture");
    require(rdapp_store_enqueue(store,pid,"AAAAAAAAAAA","18"),@"Create completed job");
    require(rdapp_store_claim(store,ignoreRow,NULL),@"Claim completed fixture");
    require(rdapp_store_finish(store,1,"complete","18",""),@"Finish fixture");
    require(rdapp_store_enqueue(store,pid,"BBBBBBBBBBB","136+140"),@"Create failed quality");
    require(rdapp_store_claim(store,ignoreRow,NULL),@"Claim failed fixture");
    require(rdapp_store_finish(store,2,"failed","","Synthetic failure"),@"Fail fixture");
    require(rdapp_store_enqueue(store,pid,"BBBBBBBBBBB","18"),@"Create queued quality");
    require(rdapp_store_enqueue(store,pid,"AAAAAAAAAAA","137+140"),@"Create missing quality");
    require(rdapp_store_cancel(store,3),@"Hold queued fixture");
    require(rdapp_store_claim(store,ignoreRow,NULL),@"Claim missing fixture");
    require(rdapp_store_retry(store,3),@"Restore queued fixture");
    require(rdapp_store_finish(store,4,"complete","137+140",""),@"Complete missing quality");
    rdapp_store_close(store);
    /* Publish the synthetic file before bridge startup reconciliation. */
    library_=[[RDLPOfflineLibrary alloc] initWithSupportDirectory:support downloadDirectory:downloads]; require(library_!=nil,@"Open bridge");
    NSDictionary *first=nil; for(NSDictionary *job in [library_ jobsForPlaylist:nil completedOnly:NO]) if([[job objectForKey:@"id"] isEqualToString:@"1"]) first=job;
    NSString *file=[library_ fileForJob:first];
    [[NSFileManager defaultManager] createDirectoryAtPath:[file stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
    require([[NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"fixture" ofType:@"mp4"]] writeToFile:file atomically:YES],@"Copy synthetic local media");
    require(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Reopen fixture");
    require(rdapp_store_finish(store,1,"complete","18",""),@"Publish completed fixture"); rdapp_store_close(store);
    [library_ startDownloads]; require(![library_ isPaused],@"Automatic queue startup");
    navigation_=[[UINavigationController alloc] init]; window_.rootViewController=navigation_;
    [RDLPLibrary savePreferredFormat:@"137+140"];
    RDLPLibraryViewController *root=[self show:RDLPScreenLibrary playlist:nil video:nil];
    require([sections(root) count]==3,@"Three library groups");
    require([[[sections(root) objectAtIndex:1] objectForKey:@"rows"] count]==1,@"Added playlist group");
    require([[[sections(root) objectAtIndex:2] objectForKey:@"rows"] count]==1,@"Account playlist group");
    screenshot(window_,[documents_ stringByAppendingPathComponent:@"library.png"]);
    NSDictionary *playlist=[[[[[sections(root) objectAtIndex:1] objectForKey:@"rows"] objectAtIndex:0] objectForKey:@"playlist"] retain];
    RDLPLibrarySections *model=[[[RDLPLibrarySections alloc] initWithLibrary:library_] autorelease];
    RDLPDownloadPolicy *policy=[[[RDLPDownloadPolicy alloc] initWithLibrary:library_] autorelease];
    require(![root enabled:@"removePlaylist"],@"No playlist removal at root");
    [root discover:nil]; confirm(root,NO); require(![library_ isDiscoveryPending],@"Cancelled discovery does nothing");
    [root syncAll:nil]; confirm(root,NO); require(![library_ isSyncPendingForInput:@"PLfixture"],@"Cancelled Sync All does nothing");
    [root add:nil]; confirm(root,NO); require(![library_ isSyncPendingForInput:@""],@"Cancelled Add does nothing");
    RDLPLibraryViewController *list=[self show:RDLPScreenPlaylist playlist:playlist video:nil];
    NSArray *videos=[[sections(list) objectAtIndex:0] objectForKey:@"rows"];
    require([[[videos objectAtIndex:0] objectForKey:@"detail"] isEqualToString:@"Downloaded"],@"Playable quality wins over missing preferred quality");
    NSDictionary *video=[[[videos objectAtIndex:0] objectForKey:@"video"] retain];
    require(![list enabled:@"removePlaylist"],@"Pending and completed jobs block playlist removal");
    NSArray *plan=[model missingPlanForPlaylist:[playlist objectForKey:@"id"] format:@"136+140"];
    require([plan count]==2,@"Bulk deduplicates membership and skips failed quality");
    [RDLPLibrary savePreferredFormat:@"136+140"]; [list downloadAll:nil];
    NSDictionary *captured=[[list valueForKey:@"request_"] retain]; confirm(list,NO);
    require([[library_ jobsForPlaylist:nil completedOnly:NO] count]==4,@"Cancelled bulk creates no jobs");
    /* Change eligibility and preference after capturing the plan. */
    [library_ enqueuePlaylist:[playlist objectForKey:@"id"] video:@"CCCCCCCCCCC" format:@"136+140"];
    NSDictionary *becamePending=[model jobForPlaylist:[playlist objectForKey:@"id"] video:@"CCCCCCCCCCC" format:@"136+140"];
    [library_ cancelJob:[becamePending objectForKey:@"id"]]; [RDLPLibrary savePreferredFormat:@"18"];
    [list performConfirmed:captured]; [captured release]; pump();
    require([RDLPDownloadPolicy job:[model jobForPlaylist:[playlist objectForKey:@"id"] video:@"CCCCCCCCCCC" format:@"136+140"] hasState:@"cancelled"],@"Bulk revalidation does not retry a now-stopped job");
    require([model jobForPlaylist:[playlist objectForKey:@"id"] video:@"AAAAAAAAAAA" format:@"136+140"]!=nil,@"Bulk preserves captured format");
    RDLPLibraryViewController *settings=[self show:RDLPScreenSettings playlist:nil video:nil];
    NSUInteger count=[[library_ jobsForPlaylist:nil completedOnly:NO] count];
    [settings performRow:[[[sections(settings) objectAtIndex:0] objectForKey:@"rows"] objectAtIndex:2]];
    require([[RDLPLibrary preferredFormat] isEqualToString:@"137+140"] && [[library_ jobsForPlaylist:nil completedOnly:NO] count]==count,@"Quality choice only saves preference");
    [settings performRow:findRow(settings,@"custom")]; confirm(settings,NO);
    require([[RDLPLibrary preferredFormat] isEqualToString:@"137+140"],@"Custom cancellation preserves quality");
    [settings performRow:findRow(settings,@"custom")]; [[settings valueForKey:@"alert_"] textFieldAtIndex:0].text=@"18"; confirm(settings,YES);
    require([[RDLPLibrary preferredFormat] isEqualToString:@"18"] && [[library_ jobsForPlaylist:nil completedOnly:NO] count]==count,@"Custom Save does not enqueue");
    NSString *cookie=[documents_ stringByAppendingPathComponent:@"test-cookies.txt"];
    [@"# Netscape HTTP Cookie File\n.example.invalid\tTRUE\t/\tFALSE\t0\tfixture\tone\n" writeToFile:cookie atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    require([library_ importCookies:cookie],@"Import synthetic cookies");
    require([settings requestCookieImport:cookie discover:NO],@"Replacement request accepted"); confirm(settings,NO);
    library_.testBusy=YES; [settings refresh:nil];
    require(![settings enabled:@"import"] && ![settings enabled:@"clearCookies"] && ![settings enabled:@"discover"],@"Cookie changes and discovery disabled while busy");
    library_.testBusy=NO; [settings refresh:nil];
    [settings performRow:findRow(settings,@"clearCookies")]; confirm(settings,NO); require([[library_ cookieStatus] isEqualToString:@"Imported"],@"Cancelled cookie removal retains working copy");
    [settings performRow:findRow(settings,@"clearCookies")]; confirm(settings,YES); require([[library_ cookieStatus] isEqualToString:@"Not Imported"] && [[NSFileManager defaultManager] fileExistsAtPath:cookie],@"Cookie removal retains original");
    RDLPLibraryViewController *detail=[self show:RDLPScreenVideo playlist:playlist video:video];
    require(findRow(detail,@"play")!=nil && findRow(detail,@"delete")!=nil,@"Completed video offers Play and confirmed Delete");
    [detail performRow:findRow(detail,@"play")]; pump();
    UIViewController *playerController=detail.presentedViewController;
    require(playerController!=nil,@"Local playback presents native player");
    if([playerController respondsToSelector:@selector(player)]) {
      AVPlayer *player=[playerController valueForKey:@"player"];
      for(NSUInteger wait=0;wait<10 && player.currentItem.status!=AVPlayerItemStatusReadyToPlay;++wait) pump();
      require(player.currentItem.status==AVPlayerItemStatusReadyToPlay,@"Native player loads synthetic MP4 without network"); [player pause];
    }
    if([playerController isKindOfClass:[MPMoviePlayerViewController class]]) {
      MPMoviePlayerController *movie=[(MPMoviePlayerViewController *)playerController moviePlayer];
      [movie play];
      for(NSUInteger wait=0;wait<10 && !(movie.loadState & MPMovieLoadStatePlayable);++wait) pump();
      require((movie.loadState & MPMovieLoadStatePlayable)!=0,@"Legacy player loads synthetic MP4 without network");
      [movie pause]; screenshot(window_,[documents_ stringByAppendingPathComponent:@"player.png"]);
      [detail dismissMoviePlayerViewControllerAnimated];
    } else [detail dismissViewControllerAnimated:NO completion:nil];
    for(NSUInteger wait=0;wait<10 && (detail.presentedViewController || navigation_.presentedViewController);++wait) pump();
    require(!detail.presentedViewController && !navigation_.presentedViewController,@"Native player dismissal returns to library");
    [detail performRow:findRow(detail,@"delete")]; confirm(detail,NO); require([[NSFileManager defaultManager] fileExistsAtPath:file],@"Cancelled delete retains file");
    RDLPLibraryViewController *queue=[self show:RDLPScreenQueue playlist:nil video:nil];
    require([sections(queue) count]==4,@"Four queue groups");
    NSDictionary *parent=[[[sections(queue) objectAtIndex:0] objectForKey:@"rows"] objectAtIndex:0];
    [queue performRow:parent]; [queue refresh:nil]; require([[[sections(queue) objectAtIndex:0] objectForKey:@"rows"] count]==1,@"Collapse survives refresh");
    [queue showJobInQueue:[model currentJob:@"1"]]; require([[[sections(queue) objectAtIndex:0] objectForKey:@"rows"] count]>1,@"Reveal expands target ancestors");
    NSDictionary *failed=[model currentJob:@"2"];
    require(![[model actionsForJob:failed] containsObject:@"Play"] && ![[model actionsForJob:failed] containsObject:@"Stop Download…"],@"Failed quality actions are state-specific");
    [queue performRow:[NSDictionary dictionaryWithObjectsAndKeys:@"job",@"action",failed,@"job",nil]]; choose(queue,@"Download Video");
    require([RDLPDownloadPolicy job:[model currentJob:@"2"] hasState:@"queued"] && [[[model currentJob:@"2"] objectForKey:@"format"] isEqualToString:@"136+140"],@"Retry uses selected quality, ignoring preference");
    [queue showJobInQueue:[model currentJob:@"2"]]; NSIndexPath *selected=queue.tableView.indexPathForSelectedRow; require(selected!=nil,@"Retried quality selected in Queue");
    UITableViewCell *cell=[queue.tableView cellForRowAtIndexPath:selected]; require([cell.accessoryView isKindOfClass:[UIButton class]],@"Queued quality has row action");
    [(UIButton *)cell.accessoryView sendActionsForControlEvents:UIControlEventTouchUpInside]; confirm(queue,NO); require([RDLPDownloadPolicy job:[model currentJob:@"2"] hasState:@"queued"],@"Cancelled row stop does nothing");
    [queue performRow:[NSDictionary dictionaryWithObjectsAndKeys:@"job",@"action",[model currentJob:@"2"],@"job",nil]]; choose(queue,@"Stop Download…"); confirm(queue,YES);
    require([RDLPDownloadPolicy job:[model currentJob:@"2"] hasState:@"cancelled"] && [RDLPDownloadPolicy job:[model currentJob:@"3"] hasState:@"queued"] && ![library_ isPaused],@"Stopping one quality preserves other pending work");
    selected=queue.tableView.indexPathForSelectedRow; require(selected.section==3,@"Selection follows quality to Needs Attention");
    require([policy canDownloadAgain:[model currentJob:@"4"]],@"Missing completed file is retryable");
    RDLPAppDelegate *lifecycle=[[[RDLPAppDelegate alloc] init] autorelease]; [lifecycle setValue:library_ forKey:@"library_"];
    [lifecycle applicationDidEnterBackground:[UIApplication sharedApplication]]; require([library_ isPaused],@"Background pauses transfers");
    [lifecycle applicationWillEnterForeground:[UIApplication sharedApplication]]; require(![library_ isPaused] && [RDLPDownloadPolicy job:[model currentJob:@"2"] hasState:@"cancelled"],@"Foreground resumes pending work without retrying stopped qualities");
    [lifecycle setValue:nil forKey:@"library_"];
    [queue refresh:nil]; screenshot(window_,[documents_ stringByAppendingPathComponent:@"queue.png"]);
    [queue.tableView setContentOffset:CGPointZero animated:NO];
    CGPoint browsingOffset=queue.tableView.contentOffset; [queue refresh:nil];
    require(CGPointEqualToPoint(browsingOffset,queue.tableView.contentOffset),@"Progress refresh must not scroll back to the selected quality");
    CGRect tableFrame=queue.tableView.frame;
    require([[queue valueForKey:@"progress_"] isHidden],@"Historical jobs do not activate progress");
    library_.testProgress=[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES],@"active",[NSNumber numberWithInt:3],@"processed",[NSNumber numberWithInt:5],@"total",[NSNumber numberWithInt:1],@"failed",[NSNumber numberWithInt:1],@"cancelled",nil];
    [queue refresh:nil]; UIProgressView *progress=[queue valueForKey:@"progress_"];
    require(!progress.hidden && progress.progress>0.59f && progress.progress<0.61f && CGRectEqualToRect(tableFrame,queue.tableView.frame),@"Progress shows run attempts without moving the table");
    screenshot(window_,[documents_ stringByAppendingPathComponent:@"progress.png"]);
    library_.testProgress=nil; [queue refresh:nil]; require(progress.hidden,@"Drained run hides progress");
    [playlist release]; [video release];
  } @catch(NSException *exception) { report=[NSString stringWithFormat:@"FAIL: %@\n%@",exception,[exception callStackSymbols]]; }
  [report writeToFile:[documents_ stringByAppendingPathComponent:@"result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  NSLog(@"%@",report);
}
@end
int main(int argc,char **argv) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init]; int result=UIApplicationMain(argc,argv,nil,@"RDLPIOSOfflineTest"); [pool drain]; return result;
}
