#import "../RDLPPlaylistViewController.h"
#import <AIFontAwesome.h>
#import "../../shared/tests/native_performance.h"
@interface RDLPPerfIOS : UIResponder <UIApplicationDelegate,RDLPPerfTable> {
  BOOL running_, interrupted_;
  UIWindow *window_; RDLPPlaylistViewController *controller_; UINavigationController *navigation_;
}
@end
@implementation RDLPPerfIOS
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options;
{
  (void)application; (void)options; [AIFontAwesome registerBundledFonts];
  window_=[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  [window_ setRootViewController:[[[UIViewController alloc] init] autorelease]];
  [window_ makeKeyAndVisible]; [self performSelector:@selector(run) withObject:nil afterDelay:0.5]; return YES;
}
- (void)openLibrary:(RDLPLibrary *)library playlist:(NSDictionary *)playlist;
{
  controller_=[[RDLPPlaylistViewController alloc] initWithLibrary:library playlist:playlist];
  navigation_=[[UINavigationController alloc] initWithRootViewController:controller_];
  [window_ setRootViewController:navigation_]; [[controller_ tableView] layoutIfNeeded];
}
- (void)scrollToRow:(NSUInteger)row;
{
  UITableView *table=[controller_ tableView];
  NSIndexPath *index=[NSIndexPath indexPathForRow:(NSInteger)row inSection:0];
  [table scrollToRowAtIndexPath:index atScrollPosition:UITableViewScrollPositionTop animated:NO];
  [table layoutIfNeeded];
  perfRequire([table cellForRowAtIndexPath:index]!=nil,@"Requested iOS row has a visible native cell");
}
- (void)refresh; { [controller_ refresh:nil]; }
- (BOOL)loading; { return [[controller_ valueForKey:@"listLoader_"] isLoading]; }
- (NSArray *)displayRows;
{ return [[[controller_ valueForKey:@"sections_"] objectAtIndex:0] objectForKey:@"rows"]; }
- (void)close;
{
  [window_ setRootViewController:[[[UIViewController alloc] init] autorelease]];
  [navigation_ release]; navigation_=nil; [controller_ release]; controller_=nil;
}
- (void)applicationWillResignActive:(UIApplication *)application;
{ (void)application; if(running_) interrupted_=YES; }
- (void)validateRun;
{ perfRequire(!interrupted_ && [[UIApplication sharedApplication] applicationState]==UIApplicationStateActive,@"Run interrupted: keep the test foregrounded and rerun"); }
- (void)run;
{
  if([[UIApplication sharedApplication] applicationState]!=UIApplicationStateActive) {
    [self performSelector:@selector(run) withObject:nil afterDelay:0.5]; return;
  }
  NSString *documents=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) objectAtIndex:0];
  [[NSFileManager defaultManager] removeItemAtPath:[documents stringByAppendingPathComponent:@"performance.plist"] error:NULL];
  [[NSFileManager defaultManager] removeItemAtPath:[documents stringByAppendingPathComponent:@"performance-error.txt"] error:NULL];
  BOOL idle=[[UIApplication sharedApplication] isIdleTimerDisabled];
  [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
  running_=YES; interrupted_=NO;
  @try {
    runNativePerformance(self,[documents stringByAppendingPathComponent:@"Performance"],
      [documents stringByAppendingPathComponent:@"performance.plist"]);
  } @catch(NSException *exception) {
    [[exception description] writeToFile:[documents stringByAppendingPathComponent:@"performance-error.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  }
  running_=NO;
  [[UIApplication sharedApplication] setIdleTimerDisabled:idle];
}
@end
int main(int argc,char **argv) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  int result=UIApplicationMain(argc,argv,nil,@"RDLPPerfIOS"); [pool drain]; return result;
}
