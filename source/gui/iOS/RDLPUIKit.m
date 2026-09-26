#import "RDLPUIKit.h"
#import "RDLPStatusBarView.h"
#import "RDLPLibrary.h"
#import "RDLPDownloadPolicy.h"
#import <AIFontAwesome.h>
#import "RDLPDownloadedPlayerViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <math.h>
/* Keep raster pixels and UIImage.scale tied to the same display scale.
   AIFontAwesome also accepts zero for this, but the cache needs the resolved
   value so images created at another screen scale cannot be reused. */
static CGFloat RDLPMainScreenScale(void) {
  CGFloat scale=[[UIScreen mainScreen] scale];
  return isfinite(scale) && scale>=1.0?scale:1.0;
}
/* Preserve the glyph color for iOS 5/6, where template rendering is unavailable.
   The selector guard keeps explicit iOS 7 template mode safe on those systems. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
static UIImage *RDLPFontAwesomeImageWithOffset(AIFontAwesomeIcon icon,CGFloat size,CGFloat canvas,CGFloat scale,UIColor *color,CGFloat verticalOffset) {
  UIImage *image=[AIFontAwesome imageForIcon:icon style:AIFontAwesomeStyleSolid
    iconSize:size canvasSize:canvas color:color scale:scale];
  if(image && verticalOffset!=0) {
    UIGraphicsBeginImageContextWithOptions([image size],NO,[image scale]);
    [image drawAtPoint:CGPointMake(0,verticalOffset)];
    image=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
  }
  if([image respondsToSelector:@selector(imageWithRenderingMode:)])
    image=[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
  return image;
}
#pragma clang diagnostic pop
static UIImage *RDLPFontAwesomeImage(AIFontAwesomeIcon icon,CGFloat size,CGFloat canvas,CGFloat scale,UIColor *color) {
  return RDLPFontAwesomeImageWithOffset(icon,size,canvas,scale,color,0);
}
@implementation RDLPUIKit
+ (void)configurePlayerFullScreenLayout:(UIViewController *)controller;
{
  /* iOS 5/6 use this flag; iOS 7+ extend content beneath translucent bars. */
  if([controller respondsToSelector:@selector(setWantsFullScreenLayout:)])
    [controller setValue:[NSNumber numberWithBool:YES] forKey:@"wantsFullScreenLayout"];
}
+ (void)setBorderedStyleForBarButtonItem:(UIBarButtonItem *)item;
{
  [item setStyle:UIBarButtonItemStyleBordered];
}
+ (void)centerTextInLabel:(UILabel *)label;
{
  /* Center is 1 in both the iOS 5 and iOS 6 alignment enums. */
  [label setTextAlignment:(__typeof__([label textAlignment]))1];
}
+ (BOOL)legacyStatusBarHidden;
{
  return [[UIApplication sharedApplication] isStatusBarHidden];
}
+ (void)setLegacyStatusBarHidden:(BOOL)hidden;
{
  [[UIApplication sharedApplication] setStatusBarHidden:hidden withAnimation:UIStatusBarAnimationNone];
}
+ (void)registerDownloadNotificationsForApplication:(UIApplication *)application;
{
  /* iOS 8 asks for alert and sound permission; iOS 5-7 need no registration. */
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
  if(![application respondsToSelector:@selector(registerUserNotificationSettings:)] ||
     ![UIUserNotificationSettings respondsToSelector:@selector(settingsForTypes:categories:)]) return;
  UIUserNotificationSettings *settings=[UIUserNotificationSettings settingsForTypes:
    UIUserNotificationTypeSound|UIUserNotificationTypeAlert categories:nil];
  [application registerUserNotificationSettings:settings];
#pragma clang diagnostic pop
#endif
}
+ (id)downloadCompletionNotificationForTitle:(NSString *)title;
{
  UILocalNotification *alert=[[[UILocalNotification alloc] init] autorelease];
  [alert setAlertBody:[NSString stringWithFormat:@"Download Complete '%@'",title]];
  [alert setSoundName:UILocalNotificationDefaultSoundName];
  return alert;
}
+ (void)presentDownloadNotification:(id)notification;
{
  [[UIApplication sharedApplication] presentLocalNotificationNow:notification];
}
+ (void)activatePlaybackAudioSessionForDelegate:(id)delegate;
{
  AVAudioSession *session=[AVAudioSession sharedInstance]; NSError *error=nil;
  /* The delegate callbacks remain available on iOS 5. */
  [session performSelector:@selector(setDelegate:) withObject:delegate];
  if(![session setCategory:AVAudioSessionCategoryPlayback error:&error] || ![session setActive:YES error:&error])
    NSLog(@"Could not activate playback audio session: %@",error);
}
+ (void)deactivatePlaybackAudioSessionForDelegate:(id)delegate;
{
  AVAudioSession *session=[AVAudioSession sharedInstance];
  if([session performSelector:@selector(delegate)]==delegate)
    [session performSelector:@selector(setDelegate:) withObject:nil];
  /* iOS 5 calls this with flags; iOS 6+ renamed the same option bit. */
  SEL selector=[session respondsToSelector:@selector(setActive:withOptions:error:)]
    ?@selector(setActive:withOptions:error:):@selector(setActive:withFlags:error:);
  NSInvocation *invocation=[NSInvocation invocationWithMethodSignature:[session methodSignatureForSelector:selector]];
  BOOL active=NO;
  NSUInteger notifyOthers=1;
  NSError **error=NULL;
  [invocation setTarget:session]; [invocation setSelector:selector];
  [invocation setArgument:&active atIndex:2];
  [invocation setArgument:&notifyOthers atIndex:3];
  [invocation setArgument:&error atIndex:4];
  [invocation invoke];
}
+ (BOOL)shouldResumePlaybackAfterInterruptionFlags:(NSUInteger)flags;
{
  return (flags & 1U)!=0; /* iOS 5's ShouldResume flag. */
}
+ (void)configureContentEdges:(UIViewController *)controller;
{
  /* iOS 7 introduced extended edges. KVC preserves the iOS 5 deployment path. */
  if([controller respondsToSelector:@selector(setEdgesForExtendedLayout:)])
    [controller setValue:[NSNumber numberWithUnsignedInteger:0] forKey:@"edgesForExtendedLayout"];
}
+ (UIImage *)statusIcon:(NSString *)status;
{
  static NSMutableDictionary *images=nil;
  if(!images) images=[[NSMutableDictionary alloc] init];
  CGFloat scale=RDLPMainScreenScale();
  NSArray *key=[NSArray arrayWithObjects:status,[NSNumber numberWithDouble:scale],nil];
  UIImage *cached=[images objectForKey:key]; if(cached) return cached;
  AIFontAwesomeIcon icon=AIFATriangleExclamation;
  if([status isEqualToString:@"Downloaded"]) icon=AIFACircleCheck;
  else if([status isEqualToString:@"Downloading"] || [status isEqualToString:@"Queued"]) icon=AIFAHourglass;
  else if([status isEqualToString:@"Not downloaded"]) icon=AIFADownload;
  UIImage *image=RDLPFontAwesomeImage(icon,14,18,scale,[UIColor blackColor]);
  if(image) [images setObject:image forKey:key]; return image;
}
+ (UIImage *)queueActionIcon:(BOOL)stop;
{ return RDLPFontAwesomeImage(stop?AIFAPause:AIFARotateRight,14,20,RDLPMainScreenScale(),[UIColor whiteColor]); }

