#import "RDLPAppDelegate.h"
#import "RDLPLibraryViewController.h"
#import "RDLPUIKit.h"
#import <AIFontAwesome.h>
@implementation RDLPAppDelegate
@synthesize window=window_;
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options;
{
  (void)application; (void)options; [AIFontAwesome registerBundledFonts];
  NSString *documents=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) objectAtIndex:0];
  NSString *support=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/RetroDLP"];
  library_=[[RDLPLibrary alloc] initWithSupportDirectory:support downloadDirectory:[documents stringByAppendingPathComponent:@"RetroDLP"]];
  window_=[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  if(library_) {
    RDLPLibraryViewController *root=[[RDLPLibraryViewController alloc] initWithLibrary:library_ mode:RDLPScreenLibrary playlist:nil video:nil];
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:root];
    window_.rootViewController=navigation; [navigation release]; [root release];
  } else {
    UIViewController *error=[[UIViewController alloc] init]; window_.rootViewController=error; [error release];
    [RDLPUIKit showMessage:@"Cannot open the RetroDLP library. Check available storage and restart the app."];
  }
  [window_ makeKeyAndVisible]; [library_ startDownloads]; return YES;
}
- (void)applicationDidEnterBackground:(UIApplication *)application;
{ (void)application; [library_ setPaused:YES]; }
- (void)applicationWillEnterForeground:(UIApplication *)application;
{ (void)application; [library_ startDownloads]; }
- (void)applicationWillTerminate:(UIApplication *)application;
{ (void)application; [library_ shutdown]; }
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)source annotation:(id)annotation;
{
  (void)application; (void)source; (void)annotation;
  if(![url isFileURL] || !library_) return NO;
  UINavigationController *navigation=(UINavigationController *)window_.rootViewController;
  RDLPLibraryViewController *controller=(RDLPLibraryViewController *)navigation.topViewController;
  return [controller requestCookieImport:[url path] discover:NO];
}
- (void)dealloc; { [library_ shutdown]; [library_ release]; [window_ release]; [super dealloc]; }
@end
