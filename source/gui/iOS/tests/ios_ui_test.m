#import "../RDLPPlaylistsViewController.h"
#import "../RDLPPlaylistViewController.h"
#import "../RDLPDownloadsViewController.h"
#import "../RDLPQueueViewController.h"
/* Native UIKit regressions. All data is synthetic and confined to this bundle.
   The scheduler override below never calls the production worker. */
#import "../RDLPLibraryViewController.h"
#import "../RDLPSettingsViewController.h"
#import "../RDLPAppDelegate.h"
#import "../RDLPUIKit.h"
#import <AIFontAwesome.h>
#import "ios_icon_test.h"
#import "../../shared/rdapp_store.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "../../shared/tests/shared_status_test.h"
#import "ios_lifecycle_test.h"
#import "ios_playback_progress_test.h"
#import "../../shared/tests/shared_metadata_test.h"
#import "../../shared/tests/shared_video_rows_test.h"

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
@property(nonatomic,copy) NSString *testStatus;
@end
@implementation RDLPOfflineLibrary
@synthesize testProgress=testProgress_, testBusy=testBusy_;
- (NSString *)testStatus { return [super status]; }
- (void)setTestStatus:(NSString *)status {
  [self showStatus:status];
}
- (NSDictionary *)activityProgress {
  if(!testProgress_ && !testBusy_) return [super activityProgress];
  return [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithBool:[self isBusy] && [[self status] length]>0],@"active",
    [testProgress_ objectForKey:@"processed"]?:@0,@"completed",
    [testProgress_ objectForKey:@"total"]?:@0,@"expected",nil];
}
- (NSDictionary *)queueProgress { return testProgress_?testProgress_:[super queueProgress]; }
- (BOOL)isBusy { return testBusy_ || [[testProgress_ objectForKey:@"active"] boolValue] || [super isBusy]; }
- (void)dealloc { [testProgress_ release]; [super dealloc]; }
- (void)startNext { /* Deliberately never schedules network or media work. */ }
- (void)work:(NSDictionary *)command {
  (void)command; [NSException raise:@"OfflineViolation" format:@"Worker must never run in this test"];
}
@end
@interface RDLPOfflineNavigationController : UINavigationController {
  BOOL lastToolbarChangeAnimated_;
}
@property(nonatomic,readonly) BOOL lastToolbarChangeAnimated;
@end
@implementation RDLPOfflineNavigationController
@synthesize lastToolbarChangeAnimated=lastToolbarChangeAnimated_;
- (void)setToolbarHidden:(BOOL)hidden animated:(BOOL)animated {
  if(hidden!=self.toolbarHidden) lastToolbarChangeAnimated_=animated;
  [super setToolbarHidden:hidden animated:animated];
}
@end
static NSArray *sections(id controller) { return [controller valueForKey:@"sections_"]; }
static NSDictionary *findRow(id controller,NSString *action) {
  for(NSDictionary *section in sections(controller)) for(NSDictionary *row in [section objectForKey:@"rows"])
    if([[row objectForKey:@"action"] isEqualToString:action]) return row;
  return nil;
}
static NSIndexPath *videoIndex(id controller,NSString *video,NSString *format) {
  NSArray *rows=[[sections(controller) objectAtIndex:0] objectForKey:@"rows"];
  for(NSUInteger i=0;i<[rows count];++i) {
    NSDictionary *row=[rows objectAtIndex:i];
    if([[[row objectForKey:@"video"] objectForKey:@"video_id"] isEqualToString:video] &&
       (!format || [[[row objectForKey:@"job"] objectForKey:@"format"] isEqualToString:format]))
      return [NSIndexPath indexPathForRow:(NSInteger)i inSection:0];
  }
  require(NO,[NSString stringWithFormat:@"Missing video row %@ (%@)",video,format]); return nil;
}
/* Exercise UIKit's real confirmation controls, not just delegate calls. The
   * older swipe implementation recursively reloaded during their dismissal. */
