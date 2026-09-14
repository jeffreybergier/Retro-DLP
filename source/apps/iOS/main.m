#import <UIKit/UIKit.h>
#import <AIFontAwesome.h>
#import "LibraryController.h"
#import "XPUIKit.h"
@interface AppDelegate : UIResponder <UIApplicationDelegate> {
  UIWindow *window_; RDLPLibrary *library_;
}
@property(nonatomic,retain) UIWindow *window;
@end
@implementation AppDelegate
@synthesize window=window_;
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options;
{
  (void)application; (void)options; [AIFontAwesome registerBundledFonts];
  NSString *documents=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) objectAtIndex:0];
  NSString *support=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/RetroDLP"];
  library_=[[RDLPLibrary alloc] initWithSupportDirectory:support downloadDirectory:[documents stringByAppendingPathComponent:@"RetroDLP"]];
  window_=[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  if(library_) {
    LibraryController *root=[[LibraryController alloc] initWithLibrary:library_ mode:0 playlist:nil video:nil];
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:root];
    window_.rootViewController=navigation; [navigation release]; [root release];
  } else {
    UIViewController *error=[[UIViewController alloc] init]; window_.rootViewController=error; [error release];
    RDShowMessage(@"Cannot open the RetroDLP library. Check available storage and restart the app.");
  }
  [window_ makeKeyAndVisible]; return YES;
}
- (void)applicationDidEnterBackground:(UIApplication *)application;
{ (void)application; [library_ setPaused:YES]; }
- (void)applicationWillTerminate:(UIApplication *)application;
{ (void)application; [library_ shutdown]; }
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)source annotation:(id)annotation;
{
  (void)application; (void)source; (void)annotation;
  if(![url isFileURL] || !library_) return NO;
  BOOL imported=[library_ importCookies:[url path]]; RDShowMessage([library_ status]); return imported;
}
- (void)dealloc; { [library_ shutdown]; [library_ release]; [window_ release]; [super dealloc]; }
@end
int main(int argc,char **argv) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  int result=UIApplicationMain(argc,argv,nil,@"AppDelegate"); [pool drain]; return result;
}