+ (UIImage *)settingsIcon;
{ return RDLPFontAwesomeImageWithOffset(AIFAGear,18,26,RDLPMainScreenScale(),[UIColor whiteColor],-1); }

+ (UIImage *)plusIcon;
{
  /* Font Awesome "plus"; this bundled header names U+F067 AIFAStd12. */
  return RDLPFontAwesomeImageWithOffset((AIFontAwesomeIcon)0xF067,18,26,RDLPMainScreenScale(),[UIColor whiteColor],-1); }

+ (UIImage *)queueToolbarIcon;
{
  /* Lift the glyph within its canvas to align with the legacy bordered button.
   * Keep the same optical adjustment on every iOS version. */
  return RDLPFontAwesomeImageWithOffset(AIFAListCheck,18,28,RDLPMainScreenScale(),[UIColor whiteColor],-1);
}

+ (UIImage *)syncIcon;
{ return RDLPFontAwesomeImageWithOffset(AIFAArrowsRotate,18,26,RDLPMainScreenScale(),[UIColor whiteColor],-1); }

+ (NSArray *)statusToolbarItems:(RDLPStatusBarView *)status target:(id)target queueAction:(SEL)action;
{
  /* Reserve the spinner slot even when it is hidden so hidesWhenStopped never
   * changes the message layout. Let UIKit size the native Queue button. */
  UIView *spinnerSlot=[[[UIView alloc] initWithFrame:CGRectMake(0,0,36,30)] autorelease];
  [[status spinner] setCenter:CGPointMake(18,15)];
  [spinnerSlot addSubview:[status spinner]];
  UIBarButtonItem *activity=[[[UIBarButtonItem alloc] initWithCustomView:spinnerSlot] autorelease];
  UIBarButtonItem *left=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
  UIBarButtonItem *right=[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease];
  UIBarButtonItem *message=[[[UIBarButtonItem alloc] initWithCustomView:status] autorelease];
  if(!action) {
    UIView *emptySlot=[[[UIView alloc] initWithFrame:CGRectMake(0,0,36,30)] autorelease];
    UIBarButtonItem *empty=[[[UIBarButtonItem alloc] initWithCustomView:emptySlot] autorelease];
    return [NSArray arrayWithObjects:activity,left,message,right,empty,nil];
  }
  UIBarButtonItem *queue=[[[UIBarButtonItem alloc] initWithImage:[self queueToolbarIcon] style:UIBarButtonItemStyleBordered target:target action:action] autorelease];
  [queue setAccessibilityLabel:@"Download Queue"];
  return [NSArray arrayWithObjects:activity,left,message,right,queue,nil];
}