static UIControl *editingControl(UIView *view,NSString *classPart) {
  if([view isKindOfClass:[UIControl class]]) {
    if([NSStringFromClass([view class]) rangeOfString:classPart].location!=NSNotFound) return (UIControl *)view;
    if([classPart isEqualToString:@"DeleteConfirmation"] &&
       (([view isKindOfClass:[UIButton class]] && [[(UIButton *)view currentTitle] isEqualToString:@"Delete"]) ||
        [view.accessibilityLabel isEqualToString:@"Delete"])) return (UIControl *)view;
  }
  for(UIView *child in view.subviews) { UIControl *found=editingControl(child,classPart); if(found) return found; }
  return nil;
}
static void nativeDelete(RDLPVideoListViewController *controller,NSIndexPath *index) {
  UITableView *table=controller.tableView;
  [table setEditing:YES animated:NO]; pump();
  [table scrollToRowAtIndexPath:index atScrollPosition:UITableViewScrollPositionNone animated:NO];
  UITableViewCell *cell=[table cellForRowAtIndexPath:index];
  UIControl *edit=editingControl(cell,@"EditControl");
  require(edit!=nil,@"UIKit exposes the native row edit control");
  [edit sendActionsForControlEvents:UIControlEventTouchUpInside]; pump();
  UIControl *button=editingControl(table,@"DeleteConfirmation");
  require(button!=nil,@"UIKit exposes its Delete confirmation button");
  [button sendActionsForControlEvents:UIControlEventTouchUpInside]; pump(); pump();
  [table setEditing:NO animated:NO]; pump();
}
static void confirmAt(id controller,BOOL accept,int line) {
  UIAlertView *alert=[controller valueForKey:@"alert_"];
  require(alert!=nil,[NSString stringWithFormat:@"Expected confirmation at test line %d",line]); [alert retain]; pump();
  [controller alertView:alert clickedButtonAtIndex:accept?1:0];
  [alert dismissWithClickedButtonIndex:accept?1:0 animated:NO]; [alert release]; pump(); pump();
}
#define confirm(controller,accept) confirmAt(controller,accept,__LINE__)
static void choose(id controller,NSString *title) {
  UIAlertView *alert=[controller valueForKey:@"alert_"]; require(alert!=nil,@"Expected job actions"); [alert retain]; pump();
  NSInteger index=0; for(NSInteger i=1;i<alert.numberOfButtons;++i) if([[alert buttonTitleAtIndex:i] isEqualToString:title]) index=i;
  require(index>0,[NSString stringWithFormat:@"Missing action %@",title]);
  [controller alertView:alert clickedButtonAtIndex:index]; [alert dismissWithClickedButtonIndex:index animated:NO]; [alert release]; pump(); pump();
}
static void screenshot(UIWindow *window,NSString *path) {
  UIGraphicsBeginImageContextWithOptions(window.bounds.size,NO,0);
  [window.layer renderInContext:UIGraphicsGetCurrentContext()];
  [UIImagePNGRepresentation(UIGraphicsGetImageFromCurrentImageContext()) writeToFile:path atomically:YES]; UIGraphicsEndImageContext();
}
@interface RDLPIOSOfflineTest : UIResponder <UIApplicationDelegate> {
  UIWindow *window_;
  RDLPOfflineLibrary *library_;
  RDLPOfflineNavigationController *navigation_;
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
- (id)show:(RDLPScreen)mode playlist:(NSDictionary *)playlist video:(NSDictionary *)video;
{
  id controller=mode==RDLPScreenLibrary?(id)[[[RDLPPlaylistsViewController alloc] initWithLibrary:library_] autorelease]:
    (mode==RDLPScreenPlaylist?(id)[[[RDLPPlaylistViewController alloc] initWithLibrary:library_ playlist:playlist] autorelease]:
    (mode==RDLPScreenDownloads?(id)[[[RDLPDownloadsViewController alloc] initWithLibrary:library_] autorelease]:
    (mode==RDLPScreenQueue?(id)[[[RDLPQueueViewController alloc] initWithLibrary:library_] autorelease]:
    [[[RDLPLibraryViewController alloc] initWithLibrary:library_ mode:mode playlist:playlist video:video] autorelease])));
  if(navigation_.presentedViewController) {
    [navigation_ dismissViewControllerAnimated:NO completion:nil]; pump(); pump();
  }
  [navigation_ setViewControllers:[NSArray arrayWithObject:controller] animated:NO]; [controller view]; [controller refresh:nil]; pump(); return controller;
}
- (void)run;
{
  [@"RUNNING" writeToFile:[documents_ stringByAppendingPathComponent:@"result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  NSString *report=@"PASS";
  @try {
    testIOSPlaybackProgress([documents_ stringByAppendingPathComponent:@"PlaybackFixture"]);
    if([[[NSBundle mainBundle] objectForInfoDictionaryKey:@"RDLPTestPlaybackOnly"] boolValue]) {
      [@"PASS: playback transition checkpoints, database reopen, backward seeking, background audio, and completion" writeToFile:[documents_ stringByAppendingPathComponent:@"result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
      return;
    }
    testIOSIconScale();
    if([[[NSBundle mainBundle] objectForInfoDictionaryKey:@"RDLPTestIconsOnly"] boolValue]) {
      [@"PASS: white icon pixels, screen scale, and compatible template rendering" writeToFile:[documents_ stringByAppendingPathComponent:@"result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
      return;
    }
    testSharedMetadata();
    testSharedVideoRows([documents_ stringByAppendingPathComponent:@"RowFixture"]);
    testSharedStatus([documents_ stringByAppendingPathComponent:@"StatusFixture"]);
    testIOSLifecycle([documents_ stringByAppendingPathComponent:@"LifecycleFixture"]);
    testIOSDownloadNotifications([documents_ stringByAppendingPathComponent:@"NotificationFixture"]);
    {
      RDLPStatusTestLibrary *errors=[[[RDLPStatusTestLibrary alloc] initWithSupportDirectory:[documents_ stringByAppendingPathComponent:@"Alerts/Support"] downloadDirectory:[documents_ stringByAppendingPathComponent:@"Alerts/Downloads"]] autorelease];
      RDLPAppDelegate *presenter=[[RDLPAppDelegate alloc] init];
      [presenter setValue:errors forKey:@"library_"];
      [errors showStatus:@"Downloading"];
      [errors importCookies:@"/synthetic-missing-cookie-file"];
      [presenter performSelector:@selector(showNextError)]; pump();
      UIAlertView *first=[presenter valueForKey:@"errorAlert_"];
      require(first.visible && [first.title isEqualToString:@"Couldn’t import cookies"],@"Shared error becomes a native alert");
      [errors importCookies:@"/synthetic-missing-cookie-file"];
      [presenter performSelector:@selector(showNextError)];
      require([presenter valueForKey:@"errorAlert_"]==first && [errors hasErrors],@"A second error waits behind the native alert");
      [first dismissWithClickedButtonIndex:0 animated:NO]; pump(); pump();
      UIAlertView *second=[presenter valueForKey:@"errorAlert_"];
      require(second.visible && ![errors hasErrors],@"Next error appears after dismissal");
      [second dismissWithClickedButtonIndex:0 animated:NO]; pump(); pump();
      require(![presenter valueForKey:@"errorAlert_"] && [[errors status] isEqualToString:@"Downloading"],@"Alerts leave download status alone");
      [presenter release];
    }
    require([[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"]==nil,@"Isolated bundle must not contain a CA resource");
    require([RDLPUIKit statusIcon:@"Downloaded"]!=nil && [RDLPUIKit queueActionIcon:YES]!=nil && [RDLPUIKit queueActionIcon:NO]!=nil,@"Status and queue action glyphs render");
    NSString *base=[documents_ stringByAppendingPathComponent:@"Fixture"];
    [[NSFileManager defaultManager] removeItemAtPath:base error:NULL];
    NSString *support=[base stringByAppendingPathComponent:@"Support"], *downloads=[base stringByAppendingPathComponent:@"Downloads"];
    rdapp_make_directory([support fileSystemRepresentation]); rdapp_make_directory([downloads fileSystemRepresentation]);
    rdapp_store *store=NULL; long long pid=0, other=0;
    require(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Open fixture");
    rdapp_entry entries[]={{.video_id="AAAAAAAAAAA",.title="A playable video",.position=0},{.video_id="BBBBBBBBBBB",.title="Failed and queued video",.position=1},{.video_id="CCCCCCCCCCC",.title="Missing video",.position=2},{.video_id="CCCCCCCCCCC",.title="Repeated video",.position=3}};
    entries[0].channel="Example Channel"; entries[0].duration=754; entries[0].has_duration=1;
    entries[1].duration=0; entries[1].has_duration=1;
    entries[2].channel="Original Channel";
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
    require(rdapp_store_finish(store,1,"complete","18",""),@"Publish completed fixture");
    require(rdapp_store_reconcile(store,[downloads fileSystemRepresentation]),@"Reconcile offline fixture without starting a worker"); rdapp_store_close(store);
    testSharedLists(library_);
    [library_ startDownloads]; require(![library_ isPaused],@"Automatic queue startup");
    navigation_=[[RDLPOfflineNavigationController alloc] init]; window_.rootViewController=navigation_;
    RDLPOfflineLibrary *emptyLibrary=[[[RDLPOfflineLibrary alloc] initWithSupportDirectory:[base stringByAppendingPathComponent:@"EmptySupport"] downloadDirectory:[base stringByAppendingPathComponent:@"EmptyDownloads"]] autorelease];
    require(emptyLibrary!=nil,@"Open empty queue fixture"); emptyLibrary.testStatus=@"";
    RDLPQueueViewController *emptyQueue=[[[RDLPQueueViewController alloc] initWithLibrary:emptyLibrary] autorelease];
    [navigation_ setViewControllers:[NSArray arrayWithObject:emptyQueue] animated:NO]; [emptyQueue view]; [emptyQueue refresh:nil]; pump();
    require([emptyQueue.tableView numberOfRowsInSection:0]==0 && navigation_.toolbarHidden && emptyQueue.tableView.tableFooterView==nil && ![emptyQueue respondsToSelector:@selector(tableView:titleForFooterInSection:)],@"Empty Queue has no placeholder section, footer, or idle toolbar");
    [RDLPLibrary savePreferredFormat:@"137+140"];
    RDLPPlaylistsViewController *root=[self show:RDLPScreenLibrary playlist:nil video:nil];
    testIOSIconImage(root.navigationItem.rightBarButtonItem.image,26,[[UIScreen mainScreen] scale],YES);
    require([root isKindOfClass:[UITableViewController class]] && root.view==root.tableView,@"Fresh-launch home is a native table controller");
    require([root.title isEqualToString:@"Playlists"] && root.tableView.style==UITableViewStylePlain,@"Plain Playlists home");
    require([root.toolbarItems count]==5 && !navigation_.toolbarHidden,@"ENIL-style home toolbar");
    UIBarButtonItem *queueButton=[root.toolbarItems lastObject];
    require(queueButton.image!=nil && queueButton.action==@selector(queue:),@"Trailing Queue button");
    RDLPStatusBarView *bar=[root valueForKey:@"statusBar_"];
    UIProgressView *barProgress=[bar valueForKey:@"progress_"];
    require(bar!=nil && barProgress.hidden,@"Idle status is text only");
    CGRect homeTableFrame=root.tableView.frame;
    library_.testProgress=[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES],@"active",@3,@"processed",@5,@"total",@1,@"failed",@1,@"cancelled",nil];
    library_.testStatus=@"Downloading"; [root refresh:nil]; pump();
    require(!barProgress.hidden && barProgress.progress>0.59f && barProgress.progress<0.61f && CGRectEqualToRect(homeTableFrame,root.tableView.frame),@"Toolbar progress preserves table geometry");
    screenshot(window_,[documents_ stringByAppendingPathComponent:@"toolbar-progress.png"]);
    [bar setStatus:@"A very long download status that must fit beside the queue button without obscuring it" progress:[library_ activityProgress] busy:NO];
    require(bar.frame.size.width<=bar.maximumWidth,@"Long status fits beside Queue");
    library_.testProgress=nil; [root refresh:nil];
    library_.testBusy=YES; [root refresh:nil];
    require(barProgress.hidden && [[bar valueForKey:@"spinner_"] isAnimating],@"Unknown progress uses a spinner, never a fabricated percentage");
    library_.testBusy=NO; [root refresh:nil];
    [root queue:nil]; pump(); pump();
    UINavigationController *queueModal=(UINavigationController *)navigation_.presentedViewController;
    require([queueModal isKindOfClass:[UINavigationController class]] && navigation_.topViewController==root,@"Queue presents modally without changing home stack");
    RDLPQueueViewController *modalQueue=(RDLPQueueViewController *)queueModal.topViewController;
    require([modalQueue.title isEqualToString:@"Download Queue"] && modalQueue.navigationItem.rightBarButtonItem.action==@selector(dismissQueue:),@"Queue has Done dismissal");
    [root queue:nil];
    require(navigation_.presentedViewController==queueModal,@"Repeated Queue action reuses modal");
    [modalQueue showJobInQueue:[[library_ jobsForPlaylist:nil completedOnly:NO] objectAtIndex:0]];
    require(queueModal.presentedViewController==nil,@"Reveal inside Queue does not nest another modal");
    screenshot(window_,[documents_ stringByAppendingPathComponent:@"queue-modal.png"]);
    [modalQueue dismissQueue:nil]; pump(); pump();
    require(navigation_.presentedViewController==nil && !navigation_.toolbarHidden && navigation_.topViewController==root,@"Done restores home toolbar");
    [root settings:nil]; pump(); pump();
    UINavigationController *settingsModal=(UINavigationController *)navigation_.presentedViewController;
    require([settingsModal isKindOfClass:[UINavigationController class]] && navigation_.topViewController==root,@"Settings presents modally");
    RDLPSettingsViewController *modalSettings=(RDLPSettingsViewController *)settingsModal.topViewController;
    require([modalSettings isKindOfClass:[UITableViewController class]] && modalSettings.view==modalSettings.tableView && modalSettings.tableView.tableFooterView==nil,@"Settings is a table controller without a status footer");
    require([modalSettings.title isEqualToString:@"Settings"] && modalSettings.navigationItem.rightBarButtonItem.action==@selector(dismissSettings:),@"Settings has Done");
    [root settings:nil]; require(navigation_.presentedViewController==settingsModal,@"Settings does not stack duplicate modals");
    screenshot(window_,[documents_ stringByAppendingPathComponent:@"settings-modal.png"]);
    [modalSettings dismissSettings:nil]; pump(); pump();
    require(navigation_.presentedViewController==nil && navigation_.topViewController==root && !navigation_.toolbarHidden,@"Done restores Playlists");
    require(root.navigationItem.leftBarButtonItem.image!=nil && root.navigationItem.leftBarButtonItem.action==@selector(settings:),@"Settings gear");
    require(root.navigationItem.rightBarButtonItem.image!=nil && root.navigationItem.rightBarButtonItem.action==@selector(showPlaylistActions:),@"Font Awesome plus opens playlist actions");
    require(findRow(root,@"queue")==nil && [[[sections(root) objectAtIndex:0] objectForKey:@"rows"] count]==1,@"System contains only All Downloads");
    require(findRow(root,@"settings")==nil,@"Settings moved out of playlist list");
    require(![root respondsToSelector:@selector(tableView:viewForHeaderInSection:)] || [root tableView:root.tableView viewForHeaderInSection:0]==nil,@"Home uses standard section headers");
    require(![root respondsToSelector:@selector(tableView:titleForFooterInSection:)] || [root tableView:root.tableView titleForFooterInSection:1]==nil,@"Home has no placeholder section footer");
    require(![root respondsToSelector:@selector(tableView:heightForHeaderInSection:)] || [root tableView:root.tableView heightForHeaderInSection:1]==root.tableView.sectionHeaderHeight,@"Home uses default section header height");
    [root showPlaylistActions:nil]; pump();
    UIActionSheet *sheet=[root valueForKey:@"playlistActions_"];
    require(sheet!=nil && sheet.numberOfButtons==5,@"Add commands, playlist commands and Cancel");
    require([[sheet buttonTitleAtIndex:0] isEqualToString:@"Add Video…"] && [[sheet buttonTitleAtIndex:1] isEqualToString:@"Add Playlist…"] && [[sheet buttonTitleAtIndex:2] isEqualToString:@"Sync All Playlists…"] && [[sheet buttonTitleAtIndex:3] isEqualToString:@"Load My Playlists…"],@"Library management commands put Add Video first");
    [sheet dismissWithClickedButtonIndex:sheet.cancelButtonIndex animated:NO];
    for(NSUInteger wait=0;wait<10 && [root valueForKey:@"playlistActions_"];++wait) pump();
    pump(); pump();
    require([root valueForKey:@"playlistActions_"]==nil && [root valueForKey:@"alert_"]==nil && navigation_.topViewController==root,@"Cancelling sheet leaves home unchanged");
    [root showPlaylistActions:nil]; pump();
    sheet=[root valueForKey:@"playlistActions_"];
    [sheet dismissWithClickedButtonIndex:0 animated:NO];
    for(NSUInteger wait=0;wait<10 && [root valueForKey:@"playlistActions_"];++wait) pump();
    pump(); pump();
    require([root valueForKey:@"playlistActions_"]==nil && [[[root valueForKey:@"alert_"] title] isEqualToString:@"Add Video"],@"First action opens Add Video after sheet dismisses");
    confirm(root,NO);
    [root showPlaylistActions:nil]; pump(); sheet=[root valueForKey:@"playlistActions_"];
    [sheet dismissWithClickedButtonIndex:1 animated:NO];
    for(NSUInteger wait=0;wait<10 && [root valueForKey:@"playlistActions_"];++wait) pump();
    pump(); pump();
    require([[[root valueForKey:@"alert_"] title] isEqualToString:@"Add Playlist"],@"Second action opens Add Playlist after sheet dismisses");
    confirm(root,NO);
    require([sections(root) count]==3,@"Three library groups");
    require([[[sections(root) objectAtIndex:1] objectForKey:@"rows"] count]==1,@"Added playlist group");
    require([[[sections(root) objectAtIndex:2] objectForKey:@"rows"] count]==1,@"Account playlist group");
    screenshot(window_,[documents_ stringByAppendingPathComponent:@"library.png"]);
    NSDictionary *playlist=[[[[[sections(root) objectAtIndex:1] objectForKey:@"rows"] objectAtIndex:0] objectForKey:@"playlist"] retain];
    RDLPLibrarySections *model=[[[RDLPLibrarySections alloc] initWithLibrary:library_] autorelease];
    NSArray *lazySections=[model sectionsForScreen:RDLPScreenLibrary playlist:nil video:nil collapsed:nil];
    NSArray *lazyRows=[[lazySections objectAtIndex:1] objectForKey:@"rows"];
    require([lazyRows count]>0 && [(RDLPLibraryRows *)lazyRows cachedObjectAtIndex:0]==nil,@"Section counts do not format playlist rows");
    require([[lazyRows objectAtIndex:0] objectForKey:@"playlist"]!=nil && [(RDLPLibraryRows *)lazyRows cachedObjectAtIndex:0]!=nil,@"Playlist formatting happens on row access");
    RDLPDownloadPolicy *policy=[[[RDLPDownloadPolicy alloc] initWithLibrary:library_] autorelease];
    RDLPDownloadsViewController *nativeList=[self show:RDLPScreenDownloads playlist:nil video:nil];
    nativeDelete(nativeList,videoIndex(nativeList,@"AAAAAAAAAAA",@"18"));
    require(![[NSFileManager defaultManager] fileExistsAtPath:file] && [nativeList tableView:nativeList.tableView numberOfRowsInSection:0]==0,@"UIKit confirmation deletes the last download without recursive reload or crash");
    /* Restore media for the remaining playback and state regressions. */
    require([[NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"fixture" ofType:@"mp4"]] writeToFile:file atomically:YES],@"Restore native-delete fixture");
    require(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Open native-delete fixture");
    require(rdapp_store_finish(store,1,"complete","18",""),@"Restore native-delete job"); rdapp_store_close(store);
    root=[self show:RDLPScreenLibrary playlist:nil video:nil];
    require(![root enabled:@"removePlaylist"],@"No playlist removal at root");
    [root discover:nil]; confirm(root,NO); require(![library_ isDiscoveryPending],@"Cancelled discovery does nothing");
    [root syncAll:nil]; confirm(root,NO); require(![library_ isSyncPendingForInput:@"PLfixture"],@"Cancelled Sync All does nothing");
    [root add:nil]; confirm(root,NO); require(![library_ isSyncPendingForInput:@""],@"Cancelled Add does nothing");
    library_.testStatus=@"";
    [root performRow:findRow(root,@"playlist")]; pump(); pump();
    require([navigation_.topViewController isKindOfClass:[RDLPPlaylistViewController class]] && navigation_.toolbarHidden,@"Playlist navigation opens the plain detail controller and hides home toolbar");
    [navigation_ popViewControllerAnimated:NO]; pump();
    require(!navigation_.toolbarHidden,@"Back restores the home toolbar");
    RDLPPlaylistViewController *list=[self show:RDLPScreenPlaylist playlist:playlist video:nil];
    require([list isKindOfClass:[UITableViewController class]] && list.view==list.tableView && list.tableView.style==UITableViewStylePlain,@"Playlist detail is a native plain table without a separate status area");
    require([list.toolbarItems count]==5 && navigation_.toolbarHidden && list.tableView.tableFooterView==nil,@"Playlist has the parent toolbar, hidden when idle, without a table status footer");
    require(list.navigationItem.rightBarButtonItem.image!=nil && [list.navigationItem.rightBarButtonItem.accessibilityLabel isEqualToString:@"Sync"] && list.navigationItem.rightBarButtonItem.action==@selector(sync:),@"Playlist navigation has accessible Sync icon");
    RDLPStatusBarView *playlistBar=[list valueForKey:@"statusBar_"];
    UIBarButtonItem *playlistQueueButton=[list.toolbarItems lastObject];
    require([[list.toolbarItems objectAtIndex:2] customView]==playlistBar && playlistQueueButton.action==@selector(queue:),@"Parent layout has centered status and trailing Queue");
    library_.testBusy=YES;
    library_.testProgress=[NSDictionary dictionaryWithObjectsAndKeys:@YES,@"active",@2,@"processed",@5,@"total",@0,@"failed",@0,@"cancelled",nil];
    library_.testStatus=@"Downloading video"; pump(); pump();
    UIProgressView *playlistProgress=[playlistBar valueForKey:@"progress_"];
    require(!navigation_.toolbarHidden && navigation_.lastToolbarChangeAnimated && !playlistProgress.hidden && playlistProgress.progress>0.39f && playlistProgress.progress<0.41f,@"Active status animates in the parent progress toolbar");
    screenshot(window_,[documents_ stringByAppendingPathComponent:@"playlist-toolbar.png"]);
    library_.testStatus=@""; pump(); pump();
    require(navigation_.toolbarHidden && navigation_.lastToolbarChangeAnimated,@"Empty status animates toolbar out even when progress is still active");
    library_.testStatus=@"Downloading again"; pump(); pump();
    library_.testStatus=@""; pump(); pump();
    require(navigation_.toolbarHidden && navigation_.lastToolbarChangeAnimated,@"Empty status animates toolbar out");
    library_.testStatus=@"Downloading video"; pump(); pump();
    [list queue:nil]; pump(); pump();
    UINavigationController *playlistQueue=(UINavigationController *)navigation_.presentedViewController;
    require([playlistQueue isKindOfClass:[UINavigationController class]] && [playlistQueue.topViewController.title isEqualToString:@"Download Queue"] && navigation_.topViewController==list,@"Playlist Queue button presents the same queue modal as parent");
    [(RDLPQueueViewController *)playlistQueue.topViewController dismissQueue:nil]; pump(); pump();
    require(navigation_.presentedViewController==nil && !navigation_.toolbarHidden,@"Queue dismissal restores active playlist toolbar");
    library_.testBusy=NO; library_.testProgress=nil; library_.testStatus=@"Finished playlist work";
    NSDate *toolbarExpiry=[NSDate dateWithTimeIntervalSinceNow:10.3];
    while([toolbarExpiry timeIntervalSinceNow]>0) { [list refresh:nil]; pump(); }
    pump();
    require(navigation_.toolbarHidden && navigation_.lastToolbarChangeAnimated,@"Expired empty status animates the whole playlist toolbar out");
    library_.testStatus=@"";
    [navigation_ setViewControllers:[NSArray arrayWithObject:root] animated:NO]; pump();
    library_.testStatus=@"";
    require(!navigation_.toolbarHidden,@"Offscreen playlist refresh cannot hide parent toolbar");
    [navigation_ setViewControllers:[NSArray arrayWithObject:list] animated:NO]; pump();
    UITableViewCell *videoCell=[list tableView:list.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    require([videoCell.accessoryView isKindOfClass:[UIImageView class]] && [(UIImageView *)videoCell.accessoryView image]!=nil && videoCell.imageView.image==nil && videoCell.accessoryType==UITableViewCellAccessoryNone,@"Video status occupies the accessory with no disclosure chevron or leading image");
    require([videoCell.accessibilityLabel rangeOfString:@"Downloaded"].location!=NSNotFound,@"Accessory status is accessible");
    require([videoCell.detailTextLabel.text hasPrefix:@"12:34 · "] && [videoCell.detailTextLabel.text hasSuffix:@" · Low (18) · Example Channel"],@"Playlist subtitle orders duration, file size, quality, and channel");
    require([videoCell.accessibilityLabel rangeOfString:@"12 minutes, 34 seconds"].location!=NSNotFound,@"Playlist duration is spoken as time");
    screenshot(window_,[documents_ stringByAppendingPathComponent:@"playlist.png"]);
    NSArray *videos=[[[[sections(list) objectAtIndex:0] objectForKey:@"rows"] copy] autorelease];
    require([videos count]==4,@"Playlist retains one row per entry regardless of quality count");
    require([[[videos objectAtIndex:0] objectForKey:@"status"] isEqualToString:@"Downloaded"] &&
      [[[[videos objectAtIndex:0] objectForKey:@"job"] objectForKey:@"format"] isEqualToString:@"18"],@"Playable quality represents video despite missing preferred quality");
    require([videoCell.detailTextLabel.text rangeOfString:@"(18)"].location!=NSNotFound,@"Downloaded playlist subtitle shows its playable job quality");
    for(NSDictionary *row in videos)
      require([[row objectForKey:@"status"] isEqualToString:@"Downloaded"] || [[row objectForKey:@"detail"] rangeOfString:@"("].location==NSNotFound,@"Playlist omits quality when no playable download is available");
    NSIndexPath *pendingIndex=videoIndex(list,@"BBBBBBBBBBB",@"18");
    UITableViewCell *pendingCell=[list tableView:list.tableView cellForRowAtIndexPath:pendingIndex];
    require([pendingCell.detailTextLabel.text isEqualToString:@"0:00"],@"Zero duration is visible without claiming a playable quality");
    require([(UIImageView *)pendingCell.accessoryView image]==[RDLPUIKit statusIcon:@"Queued"],@"Queued quality represents video ahead of failed quality");
    UITableViewCell *originalCell=[list tableView:list.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]], *repeatedCell=[list tableView:list.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]];
    require([(UIImageView *)originalCell.accessoryView image]==[(UIImageView *)repeatedCell.accessoryView image],@"Repeated playlist entries share representative status");
    require([originalCell.detailTextLabel.text isEqualToString:@"Original Channel"] && ![repeatedCell.detailTextLabel.text length],@"Duplicate entries retain independent optional metadata");
    library_.testStatus=nil;
    NSDictionary *video=[[[videos objectAtIndex:0] objectForKey:@"video"] retain];
    require(![model canRemovePlaylist:playlist],@"Pending and completed jobs block playlist removal");
    NSArray *plan=[model missingPlanForPlaylist:[playlist objectForKey:@"id"] format:@"136+140"];
    require([plan count]==2,@"Bulk deduplicates membership and skips failed quality");
    /* Keep the shared bulk-command regression independent of playlist UI. */
    RDLPLibraryViewController *bulkActions=[[[RDLPLibraryViewController alloc] initWithLibrary:library_ mode:RDLPScreenVideo playlist:playlist video:video] autorelease];
    [RDLPLibrary savePreferredFormat:@"136+140"]; [bulkActions downloadAll:nil];
    NSDictionary *captured=[[bulkActions valueForKey:@"request_"] retain]; confirm(bulkActions,NO);
    require([[library_ jobsForPlaylist:nil completedOnly:NO] count]==4,@"Cancelled bulk creates no jobs");
    /* Change eligibility and preference after capturing the plan. */
    [library_ enqueuePlaylist:[playlist objectForKey:@"id"] video:@"CCCCCCCCCCC" format:@"136+140"];
    NSDictionary *becamePending=[model jobForPlaylist:[playlist objectForKey:@"id"] video:@"CCCCCCCCCCC" format:@"136+140"];
    [library_ cancelJob:[becamePending objectForKey:@"id"]]; [RDLPLibrary savePreferredFormat:@"18"];
    [bulkActions performConfirmed:captured]; [captured release]; pump();
    require([RDLPDownloadPolicy job:[model jobForPlaylist:[playlist objectForKey:@"id"] video:@"CCCCCCCCCCC" format:@"136+140"] hasState:@"cancelled"],@"Bulk revalidation does not retry a now-stopped job");
    require([model jobForPlaylist:[playlist objectForKey:@"id"] video:@"AAAAAAAAAAA" format:@"136+140"]!=nil,@"Bulk preserves captured format");
    if(navigation_.presentedViewController) { [navigation_ dismissViewControllerAnimated:NO completion:nil]; pump(); pump(); }
    RDLPSettingsViewController *settings=[[[RDLPSettingsViewController alloc] initWithLibrary:library_] autorelease];
    [navigation_ setViewControllers:[NSArray arrayWithObject:settings] animated:NO]; [settings view]; [settings refresh:nil]; pump();
    require(settings.tableView.style==UITableViewStyleGrouped,@"Settings stays grouped");
    require(![settings respondsToSelector:@selector(tableView:titleForFooterInSection:)] || ([settings tableView:settings.tableView titleForFooterInSection:0]==nil && [settings tableView:settings.tableView titleForFooterInSection:1]==nil),@"Settings has no explanatory footers");
    NSDictionary *importRow=findRow(settings,@"import");
    require([[importRow objectForKey:@"title"] isEqualToString:@"Import Cookies..."] && ![[importRow objectForKey:@"detail"] length],@"Simple import label without subtitle");
    require([settings enabled:@"import"],@"Import enabled before cookies imported");
    for(NSInteger row=0;row<3;++row) {
      UITableViewCell *cookieCell=[settings tableView:settings.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:1]];
      require(cookieCell.accessoryType==UITableViewCellAccessoryNone && cookieCell.accessoryView==nil,@"Cookie actions have no disclosure accessory");
    }
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
    require(![settings enabled:@"import"],@"Imported cookies disable import even when idle");
    [settings performRow:findRow(settings,@"import")]; require([settings valueForKey:@"alert_"]==nil,@"Disabled import cannot open replacement dialog");
    require([settings requestCookieImport:cookie discover:NO],@"Replacement request accepted"); confirm(settings,NO);
    library_.testBusy=YES; [settings refresh:nil];
    require(![settings enabled:@"import"] && ![settings enabled:@"clearCookies"],@"Cookie changes and discovery disabled while busy");
    library_.testBusy=NO; [settings refresh:nil];
    [settings performRow:findRow(settings,@"clearCookies")]; confirm(settings,NO); require([[library_ cookieStatus] isEqualToString:@"Imported"],@"Cancelled cookie removal retains working copy");
    [settings performRow:findRow(settings,@"clearCookies")]; confirm(settings,YES); require([[library_ cookieStatus] isEqualToString:@"Not Imported"] && [[NSFileManager defaultManager] fileExistsAtPath:cookie],@"Cookie removal retains original");
    require([settings enabled:@"import"],@"Removing cookies enables import again");
    RDLPLibraryViewController *detail=[self show:RDLPScreenVideo playlist:playlist video:video];
    require(findRow(detail,@"play")!=nil && findRow(detail,@"delete")!=nil,@"Completed video offers Play and confirmed Delete");
    [library_ savePlaybackSeconds:1 forVideo:[video objectForKey:@"video_id"]];
    [detail performRow:findRow(detail,@"play")]; pump();
    UIViewController *playerController=detail.presentedViewController;
    require(playerController!=nil,@"Local playback presents native player");
    if([playerController respondsToSelector:@selector(player)]) {
      AVPlayer *player=[playerController valueForKey:@"player"];
      for(NSUInteger wait=0;wait<10 && player.currentItem.status!=AVPlayerItemStatusReadyToPlay;++wait) pump();
      require(player.currentItem.status==AVPlayerItemStatusReadyToPlay,@"Native player loads synthetic MP4 without network");
      for(NSUInteger wait=0;wait<10 && player.rate==0;++wait) pump();
      [player pause];
      require(CMTimeGetSeconds(player.currentTime)>=1,@"Modern player resumes from the database before playing");
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
    RDLPQueueViewController *queue=[self show:RDLPScreenQueue playlist:nil video:nil];
    require([queue isKindOfClass:[UITableViewController class]] && queue.view==queue.tableView && queue.tableView.style==UITableViewStylePlain,@"Queue is a native plain table controller");
    require([sections(queue) count]==1 && queue.tableView.tableFooterView==nil,@"Flat Queue has no groups or empty footer");
    require([queue.toolbarItems count]==5 && [[queue.toolbarItems objectAtIndex:2] customView]==[queue valueForKey:@"statusBar_"],@"Queue has centered status without a Queue button");
    NSArray *queueRows=[[sections(queue) objectAtIndex:0] objectForKey:@"rows"];
    long long previousID=0; NSUInteger position=0,failedIndex=NSNotFound;
    for(NSDictionary *row in queueRows) {
      NSDictionary *job=[row objectForKey:@"job"]; ++position;
      if([[job objectForKey:@"id"] isEqualToString:@"2"]) failedIndex=position-1;
      require(position==1 || [[job objectForKey:@"id"] longLongValue]<previousID,@"Queue shows newest items first");
      previousID=[[job objectForKey:@"id"] longLongValue];
      require([[row objectForKey:@"title"] isEqualToString:[NSString stringWithFormat:@"%@) %@",[job objectForKey:@"id"],[job objectForKey:@"title"]]],@"Queue uses permanent database job IDs and video titles");
      require([[row objectForKey:@"detail"] rangeOfString:[job objectForKey:@"playlist_title"]].location!=NSNotFound && [[row objectForKey:@"detail"] rangeOfString:[job objectForKey:@"format"]].location!=NSNotFound,@"Subtitle identifies playlist and exact quality");
      require([row objectForKey:@"depth"]==nil && [[row objectForKey:@"action"] isEqualToString:@"job"],@"Every queue row is a download, with no outline nodes");
    }
    [queue showJobInQueue:[model currentJob:@"2"]]; NSIndexPath *selected=queue.tableView.indexPathForSelectedRow;
    require(failedIndex!=NSNotFound && selected.row==(NSInteger)failedIndex && selected.section==0,@"Reveal selects the exact quality in newest-first order");
    UITableViewCell *cell=[queue.tableView cellForRowAtIndexPath:selected];
    UITableViewCell *defaultCell=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil] autorelease];
    require([cell.accessoryView isKindOfClass:[UIImageView class]] && cell.imageView.image==nil && cell.indentationLevel==0 && cell.textLabel.font.pointSize==defaultCell.textLabel.font.pointSize && cell.detailTextLabel.font.pointSize==defaultCell.detailTextLabel.font.pointSize,@"Queue shares native subtitle cell styling and trailing status icon");
    NSArray *statuses=[NSArray arrayWithObjects:@"Queued",@"Downloading",@"Downloaded",@"Failed",@"Stopped",@"Interrupted",@"File missing",nil];
    for(NSString *status in statuses) {
      NSString *playlistStatus=[status isEqualToString:@"Stopped"]?@"Cancelled":status;
      require([UIImagePNGRepresentation([queue statusIcon:status]) isEqualToData:UIImagePNGRepresentation([RDLPUIKit statusIcon:playlistStatus])],@"Queue status icons match Playlist");
    }
    [queue tableView:queue.tableView didSelectRowAtIndexPath:selected];
    UIAlertView *jobMenu=[queue valueForKey:@"alert_"];
    require([jobMenu.message rangeOfString:@"Synthetic failure"].location!=NSNotFound,@"Queue job dialog includes full error");
    for(NSInteger i=0;i<jobMenu.numberOfButtons;++i) require(![[jobMenu buttonTitleAtIndex:i] isEqualToString:@"Show in Queue"],@"Queue actions omit redundant navigation");
    choose(queue,@"Retry Download");
    require([RDLPDownloadPolicy job:[model currentJob:@"2"] hasState:@"queued"] && [[[model currentJob:@"2"] objectForKey:@"format"] isEqualToString:@"136+140"],@"Retry uses selected quality, ignoring preference");
    [queue tableView:queue.tableView didSelectRowAtIndexPath:selected]; choose(queue,@"Stop Download…"); confirm(queue,NO);
    require([RDLPDownloadPolicy job:[model currentJob:@"2"] hasState:@"queued"],@"Cancelled row stop does nothing");
    [queue tableView:queue.tableView didSelectRowAtIndexPath:selected]; choose(queue,@"Stop Download…"); confirm(queue,YES);
    require([RDLPDownloadPolicy job:[model currentJob:@"2"] hasState:@"cancelled"] && [RDLPDownloadPolicy job:[model currentJob:@"3"] hasState:@"queued"] && ![library_ isPaused],@"Stopping one quality preserves other pending work");
    require([queue.tableView.indexPathForSelectedRow isEqual:selected] && [[[[[sections(queue) objectAtIndex:0] objectForKey:@"rows"] objectAtIndex:failedIndex] objectForKey:@"status"] isEqualToString:@"Stopped"],@"Status changes preserve row position and stable selection");
    /* Deleting a job preserves the other jobs' permanent display numbers. */
    nativeDelete(queue,selected); [queue refresh:nil];
    queueRows=[[sections(queue) objectAtIndex:0] objectForKey:@"rows"];
    require([queueRows count]+1==position,@"Deleting a job removes exactly one queue row");
    for(NSDictionary *row in queueRows) {
      NSString *jobID=[[row objectForKey:@"job"] objectForKey:@"id"];
      require(![jobID isEqualToString:@"2"] && [[row objectForKey:@"title"] hasPrefix:[NSString stringWithFormat:@"%@) ",jobID]],@"Deleted jobs are hidden without renumbering the remaining jobs");
    }
    BOOL hasMissing=NO; for(NSDictionary *row in queueRows) if([[row objectForKey:@"status"] isEqualToString:@"File missing"]) hasMissing=YES;
    require(hasMissing,@"Missing files remain visible for retry");
    require(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Restore queue fixture");
    require(rdapp_store_finish(store,2,"cancelled","",""),@"Restore stopped quality"); rdapp_store_close(store); [queue refresh:nil];
    require([policy canDownloadAgain:[model currentJob:@"4"]],@"Missing completed file is retryable");
    RDLPAppDelegate *lifecycle=[[[RDLPAppDelegate alloc] init] autorelease]; [lifecycle setValue:library_ forKey:@"library_"];
    [library_ startDownloads];
    [lifecycle applicationDidEnterBackground:[UIApplication sharedApplication]]; require(![library_ isPaused],@"Background keeps the queue eligible while time remains");
    [lifecycle applicationWillEnterForeground:[UIApplication sharedApplication]]; require(![library_ isPaused] && [RDLPDownloadPolicy job:[model currentJob:@"2"] hasState:@"cancelled"],@"Foreground resumes pending work without retrying stopped qualities");
    [lifecycle setValue:nil forKey:@"library_"];
    [queue refresh:nil]; screenshot(window_,[documents_ stringByAppendingPathComponent:@"queue.png"]);
    [queue.tableView setContentOffset:CGPointZero animated:NO];
    CGPoint browsingOffset=queue.tableView.contentOffset; [queue refresh:nil];
    require(CGPointEqualToPoint(browsingOffset,queue.tableView.contentOffset),@"Progress refresh must not scroll back to the selected quality");
    RDLPStatusBarView *queueBar=[queue valueForKey:@"statusBar_"];
    UIProgressView *progress=[queueBar valueForKey:@"progress_"];
    require(progress.hidden,@"Historical jobs do not activate progress");
    library_.testStatus=@""; require(navigation_.toolbarHidden,@"Idle queue has no toolbar");
    library_.testProgress=[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES],@"active",[NSNumber numberWithInt:3],@"processed",[NSNumber numberWithInt:5],@"total",[NSNumber numberWithInt:1],@"failed",[NSNumber numberWithInt:1],@"cancelled",nil];
    [queue refresh:nil]; pump();
    require(navigation_.toolbarHidden && progress.hidden,@"No message means no status toolbar even if work remains active");
    library_.testStatus=@"Downloading fixture"; pump();
    CGRect tableFrame=queue.tableView.frame; [queue refresh:nil];
    require(CGRectEqualToRect(tableFrame,queue.tableView.frame),@"Progress refresh keeps the native table frame stable");
    screenshot(window_,[documents_ stringByAppendingPathComponent:@"progress.png"]);
    library_.testProgress=nil; library_.testStatus=@"Queue finished"; [queue refresh:nil];
    require(progress.hidden && !navigation_.toolbarHidden,@"Drained run leaves timed completion message");
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:10.2]];
    require(navigation_.toolbarHidden && navigation_.lastToolbarChangeAnimated,@"Queue completion toolbar disappears with animation after ten seconds");
    library_.testStatus=nil;
    RDLPStatusBarView *timedBar=[[[RDLPStatusBarView alloc] initWithFrame:CGRectZero] autorelease];
    UILabel *timedLabel=[timedBar valueForKey:@"label_"];
    [timedBar setStatus:@"Downloading" progress:nil busy:YES];
    [timedBar setStatus:@"" progress:nil busy:NO];
    require(![timedLabel.text length],@"Renderer clears immediately when shared status expires");
    [timedBar setStatus:[library_ status] progress:[library_ activityProgress] busy:NO];
    require(![timedLabel.text length],@"New view cannot resurrect expired shared status");
    /* Exercise playlist taps after the shared queue fixtures have been tested. */
    require(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Open playlist interaction fixture");
    rdapp_entry tapEntries[]={{.video_id="AAAAAAAAAAA",.title="A playable video",.position=0},{.video_id="BBBBBBBBBBB",.title="Failed and queued video",.position=1},{.video_id="CCCCCCCCCCC",.title="Missing video",.position=2},{.video_id="CCCCCCCCCCC",.title="Repeated video",.position=3},{.video_id="DDDDDDDDDDD",.title="New video",.position=4}};
    require(rdapp_store_snapshot(store,"PLfixture","Updated Playlist",tapEntries,5,&pid),@"Add undownloaded video fixture");
    require(rdapp_store_finish(store,2,"failed","","Synthetic playlist failure"),@"Restore failed quality after queue stop tests"); rdapp_store_close(store);
    library_.testStatus=@"";
    list=[self show:RDLPScreenPlaylist playlist:playlist video:nil];
    require([list.title isEqualToString:@"Updated Playlist"],@"Playlist title refreshes from library");
    NSIndexPath *playIndex=videoIndex(list,@"AAAAAAAAAAA",@"18"), *queuedIndex=videoIndex(list,@"BBBBBBBBBBB",@"18"), *newIndex=videoIndex(list,@"DDDDDDDDDDD",nil);
    [RDLPLibrary savePreferredFormat:@"137+140"];
    [library_ savePlaybackSeconds:1 forVideo:@"AAAAAAAAAAA"];
    [list tableView:list.tableView didSelectRowAtIndexPath:playIndex]; pump(); pump();
    MPMoviePlayerViewController *playlistPlayer=(MPMoviePlayerViewController *)list.presentedViewController;
    require([playlistPlayer isKindOfClass:[MPMoviePlayerViewController class]],@"Playlist tap presents MPMoviePlayerViewController even with another preferred quality");
    require([playlistPlayer.moviePlayer.contentURL isEqual:[NSURL fileURLWithPath:file]],@"Playlist plays the existing local file");
    [playlistPlayer.moviePlayer play];
    for(NSUInteger wait=0;wait<10 && !(playlistPlayer.moviePlayer.loadState & MPMovieLoadStatePlayable);++wait) pump();
    require((playlistPlayer.moviePlayer.loadState & MPMovieLoadStatePlayable)!=0,@"Playlist movie player loads offline media");
    [playlistPlayer.moviePlayer pause];
    require(playlistPlayer.moviePlayer.currentPlaybackTime>=1,@"Legacy player resumes from the database timestamp");
    playlistPlayer.moviePlayer.currentPlaybackTime=0.75; pump();
    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationWillResignActiveNotification object:[UIApplication sharedApplication]];
    require(fabs([library_ playbackSecondsForVideo:@"AAAAAAAAAAA"]-0.75)<0.25,@"Backgrounding saves legacy playback immediately");
    playlistPlayer.moviePlayer.currentPlaybackTime=0.5; pump();
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:10.2]];
    require(fabs([library_ playbackSecondsForVideo:@"AAAAAAAAAAA"]-0.5)<0.25,@"Ten-second timer saves a backward seek to the database");
    playlistPlayer.moviePlayer.currentPlaybackTime=1.5; pump();
    [list dismissMoviePlayerViewControllerAnimated];
    for(NSUInteger wait=0;wait<10 && (list.presentedViewController || navigation_.presentedViewController);++wait) pump();
    require(!list.presentedViewController && navigation_.toolbarHidden,@"Movie dismissal returns to playlist without a toolbar");
    require(fabs([library_ playbackSecondsForVideo:@"AAAAAAAAAAA"]-1.5)<0.25,@"Dismissing the legacy player saves its final position");
    [library_ savePlaybackSeconds:0.75 forVideo:@"AAAAAAAAAAA"];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:10.2]];
    require([library_ playbackSecondsForVideo:@"AAAAAAAAAAA"]==0.75,@"Dismissed player cannot overwrite a newer position");
    library_.testStatus=nil;
    NSUInteger beforeTap=[[library_ jobsForPlaylist:nil completedOnly:NO] count];
    require(![list tableView:list.tableView canEditRowAtIndexPath:queuedIndex] && ![list tableView:list.tableView canEditRowAtIndexPath:newIndex],@"Queued and undownloaded playlist rows cannot be swiped to delete");
    [list tableView:list.tableView didSelectRowAtIndexPath:queuedIndex];
    require([[library_ jobsForPlaylist:nil completedOnly:NO] count]==beforeTap && [list valueForKey:@"alert_"]==nil && !navigation_.presentedViewController,@"Queued row does not enqueue or navigate");
    [library_ cancelJob:@"3"]; [list refresh:nil];
    [list tableView:list.tableView didSelectRowAtIndexPath:videoIndex(list,@"BBBBBBBBBBB",@"136+140")]; confirm(list,YES);
    require([RDLPDownloadPolicy job:[model currentJob:@"2"] hasState:@"queued"] && [RDLPDownloadPolicy job:[model currentJob:@"3"] hasState:@"cancelled"],@"Retry targets the representative failed quality without changing its sibling");
    [library_ retryJob:@"3"];
    require([policy playable:[model currentJob:@"1"]] && videoIndex(list,@"AAAAAAAAAAA",@"18")!=nil,@"Playable quality continues to represent video with missing sibling");
    NSIndexPath *duplicateIndex=videoIndex(list,@"CCCCCCCCCCC",@"136+140");
    [list tableView:list.tableView didSelectRowAtIndexPath:duplicateIndex]; confirm(list,YES);
    NSArray *duplicateRows=[[sections(list) objectAtIndex:0] objectForKey:@"rows"];
    NSDictionary *original=[duplicateRows objectAtIndex:(NSUInteger)duplicateIndex.row], *duplicate=[duplicateRows objectAtIndex:(NSUInteger)duplicateIndex.row+1];
    require([[original objectForKey:@"status"] isEqualToString:@"Queued"] && [[original objectForKey:@"status"] isEqualToString:[duplicate objectForKey:@"status"]] && [[[original objectForKey:@"job"] objectForKey:@"id"] isEqualToString:[[duplicate objectForKey:@"job"] objectForKey:@"id"]],@"Retry refreshes both occurrences of a repeated video to the same job and status");
    [list tableView:list.tableView didSelectRowAtIndexPath:newIndex];
    NSDictionary *newJob=[model jobForPlaylist:[playlist objectForKey:@"id"] video:@"DDDDDDDDDDD" format:@"137+140"];
    require([RDLPDownloadPolicy job:newJob hasState:@"queued"] && navigation_.topViewController==list && !navigation_.presentedViewController,@"Undownloaded row queues preferred quality and stays on playlist");
    [list tableView:list.tableView didSelectRowAtIndexPath:newIndex];
    require([[library_ jobsForPlaylist:nil completedOnly:NO] count]==beforeTap+1,@"Repeated tap does not duplicate download");
    require([UIImagePNGRepresentation([RDLPUIKit statusIcon:@"Downloading"]) isEqualToData:UIImagePNGRepresentation([RDLPUIKit statusIcon:@"Queued"])],@"Downloading and queued use the same hourglass");
    require(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Open failure fixture");
    require(rdapp_store_finish(store,[[newJob objectForKey:@"id"] longLongValue],"failed","","Synthetic playlist failure"),@"Fail tapped download"); rdapp_store_close(store);
    [list refresh:nil]; [list tableView:list.tableView didSelectRowAtIndexPath:newIndex];
    require([[[list valueForKey:@"alert_"] message] rangeOfString:@"Synthetic playlist failure"].location!=NSNotFound,@"Retry alert explains failure");
    confirm(list,NO);
    require([RDLPDownloadPolicy job:[model currentJob:[newJob objectForKey:@"id"]] hasState:@"failed"],@"Cancelled retry leaves failure unchanged");
    [list tableView:list.tableView didSelectRowAtIndexPath:newIndex];
    [RDLPLibrary savePreferredFormat:@"18"]; confirm(list,YES);
    require([RDLPDownloadPolicy job:[model currentJob:[newJob objectForKey:@"id"]] hasState:@"queued"] && [model jobForPlaylist:[playlist objectForKey:@"id"] video:@"DDDDDDDDDDD" format:@"18"]==nil,@"Confirmed retry preserves failed quality despite preference change");
    [library_ cancelJob:[newJob objectForKey:@"id"]];
    [list tableView:list.tableView didSelectRowAtIndexPath:newIndex];
    [library_ retryJob:[newJob objectForKey:@"id"]]; confirm(list,YES);
    require([RDLPDownloadPolicy job:[model currentJob:[newJob objectForKey:@"id"]] hasState:@"queued"],@"Retry confirmation revalidates a job already queued elsewhere");
    [library_ cancelJob:[newJob objectForKey:@"id"]]; [library_ removeDownload:[model currentJob:[newJob objectForKey:@"id"]]];
    [RDLPLibrary savePreferredFormat:@"18"];
    [list tableView:list.tableView didSelectRowAtIndexPath:newIndex];
    require([RDLPDownloadPolicy job:[model currentJob:[newJob objectForKey:@"id"]] hasState:@"queued"] && [list valueForKey:@"alert_"]==nil && [model jobForPlaylist:[playlist objectForKey:@"id"] video:@"DDDDDDDDDDD" format:@"18"]==nil,@"Removed quality downloads again at its own quality, ignoring preference");
    /* All Downloads shares playlist presentation but keeps every completed quality. */
    NSDictionary *highJob=[model currentJob:@"4"];
    NSString *highFile=[library_ fileForJob:highJob];
    require([[NSData dataWithContentsOfFile:file] writeToFile:highFile atomically:YES],@"Publish second local quality");
    require(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Open All Downloads fixture");
    require(rdapp_store_finish(store,4,"complete","137+140",""),@"Complete second quality"); rdapp_store_close(store);
    library_.testStatus=@"";
    root=[self show:RDLPScreenLibrary playlist:nil video:nil];
    [root performRow:findRow(root,@"downloads")]; pump(); pump();
    RDLPDownloadsViewController *all=(RDLPDownloadsViewController *)navigation_.topViewController;
    require([all isKindOfClass:[RDLPDownloadsViewController class]] && [all isKindOfClass:[UITableViewController class]] && all.view==all.tableView && all.tableView.style==UITableViewStylePlain,@"All Downloads navigation opens a native plain table controller");
    require([all.title isEqualToString:@"All Downloads"] && !all.navigationItem.rightBarButtonItem && navigation_.toolbarHidden && !all.tableView.tableFooterView,@"All Downloads has no Sync button or separate status footer and hides idle toolbar");
    NSArray *downloadRows=[[sections(all) objectAtIndex:0] objectForKey:@"rows"];
    require([downloadRows count]==2,@"All Downloads keeps both completed qualities and excludes pending/failed jobs");
    NSIndexPath *lowIndex=videoIndex(all,@"AAAAAAAAAAA",@"18"), *highIndex=videoIndex(all,@"AAAAAAAAAAA",@"137+140");
    UITableViewCell *lowCell=[all tableView:all.tableView cellForRowAtIndexPath:lowIndex], *highCell=[all tableView:all.tableView cellForRowAtIndexPath:highIndex];
    NSString *representativeFormat=[[[[[sections(list) objectAtIndex:0] objectForKey:@"rows"] objectAtIndex:0] objectForKey:@"job"] objectForKey:@"format"];
    UITableViewCell *playlistComparisonCell=[list tableView:list.tableView cellForRowAtIndexPath:videoIndex(list,@"AAAAAAAAAAA",representativeFormat)];
    UITableViewCell *matchingDownloadCell=[all tableView:all.tableView cellForRowAtIndexPath:videoIndex(all,@"AAAAAAAAAAA",representativeFormat)];
    require([matchingDownloadCell.textLabel.text isEqualToString:playlistComparisonCell.textLabel.text] && [matchingDownloadCell.detailTextLabel.text isEqualToString:playlistComparisonCell.detailTextLabel.text] && [matchingDownloadCell.textLabel.font isEqual:playlistComparisonCell.textLabel.font] && [matchingDownloadCell.detailTextLabel.font isEqual:playlistComparisonCell.detailTextLabel.font] && all.tableView.rowHeight==list.tableView.rowHeight,@"All Downloads matches playlist title, subtitle, typography, and row height");
    require([highCell.textLabel.text isEqualToString:lowCell.textLabel.text] && ![highCell.detailTextLabel.text isEqualToString:lowCell.detailTextLabel.text],@"Separate qualities share title and have distinct quality subtitles");
    require([highCell.accessoryView isKindOfClass:[UIImageView class]] && highCell.accessoryType==UITableViewCellAccessoryNone && !highCell.imageView.image && [highCell.accessibilityLabel rangeOfString:@"Downloaded"].location!=NSNotFound,@"All Downloads shares accessible trailing status icon without leading image or chevron");
    screenshot(window_,[documents_ stringByAppendingPathComponent:@"downloads.png"]);
    for(NSString *format in [NSArray arrayWithObjects:@"18",@"137+140",nil]) {
      [all tableView:all.tableView didSelectRowAtIndexPath:videoIndex(all,@"AAAAAAAAAAA",format)]; pump(); pump();
      MPMoviePlayerViewController *player=(MPMoviePlayerViewController *)all.presentedViewController;
      require([player isKindOfClass:[MPMoviePlayerViewController class]] && [player.moviePlayer.contentURL isEqual:[NSURL fileURLWithPath:[format isEqualToString:@"18"]?file:highFile]],@"All Downloads plays precisely the tapped quality");
      [player.moviePlayer pause]; [all dismissMoviePlayerViewControllerAnimated];
      for(NSUInteger wait=0;wait<10 && (all.presentedViewController || navigation_.presentedViewController);++wait) pump();
      require(!all.presentedViewController && navigation_.toolbarHidden,@"Playback returns to All Downloads with hidden idle toolbar");
    }
    NSUInteger membershipCount=[[library_ entriesForPlaylist:[playlist objectForKey:@"id"]] count];
    require([all tableView:all.tableView canEditRowAtIndexPath:highIndex] && [all tableView:all.tableView editingStyleForRowAtIndexPath:highIndex]==UITableViewCellEditingStyleDelete,@"Completed qualities expose native swipe Delete");
    [all tableView:all.tableView willBeginEditingRowAtIndexPath:highIndex];
    [all tableView:all.tableView didEndEditingRowAtIndexPath:highIndex];
    require([[NSFileManager defaultManager] fileExistsAtPath:highFile],@"Dismissing swipe without Delete preserves the download");
    [all tableView:all.tableView willBeginEditingRowAtIndexPath:highIndex];
    [all refresh:nil];
    [all tableView:all.tableView commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:highIndex]; pump();
    require(![[NSFileManager defaultManager] fileExistsAtPath:highFile] && [policy playable:[model currentJob:@"1"]] && [RDLPDownloadPolicy job:[model currentJob:@"4"] hasState:@"removed"],@"Swipe Delete removes exactly the selected completed quality and preserves its sibling");
    require([all tableView:all.tableView numberOfRowsInSection:0]==1 && [[library_ entriesForPlaylist:[playlist objectForKey:@"id"]] count]==membershipCount,@"All Downloads drops deleted row while playlist membership is retained");
    require(videoIndex(list,@"AAAAAAAAAAA",@"18")!=nil,@"Playlist switches to its remaining playable quality after deletion");
    /* Restore the second quality for the missing-file and toolbar regressions. */
    require([[NSData dataWithContentsOfFile:file] writeToFile:highFile atomically:YES],@"Restore second local quality");
    require(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Reopen completed fixture");
    require(rdapp_store_finish(store,4,"complete","137+140",""),@"Restore completed quality"); rdapp_store_close(store); [all refresh:nil];
    library_.testBusy=YES; library_.testStatus=@"Downloading from All Downloads"; pump(); pump();
    require(!navigation_.toolbarHidden && navigation_.lastToolbarChangeAnimated,@"All Downloads animates active status toolbar in");
    [all queue:nil]; pump(); pump();
    UINavigationController *downloadsQueue=(UINavigationController *)navigation_.presentedViewController;
    require([downloadsQueue.topViewController.title isEqualToString:@"Download Queue"],@"All Downloads opens shared queue modal");
    [(RDLPQueueViewController *)downloadsQueue.topViewController dismissQueue:nil]; pump(); pump();
    require(!navigation_.presentedViewController && !navigation_.toolbarHidden,@"Queue dismissal restores All Downloads status toolbar");
    library_.testStatus=@""; pump(); pump();
    require(navigation_.toolbarHidden,@"All Downloads hides empty status even during active work");
    library_.testStatus=@"Another message"; pump();
    library_.testStatus=@""; pump(); pump();
    require(navigation_.toolbarHidden,@"All Downloads hides empty status");
    library_.testBusy=NO; library_.testStatus=@"Downloads finished"; pump();
    require(!navigation_.toolbarHidden,@"New idle message shows All Downloads toolbar");
    NSDate *downloadsExpiry=[NSDate dateWithTimeIntervalSinceNow:10.3];
    while([downloadsExpiry timeIntervalSinceNow]>0) { [all refresh:nil]; pump(); }
    pump();
    require(navigation_.toolbarHidden && navigation_.lastToolbarChangeAnimated,@"All Downloads animates toolbar out after ten seconds despite repeated refreshes");
    [all refresh:nil]; pump(); require(navigation_.toolbarHidden,@"Expired All Downloads message stays hidden");
    library_.testStatus=@"New download message"; pump(); pump();
    require(!navigation_.toolbarHidden,@"New message reopens expired All Downloads toolbar");
    [navigation_ popViewControllerAnimated:NO]; pump(); library_.testStatus=@"";
    require(!navigation_.toolbarHidden,@"Offscreen All Downloads cannot hide home toolbar");
    [navigation_ pushViewController:all animated:NO]; pump();
    require([[NSFileManager defaultManager] removeItemAtPath:highFile error:NULL],@"Remove selected quality after snapshot");
    [all tableView:all.tableView didSelectRowAtIndexPath:highIndex];
    require([[[all valueForKey:@"retryRequest_"] objectForKey:@"job"] isEqualToString:@"4"],@"Stale completed row retries its missing file at the same quality");
    [RDLPLibrary savePreferredFormat:@"18"]; confirm(all,YES);
    require([RDLPDownloadPolicy job:[model currentJob:@"4"] hasState:@"queued"] && [policy playable:[model currentJob:@"1"]],@"Missing-file retry preserves selected quality and sibling download");
    require([[[sections(all) objectAtIndex:0] objectForKey:@"rows"] count]==1,@"Retried job leaves completed-only All Downloads");
    lowIndex=videoIndex(all,@"AAAAAAAAAAA",@"18");
    [all tableView:all.tableView willBeginEditingRowAtIndexPath:lowIndex];
    library_.testBusy=YES;
    [all tableView:all.tableView commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:lowIndex]; pump();
    require([policy playable:[model currentJob:@"1"]],@"Work starting during a swipe prevents file removal");
    library_.testBusy=NO;
    [all tableView:all.tableView willBeginEditingRowAtIndexPath:lowIndex];
    [all tableView:all.tableView commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:lowIndex]; pump();
    require([all tableView:all.tableView numberOfRowsInSection:0]==0 && (![all respondsToSelector:@selector(tableView:titleForFooterInSection:)] || [all tableView:all.tableView titleForFooterInSection:0]==nil),@"Empty All Downloads has no placeholder section footer");
    list=[self show:RDLPScreenPlaylist playlist:playlist video:nil];
    /* Each stopped/failed quality may retain final, video, audio, and .part files. */
    NSString *staging=[downloads stringByAppendingPathComponent:[@".staging/" stringByAppendingString:[newJob objectForKey:@"id"]]];
    NSArray *partialNames=[NSArray arrayWithObjects:@"video.mp4",@"video.mp4.part",@"video.mp4.video.mp4",@"video.mp4.video.mp4.part",@"video.mp4.audio.m4a",@"video.mp4.audio.m4a.part",nil];
    for(NSString *state in [NSArray arrayWithObjects:@"failed",@"interrupted",@"cancelled",nil]) {
      require([[NSFileManager defaultManager] createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:NULL],@"Create partial download staging");
      for(NSString *name in partialNames)
        require([[@"partial media" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[staging stringByAppendingPathComponent:name] atomically:YES],@"Write partial audio/video fixture");
      require(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Open partial fixture");
      require(rdapp_store_finish(store,[[newJob objectForKey:@"id"] longLongValue],[state UTF8String],"","Retained partial download"),@"Set partial download state"); rdapp_store_close(store);
      [list refresh:nil]; newIndex=videoIndex(list,@"DDDDDDDDDDD",@"137+140");
      require([list tableView:list.tableView canEditRowAtIndexPath:newIndex],@"Failed, interrupted, and cancelled qualities support swipe Delete");
      if([state isEqualToString:@"failed"]) {
        [list tableView:list.tableView willBeginEditingRowAtIndexPath:newIndex];
        [library_ retryJob:[newJob objectForKey:@"id"]];
        require([[[[[sections(list) objectAtIndex:0] objectForKey:@"rows"] objectAtIndex:(NSUInteger)newIndex.row] objectForKey:@"status"] isEqualToString:@"Failed"],@"Refresh preserves the swiped row snapshot until editing ends");
        [list tableView:list.tableView commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:newIndex]; pump();
        require([RDLPDownloadPolicy job:[model currentJob:[newJob objectForKey:@"id"]] hasState:@"queued"] && [[NSFileManager defaultManager] fileExistsAtPath:staging],@"Delete revalidates a quality queued during the swipe and preserves its fragments");
        require(![list tableView:list.tableView canEditRowAtIndexPath:newIndex],@"Requeued partial download disables swipe Delete");
        require(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Open running fixture");
        require(rdapp_store_finish(store,[[newJob objectForKey:@"id"] longLongValue],"running","",""),@"Start partial fixture"); rdapp_store_close(store); [list refresh:nil];
        require(![list tableView:list.tableView canEditRowAtIndexPath:newIndex],@"Running partial download disables swipe Delete");
        [list tableView:list.tableView commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:newIndex]; pump();
        require([[NSFileManager defaultManager] fileExistsAtPath:staging],@"Even a stale Delete callback cannot remove running partial files");
        require(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Open stopped fixture");
        require(rdapp_store_finish(store,[[newJob objectForKey:@"id"] longLongValue],"failed","","Retained partial download"),@"Stop partial fixture"); rdapp_store_close(store); [list refresh:nil];
      }
      [list tableView:list.tableView willBeginEditingRowAtIndexPath:newIndex];
      [list tableView:list.tableView commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:newIndex]; pump();
      require(![[NSFileManager defaultManager] fileExistsAtPath:staging] && [RDLPDownloadPolicy job:[model currentJob:[newJob objectForKey:@"id"]] hasState:@"removed"],@"Swipe Delete cleans all partial files and records removal");
      require([[library_ entriesForPlaylist:[playlist objectForKey:@"id"]] count]==membershipCount && ![list tableView:list.tableView canEditRowAtIndexPath:newIndex],@"Deleted partial quality retains playlist row and no longer offers Delete");
    }
    [list sync:nil];
    require([library_ isSyncPendingForInput:@"PLfixture"] && !list.navigationItem.rightBarButtonItem.enabled,@"Sync queues playlist refresh and disables while pending");
    [playlist release]; [video release];
    require(rdapp_store_open([[support stringByAppendingPathComponent:@"retrodlp.sqlite"] fileSystemRepresentation],&store),@"Open Ad-Hoc fixture");
    require(rdapp_store_add_adhoc(store,"ABCDEFGHIJK","Individual video",NULL),@"Add Ad-Hoc fixture");
    rdapp_store_close(store);
    root=[self show:RDLPScreenLibrary playlist:nil video:nil];
    NSArray *systemRows=[[sections(root) objectAtIndex:0] objectForKey:@"rows"];
    require([systemRows count]==2 && [[[systemRows objectAtIndex:1] objectForKey:@"title"] isEqualToString:@"Ad-Hoc"],@"Ad-Hoc appears under System");
    NSDictionary *adhoc=[library_ adhocPlaylist];
    RDLPPlaylistViewController *adhocView=[self show:RDLPScreenPlaylist playlist:adhoc video:nil];
    require(!adhocView.navigationItem.rightBarButtonItem.enabled,@"Ad-Hoc Sync is disabled");
    NSUInteger commands=[[library_ valueForKey:@"commands_"] count];
    [adhocView sync:nil];
    require([[library_ valueForKey:@"commands_"] count]==commands,@"Ad-Hoc cannot enqueue sync");
    [root syncAll:nil];
    NSArray *inputs=[[root valueForKey:@"request_"] objectForKey:@"inputs"];
    require(![inputs containsObject:@RDAPP_ADHOC_PLAYLIST_ID],@"Sync All excludes Ad-Hoc");
    if([root valueForKey:@"alert_"]) confirm(root,NO);
    require([RDLPLibrary savePreferredFormat:@"137+140"],@"Select Add Video quality");
    [library_ addVideoInput:@"  YE7VzlLtp-4  "];
    NSDictionary *addedJob=[library_ jobForPlaylist:[[library_ adhocPlaylist] objectForKey:@"id"] video:@"YE7VzlLtp-4" format:@"137+140"];
    require([RDLPLibrary savePreferredFormat:@"18"],@"Change quality after adding");
    require([[addedJob objectForKey:@"state"] isEqualToString:@"queued"] &&
      [[addedJob objectForKey:@"video_id"] isEqualToString:@"YE7VzlLtp-4"] &&
      [[addedJob objectForKey:@"format"] isEqualToString:@"137+140"],@"Add Video immediately queues the selected download quality without a worker");
  } @catch(NSException *exception) { report=[NSString stringWithFormat:@"FAIL: %@\n%@",exception,[exception callStackSymbols]]; }
  [report writeToFile:[documents_ stringByAppendingPathComponent:@"result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  NSLog(@"%@",report);
}
@end
int main(int argc,char **argv) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init]; int result=UIApplicationMain(argc,argv,nil,@"RDLPIOSOfflineTest"); [pool drain]; return result;
}
