#import "RDLPAppDelegate.h"
#import "RDLPLibraryViewController.h"
#import "RDLPPlaylistsViewController.h"
#import "RDLPUIKit.h"
#import <AIFontAwesome.h>
@interface RDLPAppDelegate (Errors)
- (void)errorsChanged:(id)sender;
- (void)showNextError;
- (void)activityChanged:(id)sender;
- (UIBackgroundTaskIdentifier)beginBackgroundTask;
- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)task;
- (void)finishBackgroundTask;
- (void)backgroundTimeExpired;
- (void)registerDownloadNotifications:(UIApplication *)application;
- (void)downloadCompleted:(NSNotification *)notification;
- (void)presentDownloadNotification:(UILocalNotification *)notification;
@end
@implementation RDLPAppDelegate
@synthesize window=window_;
- (id)init;
{ self=[super init]; if(self) backgroundTask_=UIBackgroundTaskInvalid; return self; }
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options;
{
  (void)application; (void)options; [AIFontAwesome registerBundledFonts];
  NSString *documents=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) objectAtIndex:0];
  NSString *support=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/RetroDLP"];
  library_=[[RDLPLibrary alloc] initWithSupportDirectory:support downloadDirectory:[documents stringByAppendingPathComponent:@"RetroDLP"]];
  window_=[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  if(library_) {
    [self registerDownloadNotifications:application];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadCompleted:) name:RDLPLibraryDownloadDidComplete object:library_];
    RDLPPlaylistsViewController *root=[[RDLPPlaylistsViewController alloc] initWithLibrary:library_];
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:root];
    window_.rootViewController=navigation; [navigation release]; [root release];
  } else {
    UIViewController *error=[[UIViewController alloc] init]; window_.rootViewController=error; [error release];
    [RDLPUIKit showMessage:@"Cannot open the RetroDLP library. Check available storage and restart the app."];
  }
  [window_ makeKeyAndVisible];
  if(library_) {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(errorsChanged:) name:RDLPLibraryErrorDidOccur object:library_];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(activityChanged:) name:RDLPLibraryActivityDidChange object:library_];
    [self errorsChanged:nil]; [library_ startDownloads];
  }
  return YES;
}
- (void)registerDownloadNotifications:(UIApplication *)application;
{
  /* Like ENIL, use local alerts on iOS 5+ and ask for alert/sound permission
     only where the iOS 8 registration API exists. No remote push registration. */
  SEL registerSelector=@selector(registerUserNotificationSettings:);
  Class settingsClass=NSClassFromString(@"UIUserNotificationSettings");
  SEL createSelector=@selector(settingsForTypes:categories:);
  if(![application respondsToSelector:registerSelector] ||
     ![settingsClass respondsToSelector:createSelector]) return;
  id (*createSettings)(id,SEL,NSUInteger,id)=(id (*)(id,SEL,NSUInteger,id))[settingsClass methodForSelector:createSelector];
  id settings=createSettings(settingsClass,createSelector,6,nil); /* Sound=2, Alert=4. */
  [application performSelector:registerSelector withObject:settings];
}
- (void)downloadCompleted:(NSNotification *)notification;
{
  if(!backgrounded_) return;
  NSString *title=[[notification userInfo] objectForKey:@"title"];
  if(![title length]) title=[[notification userInfo] objectForKey:@"video_id"];
  if(![title length]) title=@"Video";
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  UILocalNotification *alert=[[UILocalNotification alloc] init];
  alert.alertBody=[NSString stringWithFormat:@"Download Complete '%@'",title];
  alert.soundName=UILocalNotificationDefaultSoundName;
  [self presentDownloadNotification:alert];
  [alert release];
#pragma clang diagnostic pop
}
- (void)presentDownloadNotification:(UILocalNotification *)notification;
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [[UIApplication sharedApplication] presentLocalNotificationNow:notification];
#pragma clang diagnostic pop
}
- (void)applicationDidEnterBackground:(UIApplication *)application;
{ (void)application; backgrounded_=YES; [self activityChanged:nil]; }
- (void)applicationWillEnterForeground:(UIApplication *)application;
{
  (void)application; backgrounded_=NO; backgroundTimeExpired_=NO;
  [self activityChanged:nil]; [library_ startDownloads];
}
- (void)applicationWillTerminate:(UIApplication *)application;
{ (void)application; [library_ shutdown]; [self finishBackgroundTask]; }
- (UIBackgroundTaskIdentifier)beginBackgroundTask;
{
  return [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{ [self backgroundTimeExpired]; }];
}
- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)task;
{ [[UIApplication sharedApplication] endBackgroundTask:task]; }
- (void)finishBackgroundTask;
{
  if(backgroundTask_==UIBackgroundTaskInvalid) return;
  UIBackgroundTaskIdentifier task=backgroundTask_; backgroundTask_=UIBackgroundTaskInvalid;
  [self endBackgroundTask:task];
}
- (void)activityChanged:(id)sender;
{
  (void)sender;
  if(![library_ operationCount]) { [self finishBackgroundTask]; return; }
  if(backgroundTimeExpired_ || backgroundTask_!=UIBackgroundTaskInvalid) return;
  /* Request before the worker starts, even in the foreground. No background
     mode/entitlement is needed for UIKit's finite task-completion allowance. */
  backgroundTask_=[self beginBackgroundTask];
  if(backgroundTask_==UIBackgroundTaskInvalid && backgrounded_) [self backgroundTimeExpired];
}
- (void)backgroundTimeExpired;
{
  backgroundTimeExpired_=YES;
  /* Cancels sync/discovery as well as media transfers and blocks new workers.
     Never wait for the worker or its database lock in an expiration handler. */
  [library_ suspendOperations]; [self finishBackgroundTask];
}
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)source annotation:(id)annotation;
{
  (void)application; (void)source; (void)annotation;
  if(![url isFileURL] || !library_) return NO;
  UINavigationController *navigation=(UINavigationController *)window_.rootViewController;
  id controller=navigation.topViewController;
  return [controller requestCookieImport:[url path] discover:NO];
}
- (void)errorsChanged:(id)sender;
{
  (void)sender;
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showNextError) object:nil];
  [self performSelector:@selector(showNextError) withObject:nil afterDelay:0.1];
}
- (void)showNextError;
{
  if(errorAlert_ || ![library_ hasErrors]) return;
  /* Wait for an input/confirmation alert to dismiss, and for foregrounding. */
  if([UIApplication sharedApplication].applicationState!=UIApplicationStateActive) { [self errorsChanged:nil]; return; }
  for(UIWindow *window in [UIApplication sharedApplication].windows)
    if(!window.hidden && window.windowLevel>=UIWindowLevelAlert) { [self errorsChanged:nil]; return; }
  NSDictionary *error=[library_ takeError]; if(!error) return;
  errorAlert_=[[UIAlertView alloc] initWithTitle:[error objectForKey:@"title"] message:[error objectForKey:@"detail"] delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
  [errorAlert_ show];
}
- (void)alertView:(UIAlertView *)alert didDismissWithButtonIndex:(NSInteger)index;
{
  (void)index; if(alert!=errorAlert_) return;
  errorAlert_.delegate=nil; [errorAlert_ release]; errorAlert_=nil; [self errorsChanged:nil];
}
- (void)dealloc;
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [self finishBackgroundTask];
  errorAlert_.delegate=nil; [errorAlert_ dismissWithClickedButtonIndex:0 animated:NO]; [errorAlert_ release];
  [library_ shutdown]; [library_ release]; [window_ release]; [super dealloc];
}
@end