+ (void)showMessage:(NSString *)message; {
  UIAlertView *alert=[[UIAlertView alloc] initWithTitle:@"RetroDLP" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
  [alert show]; [alert release];
}
+ (void)presentPlayer:(UIViewController *)owner library:(RDLPLibrary *)library job:(NSDictionary *)job; {
  NSString *path=[library fileForJob:job];
  if(!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) { [self showMessage:@"The downloaded file is missing. Retry its download from Queue."]; return; }
  RDLPDownloadedPlayerViewController *controller=[[RDLPDownloadedPlayerViewController alloc]
    initWithLibrary:library job:job URL:[NSURL fileURLWithPath:path]];
  [owner presentViewController:controller animated:YES completion:nil];
  [controller release];
}
+ (void)presentPlayer:(UIViewController *)owner library:(RDLPLibrary *)library playlist:(NSString *)playlist entry:(NSDictionary *)entry job:(NSDictionary *)selectedJob;
{
  RDLPDownloadPolicy *policy=[[[RDLPDownloadPolicy alloc] initWithLibrary:library] autorelease];
  NSDictionary *selectedFile=[policy localFileForJob:selectedJob];
  if(!selectedFile) { [self showMessage:@"The downloaded file is missing. Retry its download from Queue."]; return; }
  /* Query completed jobs once, newest first, instead of querying every entry.
   * Keep the same representative-quality policy as the playlist's rows. */
  NSMutableDictionary *jobsByVideo=[NSMutableDictionary dictionary], *URLsByVideo=[NSMutableDictionary dictionary];
  NSArray *completed=[library jobsForPlaylist:playlist completedOnly:YES];
  NSUInteger index=0, count=[completed count];
  while(index<count) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    NSUInteger end=MIN(index+32,count);
    for(;index<end;++index) {
      NSDictionary *job=[completed objectAtIndex:index];
      NSString *video=[job objectForKey:@"video_id"];
      if([jobsByVideo objectForKey:video]) continue;
      NSDictionary *file=[policy localFileForJob:job];
      if(!file) continue;
      [jobsByVideo setObject:job forKey:video];
      [URLsByVideo setObject:[NSURL fileURLWithPath:[file objectForKey:@"path"]] forKey:video];
    }
    [pool drain];
  }
  NSMutableArray *jobs=[NSMutableArray array], *URLs=[NSMutableArray array];
  NSUInteger selected=NSNotFound;
  NSArray *entries=[library entriesForPlaylist:playlist];
  index=0; count=[entries count];
  while(index<count) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    NSUInteger end=MIN(index+32,count);
    for(;index<end;++index) {
      NSDictionary *candidate=[entries objectAtIndex:index];
      NSString *video=[candidate objectForKey:@"video_id"];
      BOOL tapped=[video isEqualToString:[entry objectForKey:@"video_id"]] &&
        [[candidate objectForKey:@"position"] isEqual:[entry objectForKey:@"position"]];
      NSDictionary *job=tapped?selectedJob:[jobsByVideo objectForKey:video];
      if(!job) continue;
      if(tapped) selected=[jobs count];
      [jobs addObject:job];
      [URLs addObject:tapped?[NSURL fileURLWithPath:[selectedFile objectForKey:@"path"]]:[URLsByVideo objectForKey:video]];
    }
    [pool drain];
  }
  /* A sync may remove/reorder the tapped occurrence while the list is visible.
   * In that case play the exact tapped file rather than selecting a different row. */
  if(selected==NSNotFound) { [self presentPlayer:owner library:library job:selectedJob]; return; }
  RDLPDownloadedPlayerViewController *controller=[[RDLPDownloadedPlayerViewController alloc]
    initWithLibrary:library jobs:jobs URLs:URLs startingAtIndex:selected];
  [owner presentViewController:controller animated:YES completion:nil];
  [controller release];
}
+ (UIBarButtonItem *)item:(NSString *)title target:(id)target action:(SEL)action;
{ return [[[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered target:target action:action] autorelease]; }
@end
